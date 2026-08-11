-- ArenaChillPrep — Classes/ArenaPrep
-- Answers one question: is the Arena Preparation buff (spell 32727) active
-- right now? Plus: which bracket are we in, and how long until the gates open.
--
-- Buff lookup (verified on 2.5.5): C_UnitAuras.GetPlayerAuraBySpellID(32727)
-- returns an aura object. Do NOT use
-- UnitBuff("player", name) — crashes on 2.5.5 (deprecated wrapper proxies to
-- C_UnitAuras.GetBuffDataByIndex which only accepts a numeric index) — nor
-- UnitAura(unit, i, filter), which returns shifted legacy positions with no
-- spellID/expirationTime.
-- Gate countdown (verified on 2.5.5): the prep buff aura reports duration=0,
-- so the countdown comes from CHAT_MSG_BG_SYSTEM_NEUTRAL + the localized
-- message map (see .github/CONTEXT.md gotcha #12 and
-- ACP.Data.Constants.ARENA_COUNTDOWN_MESSAGES).

---@type ACP
local _, ACP = ...;

local GetTime = _G.GetTime;
local IsInInstance = _G.IsInInstance;
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID or nil;
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex or nil;

---@class ArenaPrep
local ArenaPrep = {
    _initialized = false,

    ---@type boolean
    buffActive = false,

    ---@type number|nil
    buffExpirationTime = nil,

    ---@type number|nil
    countdownEndTime = nil,

    ---@type string|nil
    bracket = nil,
};

---@type ArenaPrep
ACP.ArenaPrep = ArenaPrep;

--- Maximum aura index scanned by the spellID fallback lookup.
local MAX_AURA_INDEX = 40;

--- Scan the player's auras for the prep buff.
---@return boolean active
---@return number|nil expirationTime
function ArenaPrep:scanBuff()
    local spellID = ACP.Data.Constants.ARENA_PREP_SPELL_ID;
    local unit = "player";

    -- Primary: direct lookup by spellID.
    if (GetPlayerAuraBySpellID) then
        local aura = GetPlayerAuraBySpellID(spellID);

        if (aura) then
            return true, aura.expirationTime;
        end

        return false, nil;
    end

    -- Fallback: iterate the object-based aura API by index.
    if (GetAuraDataByIndex) then
        for i = 1, MAX_AURA_INDEX do
            local aura = GetAuraDataByIndex(unit, i, "HELPFUL");

            if (not aura) then
                break;
            end

            if (aura.spellId == spellID) then
                return true, aura.expirationTime;
            end
        end

        return false, nil;
    end

    return false, nil;
end

--- Forced re-check of the buff state. Fires ACP_BUFF_GAINED / ACP_BUFF_LOST on
--- state changes. Called on UNIT_AURA ("player"), PLAYER_ENTERING_WORLD, on the
--- 1 s safety ticker while active, and once at addon load (/reload-in-arena).
function ArenaPrep:checkNow()
    local active, expirationTime = self:scanBuff();

    if (active) then
        self.buffExpirationTime = expirationTime;
        self.bracket = self:computeBracket();
        self:startTicker();

        -- Seed the gate countdown until the first countdown message arrives.
        -- On 2.5.5 the prep buff aura reports duration=0, so the aura cannot
        -- measure it — see .github/CONTEXT.md gotcha #12.
        if (not self.countdownEndTime) then
            self.countdownEndTime = GetTime() + ACP.Data.Constants.ARENA_PREP_SECONDS;
        end
    else
        self.buffExpirationTime = nil;
        self.bracket = nil;
        self.countdownEndTime = nil;
        self:stopTicker();
    end

    if (active ~= self.buffActive) then
        self.buffActive = active;

        if (active) then
            ACP:debugPrint("prep buff gained (bracket: %s)", self.bracket or "unknown");
            ACP.Events:fire("ACP_BUFF_GAINED");
        else
            ACP:debugPrint("prep buff lost");
            ACP.Events:fire("ACP_BUFF_LOST");
        end
    end
end

--- Handle an arena countdown system message (CHAT_MSG_BG_SYSTEM_NEUTRAL).
--- Matches the localized map and sets the gate-open timestamp precisely.
---@param msg string
function ArenaPrep:handleCountdownMessage(msg)
    local seconds = ACP.Data.Constants.ARENA_COUNTDOWN_MESSAGES[msg];

    if (seconds == nil) then
        return;
    end

    self.countdownEndTime = GetTime() + seconds;
    ACP:debugPrint("arena countdown message: %d s remaining", seconds);
end

--- Whether the arena preparation buff is active right now.
---@return boolean
function ArenaPrep:isActive()
    return self.buffActive;
end

--- Seconds until the gates open, or nil when the countdown is unknown (the
--- gate check then does not block). Clamped at 0 so an expired countdown never
--- passes a gate safety comparison.
--- Priority: countdown messages (verified working on 2.5.5); fallback: aura
--- expirationTime (reports 0 for the prep buff on 2.5.5 — usually unavailable).
---@return number|nil
function ArenaPrep:getRemainingTime()
    local now = GetTime();

    if (self.countdownEndTime) then
        local remaining = self.countdownEndTime - now;

        return remaining > 0 and remaining or 0;
    end

    if (self.buffExpirationTime) then
        local remaining = self.buffExpirationTime - now;

        return remaining > 0 and remaining or 0;
    end

    return nil;
end

--- Current arena bracket ("2v2"/"3v3"/"5v5"), or nil outside an arena or in an
--- unknown party size.
---@return string|nil
function ArenaPrep:getBracket()
    return self.bracket;
end

--- Whether the player is inside an arena instance.
---@return boolean
function ArenaPrep:isInArena()
    local inInstance, instanceType = IsInInstance();

    return inInstance and instanceType == "arena";
end

--- Current instance type ("arena"/"party"/"raid"/"pvp"/"none"/...).
---@return string
function ArenaPrep:getInstanceType()
    local _, instanceType = IsInInstance();

    return instanceType or "none";
end

--- Current number of party members (0 when solo or the API is unavailable).
--- TBC-era name: GetNumPartyMembers; GetNumSubgroupMembers only exists from
--- 5.0.4+. Shared by bracket detection, partner detection and /acp status.
---@return number
function ArenaPrep:getPartySize()
    local getNumPartyMembers = _G.GetNumPartyMembers or _G.GetNumSubgroupMembers;

    return (getNumPartyMembers and getNumPartyMembers()) or 0;
end

--- Resolve a player name to a party unit token ("party1".."partyN").
--- Used to normalize a partner recorded by name (manual trades) back to the
--- token the controller keys `givenTo` by.
---@param name string|nil
---@return string|nil
function ArenaPrep:findPartyUnitByName(name)
    if (not name) then
        return nil;
    end

    local count = self:getPartySize();

    for i = 1, count do
        local unit = "party" .. i;

        if (UnitName(unit) == name) then
            return unit;
        end
    end

    return nil;
end

--- Determine the arena bracket from the party size (source of truth — the
--- group is locked once inside the arena), cross-checked with
--- GetNumArenaOpponents when available (2.5.1+, present on 20506).
---@return string|nil
function ArenaPrep:computeBracket()
    if (not self:isInArena()) then
        return nil;
    end

    local partySize = self:getPartySize() + 1;

    local bracket = ACP.Data.Constants.BRACKET_BY_SIZE[partySize];

    -- Sanity check only: returns 1/2/4 and may be 0 briefly at arena load,
    -- so it never overrides the party size — log a mismatch if any.
    if (bracket and _G.GetNumArenaOpponents) then
        local opponents = _G.GetNumArenaOpponents();

        if (opponents and opponents > 0 and opponents + 1 ~= partySize) then
            ACP:debugPrint("bracket mismatch: partySize %d vs opponents %d", partySize, opponents);
        end
    end

    return bracket;
end

--- 1 s safety ticker while the buff is active: UNIT_AURA on TBC doesn't always
--- fire when the buff fades — a known quirk — so the ticker catches the fade.
function ArenaPrep:startTicker()
    ACP.Utils.Timers:interval("ArenaPrepTick", ACP.Data.Constants.BUFF_CHECK_TICK, function()
        self:checkNow();
    end);
end

function ArenaPrep:stopTicker()
    ACP.Utils.Timers:cancel("ArenaPrepTick");
end

function ArenaPrep:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    -- UNIT_AURA fires for every unit whose auras change — filter to "player".
    ACP.Events:register("ArenaPrep.UNIT_AURA", "UNIT_AURA", function(unit)
        if (unit == "player") then
            self:checkNow();
        end
    end);

    -- Fires on login, zone change and /reload — a cheap full re-check.
    ACP.Events:register("ArenaPrep.PLAYER_ENTERING_WORLD", "PLAYER_ENTERING_WORLD", function()
        self:checkNow();
    end);

    -- The arena countdown messages arrive here (verified on 2.5.5 — the prep
    -- buff aura reports duration=0, so chat messages are the countdown source).
    ACP.Events:register("ArenaPrep.CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_NEUTRAL", function(msg)
        self:handleCountdownMessage(msg);
    end);
end

return ACP;
