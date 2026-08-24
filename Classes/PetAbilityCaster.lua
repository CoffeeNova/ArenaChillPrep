-- ArenaChillPrep — Classes/PetAbilityCaster
-- Pet-ability step execution, extracted from WorkflowEngine (refactor
-- Phase 5): pet macro baking, the pressed-but-unverified poll, the
-- PostClick (onSecurePress) handling and the pet-arming lifecycle. Every
-- function takes the ENGINE as its first argument — the engine OWNS the
-- state; this module only implements the pet mechanics.

---@type ACP
local _, ACP = ...;

local tostring = _G.tostring;

--- State machine values (Data/Constants.WORKFLOW_STATE).
local WS = ACP.Data.Constants.WORKFLOW_STATE;

--- Pause reason keys (Data/Constants.WORKFLOW_REASON).
local Reason = ACP.Data.Constants.WORKFLOW_REASON;

---@class PetAbilityCaster
local PetAbilityCaster = {};

---@type PetAbilityCaster
ACP.PetAbilityCaster = PetAbilityCaster;

--- The secure macro a pet step casts: "/cast [pet:<type>,@unit] <pet ability>".
--- The @unit conditional is the 20506-reliable target form (the old
--- [target=unit] form did NOT redirect pet abilities in live tests 2026-08-22 —
--- a Fire Shield step with target=party1 buffed the PLAYER; TBC Classic guides
--- use [@arena1]/[@mouseover] for pet abilities on this client). The
--- [pet:<type>] conditional gates the cast on the RIGHT pet being out: when it
--- isn't (e.g. the pet was dismissed mid-summon), the macro does NOTHING instead
--- of the client treating it as a player cast — no interruption, no
--- "blocked action" popup. This is how Sacrifice is pressed during the
--- Summon Felhunter cast (the Voidwalker is still out until the summon
--- completes) — the requirement that ALL pet abilities work armed-during-cast.
--- "player" and a missing target both default to @player (the warlock); a
--- party target keeps its explicit unit.
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

--- Whether a pet ability ACTUALLY applied (2026-08-22, live-verified): the
--- client applies a pet ability only when the key is pressed near the END of
--- the player's cast — an early press is silently swallowed (Sacrifice pressed
--- +2 s into a 6 s summon did nothing; +5 s fired). The engine must therefore
--- NOT mark a pet step done on the press itself; it marks it done only when
--- the effect is visible:
---   1. the ability's buff is on the target (matched by NAME like
---      isAlreadyBuffed — covers Fire Shield AND the Sacrifice shield);
---   2. the Voidwalker is GONE while the player's cast is still in progress
---      (Sacrifice consumes the pet).
---@param engine WorkflowEngine
---@param step table
---@return boolean
function PetAbilityCaster:isPetAbilityApplied(engine, step)
    if (engine:hasBuff(step.target or "player", engine:spellName(step.spellID))) then
        return true;
    end

    -- Sacrifice consumes the Voidwalker. Only during the player's cast — after
    -- the summon completes the NEW pet exists, so "pet gone" would no longer
    -- prove anything (and UnitExists is true anyway).
    local entry = engine:getCatalogEntry(step.spellID);

    if (entry and entry.pet == "voidwalker" and engine.waitingForCast
        and _G.UnitExists and not _G.UnitExists("pet")) then
        return true;
    end

    return false;
end

--- Poll a pressed-but-unconfirmed pet step: when the ability's effect lands
--- (isPetAbilityApplied), mark the armed step done / advance the standalone
--- step. The poll is user-paced — no timeout; the user keeps pressing until
--- the client applies the ability. Bails as soon as the state no longer
--- matches (advance/pause/reset/interrupt all clear pendingPetStep or cancel
--- the timer via cancelTimers).
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

--- Point every live secure button at a macro that casts a pet ability by name
--- (/cast resolves pet abilities — e.g. Fire Shield, Sacrifice). The pet casts
--- the ability independently of the player's cast/GCD, so the step is
--- user-paced: the press (PostClick → onSecurePress) is the completion signal
--- and the engine does not wait for any player cast to finish.
---@param engine WorkflowEngine
---@param step table  the pet step
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

--- The secure button was clicked by the user's hardware key press (PostClick).
--- Branches by what is pending: an armed pet step during a player cast, a
--- standalone pet step, or a player-cast press (handled by the SENT/START flow).
--- The slot parameter is the pressed button's slot (nil for the /acp bind
--- hotkey button); a press from a button that does not belong to the current
--- slot is ignored (defensive — the client routes one key to one button).
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
        -- The armed pet ability was pressed during the player's cast. The
        -- press is NOT enough: the client silently swallows pet abilities
        -- pressed early in the cast (live 2026-08-22 — Sacrifice at +2 s of a
        -- 6 s summon did nothing, +5 s fired). Mark the step done ONLY when
        -- the effect is verified (isPetAbilityApplied); otherwise keep it
        -- armed — the user keeps spamming the key until the ability lands
        -- (armPetVerify also catches the effect the moment it appears).
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
        -- A standalone pet step's key was pressed — the same verification
        -- applies: advance only once the ability's effect is visible. The
        -- key stays click-bound (no takeover), so re-presses re-run the macro.
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
    -- Player-cast presses are handled by the UNIT_SPELLCAST_SENT/START flow.
end

return ACP;
