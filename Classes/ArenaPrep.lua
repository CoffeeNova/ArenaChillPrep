-- ArenaChillPrep — Classes/ArenaPrep
-- Prep buff (32727) detection, bracket detection, gate countdown.
--
-- Buff lookup: C_UnitAuras.GetPlayerAuraBySpellID only — UnitBuff("player",
-- name) crashes on 2.5.5 and UnitAura returns shifted legacy positions.
-- Countdown: the aura reports duration=0, so the countdown comes from
-- CHAT_MSG_BG_SYSTEM_NEUTRAL + ARENA_COUNTDOWN_MESSAGES.

---@type ACP
local _, ACP = ...;

local GetTime = _G.GetTime;
local IsInInstance = _G.IsInInstance;
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID or nil;

---@class ArenaPrep
local ArenaPrep = {
    _initialized = false,

    ---@type boolean
    buffActive = false,

    ---@type number|nil
    countdownEndTime = nil,

    ---@type string|nil
    bracket = nil,
};

---@type ArenaPrep
ACP.ArenaPrep = ArenaPrep;

---@return boolean active
function ArenaPrep:scanBuff()
    local aura = GetPlayerAuraBySpellID(ACP.Data.Constants.ARENA_PREP_SPELL_ID);

    return aura ~= nil;
end

--- Forced re-check; fires ACP_BUFF_GAINED / ACP_BUFF_LOST on state changes.
function ArenaPrep:checkNow()
    local active = self:scanBuff();

    if (active) then
        self.bracket = self:computeBracket();
        self:startTicker();

        -- Seed the countdown until the first countdown message arrives.
        if (not self.countdownEndTime) then
            self.countdownEndTime = GetTime() + ACP.Data.Constants.ARENA_PREP_SECONDS;
        end
    else
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

---@param msg string
function ArenaPrep:handleCountdownMessage(msg)
    local seconds = ACP.Data.Constants.ARENA_COUNTDOWN_MESSAGES[msg];

    if (seconds == nil) then
        return;
    end

    self.countdownEndTime = GetTime() + seconds;
    ACP:debugPrint("arena countdown message: %d s remaining", seconds);
end

---@return boolean
function ArenaPrep:isActive()
    return self.buffActive;
end

--- Seconds until the gates open (clamped at 0), or nil when unknown — the
--- gate check then does not block.
---@return number|nil
function ArenaPrep:getRemainingTime()
    local now = GetTime();

    if (self.countdownEndTime) then
        local remaining = self.countdownEndTime - now;

        return remaining > 0 and remaining or 0;
    end

    return nil;
end

---@return string|nil
function ArenaPrep:getBracket()
    return self.bracket;
end

---@return boolean
function ArenaPrep:isInArena()
    local inInstance, instanceType = IsInInstance();

    return inInstance and instanceType == "arena";
end

---@return string
function ArenaPrep:getInstanceType()
    local _, instanceType = IsInInstance();

    return instanceType or "none";
end

--- Party members (0 when solo). TBC-era name: GetNumPartyMembers.
---@return number
function ArenaPrep:getPartySize()
    local getNumPartyMembers = _G.GetNumPartyMembers or _G.GetNumSubgroupMembers;

    return (getNumPartyMembers and getNumPartyMembers()) or 0;
end

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

--- Bracket from the party size (the group is locked once inside).
---@return string|nil
function ArenaPrep:computeBracket()
    if (not self:isInArena()) then
        return nil;
    end

    local partySize = self:getPartySize() + 1;

    local bracket = ACP.Data.Constants.BRACKET_BY_SIZE[partySize];

    -- Sanity check only; opponents may be 0 briefly at arena load.
    if (bracket and _G.GetNumArenaOpponents) then
        local opponents = _G.GetNumArenaOpponents();

        if (opponents and opponents > 0 and opponents + 1 ~= partySize) then
            ACP:debugPrint("bracket mismatch: partySize %d vs opponents %d", partySize, opponents);
        end
    end

    return bracket;
end

-- 1 s safety ticker while the buff is active (UNIT_AURA does not always fire
-- when the buff fades on TBC).
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

    ACP.Events:register("ArenaPrep.UNIT_AURA", "UNIT_AURA", function(unit)
        if (unit == "player") then
            self:checkNow();
        end
    end);

    ACP.Events:register("ArenaPrep.PLAYER_ENTERING_WORLD", "PLAYER_ENTERING_WORLD", function()
        self:checkNow();
    end);

    ACP.Events:register("ArenaPrep.CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_NEUTRAL", function(msg)
        self:handleCountdownMessage(msg);
    end);
end

return ACP;
