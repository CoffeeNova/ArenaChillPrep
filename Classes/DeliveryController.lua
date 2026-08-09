-- ArenaChillPrep — Classes/DeliveryController
-- Orchestrator — the only module that makes decisions.
-- State machine: IDLE -> ACTIVE -> TRADING -> DONE (see .github/ARCHITECTURE.md 2.5).
--
-- Responsibilities:
--   - bracket gate on ACP_BUFF_GAINED (Settings "brackets.<bracket>", 2v2 default);
--   - runtime-only `givenTo` set (reset on ACP_BUFF_LOST, never saved);
--   - gate safety: start trades only while getRemainingTime() >= gateSafetySeconds;
--   - partner detection: first non-self party member (party1..N — arena
--     teammates are always party slots, no manual selection);
--   - "ready" decision: an enabled item category has count >= setting.count;
--   - tradeDelay pause before opening the trade;
--   - combat deferral via PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local UnitExists = _G.UnitExists;
local UnitIsUnit = _G.UnitIsUnit;
local UnitAffectingCombat = _G.UnitAffectingCombat;
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost;

---@class DeliveryController
local DeliveryController = {
    _initialized = false,

    --- "IDLE" | "ACTIVE" | "TRADING" | "DONE"
    state = "IDLE",

    --- Runtime-only set of partners already served this prep (unit tokens).
    --- Reset on ACP_BUFF_LOST; never persisted to ArenaChillPrepDB.
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
    if (self.state ~= newState) then
        ACP:debugPrint("state: %s -> %s", self.state, newState);
        self.state = newState;
    end
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
    self:setState("IDLE");
end

--- The set of item categories the current class can pass (from the catalog).
---@return table
function DeliveryController:getCategories()
    local classItems = ACP.Data.Items.classItems;
    local englishClass = select(2, UnitClass("player"));

    return classItems[englishClass] or {};
end

--- Whether the selected ranks of an enabled category are ALL ready.
--- Ranks are grouped by their catalog `rank`: paired IDs (19012/19013 = Major)
--- count as ONE rank — the sum of their counts must reach `setting.count`.
---@param category string  plural catalog key ("healthstones")
---@param setting table
---@return boolean
function DeliveryController:categoryReady(category, setting)
    local needed = setting.count or 1;
    local catalog = ACP.Data.Items[category] or {};
    local readyByRank = {}; -- rank -> boolean

    for itemID, enabled in pairs(setting.ranks or {}) do
        if (enabled) then
            local record = catalog[itemID];

            if (record) then
                local rank = record.rank;

                if (not readyByRank[rank]) then
                    local rankCount = 0;

                    -- Sum counts of ALL selected IDs of this rank.
                    for id, en in pairs(setting.ranks or {}) do
                        if (en and catalog[id] and catalog[id].rank == rank) then
                            rankCount = rankCount + ACP.Inventory:getCount(id);
                        end
                    end

                    ACP:debugPrint("itemsReady: category=%s rank=%d count=%d needed=%d",
                        category, rank, rankCount, needed);

                    readyByRank[rank] = rankCount >= needed;
                end
            end
        end
    end

    -- Every selected rank must be ready (no false entries).
    local anySelected = false;

    for _, ready in pairs(readyByRank) do
        anySelected = true;

        if (not ready) then
            return false;
        end
    end

    return anySelected;
end

--- Whether an enabled item category has every selected rank ready.
--- The settings key is the SINGULAR category name (items.healthstone) while
--- the catalog key is the PLURAL (healthstones) — map plural → singular.
---@return boolean
function DeliveryController:itemsReady()
    local categories = self:getCategories();

    for _, category in ipairs(categories) do
        -- "healthstones" -> "healthstone"
        local settingsKey = category:sub(1, -2);
        local setting = ACP.Settings:get("items." .. settingsKey);

        if (setting and setting.enabled) then
            if (self:categoryReady(category, setting)) then
                return true;
            end
        else
            ACP:debugPrint("itemsReady: category=%s setting %s missing or disabled",
                category, tostring(settingsKey));
        end
    end

    return false;
end

--- First eligible partner: the first party member who isn't the player and
--- hasn't already received items this prep. Arena teammates are always
--- party1..partyN, so no manual slot is needed.
---@return string|nil
function DeliveryController:findPartner()
    local getNumPartyMembers = _G.GetNumPartyMembers or _G.GetNumSubgroupMembers;
    local count = (getNumPartyMembers and getNumPartyMembers()) or 0;

    for i = 1, count do
        local unit = "party" .. i;

        if (UnitExists(unit) and not UnitIsUnit(unit, "player") and not self.givenTo[unit]) then
            return unit;
        end
    end

    return nil;
end

--- Are we allowed to start a new trade right now?
---@return boolean
function DeliveryController:canStartTrade()
    if (not ACP.Settings:get("enabled")) then
        ACP:debugPrint("canStartTrade: disabled");
        return false;
    end

    if (not ACP.ArenaPrep:isInArena()) then
        ACP:debugPrint("canStartTrade: not in arena");
        return false;
    end

    if (UnitAffectingCombat("player")) then
        ACP:debugPrint("canStartTrade: in combat");
        return false;
    end

    -- A dead player cannot initiate a trade; retry after revival
    -- (PLAYER_REGEN_ENABLED / the ACTIVE ticker) if the buff is still active.
    if (UnitIsDeadOrGhost("player")) then
        ACP:debugPrint("canStartTrade: player dead");
        return false;
    end

    -- Gate safety: never start a trade too close to the gates opening.
    local remaining = ACP.ArenaPrep:getRemainingTime();

    if (remaining ~= nil and remaining < (ACP.Settings:get("gateSafetySeconds") or 15)) then
        ACP:print("skipping trade: %0.1f s left, below gateSafetySeconds (%s)",
            remaining, tostring(ACP.Settings:get("gateSafetySeconds") or 15));
        return false;
    end

    ACP:debugPrint("canStartTrade: ok");
    return true;
end

--- The heart of ACTIVE: if items are ready and a partner exists — schedule
--- the trade after `tradeDelay`.
function DeliveryController:checkReady()
    if (self.state ~= "ACTIVE") then
        return;
    end

    -- Bracket gate is enforced here too (the bracket may resolve later than
    -- the buff gain — see onBuffGained). If it resolves to a disabled bracket,
    -- drop out of ACTIVE entirely.
    local bracket = ACP.ArenaPrep:getBracket();

    if (bracket and not ACP.Settings:get("brackets." .. bracket)) then
        ACP:print("bracket %s disabled, skipping (enable it in settings)", bracket);
        self:setState("IDLE");
        return;
    end

    if (not self:canStartTrade()) then
        return;
    end

    if (not self:itemsReady()) then
        return;
    end

    local partner = self:findPartner();

    if (not partner) then
        local givenCount = 0;

        for _ in pairs(self.givenTo) do
            givenCount = givenCount + 1;
        end

        if (givenCount > 0) then
            ACP:debugPrint("no eligible partner (givenTo: %d)", givenCount);
            self:setState("DONE");
        else
            ACP:print("items ready but no partner found (are you in a group?)");
        end

        return;
    end

    local tradeDelay = ACP.Settings:get("tradeDelay") or 1.5;
    ACP:print("scheduling trade with %s in %.1f s", partner, tradeDelay);

    ACP.Utils.Timers:after("TradeDelay", tradeDelay, function()
        -- Re-check before actually sending the request.
        if (self.state ~= "ACTIVE") then
            return;
        end

        if (not self:canStartTrade()) then
            return;
        end

        if (not self:itemsReady()) then
            return;
        end

        self.currentPartner = partner;
        self:setState("TRADING");
        ACP.TradeManager:startTrade(partner);

        -- One-shot open timeout: InitiateTrade can fail silently (out of
        -- range, partner offline/dead) without firing TRADE_SHOW or
        -- TRADE_CLOSED. Without this the controller would stay TRADING
        -- forever. ACP_TRADE_OPENED (window shown) cancels it.
        ACP.Utils.Timers:after("TradeOpen", ACP.Data.Constants.TRADE_OPEN_TIMEOUT, function()
            if (self.state ~= "TRADING") then
                return; -- already resolved (window opened / trade completed)
            end

            ACP:debugPrint("trade window did not open within %.1f s", ACP.Data.Constants.TRADE_OPEN_TIMEOUT);
            ACP.TradeManager:cancel();
            self:onTradeFailed("timeout");
        end);
    end);
end

--- Every-tick readiness poll while in ACTIVE. Safety net for events that may
--- be missed on 2.5.5 (e.g. BAG_UPDATE on crafted healthstones). Uses a
--- one-shot self-rescheduling ticker: while state stays ACTIVE it re-checks;
--- once a trade is scheduled/started it stops polling.
function DeliveryController:startCheckTicker()
    ACP.Utils.Timers:interval("DeliveryCheck", 0.5, function()
        -- Only poll while ACTIVE and nothing pending.
        if (self.state ~= "ACTIVE") then
            ACP.Utils.Timers:cancel("DeliveryCheck");
            return;
        end

        if (ACP.Utils.Timers.Handles["TradeDelay"]) then
            return; -- a trade is already scheduled, wait for it
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
        self:setState("ACTIVE");
        self:startCheckTicker();
        return;
    end

    if (not ACP.Settings:get("brackets." .. bracket)) then
        ACP:print("bracket %s disabled, skipping (enable it in settings)", bracket);
        self:setState("IDLE");
        return;
    end

    ACP:debugPrint("bracket %s enabled, prep active", bracket);
    self:setState("ACTIVE");
    self:startCheckTicker();
    self:checkReady();
end

--- ACP_BUFF_LOST: everything resets for the next arena.
function DeliveryController:onBuffLost()
    self:reset();
end

--- ACP_ITEMS_CHANGED: a crafted item appeared/changed — re-evaluate.
function DeliveryController:onItemsChanged()
    if (self.state == "ACTIVE") then
        self:checkReady();
    end
end

--- ACP_TRADE_COMPLETED: mark the partner, decide what's next.
--- Handles both auto-initiated trades (currentPartner) and manual trades the
--- player completed himself (TradeManager.partnerUnit recorded on TRADE_SHOW).
--- While an unserved partner remains, the controller returns to ACTIVE — even
--- if no items are left right now: the next crafted item (ACP_ITEMS_CHANGED)
--- goes to the next partner (3v3/5v5). Only when every partner has been
--- served does it go DONE.
function DeliveryController:onTradeCompleted()
    local partner = self.currentPartner or ACP.TradeManager.partnerUnit;

    if (partner) then
        self.givenTo[partner] = true;
        ACP:print("handed items to %s", partner);
    end

    self.currentPartner = nil;
    self.retryCount = 0;

    -- The buff may have faded while the window was open (gates opened, e.g.
    -- with autoAccept off). A completion after that must not resume trading.
    if (not ACP.ArenaPrep:isActive()) then
        self:setState("IDLE");
        return;
    end

    if (self:findPartner()) then
        self:setState("ACTIVE");
        self:checkReady();
    else
        self:setState("DONE");
    end
end

--- ACP_TRADE_FAILED: silent retry with backoff, up to MAX_TRADE_RETRIES.
--- Only acts while TRADING: a stray failure verdict arriving after a reset
--- (e.g. the window was closed after the buff faded / gates opened) must not
--- return the controller to ACTIVE and risk a trade after the gates open.
function DeliveryController:onTradeFailed(reason)
    if (self.state ~= "TRADING") then
        ACP:debugPrint("ignoring stray trade failure: %s (state: %s)", tostring(reason), self.state);
        return;
    end

    ACP:debugPrint("trade failed: %s (attempt %d/%d)", tostring(reason), self.retryCount + 1, ACP.Data.Constants.MAX_TRADE_RETRIES);

    self.currentPartner = nil;
    self:setState("ACTIVE");

    self.retryCount = self.retryCount + 1;

    if (self.retryCount > ACP.Data.Constants.MAX_TRADE_RETRIES) then
        self.retryCount = 0;
        return; -- silent give-up until the next event
    end

    local backoff = ACP.Data.Constants.RETRY_BACKOFF[self.retryCount] or 8;

    ACP.Utils.Timers:after("TradeRetry", backoff, function()
        if (self.state == "ACTIVE") then
            self:checkReady();
        end
    end);
end

--- PLAYER_REGEN_DISABLED: combat cancels pending attempts; an already-open
--- window is left untouched.
function DeliveryController:onCombatStart()
    ACP.Utils.Timers:cancel("TradeDelay");
    ACP.Utils.Timers:cancel("TradeRetry");

    if (self.state ~= "TRADING") then
        self:setState("ACTIVE");
    end
end

--- PLAYER_REGEN_ENABLED: combat over — retry if the buff is still active.
function DeliveryController:onCombatEnd()
    if (self.state == "ACTIVE" and ACP.ArenaPrep:isActive()) then
        self:checkReady();
    end
end

function DeliveryController:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

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

    -- The trade window opened → cancel the one-shot open timeout.
    ACP.Events:register("DC.TRADE_OPENED", "ACP_TRADE_OPENED", function()
        ACP.Utils.Timers:cancel("TradeOpen");
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
        if (self.state == "ACTIVE") then
            self:checkReady();
        end
    end);
end

return ACP;
