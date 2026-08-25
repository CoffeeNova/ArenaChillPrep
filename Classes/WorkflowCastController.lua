-- ArenaChillPrep — Classes/WorkflowCastController
-- Player-cast step execution: secure-button arming, UNIT_SPELLCAST_* events,
-- completion/timeout waits. Operates on the engine (first argument).

---@type ACP
local _, ACP = ...;

local tostring = _G.tostring;
local InCombatLockdown = _G.InCombatLockdown;
local UnitCastingInfo = _G.UnitCastingInfo;
local GetSpellCooldown = _G.GetSpellCooldown;
local GetTime = _G.GetTime;

local WS = ACP.Data.Constants.WORKFLOW_STATE;

local Reason = ACP.Data.Constants.WORKFLOW_REASON;

---@class WorkflowCastController
local WorkflowCastController = {};

---@type WorkflowCastController
ACP.WorkflowCastController = WorkflowCastController;

---@param engine WorkflowEngine
---@param step table
function WorkflowCastController:castSpell(engine, step)
    local castSpellID, _ = engine:resolveCastInfo(step);
    local name = engine:spellName(castSpellID);
    local entry = engine:getCatalogEntry(castSpellID);

    if (entry and entry.buffSpellID and engine:effectiveSkip(step) and engine:isAlreadyBuffed(step)) then
        engine:advance();
        return;
    end

    engine.pendingCastSpellID = castSpellID;
    engine:requestKeyCast(name, step);

    if (not (entry and entry.isCastTime)) then
        engine.instantPressDetected = false;
        engine:waitForInstantEffect(step);
    end
end

---@param engine WorkflowEngine
---@param name string
---@param step table
function WorkflowCastController:requestKeyCast(engine, name, step)
    engine.waitingForKey = true;
    engine.waitingForCast = false;

    if (step.spellID) then
        -- Cast the RESOLVED spellID; restore "spell" (equipItem re-points to "item").
        local castSpellID = engine.pendingCastSpellID or step.spellID;
        engine:setCastAttribute("type", "spell");
        engine:setCastAttribute("spell", castSpellID);
        -- Direct targeting via the button's `unit` attribute; nil = current target.
        engine:setCastAttribute("unit", step.target or nil);
    end

    local key = engine:resolveCastKey(engine.currentSlot);

    if (not key) then
        if (engine.debugBypass) then
            ACP:print(ACP.L.workflow.testNoKey, engine.currentSlot);
        end
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
---@param unit string
---@param spellID number|nil
---@return boolean
function WorkflowCastController:isWaitingForKeyOrCast(engine, unit, spellID)
    if (unit ~= "player" or engine.state ~= WS.RUNNING or not (engine.waitingForKey or engine.waitingForCast)) then
        return false;
    end

    -- Spell-ID guard: the player's own manual casts fire SENT/START too.
    if (engine.pendingCastSpellID and spellID and spellID ~= engine.pendingCastSpellID) then
        return false;
    end

    return true;
end

---@param engine WorkflowEngine
---@param unit string
---@return boolean
function WorkflowCastController:isRunningCastStep(engine, unit)
    return unit == "player" and engine.state == WS.RUNNING and engine.waitingForCast;
end

---@param engine WorkflowEngine
function WorkflowCastController:onKeyPressed(engine)
    if (engine.waitingForCast) then
        return;
    end

    local C = ACP.Data.Constants;
    engine.waitingForKey = false;

    local def = engine:getDefinition(engine.currentSlot);
    local step = def and def.steps[engine.stepIndex];
    local entry = step and engine:getCatalogEntry(step.spellID);

    if (entry and entry.isCastTime) then
        engine.waitingForCast = true;
        engine:armCastTimeout();

        -- Arm the NEXT pet step so it can be pressed DURING this cast; gated
        -- on the pet existing (a mid-cast press with no pet would interrupt).
        local nextStep = def and def.steps[engine.stepIndex + 1];

        if (nextStep and nextStep.type == C.WORKFLOW_STEP_PET
            and _G.UnitExists and _G.UnitExists("pet")) then
            engine.pendingPetStep = engine.stepIndex + 1;
            engine.petStepDone = false;
            engine.waitingForPet = true;
            engine.waitingForKey = true;

            local macro = ACP.PetAbilityCaster:petMacroText(engine, nextStep);
            engine:setCastAttribute("type", "macro");
            engine:setCastAttribute("macrotext", macro);
            engine:setCastAttribute("unit", nil);
            ACP:debugPrint("workflow pet macro: %s", macro);
            ACP:debugPrint("workflow pet ability armed during cast: %s (step %d) petGUID=%s", engine:spellName(nextStep.spellID), engine.pendingPetStep, tostring(_G.UnitGUID and _G.UnitGUID("pet")));
        else
            -- No pet step armed: make the buttons inert for this cast.
            if (nextStep and nextStep.type == C.WORKFLOW_STEP_PET) then
                ACP:debugPrint("workflow pet step NOT armed (pet not out): %s (step %d)", engine:spellName(nextStep.spellID), engine.stepIndex + 1);
            end
            engine:clearKeyCast();
        end
    else
        engine.waitingForCast = false;
        engine.instantPressDetected = true;
    end
end

---@param engine WorkflowEngine
function WorkflowCastController:armCastTimeout(engine)
    ACP.Utils.Timers:after("WorkflowCastTimeout", ACP.Data.Constants.WORKFLOW_CAST_TIMEOUT, function()
        engine:onCastTimeout();
    end);
end

---@param engine WorkflowEngine
function WorkflowCastController:onCastTimeout(engine)
    if (engine.state ~= WS.RUNNING or not engine.waitingForCast) then
        return;
    end

    if (UnitCastingInfo and UnitCastingInfo("player")) then
        return;
    end

    ACP:debugPrint("workflow cast dropped: accepted=%s inCombat=%s affectingCombat=%s shards=%d",
        tostring(engine.castAccepted),
        tostring(InCombatLockdown and InCombatLockdown()),
        tostring(UnitAffectingCombat and UnitAffectingCombat("player")),
        ACP.Inventory:countItem(ACP.Data.Constants.SOUL_SHARD_ITEM_ID));
    engine:pause(engine.castAccepted and Reason.CastTimeout or Reason.CastBlocked);
end

--- Waits for an instant cast's EFFECT (the client may not fire SENT for
--- instant spells). Buff steps: the buff landing — or, when the target was
--- ALREADY buffed at step start (skip-completed OFF → re-cast), a refresh
--- (aura expiration changed) or a detected press. Other steps: SENT or a new
--- GCD (start >= stepStart). User-paced — no timeout while waiting for the
--- press.
---@param engine WorkflowEngine
---@param step table
function WorkflowCastController:waitForInstantEffect(engine, step)
    local entry = engine:getCatalogEntry(step.spellID);
    local spellID = step.spellID;
    local stepStart = GetTime and GetTime() or 0;
    local detected = false;
    local ticks = 0;

    local buffUnit = step.target or "player";
    local buffName = (entry and entry.buffSpellID) and engine:spellName(spellID) or nil;
    local baselineExpiration = buffName and engine:getBuffExpiration(buffUnit, buffName) or nil;
    local baselinePresent = baselineExpiration ~= nil;

    ACP.Utils.Timers:interval("WorkflowGCD", ACP.Data.Constants.WORKFLOW_GCD_TICK, function()
        if (engine.state ~= WS.RUNNING or engine.waitingForCast or engine.expectedItemID) then
            return;
        end

        ticks = ticks + 1;

        if (not detected) then
            if (entry and entry.buffSpellID) then
                if (engine:isAlreadyBuffed(step)) then
                    if (not baselinePresent) then
                        detected = true;
                    elseif (engine.instantPressDetected) then
                        detected = true;
                    else
                        local now = engine:getBuffExpiration(buffUnit, buffName);

                        if (now and now ~= baselineExpiration) then
                            detected = true;
                        end
                    end
                end
            elseif (engine.instantPressDetected) then
                detected = true;
            else
                -- `GetSpellCooldown and GetSpellCooldown(...)` would truncate to
                -- ONE value (`and` drops the extra returns) — capture both.
                local start, duration;

                if (GetSpellCooldown) then
                    start, duration = GetSpellCooldown(spellID);
                end

                if (start and duration and duration > 0 and start >= stepStart) then
                    detected = true;
                end
            end

            if (not detected) then
                return;
            end

            engine.castAccepted = true;
            engine.waitingForKey = false;
        end

        if (entry and entry.buffSpellID) then
            ACP.Utils.Timers:cancel("WorkflowGCD");
            engine:advance();
            return;
        end

        -- Non-buff step: advance once the GCD clears after detection.
        local duration;

        if (GetSpellCooldown) then
            _, duration = GetSpellCooldown(spellID);
        end

        if (not (duration and duration > 0) and ticks >= 3) then
            ACP.Utils.Timers:cancel("WorkflowGCD");
            engine:advance();
        end
    end);
end

---@param engine WorkflowEngine
function WorkflowCastController:onCastComplete(engine)
    engine.waitingForCast = false;
    engine.waitingForKey = false;
    engine:clearKeyCast();
    ACP.Utils.Timers:cancel("WorkflowCastTimeout");

    if (engine.expectedItemID) then
        if (engine:isItemCreated()) then
            engine.expectedItemID = nil;
            engine.expectedItemIDs = nil;
            engine.expectedBaseline = nil;
            engine:advance();
            return;
        end

        -- Item not in bags yet: ACP_ITEMS_CHANGED or the poll will advance us.
        engine:waitForItem(engine.expectedItemID);
        return;
    end

    engine:advance();
end

---@param engine WorkflowEngine
function WorkflowCastController:clearKeyCast(engine)
    -- Inert buttons: a stray key press outside a workflow must do nothing.
    engine:setCastAttribute("type", "spell");
    engine:setCastAttribute("spell", "");
    engine:setCastAttribute("unit", nil);
end

---@param engine WorkflowEngine
function WorkflowCastController:_init(engine)
    ACP.Events:register("WCC.SPELLCAST_SENT", "UNIT_SPELLCAST_SENT", function(unit, target, castGUID, spellID)
        if (not self:isWaitingForKeyOrCast(engine, unit, spellID)) then
            return;
        end

        engine.castAccepted = true;

        if (engine.waitingForKey) then
            engine:onKeyPressed();
        end

        ACP:debugPrint("workflow cast accepted (step %d)", engine.stepIndex);
    end);

    ACP.Events:register("WCC.SPELLCAST_START", "UNIT_SPELLCAST_START", function(unit, target, castGUID, spellID)
        if (not self:isWaitingForKeyOrCast(engine, unit, spellID)) then
            return;
        end

        if (engine.waitingForKey) then
            engine.castAccepted = true;
            engine:onKeyPressed();
        end

        ACP:debugPrint("workflow cast started (step %d)", engine.stepIndex);
    end);

    ACP.Events:register("WCC.SPELLCAST_STOP", "UNIT_SPELLCAST_STOP", function(unit)
        if (not self:isRunningCastStep(engine, unit)) then
            return;
        end

        if (UnitCastingInfo and UnitCastingInfo("player")) then
            return;
        end

        engine:onCastComplete();
    end);

    ACP.Events:register("WCC.SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SUCCEEDED", function(unit)
        if (not self:isRunningCastStep(engine, unit)) then
            return;
        end

        if (UnitCastingInfo and UnitCastingInfo("player")) then
            return;
        end

        engine:onCastComplete();
    end);

    ACP.Events:register("WCC.SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_INTERRUPTED", function(unit)
        if (not self:isRunningCastStep(engine, unit)) then
            return;
        end

        -- Re-arm the SAME step; the hotkey re-casts it.
        engine.waitingForCast = false;
        engine.waitingForPet = false;
        engine.pendingPetStep = nil;
        engine.petStepDone = false;
        ACP.Utils.Timers:cancel("WorkflowCastTimeout");
        ACP.Utils.Timers:cancel("WorkflowPetVerify");

        local def = engine:getDefinition(engine.currentSlot);
        local step = def and def.steps[engine.stepIndex];
        local name = step and engine:spellName(step.spellID);

        if (step and name) then
            engine:requestKeyCast(name, step);
        else
            engine:pause(Reason.CastInterrupted);
        end
    end);

    ACP.Events:register("WCC.SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED", function(unit)
        if (not self:isRunningCastStep(engine, unit)) then
            return;
        end

        engine:pause(Reason.CastFailed);
    end);
end

return ACP;
