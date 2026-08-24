-- ArenaChillPrep — Classes/Preconditions
-- Shared readiness checks for both orchestrators (W5): DeliveryController
-- (trading) and WorkflowEngine (casting) duplicated four of five gates with
-- divergent combat APIs. This module is the single canonical source; each
-- orchestrator keeps only its action-specific gates.
--
-- COMBAT API decision (ADR, plan open question 4): the two APIs test
-- DIFFERENT things — UnitAffectingCombat is the combat-state signal (you
-- cannot trade in combat), InCombatLockdown is the secure-frame protection
-- signal (you cannot cast in lockdown). BOTH are kept, exposed separately:
--   notInCombat()   -> trading (DeliveryController)
--   notInLockdown() -> casting (WorkflowEngine)

---@type ACP
local _, ACP = ...;

local UnitAffectingCombat = _G.UnitAffectingCombat;
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost;
local InCombatLockdown = _G.InCombatLockdown;

---@class Preconditions
local Preconditions = {};

---@type Preconditions
ACP.Preconditions = Preconditions;

--- Master switch enabled.
---@return boolean
function Preconditions:enabled()
    return not not ACP.Settings:get("enabled");
end

--- The player is inside an arena instance.
---@return boolean
function Preconditions:inArena()
    return ACP.ArenaPrep:isInArena() == true;
end

--- The arena preparation buff is active.
---@return boolean
function Preconditions:buffActive()
    return ACP.ArenaPrep:isActive() == true;
end

--- Not in combat (trading precondition — combat state).
---@return boolean
function Preconditions:notInCombat()
    return not UnitAffectingCombat("player");
end

--- Not in secure-frame lockdown (casting precondition).
---@return boolean
function Preconditions:notInLockdown()
    return not (InCombatLockdown and InCombatLockdown());
end

--- The player is alive.
---@return boolean
function Preconditions:notDead()
    return not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"));
end

--- Far enough from the gates opening (gate safety threshold).
---@return boolean
function Preconditions:gateSafetyOk()
    local gateSafety = ACP.Settings:get("gateSafetySeconds") or ACP.Data.Constants.GATE_SAFETY_DEFAULT;
    local remaining = ACP.ArenaPrep:getRemainingTime();

    return remaining == nil or remaining >= gateSafety;
end

return ACP;
