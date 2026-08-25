-- ArenaChillPrep — Classes/WorkflowCastController
-- Player-cast step execution, extracted from WorkflowEngine (refactor
-- Phase 5): castSpell / requestKeyCast / the UNIT_SPELLCAST_* event
-- handlers / completion & timeout waits / button re-arming. Every function
-- takes the ENGINE as its first argument — the engine OWNS the state; this
-- module only implements the cast mechanics.

---@type ACP
local _, ACP = ...;

local tostring = _G.tostring;
local InCombatLockdown = _G.InCombatLockdown;
local UnitCastingInfo = _G.UnitCastingInfo;
local GetSpellCooldown = _G.GetSpellCooldown;
local GetTime = _G.GetTime;

--- State machine values (Data/Constants.WORKFLOW_STATE).
local WS = ACP.Data.Constants.WORKFLOW_STATE;

--- Pause reason keys (Data/Constants.WORKFLOW_REASON).
local Reason = ACP.Data.Constants.WORKFLOW_REASON;

---@class WorkflowCastController
local WorkflowCastController = {};

---@type WorkflowCastController
ACP.WorkflowCastController = WorkflowCastController;

--- Every step (instant AND cast-time) casts through the secure hotkey
--- (§3.6): 20506 blocks insecure casting even for INSTANT spells outside safe
--- zones — verified 2026-08-19 (bare CastSpellByName("Fel Armor") in the open
--- world pops "blocked from an action"; no GCD, no buff). The engine points
--- the button at the spell and waits for the user's key press (waitingForKey).
--- Completion is waited for by cast type:
---   cast-time → events (SENT/START → waitingForCast, STOP/SUCCEEDED → advance);
---   instant   → waitForInstantEffect (the cast's effect: the buff landing, a
---               registered GCD, or SENT if the client fires it — verified
---               2026-08-19 that SENT may NOT fire for instant spells, so the
---               effect watch is the primary completion signal).
---
--- TARGETING: the step's unit travels in the button's `unit` attribute only
--- (requestKeyCast) — the old TargetUnit("party1")/TargetLastTarget() swap was
--- REMOVED (2026-08-22): calling TargetUnit from insecure code popped
--- "blocked action" on the first party-targeted cast, and the swap was fully
--- redundant with the unit attribute anyway.
---@param engine WorkflowEngine
---@param step table
function WorkflowCastController:castSpell(engine, step)
    local castSpellID, _ = engine:resolveCastInfo(step);
    local name = engine:spellName(castSpellID);
    local entry = engine:getCatalogEntry(castSpellID);

    -- Already has the buff and skip-completed is enabled: the goal state is
    -- met — no key press needed.
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

--- CAST step (§3.6): the client requires a real hardware event to cast —
--- insecure casting is blocked even out of combat (verified 2026-08-18). Point
--- every live secure button (the /acp bind hotkey button + the current slot's
--- button — both permanently click-bound, no takeover) at the spell and wait
--- for the user's key press (waitingForKey). UNIT_SPELLCAST_SENT/START then
--- transition to waitingForCast + timeout.
---@param engine WorkflowEngine
---@param name string  localized spell name
---@param step table
function WorkflowCastController:requestKeyCast(engine, name, step)
    engine.waitingForKey = true;
    engine.waitingForCast = false;

    if (step.spellID) then
        -- SecureActionButtonTemplate accepts the exact spellID on this client
        -- (BetterFishing/Details pattern). Use the RESOLVED cast spellID: a
        -- stored lower rank can be unlearned at high level, so casting it by
        -- spellID silently does nothing — the engine resolves the player's
        -- actual known rank (resolveCastInfo) for both createItem and cast
        -- steps. "type" is restored here too — an equipItem step re-points the
        -- buttons to type="item" and they must be spell buttons again.
        local castSpellID = engine.pendingCastSpellID or step.spellID;
        engine:setCastAttribute("type", "spell");
        engine:setCastAttribute("spell", castSpellID);
        -- Target the cast directly at the step's unit via the button's `unit`
        -- attribute (the M6 ActionBook pattern — spell + unit attribute group,
        -- verified on 20506). A nil target keeps the default current-target
        -- behavior (summons/conjures self-cast).
        engine:setCastAttribute("unit", step.target or nil);
    end

    local key = engine:resolveCastKey(engine.currentSlot);

    if (not key) then
        -- No key can cast this step. Outside a test the workflow just waits
        -- quietly; in test mode surface it so the player knows to bind a key.
        if (engine.debugBypass) then
            ACP:print(ACP.L.workflow.testNoKey, engine.currentSlot);
        end
        engine.waitingForKey = false;
        engine:pause(Reason.NoHotkey);
        return;
    end

    if (engine.debugBypass) then
        -- Test mode: the "Press <key> to cast <spell>" prompt is the whole
        -- point of the test driver, so show it in chat (not just debug).
        ACP:print(ACP.L.workflow.pressKey, key, name);
    else
        ACP:debugPrint(ACP.L.workflow.pressKey, key, name);
    end
end

--- Whether a player cast event belongs to the armed workflow step: the engine
--- must be running and waiting for the key press or a cast in progress, AND
--- (spell-ID guard, 2026-08-22) the spell must be the one the engine armed —
--- the player's own manual casts fire SENT/START too and must not be treated
--- as the workflow key press (they would skip the step without casting it).
---@param engine WorkflowEngine
---@param unit string
---@param spellID number|nil
---@return boolean
function WorkflowCastController:isWaitingForKeyOrCast(engine, unit, spellID)
    if (unit ~= "player" or engine.state ~= WS.RUNNING or not (engine.waitingForKey or engine.waitingForCast)) then
        return false;
    end

    if (engine.pendingCastSpellID and spellID and spellID ~= engine.pendingCastSpellID) then
        return false;
    end

    return true;
end

--- Whether a cast-completion event can belong to the current cast-time step
--- (the engine is running AND a cast is in progress). Signal-only: callers
--- still verify the cast actually ended before acting.
---@param engine WorkflowEngine
---@param unit string
---@return boolean
function WorkflowCastController:isRunningCastStep(engine, unit)
    return unit == "player" and engine.state == WS.RUNNING and engine.waitingForCast;
end

--- The user pressed the cast key and the client accepted the cast (SENT/START).
--- Cast-time → waitingForCast + completion timeout; the buttons are re-pointed
--- at the armed pet macro (or made inert so mid-cast presses do nothing).
--- Instant → flag the press for waitForInstantEffect (which may already have
--- detected the effect via the buff landing, since the client may not fire SENT
--- for instant spells).
--- Guard: both SENT and START fire for one cast (START follows SENT); the
--- first transition already armed the cast-time wait (and the optional pet
--- step), so a second onKeyPressed for the same cast is a no-op (a live "pet
--- ability armed during cast" was logged twice per cast, 2026-08-22).
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
        -- If the NEXT step is a pet ability, arm it now so it can be pressed
        -- DURING this cast (the pet casts independently of the player). The
        -- buttons are re-pointed at the pet macro; a second key press casts
        -- the pet ability while the player's cast is still in progress.
        -- GATED on the pet EXISTING: pressing the armed key during a SUMMON
        -- (pet not out yet) executes the pet macro with no pet to route it to —
        -- the client then treats it as a player cast, which interrupts the
        -- summon and pops "blocked action" (live 2026-08-22). Without the pet
        -- the step is not armed and runs standalone after the summon completes.
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
            -- No pet step armed: make the buttons inert for the duration of the
            -- cast — the slot key stays click-bound now (no takeover/release),
            -- so a mid-cast press must do nothing instead of re-casting.
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

--- Arm the cast-time completion safety timeout. Fires WORKFLOW_CAST_TIMEOUT
--- seconds after a cast is ACCEPTED (the key was pressed); pauses if the cast
--- never completes.
---@param engine WorkflowEngine
function WorkflowCastController:armCastTimeout(engine)
    ACP.Utils.Timers:after("WorkflowCastTimeout", ACP.Data.Constants.WORKFLOW_CAST_TIMEOUT, function()
        engine:onCastTimeout();
    end);
end

--- Cast-time timeout callback: no cast in progress after WORKFLOW_CAST_TIMEOUT
--- since the cast was accepted. Emit client state, then pause.
---@param engine WorkflowEngine
function WorkflowCastController:onCastTimeout(engine)
    if (engine.state ~= WS.RUNNING or not engine.waitingForCast) then
        return;
    end

    -- Defense in depth: a legitimately long cast is still going — wait for
    -- the real completion event instead of pausing.
    if (UnitCastingInfo and UnitCastingInfo("player")) then
        return;
    end

    -- No cast in progress and never completed — emit client state so the next
    -- run is self-diagnosing.
    ACP:debugPrint("workflow cast dropped: accepted=%s inCombat=%s affectingCombat=%s shards=%d",
        tostring(engine.castAccepted),
        tostring(InCombatLockdown and InCombatLockdown()),
        tostring(UnitAffectingCombat and UnitAffectingCombat("player")),
        ACP.Inventory:countItem(ACP.Data.Constants.SOUL_SHARD_ITEM_ID));
    engine:pause(engine.castAccepted and Reason.CastTimeout or Reason.CastBlocked);
end

--- Instant-step wait: watch for the cast's EFFECT (the press happening) and
--- advance when the step's goal is met. The client may NOT fire
--- UNIT_SPELLCAST_SENT for instant spells (verified stall 2026-08-19), so the
--- effect is the primary signal:
---   buff steps → the buff appearing in the aura list (isAlreadyBuffed). This
---               is the ONLY signal for buff steps — the GCD is NOT consulted
---               because the previous step's GCD can still be running when this
---               step begins (a false "press" would skip the step silently).
---   other steps → SENT (if the client fires it) or a NEW GCD started after
---               this step began (start >= stepStart).
--- Buff steps advance immediately once detected (the buff present proves the
--- cast landed); non-buff steps advance once the GCD clears after detection.
--- The watch is user-paced — no timeout while waitingForKey (the user controls
--- when to press).
---@param engine WorkflowEngine
---@param step table
function WorkflowCastController:waitForInstantEffect(engine, step)
    local entry = engine:getCatalogEntry(step.spellID);
    local spellID = step.spellID;
    local stepStart = GetTime and GetTime() or 0;
    local detected = false;
    local ticks = 0;

    ACP.Utils.Timers:interval("WorkflowGCD", ACP.Data.Constants.WORKFLOW_GCD_TICK, function()
        if (engine.state ~= WS.RUNNING or engine.waitingForCast or engine.expectedItemID) then
            return;
        end

        ticks = ticks + 1;

        if (not detected) then
            if (entry and entry.buffSpellID) then
                if (engine:isAlreadyBuffed(step)) then
                    detected = true; -- the buff landed (SENT may not fire for instant)
                end
            elseif (engine.instantPressDetected) then
                detected = true; -- SENT/START fired for this step
            else
                local start, duration = GetSpellCooldown and GetSpellCooldown(spellID);

                if (start and duration and duration > 0 and start >= stepStart) then
                    detected = true; -- a NEW GCD began (the press landed)
                end
            end

            if (not detected) then
                return; -- the user hasn't pressed yet
            end

            engine.castAccepted = true;
            engine.waitingForKey = false;
        end

        if (entry and entry.buffSpellID) then
            -- Buff present → the cast landed → the step is done.
            ACP.Utils.Timers:cancel("WorkflowGCD");
            engine:advance();
            return;
        end

        -- Non-buff step: advance once the GCD is clear after detection.
        local _, duration = GetSpellCooldown and GetSpellCooldown(spellID);

        if (not (duration and duration > 0) and ticks >= 3) then
            ACP.Utils.Timers:cancel("WorkflowGCD");
            engine:advance();
        end
    end);
end

--- A cast finished (UNIT_SPELLCAST_STOP/SUCCEEDED, verified not casting).
--- For createItem the item may still be landing — check bags, else wait.
--- Does NOT clear pendingPetStep/petStepDone — an armed pet step pressed during
--- this cast keeps its "done" flag so the engine skips it when it advances to
--- that index; an un-pressed pet step is reached normally afterwards.
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

        -- Item not in bags yet: ACP_ITEMS_CHANGED (tracked items) or the
        -- polling safety net (untracked items) will advance us.
        engine:waitForItem(engine.expectedItemID);
        return;
    end

    engine:advance();
end

--- Reset every live cast button to an inert value so a stray key press
--- OUTSIDE a workflow does nothing (a secure button retains its last
--- attribute; without this, the key would keep re-casting the last step's
--- spell after the workflow is DONE/paused/reset).
---@param engine WorkflowEngine
function WorkflowCastController:clearKeyCast(engine)
    -- Restore the spell type too: an equipItem step switches the buttons to
    -- type="item" — a stale "item" type would make a stray key press USE the
    -- last item instead of casting after the workflow ends.
    engine:setCastAttribute("type", "spell");
    engine:setCastAttribute("spell", "");
    -- Clear the target unit as well — a stale unit attribute (e.g. a party1
    -- step) would retarget a later untargeted cast at the old unit.
    engine:setCastAttribute("unit", nil);
end

--- Register the cast event handlers (owns the UNIT_SPELLCAST_* subscriptions).
---@param engine WorkflowEngine
function WorkflowCastController:_init(engine)
    -- Cast acceptance signal: UNIT_SPELLCAST_SENT fires when the client
    -- ACCEPTS a cast command (instant and cast-time spells alike) — i.e. the
    -- user pressed the hotkey. Branch by cast type: cast-time → waitingForCast
    -- + completion timeout; instant → GCD-driven completion (waitForGCD).
    -- SPELL-ID GUARD (2026-08-22): the player's own MANUAL casts fire SENT too.
    -- When the engine is waitingForKey (armed step ready), a manual cast's
    -- SENT must NOT be treated as the workflow key being pressed — the engine
    -- would then transition to waitingForCast, the manual cast's STOP would
    -- trigger onCastComplete → advance → the workflow STEP IS SKIPPED without
    -- ever being cast. Only accept SENT for the spell the engine armed.
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

    -- The cast bar appeared. For a cast-time step this is the same
    -- "key pressed, cast accepted" transition as SENT (SENT may be skipped by
    -- the client for some casts); completion is still driven by
    -- STOP/SUCCEEDED (see the research: START is a signal, not completion).
    -- Same spell-ID guard as SENT — a manual cast's START must not arm the
    -- engine or pet step.
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

    -- Cast completion signals. Signal-only: verify the player is no longer
    -- casting before treating the event as completion (§3.6).
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

        -- The user stopped the cast (movement, ESC, /stopcasting): re-arm the
        -- SAME step in waitingForKey so the next F9 press re-casts it — the
        -- hotkey IS the resume mechanism (no /acp workflow 1 needed). Combat
        -- still hard-pauses via PLAYER_REGEN_DISABLED.
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
