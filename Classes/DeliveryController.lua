-- ArenaChillPrep — Classes/DeliveryController
-- Orchestrator: bracket gate → wait for items → open trade → hand off.
-- State machine: IDLE -> ACTIVE -> TRADING -> DONE. `givenTo` is runtime-only
-- (reset on ACP_BUFF_LOST, never saved).

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local TradeFrame = _G.TradeFrame;
local UnitExists = _G.UnitExists;
local UnitIsUnit = _G.UnitIsUnit;

--- State machine values (Data/Constants.DELIVERY_STATE).
local DS = ACP.Data.Constants.DELIVERY_STATE;

---@class DeliveryController
local DeliveryController = {
    _initialized = false,

    --- "IDLE" | "ACTIVE" | "TRADING" | "DONE"
    state = DS.IDLE,

    --- Partners already served this prep (runtime-only, reset on ACP_BUFF_LOST).
    ---@type table<string, boolean>
    givenTo = {},

    ---@type string|nil
    currentPartner = nil,

    ---@type number
    retryCount = 0,
};

---@type DeliveryController
ACP.DeliveryController = DeliveryController;

function DeliveryController:setState(newState)
    ACP.StateMachine:setState(self, newState, DS);
end

--- Reset everything for a fresh prep.
function DeliveryController:reset()
    self.givenTo = {};
    self.currentPartner = nil;
    self.retryCount = 0;
    ACP.Utils.Timers:cancel("TradeDelay");
    ACP.Utils.Timers:cancel("TradeRetry");
    ACP.Utils.Timers:cancel("TradeOpen");
    ACP.Utils.Timers:cancel("DeliveryCheck");
    self:setState(DS.IDLE);
end

--- Whether the bracket is enabled in Settings; logs a message when disabled.
---@param bracket string
---@return boolean
function DeliveryController:bracketEnabled(bracket)
    if (ACP.Settings:get("brackets." .. bracket)) then
        return true;
    end

    ACP:debugPrint("bracket %s disabled, skipping (enable it in settings)", bracket);
    return false;
end

--- Number of partners already served this prep (drives the DONE decision).
---@return number
function DeliveryController:givenCount()
    local count = 0;

    for _ in pairs(self.givenTo) do
        count = count + 1;
    end

    return count;
end

--- The set of item categories the current class can pass (from the catalog).
--- Delegates to TradePlanner (single source for the class → items mapping).
---@return table
function DeliveryController:getCategories()
    return ACP.TradePlanner:getCategories();
end

--- Whether the selected ranks of an enabled category are ALL ready.
--- Delegates to TradePlanner (single source for the rank grouping).
---@param category string  plural catalog key ("healthstones")
---@param setting table
---@return boolean
function DeliveryController:categoryReady(category, setting)
    return ACP.TradePlanner:categoryReady(category, setting);
end

--- Whether every enabled item category the PARTNER should receive has ALL
--- its selected ranks ready. `partnerUnit` picks the per-partner categories
--- (a Mage gives water only to mana-using partners — see
--- TradePlanner:categoriesForPartner); nil means every category of the class
--- (a Warlock has a single category, so its behavior is unchanged).
---@param partnerUnit string|nil
---@return boolean
function DeliveryController:itemsReady(partnerUnit)
    local categories = ACP.TradePlanner:categoriesForPartner(partnerUnit);
    local anyEnabled = false;

    for _, category in ipairs(categories) do
        local settingsKey = ACP.Data.Items:settingsKeyFor(category);
        local setting = ACP.Settings:get("items." .. settingsKey);

        if (setting and setting.enabled) then
            anyEnabled = true;

            if (not self:categoryReady(category, setting)) then
                ACP:debugPrint("itemsReady: category=%s not ready yet", category);
                return false;
            end
        else
            ACP:debugPrint("itemsReady: category=%s setting %s missing or disabled",
                category, tostring(settingsKey));
        end
    end

    return anyEnabled;
end

--- First eligible partner: the first party member who isn't the player and
--- hasn't already received items this prep. Arena teammates are always
--- party1..partyN, so no manual slot is needed.
---@return string|nil
function DeliveryController:findPartner()
    local count = ACP.ArenaPrep:getPartySize();

    for i = 1, count do
        local unit = "party" .. i;

        if (UnitExists(unit) and not UnitIsUnit(unit, "player") and not self.givenTo[unit]
            and self:partnerClassAllowed(unit)) then
            return unit;
        end
    end

    return nil;
end

--- Whether auto-trade to `unit` is allowed by the "do not trade to same
--- class" setting (always compares against the player's own class).
---@param unit string
---@return boolean
function DeliveryController:partnerClassAllowed(unit)
    if (ACP.Settings:get("noTradeSameClass") ~= true) then
        return true;
    end

    local _, playerClass = UnitClass("player");
    local _, unitClass = UnitClass(unit);

    if (playerClass and unitClass and playerClass == unitClass) then
        ACP:debugPrint("skipping trade with %s: same class (%s)", tostring(unit), tostring(playerClass));
        return false;
    end

    return true;
end

--- Are we allowed to start a new trade right now?
---@return boolean
function DeliveryController:canStartTrade()
    if (not ACP.Preconditions:enabled()) then
        ACP:debugPrint("canStartTrade: disabled");
        return false;
    end

    if (not ACP.Preconditions:inArena()) then
        ACP:debugPrint("canStartTrade: not in arena");
        return false;
    end

    if (not ACP.Preconditions:notInCombat()) then
        ACP:debugPrint("canStartTrade: in combat");
        return false;
    end

    -- A dead player cannot initiate a trade; retry after revival
    -- (PLAYER_REGEN_ENABLED / the ACTIVE ticker) if the buff is still active.
    if (not ACP.Preconditions:notDead()) then
        ACP:debugPrint("canStartTrade: player dead");
        return false;
    end

    -- Gate safety: never start a trade too close to the gates opening.
    if (not ACP.Preconditions:gateSafetyOk()) then
        local gateSafety = ACP.Settings:get("gateSafetySeconds") or ACP.Data.Constants.GATE_SAFETY_DEFAULT;
        local remaining = ACP.ArenaPrep:getRemainingTime();
        ACP:debugPrint("skipping trade: %0.1f s left, below gateSafetySeconds (%s)",
            remaining, tostring(gateSafety));
        return false;
    end

    ACP:debugPrint("canStartTrade: ok");
    return true;
end

--- The heart of ACTIVE: if items are ready and a partner exists — schedule
--- the trade after `tradeDelay`.
function DeliveryController:checkReady()
    if (self.state ~= DS.ACTIVE) then
        return;
    end

    -- Pile-up guard: never schedule a new attempt while one is already
    -- pending (a trade is scheduled or a retry is backing off). Applies to
    -- EVERY caller — the poll ticker, ACP_ITEMS_CHANGED, roster updates.
    if (ACP.Utils.Timers.Handles["TradeDelay"] or ACP.Utils.Timers.Handles["TradeRetry"]) then
        return;
    end

    -- Bracket gate is enforced here too (the bracket may resolve later than
    -- the buff gain — see onBuffGained). If it resolves to a disabled bracket,
    -- drop out of ACTIVE entirely.
    local bracket = ACP.ArenaPrep:getBracket();

    if (bracket and not self:bracketEnabled(bracket)) then
        self:setState(DS.IDLE);
        return;
    end

    if (not self:canStartTrade()) then
        return;
    end

    -- The partner decides the readiness (a Mage gives water only to
    -- mana-using partner classes), so it is determined before itemsReady.
    local partner = self:findPartner();

    if (not partner) then
        if (self:givenCount() > 0) then
            ACP:debugPrint("no eligible partner (givenTo: %d)", self:givenCount());
            self:setState(DS.DONE);
        elseif (self:itemsReady()) then
            ACP:debugPrint("items ready but no partner found (are you in a group?)");
        end

        return;
    end

    if (not self:itemsReady(partner)) then
        return;
    end

    local tradeDelay = ACP.Settings:get("tradeDelay") or 1.5;
    ACP:debugPrint("scheduling trade with %s in %.1f s", partner, tradeDelay);

    ACP.Utils.Timers:after("TradeDelay", tradeDelay, function()
        -- Re-check before actually sending the request.
        if (self.state ~= DS.ACTIVE) then
            return;
        end

        if (not self:canStartTrade()) then
            return;
        end

        if (not self:itemsReady(partner)) then
            return;
        end

        self.currentPartner = partner;
        self:setState(DS.TRADING);
        ACP.TradeManager:startTrade(partner);

        -- One-shot open timeout: InitiateTrade can fail silently (out of
        -- range, partner offline/dead) without any window event.
        ACP.Utils.Timers:after("TradeOpen", ACP.Data.Constants.TRADE_OPEN_TIMEOUT, function()
            if (self.state ~= DS.TRADING) then
                return; -- already resolved (window opened / trade completed)
            end

            -- Never cancel a trade whose window is actually up (a stale
            -- C_Timer can fire after cancel — see Utils/Timers).
            if (TradeFrame and TradeFrame:IsShown()) then
                return;
            end

            ACP:debugPrint("trade window did not open within %.1f s", ACP.Data.Constants.TRADE_OPEN_TIMEOUT);
            ACP.TradeManager:cancel();
            self:onTradeFailed("timeout");
        end);
    end);
end

--- Whether an inbound (partner-initiated) trade window should be taken over
--- and filled with prep items: prepping (ACTIVE) and the partner is a
--- teammate (never inject items into a trade with a random person).
---@return boolean
function DeliveryController:shouldTakeOverInboundTrade()
    if (self.state ~= DS.ACTIVE) then
        return false;
    end

    if (not ACP.Preconditions:enabled()) then
        return false;
    end

    if (not ACP.Preconditions:inArena()) then
        return false;
    end

    if (not ACP.Preconditions:notInCombat()) then
        return false;
    end

    -- Only deliver to an actual teammate — never inject prep items into a
    -- trade the player opened with a random person.
    local partner = ACP.TradeManager:getPartner();

    if (partner and not ACP.ArenaPrep:findPartyUnitByName(partner)) then
        ACP:debugPrint("inbound trade with non-teammate %s, not taking over", tostring(partner));
        return false;
    end

    -- Respect the "do not trade to same class" setting for inbound trades too.
    if (partner and not self:partnerClassAllowed(partner)) then
        ACP:debugPrint("inbound trade with same-class %s, not taking over", tostring(partner));
        return false;
    end

    return true;
end

--- ACP_TRADE_OPENED: cancel pending scheduling, credit the partner, stop
--- polling, fill the placement queue.
---@param partner string
function DeliveryController:onTradeOpened(partner)
    ACP.Utils.Timers:cancel("TradeOpen");
    ACP.Utils.Timers:cancel("TradeDelay");

    if (not self.currentPartner) then
        self.currentPartner = partner;
    end

    -- Normalize a NAME (inbound trade) to a party token so the per-partner
    -- class filters can read UnitClass(unit).
    if (self.currentPartner and not self.currentPartner:match("^party%d+$")) then
        self.currentPartner = ACP.ArenaPrep:findPartyUnitByName(self.currentPartner) or self.currentPartner;
    end

    if (self.state == DS.ACTIVE) then
        self:setState(DS.TRADING);
    end

    ACP.TradeManager:queueItems(ACP.TradePlanner:buildQueue(self.currentPartner));
end

--- Every-tick readiness poll while ACTIVE (safety net for events that may be
--- missed on 2.5.5).
function DeliveryController:startCheckTicker()
    ACP.Utils.Timers:interval("DeliveryCheck", 0.5, function()
        -- Only poll while ACTIVE; checkReady enforces the pending-timer guards.
        if (self.state ~= DS.ACTIVE) then
            ACP.Utils.Timers:cancel("DeliveryCheck");
            return;
        end

        self:checkReady();
    end);
end

--- ACP_BUFF_GAINED: bracket gate, then ACTIVE and an immediate readiness check
--- (covers the "item already in bags at prep start" case).
function DeliveryController:onBuffGained()
    local bracket = ACP.ArenaPrep:getBracket();

    -- The bracket may not be known yet (party size loads after the buff) —
    -- defer the gate until it resolves, don't skip the prep outright.
    if (not bracket) then
        ACP:debugPrint("bracket unknown yet, deferring gate");
        self:setState(DS.ACTIVE);
        self:startCheckTicker();
        return;
    end

    if (not self:bracketEnabled(bracket)) then
        self:setState(DS.IDLE);
        return;
    end

    ACP:debugPrint("bracket %s enabled, prep active", bracket);
    self:setState(DS.ACTIVE);
    self:startCheckTicker();
    self:checkReady();
end

--- ACP_BUFF_LOST: everything resets for the next arena.
function DeliveryController:onBuffLost()
    self:reset();
end

--- ACP_ITEMS_CHANGED: a crafted item appeared/changed — re-evaluate.
function DeliveryController:onItemsChanged()
    if (self.state == DS.ACTIVE) then
        self:checkReady();
    elseif (self.state == DS.TRADING and TradeFrame and TradeFrame:IsShown()) then
        -- Items became ready mid-trade (e.g. crafted while the window was open,
        -- including an inbound trade we took over): refresh the placement queue
        -- so they get delivered into the already-open window too.
        ACP.TradeManager:queueItems(ACP.TradePlanner:buildQueue(self.currentPartner));
    end
end

--- ACP_TRADE_COMPLETED: mark the partner (normalized to a party token — a
--- manual trade records the player NAME, which would leave the token unmarked
--- and re-offer the same teammate). Next partner → ACTIVE; none → DONE.
function DeliveryController:onTradeCompleted()
    -- Normalize the partner to a party unit token before recording it in
    -- `givenTo`: auto-trades carry the token (currentPartner), but a MANUAL
    -- trade records the player NAME (TradeManager.partnerUnit set on
    -- TRADE_SHOW). Recording a name would leave the token unmarked and the
    -- controller would offer the same teammate again.
    local partner = self.currentPartner or ACP.TradeManager:getPartner();

    if (partner and not partner:match("^party%d+$")) then
        partner = ACP.ArenaPrep:findPartyUnitByName(partner) or partner;
    end

    if (not partner) then
        partner = ACP.ArenaPrep:findPartyUnitByName(UnitName("NPC", true));
    end

    if (partner) then
        self.givenTo[partner] = true;
        ACP:debugPrint("handed items to %s", partner);
    end

    self.currentPartner = nil;
    self.retryCount = 0;

    -- The buff may have faded while the window was open (gates opened while
    -- the player was still confirming the trade manually). A completion after
    -- that must not resume trading.
    if (not ACP.ArenaPrep:isActive()) then
        self:setState(DS.IDLE);
        return;
    end

    if (self:findPartner()) then
        self:setState(DS.ACTIVE);
        self:checkReady();
    else
        self:setState(DS.DONE);
    end
end

--- ACP_TRADE_FAILED: silent retry with backoff. Only acts while TRADING — a
--- stray failure verdict after a reset must not resume trading.
function DeliveryController:onTradeFailed(reason)
    if (self.state ~= DS.TRADING) then
        ACP:debugPrint("ignoring stray trade failure: %s (state: %s)", tostring(reason), self.state);
        return;
    end

    ACP:debugPrint("trade failed: %s (attempt %d/%d)", tostring(reason), self.retryCount + 1, ACP.Settings:get("tradeRetries") or 1);

    self.currentPartner = nil;
    self:setState(DS.ACTIVE);

    self.retryCount = self.retryCount + 1;

    if (self.retryCount > (ACP.Settings:get("tradeRetries") or 1)) then
        self.retryCount = 0;
        return; -- silent give-up until the next event
    end

    local backoff = ACP.Data.Constants.RETRY_BACKOFF[self.retryCount] or 8;

    ACP.Utils.Timers:after("TradeRetry", backoff, function()
        if (self.state == DS.ACTIVE) then
            self:checkReady();
        end
    end);
end

--- PLAYER_REGEN_DISABLED: combat cancels pending attempts; an already-open
--- window is left untouched.
function DeliveryController:onCombatStart()
    ACP.Utils.Timers:cancel("TradeDelay");
    ACP.Utils.Timers:cancel("TradeRetry");
end

--- PLAYER_REGEN_ENABLED: combat over — retry if the buff is still active.
function DeliveryController:onCombatEnd()
    if (self.state == DS.ACTIVE and ACP.ArenaPrep:isActive()) then
        self:checkReady();
    end
end

function DeliveryController:_init()
    if (not ACP.StateMachine:initOnce(self)) then
        return;
    end

    ACP.Events:register("DC.BUFF_GAINED", "ACP_BUFF_GAINED", function()
        self:onBuffGained();
    end);

    ACP.Events:register("DC.BUFF_LOST", "ACP_BUFF_LOST", function()
        self:onBuffLost();
    end);

    ACP.Events:register("DC.ITEMS_CHANGED", "ACP_ITEMS_CHANGED", function()
        self:onItemsChanged();
    end);

    ACP.Events:register("DC.TRADE_COMPLETED", "ACP_TRADE_COMPLETED", function()
        self:onTradeCompleted();
    end);

    -- The trade window opened → take over the window (credit the partner, stop
    -- polling / scheduling) and fill the low-level placement queue.
    ACP.Events:register("DC.TRADE_OPENED", "ACP_TRADE_OPENED", function(partner)
        self:onTradeOpened(partner);
    end);

    ACP.Events:register("DC.TRADE_FAILED", "ACP_TRADE_FAILED", function(reason)
        self:onTradeFailed(reason);
    end);

    ACP.Events:register("DC.COMBAT_START", "PLAYER_REGEN_DISABLED", function()
        self:onCombatStart();
    end);

    ACP.Events:register("DC.COMBAT_END", "PLAYER_REGEN_ENABLED", function()
        self:onCombatEnd();
    end);

    -- Party roster changes (e.g. converted to raid when the arena loads) —
    -- the bracket may resolve after the buff gain, so re-evaluate.
    ACP.Events:register("DC.GROUP_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE", function()
        if (self.state == DS.ACTIVE) then
            self:checkReady();
        end
    end);
end

return ACP;
