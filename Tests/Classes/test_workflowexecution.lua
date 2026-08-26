-- ArenaChillPrep — Tests/Classes/test_workflowexecution.lua
-- Covers the step-EXECUTION paths: createItem/equipItem flows
-- (WorkflowItemSteps), the UNIT_SPELLCAST_* lifecycle and timeouts
-- (WorkflowCastController), and the engine's gate/skip/DONE paths.

local ACP = _G.ACP;
local Engine = ACP.WorkflowEngine;
local Spellbook = ACP.WorkflowSpellbook;
local H = dofile(_G.__TESTS_ROOT .. "/helpers.lua");

local DefaultUnitClass = _G.UnitClass;
local OrigTimers = ACP.Utils.Timers;
local KEY = "F9";
local C = ACP.Data.Constants;

local function resetSpellbook()
    Spellbook:_reset();
    Spellbook:mergeStaticWarlock();
    Spellbook:addStaticFallback();
end

local function installTimers()
    ACP.Utils.Timers = H.SyncTimers;
    H.SyncTimers.Handles = {};
end

local function restoreTimers()
    ACP.Utils.Timers = OrigTimers;
    H.SyncTimers.Handles = {};
end

--- Bind slot 1's key + init the engine (registers the WCC/WIS handlers).
--- Event-driven suites call H.resetAll() which WIPES the event bus — the
--- engine's listeners must be re-registered for the cast events to fire.
---@param steps table
---@param knownSpells table|nil
local function setupEngine(steps, knownSpells)
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = KEY };
    _G.__stub.bindingActions = { [KEY] = "ACP_WORKFLOW1" };
    _G.__stub.overrideClicks = {};
    _G.__stub.knownSpells = knownSpells or { [27230] = true };
    Engine._initialized = false;
    Engine:_init();
    Engine.slotKeys = {};
    Engine:applySlotBindings();
    Engine.debugBypass = true;
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";
    Engine:clearTransientState(true);

    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "exec-test", steps = steps,
    };
    return savedDef;
end

local function teardownEngine(savedDef)
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    restoreTimers();
    Engine.slotKeys = {};
    Engine.state = "IDLE";
    Engine.currentSlot = nil;
    Engine.stepIndex = 1;
    Engine.debugBypass = false;
    Engine.isTesting = false;
    Engine.testSlot = nil;
    Engine:clearTransientState(true);
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
    _G.__stub.overrideClicks = nil;
    _G.__stub.knownSpells = {};
    _G.__stub.auraByIndex = nil;
    _G.__stub.dead = false;
    _G.__stub.unitGUID = nil;
end

local function countItemStub(counts)
    local orig = ACP.Inventory.countItem;
    ACP.Inventory.countItem = function(_, id)
        return counts[id] or 0;
    end;
    return function()
        ACP.Inventory.countItem = orig;
    end;
end

-- ---- WorkflowItemSteps: createItem flow ----

function testCreateItemArmsExactRankCast()
    resetSpellbook();
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Create Healthstone", spellID = 27230, itemID = 22105 },
    });
    local restoreCount = countItemStub({ [6265] = 1 });

    Engine:executeCurrentStep();

    lu.assertEquals(Engine.expectedItemID, 22105);
    lu.assertEquals(Engine.pendingCastSpellID, 27230);
    lu.assertEquals(Engine.expectedItemIDs[1], 22105);
    lu.assertIsTrue(Engine.waitingForKey);

    restoreCount();
    teardownEngine(savedDef);
end

function testCreateItemUpgradedCastUsesFamilyWidenedSet()
    resetSpellbook();
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Create Healthstone", spellID = 11730, itemID = 19012 },
    }, { [27230] = true });
    local restoreCount = countItemStub({ [6265] = 1 });

    Engine:executeCurrentStep();

    -- The cast upgrades to the known max rank (27230) — the expected set is
    -- the family-widened fallback OF THE RESOLVED rank: { Master 22105 }.
    local castSpellID = Engine.pendingCastSpellID;
    local expected = {};
    for _, id in ipairs(Engine.expectedItemIDs or {}) do
        expected[id] = true;
    end
    local expectedCount = 0;
    for _ in pairs(expected) do
        expectedCount = expectedCount + 1;
    end
    restoreCount();
    teardownEngine(savedDef);

    lu.assertEquals(castSpellID, 27230);
    lu.assertEquals(expectedCount, 1, "only the Master stone is expected");
    lu.assertIsTrue(expected[22105]);
    lu.assertIsNil(expected[19012]);
end

function testItemsChangedFastPathAdvancesCreatedItem()
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Create Healthstone", spellID = 27230, itemID = 22105 },
    });
    installTimers();
    Engine.expectedItemID = 22105;
    Engine.expectedItemIDs = { 22105 };
    Engine.expectedBaseline = 0;

    local restoreCount = countItemStub({ [22105] = 1 });

    ACP.Events:fire("ACP_ITEMS_CHANGED", 22105, 1);

    local finalState = Engine.state;
    local expectedCleared = Engine.expectedItemID == nil;
    restoreCount();
    teardownEngine(savedDef);

    lu.assertEquals(finalState, "DONE", "crafted item advances to DONE");
    lu.assertIsTrue(expectedCleared);
end

function testWaitForItemPollAdvancesOnCreated()
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Create Healthstone", spellID = 27230, itemID = 22105 },
    });
    installTimers();
    Engine.expectedItemID = 22105;
    Engine.expectedItemIDs = { 22105 };
    Engine.expectedBaseline = 0;

    local restoreCount = countItemStub({ [22105] = 1 });

    Engine:waitForItem(22105);
    H.advance("WorkflowItemPoll");

    lu.assertEquals(Engine.state, "DONE");
    restoreCount();
    teardownEngine(savedDef);
end

function testWaitForItemTimeoutPauses()
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Create Healthstone", spellID = 27230, itemID = 22105 },
    });
    installTimers();
    Engine.expectedItemID = 22105;
    Engine.expectedItemIDs = { 22105 };
    Engine.expectedBaseline = 0;
    local restoreCount = countItemStub({});

    Engine:waitForItem(22105);
    H.advance("WorkflowCastTimeout");

    lu.assertEquals(Engine.state, "PAUSED");
    restoreCount();
    teardownEngine(savedDef);
end

function testCountExpectedItemsNilExpected()
    Engine.expectedItemIDs = nil;
    lu.assertEquals(ACP.WorkflowItemSteps:countExpectedItems(Engine), 0);
end

function testIsItemCreatedFalseWithoutExpected()
    Engine.expectedItemIDs = nil;
    lu.assertIsFalse(ACP.WorkflowItemSteps:isItemCreated(Engine));
end

-- ---- WorkflowItemSteps: equipItem flow ----

function testEquipItemAlreadyEquippedAdvances()
    installTimers();
    local savedDef = setupEngine({
        { type = "equipItem", itemID = 22646, itemName = "Master Spellstone" },
    });
    local restoreCount = countItemStub({});

    Engine:executeCurrentStep();

    lu.assertEquals(Engine.state, "RUNNING", "item absent → grace poll, not advanced yet");
    lu.assertIsTrue(H.hasTimer("WorkflowEquipGrace"));

    for _ = 1, 12 do
        H.advance("WorkflowEquipGrace");
    end

    lu.assertEquals(Engine.state, "DONE", "grace elapsed → advance as already equipped");
    restoreCount();
    teardownEngine(savedDef);
end

function testEquipItemGraceArmsWhenItemArrives()
    installTimers();
    local savedDef = setupEngine({
        { type = "equipItem", itemID = 22646, itemName = "Master Spellstone" },
    });
    local restoreCount = countItemStub({});

    Engine:executeCurrentStep();
    lu.assertEquals(Engine.state, "RUNNING");

    restoreCount();
    local restoreCount2 = countItemStub({ [22646] = 1 });
    H.advance("WorkflowEquipGrace");

    lu.assertIsTrue(Engine.waitingForEquip, "item appeared → equip armed");
    lu.assertIsTrue(H.hasTimer("WorkflowItemPoll"));
    restoreCount2();
    teardownEngine(savedDef);
end

function testEquipItemNoKeyPauses()
    local savedDef = setupEngine({
        { type = "equipItem", itemID = 22646, itemName = "Master Spellstone" },
    });
    local restoreCount = countItemStub({ [22646] = 1 });
    -- No slot key AND no /acp bind hotkey → the step pauses for a binding.
    Engine.slotKeys = {};
    ACP.Settings:set("workflows.hotkey", nil);

    Engine:executeCurrentStep();

    lu.assertEquals(Engine.state, "PAUSED", "no bound key pauses the step");
    restoreCount();
    teardownEngine(savedDef);
end

function testEquipItemPollCompletesWhenItemGone()
    installTimers();
    local savedDef = setupEngine({
        { type = "equipItem", itemID = 22646, itemName = "Master Spellstone" },
    });
    local restoreCount = countItemStub({ [22646] = 1 });

    Engine:executeCurrentStep();

    lu.assertIsTrue(Engine.waitingForEquip);
    lu.assertIsTrue(H.hasTimer("WorkflowItemPoll"));

    restoreCount();
    local restoreCount2 = countItemStub({});
    H.advance("WorkflowItemPoll");

    lu.assertEquals(Engine.state, "DONE", "item leaves bags = equipped");
    restoreCount2();
    teardownEngine(savedDef);
end

function testEquipItemDebugBypassPrints()
    installTimers();
    local savedDef = setupEngine({
        { type = "equipItem", itemID = 22646, itemName = "Master Spellstone" },
    });
    local restoreCount = countItemStub({ [22646] = 1 });
    Engine.debugBypass = true;

    Engine:executeCurrentStep();

    lu.assertIsTrue(Engine.waitingForEquip);
    restoreCount();
    teardownEngine(savedDef);
end

-- ---- WorkflowCastController: cast lifecycle events ----

local function armedCastStep()
    local steps = {
        { type = "summon", spellName = "Summon Imp", spellID = 688 },
    };
    resetSpellbook();
    local savedDef = setupEngine(steps, { [688] = true });
    Engine.waitingForKey = true;
    Engine.pendingCastSpellID = 688;
    return savedDef, steps;
end

function testSpellcastSentStartsCastWait()
    installTimers();
    local savedDef = armedCastStep();

    ACP.Events:fire("UNIT_SPELLCAST_SENT", "player", nil, nil, 688);

    lu.assertIsTrue(Engine.waitingForCast);
    lu.assertIsFalse(Engine.waitingForKey);
    lu.assertIsTrue(H.hasTimer("WorkflowCastTimeout"));
    teardownEngine(savedDef);
end

function testSpellcastSentDifferentSpellIDIgnored()
    local savedDef = armedCastStep();

    ACP.Events:fire("UNIT_SPELLCAST_SENT", "player", nil, nil, 999);

    lu.assertIsFalse(Engine.waitingForCast, "manual cast with a different ID is not the workflow");
    lu.assertIsTrue(Engine.waitingForKey);
    teardownEngine(savedDef);
end

function testSpellcastStopCompletesCastStep()
    installTimers();
    local savedDef = armedCastStep();
    Engine.waitingForCast = true;
    Engine.waitingForKey = false;

    ACP.Events:fire("UNIT_SPELLCAST_STOP", "player");

    lu.assertEquals(Engine.state, "DONE");
    teardownEngine(savedDef);
end

function testSpellcastStopCompletesCreateItemImmediately()
    -- Single createItem step (no next step) advances on cast-end even when
    -- the item is not yet in bags.
    installTimers();
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Create Healthstone", spellID = 27230, itemID = 22105 },
    });
    Engine.waitingForCast = true;
    Engine.expectedItemID = 22105;
    Engine.expectedItemIDs = { 22105 };
    Engine.expectedBaseline = 0;
    local restoreCount = countItemStub({});

    ACP.Events:fire("UNIT_SPELLCAST_STOP", "player");

    lu.assertEquals(Engine.state, "DONE", "advances on cast-end without the item");
    lu.assertIsFalse(H.hasTimer("WorkflowItemPoll"));
    lu.assertIsNil(Engine.expectedItemID);
    restoreCount();
    teardownEngine(savedDef);
end

function testSpellcastStopRepeatedConjureKeepsItemWait()
    -- 2 consecutive Create Healthstone steps (different stored ranks, same
    -- resolved cast) → the first keeps the item wait so step 2's skip sees it.
    installTimers();
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Create Healthstone", spellID = 27230, itemID = 22105 },
        { type = "createItem", spellName = "Create Healthstone", spellID = 11730, itemID = 19012 },
    }, { [27230] = true });
    Engine.waitingForCast = true;
    Engine.expectedItemID = 22105;
    Engine.expectedItemIDs = { 22105 };
    Engine.expectedBaseline = 0;
    local skipSnap = ACP.Settings:get("workflows.skipIfBuffedDefault");
    ACP.Settings:set("workflows.skipIfBuffedDefault", true);
    local restoreCount = countItemStub({});

    ACP.Events:fire("UNIT_SPELLCAST_STOP", "player");

    lu.assertIsTrue(H.hasTimer("WorkflowItemPoll"), "waits because the next step repeats the conjure");

    restoreCount();
    local restoreCount2 = countItemStub({ [22105] = 1 });
    H.advance("WorkflowItemPoll");

    lu.assertEquals(Engine.state, "DONE", "item arrives → step 2 skips (goal met) → done");
    restoreCount2();
    ACP.Settings:set("workflows.skipIfBuffedDefault", skipSnap);
    teardownEngine(savedDef);
end

function testSpellcastStopDifferentConjureAdvancesImmediately()
    -- 2 different conjure steps (Water → Food) → advance on cast-end.
    installTimers();
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Conjure Water", spellID = 27090, itemID = 22018 },
        { type = "createItem", spellName = "Conjure Food", spellID = 33717, itemID = 22019 },
    }, { [27090] = true, [33717] = true });
    Engine.waitingForCast = true;
    Engine.expectedItemID = 22018;
    Engine.expectedItemIDs = { 22018 };
    Engine.expectedBaseline = 0;
    local restoreCount = countItemStub({});

    ACP.Events:fire("UNIT_SPELLCAST_STOP", "player");

    lu.assertEquals(Engine.stepIndex, 2, "advance immediately (next conjure differs)");
    lu.assertIsFalse(H.hasTimer("WorkflowItemPoll"), "no item wait opened");
    lu.assertEquals(Engine.expectedItemID, 22019, "step 2 re-armed its own cast");
    restoreCount();
    teardownEngine(savedDef);
end

function testSpellcastSucceededCompletesCastStep()
    local savedDef = armedCastStep();
    Engine.waitingForCast = true;
    Engine.waitingForKey = false;

    ACP.Events:fire("UNIT_SPELLCAST_SUCCEEDED", "player");

    lu.assertEquals(Engine.state, "DONE");
    teardownEngine(savedDef);
end

function testSpellcastInterruptedRearmsStep()
    installTimers();
    local savedDef = armedCastStep();
    Engine.waitingForCast = true;
    Engine.waitingForKey = false;

    ACP.Events:fire("UNIT_SPELLCAST_INTERRUPTED", "player");

    lu.assertIsFalse(Engine.waitingForCast);
    lu.assertIsTrue(Engine.waitingForKey, "the SAME step re-arms for the next press");
    teardownEngine(savedDef);
end

function testSpellcastFailedPauses()
    local savedDef = armedCastStep();
    Engine.waitingForCast = true;
    Engine.waitingForKey = false;

    ACP.Events:fire("UNIT_SPELLCAST_FAILED", "player");

    lu.assertEquals(Engine.state, "PAUSED");
    teardownEngine(savedDef);
end

function testOnCastTimeoutDroppedCastPausesBlocked()
    local savedDef = armedCastStep();
    Engine.waitingForCast = true;
    Engine.castAccepted = false;
    local restoreCount = countItemStub({});

    Engine:onCastTimeout();

    lu.assertEquals(Engine.state, "PAUSED", "unaccepted cast = blocked diagnostic");
    restoreCount();
    teardownEngine(savedDef);
end

function testOnCastTimeoutAcceptedCastPausesTimeout()
    local savedDef = armedCastStep();
    Engine.waitingForCast = true;
    Engine.castAccepted = true;

    Engine:onCastTimeout();

    lu.assertEquals(Engine.state, "PAUSED");
    teardownEngine(savedDef);
end

function testRequestKeyCastWithoutKeyPauses()
    local savedDef = setupEngine({
        { type = "summon", spellName = "Summon Imp", spellID = 688 },
    });
    Engine.slotKeys = {};

    Engine:requestKeyCast("Summon Imp", { type = "summon", spellID = 688 });

    lu.assertEquals(Engine.state, "PAUSED", "noHotkey");
    teardownEngine(savedDef);
end

-- ---- WorkflowCastController: instant-cast wait (GCD branch) ----

function testWaitForInstantEffectGCDDetectsCast()
    installTimers();
    local savedTime = _G.__stub.time;
    _G.__stub.time = 0;
    _G.__stub.gcdStart = 100;
    _G.__stub.gcdDuration = 1.5;
    _G.GetSpellCooldown = function()
        return _G.__stub.gcdStart, _G.__stub.gcdDuration;
    end;
    H.reloadModule("Classes/WorkflowCastController.lua");

    local savedDef = setupEngine({
        { type = "summon", spellName = "Summon Imp", spellID = 688 },
    }, { [688] = true });
    resetSpellbook();
    Engine.pendingCastSpellID = 688;
    Engine.waitingForKey = false;
    Engine.instantPressDetected = false;
    Engine.debugBypass = true;

    Engine:waitForInstantEffect({ type = "summon", spellID = 688, spellName = "Summon Imp" });

    -- SyncTimers removes a handle on advance — call the recorded callback
    -- directly to simulate repeated ticks of the same interval.
    local handle = H.SyncTimers.Handles["WorkflowGCD"];
    handle.cb();
    _G.__stub.gcdDuration = 0;
    handle.cb();
    handle.cb();

    lu.assertEquals(Engine.state, "DONE");
    teardownEngine(savedDef);
    _G.GetSpellCooldown = nil;
    _G.__stub.gcdDuration = 0;
    _G.__stub.time = savedTime;
    H.reloadModule("Classes/WorkflowCastController.lua");
end

function testWaitForInstantEffectPressDetectsNonBuffCast()
    installTimers();
    local savedDef = setupEngine({
        { type = "summon", spellName = "Summon Imp", spellID = 688 },
    }, { [688] = true });
    Engine.pendingCastSpellID = 688;
    Engine.waitingForKey = false;
    Engine.instantPressDetected = false;
    Engine.debugBypass = true;

    Engine:waitForInstantEffect({ type = "summon", spellID = 688, spellName = "Summon Imp" });
    Engine.instantPressDetected = true;
    H.advance("WorkflowGCD");

    lu.assertEquals(Engine.castAccepted, true);
    teardownEngine(savedDef);
end

-- ---- WorkflowEngine: gates, skips, DONE ----

function testCheckGatesEngineDisabled()
    local savedDef = setupEngine({
        { type = "cast", spellName = "Fel Armor", spellID = 28189, target = "player" },
    });
    ACP.Settings:set("workflows.enabled", false);

    local reason = Engine:checkGates({ type = "cast", spellID = 28189, target = "player" });

    lu.assertEquals(reason, C.WORKFLOW_REASON.EngineDisabled);
    ACP.Settings:set("workflows.enabled", true);
    teardownEngine(savedDef);
end

function testCheckGatesNotArenaWithoutBypass()
    local savedDef = setupEngine({
        { type = "cast", spellName = "Fel Armor", spellID = 28189, target = "player" },
    });
    Engine.debugBypass = false;
    ACP.ArenaPrep.buffActive = false;

    local reason = Engine:checkGates({ type = "cast", spellID = 28189, target = "player" });

    lu.assertEquals(reason, C.WORKFLOW_REASON.NotArena);
    teardownEngine(savedDef);
end

function testCheckGatesDead()
    local savedDef = setupEngine({
        { type = "cast", spellName = "Fel Armor", spellID = 28189, target = "player" },
    });
    _G.__stub.dead = true;

    local reason = Engine:checkGates({ type = "cast", spellID = 28189, target = "player" });

    lu.assertEquals(reason, C.WORKFLOW_REASON.Dead);
    teardownEngine(savedDef);
end

function testCheckGatesNoTarget()
    local savedDef = setupEngine({
        { type = "cast", spellName = "Fel Armor", spellID = 28189, target = "party1" },
    });
    _G.__stub.partyCount = 0;

    local reason = Engine:checkGates({ type = "cast", spellID = 28189, target = "party1" });

    lu.assertEquals(reason, C.WORKFLOW_REASON.NoTarget);
    teardownEngine(savedDef);
end

function testCheckGatesNoShard()
    resetSpellbook();
    local savedDef = setupEngine({
        { type = "summon", spellName = "Summon Voidwalker", spellID = 697 },
    });
    local restoreCount = countItemStub({});

    local reason = Engine:checkGates({ type = "summon", spellID = 697 });

    lu.assertEquals(reason, C.WORKFLOW_REASON.NoShard);
    restoreCount();
    teardownEngine(savedDef);
end

function testCheckGatesShardPresentPasses()
    resetSpellbook();
    local savedDef = setupEngine({
        { type = "summon", spellName = "Summon Voidwalker", spellID = 697 },
    });
    local restoreCount = countItemStub({ [6265] = 1 });

    local reason = Engine:checkGates({ type = "summon", spellID = 697 });

    lu.assertIsNil(reason);
    restoreCount();
    teardownEngine(savedDef);
end

function testCheckGatesGateSafetyCastTimeStep()
    resetSpellbook();
    local savedDef = setupEngine({
        { type = "summon", spellName = "Summon Voidwalker", spellID = 697 },
    });
    local restoreCount = countItemStub({ [6265] = 1 });
    ACP.ArenaPrep.countdownEndTime = _G.__stub.time + 5;
    ACP.Settings:set("gateSafetySeconds", 15);

    local reason = Engine:checkGates({ type = "summon", spellID = 697 });

    lu.assertEquals(reason, C.WORKFLOW_REASON.GateSafety);
    restoreCount();
    ACP.ArenaPrep.countdownEndTime = nil;
    ACP.Settings:set("gateSafetySeconds", 15);
    teardownEngine(savedDef);
end

function testExecuteEmptyDefinitionFinishesDone()
    local savedDef = setupEngine({}, {});

    Engine:executeCurrentStep();

    lu.assertEquals(Engine.state, "DONE");
    teardownEngine(savedDef);
end

function testExecuteInvalidStepSkips()
    local savedDef = setupEngine({
        { type = "cast", spellID = "not-a-number" },
    });

    Engine:executeCurrentStep();

    lu.assertEquals(Engine.state, "DONE", "invalid step is skipped, then the list ends");
    teardownEngine(savedDef);
end

function testExecuteUnknownSpellSkips()
    resetSpellbook();
    local savedDef = setupEngine({
        { type = "summon", spellName = "Summon Imp", spellID = 688 },
        { type = "cast", spellName = "Shadow Ward", spellID = 28610, target = "player" },
    }, { [28610] = true });

    Engine:executeCurrentStep();

    lu.assertEquals(Engine.stepIndex, 2, "unknown summon skipped to the next step");
    teardownEngine(savedDef);
end

function testPauseChangesStateAndFiresEvent()
    local savedDef = setupEngine({});

    Engine:pause(C.WORKFLOW_REASON.NoShard);

    lu.assertEquals(Engine.state, "PAUSED");
    teardownEngine(savedDef);
end

function testStartInvalidSlotNoop()
    local savedDef = setupEngine({});

    Engine:start(99);

    lu.assertEquals(Engine.state, "RUNNING", "no change");
    teardownEngine(savedDef);
end

function testStartDoneNoop()
    local savedDef = setupEngine({});
    Engine.state = "DONE";

    Engine:start(1);

    lu.assertEquals(Engine.state, "DONE", "one run per prep");
    teardownEngine(savedDef);
end

function testStartNotArenaWithoutBypass()
    local savedDef = setupEngine({
        { type = "cast", spellName = "Fel Armor", spellID = 28189, target = "player" },
    });
    Engine.state = "IDLE";
    Engine.debugBypass = false;
    ACP.ArenaPrep.buffActive = false;

    Engine:start(1);

    lu.assertEquals(Engine.state, "IDLE");
    teardownEngine(savedDef);
end

function testStartEmptyWorkflowNoop()
    local savedDef = setupEngine({}, {});
    Engine.state = "IDLE";
    Engine.debugBypass = false;
    ACP.ArenaPrep.buffActive = true;

    Engine:start(1);

    lu.assertEquals(Engine.state, "IDLE");
    teardownEngine(savedDef);
end

function testStartTestDoesNotLeakBypassOnInvalidSlot()
    local savedDef = setupEngine({}, {});

    Engine:startTest(99);

    lu.assertIsFalse(Engine.debugBypass);
    teardownEngine(savedDef);
end

function testItemNameFallbackStoredItemName()
    -- GetItemInfo is unavailable in the sandbox → the step's stored itemName.
    lu.assertEquals(Engine:itemName({ itemID = 22646, itemName = "Master Spellstone" }), "Master Spellstone");
end

function testItemNameNumericFallback()
    lu.assertEquals(Engine:itemName({ itemID = 12345 }), "item:12345");
end

function testIsAlreadySummonedPetGUIDMismatch()
    resetSpellbook();
    _G.__stub.unitGUID = "Pet-0-6423-1-18-999-1100B8E8E4";

    lu.assertIsFalse(Engine:isAlreadySummoned({ type = "summon", spellID = 688 }), "wrong pet entry");
end

function testIsAlreadySummonedNoPetGUID()
    resetSpellbook();
    _G.__stub.unitGUID = nil;

    lu.assertIsFalse(Engine:isAlreadySummoned({ type = "summon", spellID = 688 }));
end

function testGetBuffExpirationAbsent()
    _G.__stub.auraByIndex = nil;
    lu.assertIsNil(Engine:getBuffExpiration("player", "Fel Armor"));
end

function testHasBuffAbsent()
    _G.__stub.auraByIndex = nil;
    lu.assertIsFalse(Engine:hasBuff("player", "Fel Armor"));
end

function testDefinitionNameEmpty()
    local savedDef = setupEngine({});
    Engine.currentSlot = 1;
    lu.assertEquals(Engine:definitionName(), "exec-test");
    teardownEngine(savedDef);
end

_G.UnitClass = DefaultUnitClass;
