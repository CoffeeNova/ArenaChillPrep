-- ArenaChillPrep — Classes/Preconditions
-- Shared readiness gates: notInCombat (trading) vs notInLockdown (casting) —
-- the two combat APIs test different things, both are kept.

---@type ACP
local _, ACP = ...;

local UnitAffectingCombat = _G.UnitAffectingCombat;
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost;
local InCombatLockdown = _G.InCombatLockdown;

---@class Preconditions
local Preconditions = {};

---@type Preconditions
ACP.Preconditions = Preconditions;

---@return boolean
function Preconditions:enabled()
    return not not ACP.Settings:get("enabled");
end

---@return boolean
function Preconditions:inArena()
    return ACP.ArenaPrep:isInArena() == true;
end

---@return boolean
function Preconditions:buffActive()
    return ACP.ArenaPrep:isActive() == true;
end

---@return boolean
function Preconditions:notInCombat()
    return not UnitAffectingCombat("player");
end

---@return boolean
function Preconditions:notInLockdown()
    return not (InCombatLockdown and InCombatLockdown());
end

---@return boolean
function Preconditions:notDead()
    return not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"));
end

---@return boolean
function Preconditions:gateSafetyOk()
    local gateSafety = ACP.Settings:get("gateSafetySeconds") or ACP.Data.Constants.GATE_SAFETY_DEFAULT;
    local remaining = ACP.ArenaPrep:getRemainingTime();

    return remaining == nil or remaining >= gateSafety;
end

return ACP;
