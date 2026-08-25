-- ArenaChillPrep — Classes/PetAbilityCaster
-- Pet-ability steps: macro baking, pressed-but-unverified poll, PostClick
-- handling, arming during a player cast. Operates on the engine (first arg).

---@type ACP
local _, ACP = ...;

local tostring = _G.tostring;

local WS = ACP.Data.Constants.WORKFLOW_STATE;

local Reason = ACP.Data.Constants.WORKFLOW_REASON;

---@class PetAbilityCaster
local PetAbilityCaster = {};

---@type PetAbilityCaster
ACP.PetAbilityCaster = PetAbilityCaster;

--- "/cast [pet:<type>,@unit] <ability>": [@unit] is the 20506-reliable target
--- form; [pet:<type>] makes the press a no-op when that pet is not out.
---@param engine WorkflowEngine
---@param step table
---@return string
function PetAbilityCaster:petMacroText(engine, step)
    local name = engine:spellName(step.spellID);
    local target = (step.target and step.target ~= "player") and step.target or "player";
    local entry = engine:getCatalogEntry(step.spellID);
    local petCond = (entry and entry.pet) and ("pet:" .. tostring(entry.pet) .. ",") or "";

    return ("/cast [%s@%s] %s"):format(petCond, target, name);
end

--- A press is NOT completion: the client silently swallows a pet ability
--- pressed early in the player's cast. Verified by effect: the ability's buff
--- on the target (by name) or the Voidwalker gone while the cast runs.
---@param engine WorkflowEngine
---@param step table
---@return boolean
function PetAbilityCaster:isPetAbilityApplied(engine, step)
    if (engine:hasBuff(step.target or "player", engine:spellName(step.spellID))) then
        return true;
    end

    local entry = engine:getCatalogEntry(step.spellID);

    if (entry and entry.pet == "voidwalker" and engine.waitingForCast
        and _G.UnitExists and not _G.UnitExists("pet")) then
        return true;
    end

    return false;
end

---@param engine WorkflowEngine
function PetAbilityCaster:armPetVerify(engine)
    ACP.Utils.Timers:interval("WorkflowPetVerify", 0.1, function()
        if (engine.state ~= WS.RUNNING) then
            return;
        end

        local def = engine:getDefinition(engine.currentSlot);
        local step;

        if (engine.pendingPetStep) then
            step = def and def.steps[engine.pendingPetStep];
        elseif (engine.waitingForPet) then
            step = def and def.steps[engine.stepIndex];
        end

        if (not step or step.type ~= ACP.Data.Constants.WORKFLOW_STEP_PET or not engine:isPetAbilityApplied(step)) then
            return;
        end

        ACP.Utils.Timers:cancel("WorkflowPetVerify");

        if (engine.pendingPetStep) then
            ACP:debugPrint("workflow pet ability verified: %s (step %d)", engine:spellName(step.spellID), engine.pendingPetStep);
            engine.petStepDone = true;
            engine.pendingPetStep = nil;
            engine.waitingForPet = false;
            engine.waitingForKey = false;
            engine:clearKeyCast();
        else
            ACP:debugPrint("workflow pet ability verified: %s (step %d)", engine:spellName(step.spellID), engine.stepIndex);
            engine.waitingForPet = false;
            engine.waitingForKey = false;
            engine:clearKeyCast();
            engine:advance();
        end
    end);
end

---@param engine WorkflowEngine
---@param step table
function PetAbilityCaster:petAbility(engine, step)
    local name = engine:spellName(step.spellID);
    local macro = self:petMacroText(engine, step);

    engine:setCastAttribute("type", "macro");
    engine:setCastAttribute("macrotext", macro);
    engine:setCastAttribute("unit", nil);

    ACP:debugPrint("workflow pet macro: %s", macro);

    engine.waitingForPet = true;
    engine.waitingForKey = true;

    local key = engine:resolveCastKey(engine.currentSlot);

    if (not key) then
        if (engine.debugBypass) then
            ACP:print(ACP.L.workflow.testNoKey, engine.currentSlot);
        end
        engine.waitingForPet = false;
        engine.waitingForKey = false;
        engine:pause(Reason.NoHotkey);
        return;
    end

    if (engine.debugBypass) then
        ACP:print(ACP.L.workflow.pressKey, key, name);
    else
        ACP:debugPrint(ACP.L.workflow.pressKey, key, name);
    end
end

---@param engine WorkflowEngine
---@param slot number|nil
function PetAbilityCaster:onSecurePress(engine, slot)
    local C = ACP.Data.Constants;
    if (engine.state ~= WS.RUNNING) then
        return;
    end

    if (slot and engine.currentSlot and slot ~= engine.currentSlot) then
        return;
    end

    local def = engine:getDefinition(engine.currentSlot);

    if (engine.pendingPetStep) then
        local petStep = def and def.steps[engine.pendingPetStep];

        if (petStep and petStep.type == C.WORKFLOW_STEP_PET) then
            local name = engine:spellName(petStep.spellID);
            ACP:debugPrint("workflow pet ability pressed during cast: %s (step %d) petExists=%s petGUID=%s", name, engine.pendingPetStep, tostring(_G.UnitExists and _G.UnitExists("pet")), tostring(_G.UnitGUID and _G.UnitGUID("pet")));

            if (engine:isPetAbilityApplied(petStep)) then
                ACP:debugPrint("workflow pet ability verified: %s (step %d)", name, engine.pendingPetStep);
                engine.petStepDone = true;
                engine.pendingPetStep = nil;
                engine.waitingForPet = false;
                engine.waitingForKey = false;
                ACP.Utils.Timers:cancel("WorkflowPetVerify");
                engine:clearKeyCast();
            else
                ACP:debugPrint("workflow pet ability NOT applied yet: %s (step %d) — keep pressing", name, engine.pendingPetStep);
                engine:armPetVerify();
            end

            return;
        end
    end

    if (engine.waitingForPet) then
        local step = def and def.steps[engine.stepIndex];

        if (step and step.type == C.WORKFLOW_STEP_PET and engine:isPetAbilityApplied(step)) then
            ACP:debugPrint("workflow pet ability verified: %s (step %d)", engine:spellName(step.spellID), engine.stepIndex);
            engine.waitingForPet = false;
            engine.waitingForKey = false;
            ACP.Utils.Timers:cancel("WorkflowPetVerify");
            engine:clearKeyCast();
            engine:advance();
        else
            ACP:debugPrint("workflow pet ability NOT applied yet: %s (step %d) — keep pressing", step and engine:spellName(step.spellID) or "?", engine.stepIndex);
            engine:armPetVerify();
        end
    end
end

return ACP;
