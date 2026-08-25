-- ArenaChillPrep — Tests/Classes/test_workflowengine.lua
-- Covers Classes/WorkflowEngine.lua: rank-resolution for conjure/createItem
-- steps (an unlearned lower rank must upgrade to the player's known rank) and
-- the rank-aware createItem completion check.
--
-- Driven through _G.__stub.knownSpells (IsPlayerSpell) and the real
-- WorkflowSpellbook catalog (mergeStaticWarlock). No timers/UI involved.

local ACP = _G.ACP;
local Engine = ACP.WorkflowEngine;
local Spellbook = ACP.WorkflowSpellbook;
local H = dofile(_G.__TESTS_ROOT .. "/helpers.lua");

local function resetSpellbook()
    Spellbook:_reset();
    Spellbook:mergeStaticWarlock();
end

-- Override slot 1's key onto its secure button from a clean binding state.
-- The override does NOT displace the command binding (unlike SetBindingClick),
-- so the Key Bindings UI / key capture keep working — real client semantics.
local function applyFreshSlotBindings(key)
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.overrideClicks = {};
    Engine.slotKeys = {};
    Engine:applySlotBindings();
end

function testGetHighestKnownRankPicksKnownMax()
    -- Arrange: player knows only rank 6 (27230) of Create Healthstone.
    _G.__stub.knownSpells = { [27230] = true };
    resetSpellbook();

    -- Act
    local entry = Spellbook:getHighestKnownRank("Create Healthstone");

    -- Assert
    lu.assertEquals(entry.spellID, 27230);
    lu.assertEquals(entry.itemID, 22105);
end

function testGetHighestKnownRankNilWhenNoneKnown()
    -- Arrange: player knows no Create Healthstone rank.
    _G.__stub.knownSpells = {};
    resetSpellbook();

    -- Act
    local entry = Spellbook:getHighestKnownRank("Create Healthstone");

    -- Assert
    lu.assertNil(entry);
end

function testResolveCastInfoUpgradesUnlearnedLowerRank()
    -- Arrange: step stored rank 5 (11730/19012); player knows rank 6.
    _G.__stub.knownSpells = { [27230] = true };
    resetSpellbook();

    -- Act
    local castSpellID, castItemID = Engine:resolveCastInfo({ spellID = 11730, itemID = 19012 });

    -- Assert: cast the known max rank, expect its item (auto-upgrade).
    lu.assertEquals(castSpellID, 27230);
    lu.assertEquals(castItemID, 22105);
end

function testResolveCastInfoKeepsKnownRank()
    -- Arrange: step stored rank 6 (27230/22105); player knows it.
    _G.__stub.knownSpells = { [27230] = true };
    resetSpellbook();

    -- Act
    local castSpellID, castItemID = Engine:resolveCastInfo({ spellID = 27230, itemID = 22105 });

    -- Assert: unchanged.
    lu.assertEquals(castSpellID, 27230);
    lu.assertEquals(castItemID, 22105);
end

function testResolveCastInfoKeepsKnownLowerRank()
    -- Arrange: step stored rank 5 (11730/19012); player knows rank 5 (and 6).
    -- The stored, castable rank must be used verbatim — no forced upgrade to
    -- rank 6, which would create the wrong item (Master instead of Major).
    _G.__stub.knownSpells = { [11730] = true, [27230] = true };
    resetSpellbook();

    -- Act
    local castSpellID, castItemID = Engine:resolveCastInfo({ spellID = 11730, itemID = 19012 });

    -- Assert
    lu.assertEquals(castSpellID, 11730);
    lu.assertEquals(castItemID, 19012);
end

function testResolveExpectedItemsFamilyForKnownRank()
    -- Arrange: cast rank 6 Create Healthstone.
    _G.__stub.knownSpells = { [27230] = true };
    resetSpellbook();

    -- Act
    local ids = Engine:resolveExpectedItems(27230, 22105);

    -- Assert: only the max-rank item (no lower rank in the family).
    lu.assertEquals(#ids, 1);
    lu.assertEquals(ids[1], 22105);
end

function testResolveExpectedItemsFamilyForLowerRank()
    -- Arrange: the UNLEARNED-rank fallback for a rank-5 step — the cast is
    -- upgraded to a higher known rank (Master 22105), so both rank >= 5 items
    -- (each expanded to its variant pair) must be accepted.
    _G.__stub.knownSpells = { [27230] = true };
    resetSpellbook();

    -- Act
    local ids = Engine:resolveExpectedItems(11730, 19012);

    -- Assert: rank >= 5 family = { Major 19012, Major 19013, Master 22105 }.
    local found = {};
    for _, id in ipairs(ids) do found[id] = true; end
    lu.assertEquals(#ids, 3);
    lu.assertTrue(found[19012], "19012 accepted");
    lu.assertTrue(found[19013], "19013 (conjured variant) accepted");
    lu.assertTrue(found[22105], "22105 accepted");
end

function testResolveExpectedItemsNonStoneFallsBackToItem()
    -- Arrange: a non-stone createItem (e.g. Create Soulstone 693/22103).
    _G.__stub.knownSpells = {};
    resetSpellbook();

    -- Act
    local ids = Engine:resolveExpectedItems(693, 22103);

    -- Assert: exact itemID fallback.
    lu.assertEquals(#ids, 1);
    lu.assertEquals(ids[1], 22103);
end

-- Regression: resolveCastInfo must be a TOP-LEVEL method available immediately
-- after load, NOT a function nested inside getCatalogEntry (a structurally
-- corrupt edit assigned it only as a side effect of getCatalogEntry — which
-- skipped for spellbook-known spells, leaving it nil and crashing castSpell
-- at runtime, e.g. "Summon Imp"). Reload the engine fresh (new table) and
-- confirm resolveCastInfo is callable with no prior getCatalogEntry call.
function testResolveCastInfoAvailableImmediatelyAfterLoad()
    -- Arrange: fresh engine module (pristine table, no side effects).
    H.reloadModule("Classes/WorkflowEngine.lua");
    local fresh = ACP.WorkflowEngine;

    -- Act: call resolveCastInfo with no earlier getCatalogEntry invocation.
    local ok, castSpellID = pcall(fresh.resolveCastInfo, fresh, { spellID = 688, itemID = 6265 });

    -- Assert: method exists and runs (Summon Imp 688 is spellbook-known — the
    -- exact case that crashed on the nested-function corruption).
    lu.assertTrue(ok);
    lu.assertEquals(castSpellID, 688);
end

-- Regression: at level 70 the client may report the unlearned lower rank 11730
-- as "known" via IsPlayerSpell (so the old code cast 11730 and silently stalled).
-- resolveCastInfo must ALWAYS resolve to the HIGHEST known rank of the family
-- (27230), even when the stored lower rank is also "known".
function testResolveCastInfoUpgradesUnlearnedLowRankViaFamilyGroup()
    -- Arrange: step stored rank 1 (6201, unlearned); player knows rank 6. The
    -- upgrade must resolve through the family group "Create Healthstone", not
    -- the rank-suffixed localized name the spellbook scan reports.
    _G.__stub.knownSpells = { [27230] = true };
    resetSpellbook();

    -- Act
    local castSpellID, castItemID = Engine:resolveCastInfo({ spellID = 6201, itemID = 19004 });

    -- Assert: upgrades to the known max rank (Master 27230 / 22105).
    lu.assertEquals(castSpellID, 27230);
    lu.assertEquals(castItemID, 22105);
end

-- Regression: when a cast-time step (e.g. Summon Imp) is immediately followed by
-- a pet step (e.g. Fire Shield), the pet ability is ARMED to be cast DURING the
-- player's cast. The slot key is PERMANENTLY click-bound to the slot's secure
-- button (applySlotBindings — no takeover/release dance anymore, 2026-08-22),
-- so the second press (for the pet ability) clicks the pet-macro button and
-- onSecurePress fires (the "Fire Shield doesn't get pressed / workflow stalls"
-- bug). The arming block re-points the button at the pet macro.
function testOnKeyPressedArmsPetStepAndKeepsKeyTakenOver()
    -- Arrange
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    Spellbook:_reset();
    Spellbook:mergeStaticWarlock();
    Spellbook:addStaticFallback(); -- populates summons (688) with isCastTime

    local key = "F9";
    local buttonName = ACP.Data.Constants.WORKFLOW_BUTTON_NAME .. "1";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.overrideClicks = {};

    Engine:_init();
    applyFreshSlotBindings(key);
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";
    Engine.waitingForCast = false;
    Engine.waitingForKey = false;
    Engine.waitingForPet = false;
    Engine.pendingPetStep = nil;

    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "pet-test", steps = {
            { type = "summon", spellID = 688, spellName = "Summon Imp" },
            { type = "pet", spellID = 27269, spellName = "Fire Shield" },
        },
    };

    -- Act: simulate the player's cast being accepted (SENT/START -> onKeyPressed).
    Engine:onKeyPressed();

    -- Assert: pet step armed AND the key is still click-bound to the slot
    -- button (no release — the 2nd press lands on the pet macro directly).
    lu.assertEquals(Engine.pendingPetStep, 2);
    lu.assertEquals(Engine.waitingForPet, true);
    lu.assertEquals(_G.__stub.overrideClicks[key], buttonName);

    -- Cleanup
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    Engine.slotKeys = {};
    Engine.state = "IDLE";
    Engine.currentSlot = nil;
    Engine.stepIndex = 1;
    Engine.pendingPetStep = nil;
    Engine.waitingForPet = false;
    Engine.waitingForCast = false;
    Engine.waitingForKey = false;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
    _G.__stub.overrideClicks = nil;
end

-- Regression: a pet-ability macro that does not bake an explicit target only
-- fires when the PLAYER has a target selected (the pet then casts on it). A
-- self/party pet step must therefore always include [@unit] so the pet casts
-- regardless of the player's current selection. The @unit form is the
-- 20506-reliable conditional — live tests showed the old [target=party1] form
-- falling through to the player (the imp buffed the warlock instead of the
-- mate, 2026-08-22).
function testPetAbilityMacroBakesExplicitTarget()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    Engine:_init();
    Engine.currentSlot = 1;
    Engine.state = "RUNNING";
    Engine.waitingForPet = false;
    Engine.waitingForKey = false;

    -- Act + Assert: self-targeted -> [pet:imp,@player] (plain /cast silently
    -- did nothing without a manual target selection; the pet conditional makes
    -- the macro a no-op when the imp is not out — no cast interruption).
    Engine:petAbility({ type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" });
    lu.assertEquals(Engine.castButton.attributes.macrotext, "/cast [pet:imp,@player] Fire Shield");

    -- Party-targeted keeps its explicit unit.
    Engine:petAbility({ type = "pet", spellID = 27269, spellName = "Fire Shield", target = "party1" });
    lu.assertEquals(Engine.castButton.attributes.macrotext, "/cast [pet:imp,@party1] Fire Shield");
    lu.assertNil(Engine.castButton.attributes.unit, "a stale cast unit must not leak into a pet macro");

    -- The Voidwalker's Sacrifice bakes its own pet conditional.
    Engine:petAbility({ type = "pet", spellID = 7812, spellName = "Sacrifice" });
    lu.assertEquals(Engine.castButton.attributes.macrotext, "/cast [pet:voidwalker,@player] Sacrifice");

    -- Cleanup
    Engine.waitingForPet = false;
    Engine.waitingForKey = false;
    Engine.state = "IDLE";
end

-- Regression: consecutive pet steps (e.g. Fire Shield x2). The FIRST key press
-- completes the pet step via onSecurePress; the key stays click-bound to the
-- slot button (no takeover/release anymore, 2026-08-22), so the NEXT pet step
-- re-arms the same button and resolves the key from the remembered slotKeys.
-- Previously the second pet step found no key, paused with "noHotkey", and the
-- next press restarted the workflow from step 1 (the ";" infinite loop).
function testConsecutivePetStepsDoNotPauseNoHotkey()
    -- Arrange
    local key = "F9";
    local buttonName = ACP.Data.Constants.WORKFLOW_BUTTON_NAME .. "1";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.overrideClicks = {};
    _G.__stub.dead = false;
    _G.__stub.inCombat = false;
    local savedCountdown = ACP.ArenaPrep.countdownEndTime;
    ACP.ArenaPrep.countdownEndTime = nil;
    Engine:_init();
    applyFreshSlotBindings(key);
    Engine.debugBypass = true;
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";
    Engine.waitingForPet = false;
    Engine.waitingForKey = false;

    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "pet-chain", steps = {
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
        },
    };

    -- Act: run step 1 (arms the button), then simulate the user's press
    -- (the buff landed -> the press verifies immediately).
    _G.__stub.auraByIndex = { name = "Fire Shield" };
    Engine:executeCurrentStep();
    Engine:onSecurePress(1);

    -- Assert: advanced to step 2, still RUNNING and waiting for the key again.
    lu.assertEquals(Engine.state, "RUNNING");
    lu.assertEquals(Engine.stepIndex, 2);
    lu.assertEquals(Engine.waitingForPet, true);
    lu.assertEquals(_G.__stub.overrideClicks[key], buttonName);

    -- Cleanup
    _G.__stub.auraByIndex = nil;
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    ACP.ArenaPrep.countdownEndTime = savedCountdown;
    Engine.slotKeys = {};
    Engine:reset();
    Engine.debugBypass = false;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
    _G.__stub.overrideClicks = nil;
end

-- Regression: applySlotBindings overrides each slot's Key Bindings UI key onto
-- that slot's secure button via SetOverrideBindingClick — the player's COMMAND
-- binding stays intact (the displaced-command approach broke key assignment,
-- live 2026-08-22). resolveCastKey must return the remembered slot key and
-- fall back to the /acp bind hotkey for unbound slots.
function testResolveCastKeyReturnsSlotKey()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    Engine:_init();
    applyFreshSlotBindings(key);
    Engine.currentSlot = 1;

    -- The override must NOT displace the command binding (the Key Bindings UI
    -- and the Workflows key capture rely on GetBindingKey).
    lu.assertEquals(_G.__stub.bindingKeys["ACP_WORKFLOW1"], key);
    lu.assertEquals(_G.__stub.overrideClicks[key], ACP.Data.Constants.WORKFLOW_BUTTON_NAME .. "1");

    -- Act
    local resolved = Engine:resolveCastKey(1);

    -- Assert: the remembered slot key wins; unbound slots fall back to the
    -- /acp bind hotkey (nil here — no hotkey configured in the test DB).
    lu.assertEquals(resolved, key);
    lu.assertNil(Engine:resolveCastKey(2));

    -- Cleanup
    Engine.slotKeys = {};
    Engine.currentSlot = nil;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
    _G.__stub.overrideClicks = nil;
end

-- Regression: a completed workflow must NOT go a second round — after DONE a
-- key press is a no-op in BOTH modes (the user complained the workflow kept
-- re-running and re-buffing, 2026-08-22). A fresh run starts on ACP_BUFF_LOST
-- (new arena) or by re-issuing /acp workflowtest, which resets explicitly.
function testStartInDebugBypassNoopAfterDone()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    Engine:_init();
    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "rerun-test", steps = {
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
        },
    };
    Engine.debugBypass = true;
    Engine.state = "DONE"; -- simulate a previous completed run
    Engine.currentSlot = 1;
    Engine.stepIndex = 8;

    -- Act: the workflow key is pressed again after completion.
    Engine:start(1);

    -- Assert: still DONE — the key press must NOT reset/restart the workflow.
    lu.assertEquals(Engine.state, "DONE");
    lu.assertEquals(Engine.stepIndex, 8);

    -- An explicit reset (the /acp workflowtest path) re-arms a fresh run.
    Engine:reset();
    lu.assertEquals(Engine.state, "IDLE");
    lu.assertNil(Engine.currentSlot);
    lu.assertEquals(Engine.stepIndex, 1);

    -- Cleanup
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    Engine.debugBypass = false;
    Engine.state = "IDLE";
    Engine.currentSlot = nil;
end

-- Regression: with debugBypass on, start() from PAUSED must RESUME (state
-- RUNNING, same stepIndex) — not reset to step 1. The old "reset from any
-- non-IDLE state" guard silently rewound a paused workflow (part of the ";"
-- reset loop from the user's log).
function testStartInDebugBypassResumesPaused()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.dead = false;
    _G.__stub.inCombat = false;
    local savedCountdown = ACP.ArenaPrep.countdownEndTime;
    ACP.ArenaPrep.countdownEndTime = nil;
    Engine:_init();
    applyFreshSlotBindings(key);
    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "resume-test", steps = {
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
        },
    };
    Engine.debugBypass = true;
    Engine.state = "PAUSED";
    Engine.currentSlot = 1;
    Engine.stepIndex = 3;

    -- Act
    Engine:start(1);

    -- Assert: resumed at the SAME step (3), not rewound to step 1.
    lu.assertEquals(Engine.state, "RUNNING");
    lu.assertEquals(Engine.stepIndex, 3);
    lu.assertEquals(Engine.waitingForPet, true);

    -- Cleanup
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    ACP.ArenaPrep.countdownEndTime = savedCountdown;
    Engine.slotKeys = {};
    Engine:reset();
    Engine.debugBypass = false;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
end

-- Regression: the "skip completed steps" setting now applies to summon steps —
-- a summon step is skipped when the pet is already out
-- (matched by the pet's creature entry ID, locale-independent).
function testIsAlreadySummonedMatchesPetEntry()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    Engine:_init();

    -- Act + Assert: Imp (688 -> petEntry 416) out.
    _G.__stub.unitGUID = "Pet-0-6423-1-18-416-1100B8E8E4";
    lu.assertTrue(Engine:isAlreadySummoned({ type = "summon", spellID = 688 }));

    -- A different pet (Voidwalker 1860) does NOT match the Imp step.
    _G.__stub.unitGUID = "Pet-0-6423-1-18-1860-1100B8E8E4";
    lu.assertFalse(Engine:isAlreadySummoned({ type = "summon", spellID = 688 }));

    -- No pet at all -> not summoned.
    _G.__stub.unitGUID = nil;
    lu.assertFalse(Engine:isAlreadySummoned({ type = "summon", spellID = 688 }));

    -- Cleanup
    Engine:reset();
    _G.__stub.unitGUID = nil;
end

-- Regression: skip also applies to createItem steps — a createItem step is
-- skipped when its product is already in bags.
function testIsItemAlreadyPresentWhenInBags()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    Engine:_init();

    local orig = ACP.Inventory.countItem;
    ACP.Inventory.countItem = function(_, id) return id == 22105 and 1 or 0; end;

    -- Act + Assert: Master Healthstone 22105 in bags -> present.
    lu.assertTrue(Engine:isItemAlreadyPresent({ type = "createItem", spellID = 27230, itemID = 22105 }));

    -- Empty bags -> not present.
    ACP.Inventory.countItem = function() return 0; end;
    lu.assertFalse(Engine:isItemAlreadyPresent({ type = "createItem", spellID = 27230, itemID = 22105 }));

    -- Cleanup
    ACP.Inventory.countItem = orig;
    Engine:reset();
end

-- Regression: on TBC 2.5.5 the stone ranks COEXIST (verified in-game) — a
-- castable rank-5 step (11730/19012) must NOT be satisfied by a leftover
-- Master Healthstone (22105). Both Major variants count (the client conjures
-- 19013 while the step stores 19012 — live-verified 2026-08-22).
function testIsItemAlreadyPresentExactRankWhenKnown()
    -- Arrange
    _G.__stub.knownSpells = { [11730] = true };
    resetSpellbook();

    local orig = ACP.Inventory.countItem;
    ACP.Inventory.countItem = function(_, id) return id == 22105 and 1 or 0; end;

    -- Act + Assert: only the Master stone in bags -> NOT present (exact rank).
    lu.assertFalse(Engine:isItemAlreadyPresent({ type = "createItem", spellID = 11730, itemID = 19012 }));

    -- The exact Major 19012 in bags -> present.
    ACP.Inventory.countItem = function(_, id) return id == 19012 and 1 or 0; end;
    lu.assertTrue(Engine:isItemAlreadyPresent({ type = "createItem", spellID = 11730, itemID = 19012 }));

    -- The variant the client actually conjures (19013) also satisfies the step.
    ACP.Inventory.countItem = function(_, id) return id == 19013 and 1 or 0; end;
    lu.assertTrue(Engine:isItemAlreadyPresent({ type = "createItem", spellID = 11730, itemID = 19012 }));

    -- Cleanup
    ACP.Inventory.countItem = orig;
    _G.__stub.knownSpells = {};
end

-- Regression: dispatch skips a summon step when the pet is already out,
-- advancing past it without requesting a cast (the global setting governs).
function testDispatchSkipsSummonWhenPetOut()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.unitGUID = "Pet-0-6423-1-18-416-1100B8E8E4";
    _G.__stub.knownSpells = { [688] = true };
    local savedKnown = _G.__stub.knownSpells;
    Engine:_init();
    Engine.debugBypass = true;
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";

    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "summon-skip", steps = {
            { type = "summon", spellID = 688 },
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
        },
    };

    -- Act: run the first step (the skipped summon).
    Engine:executeCurrentStep();

    -- Assert: Imp already out -> step skipped, advanced to step 2 (pet step).
    lu.assertEquals(Engine.stepIndex, 2);

    -- Cleanup
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    _G.__stub.knownSpells = savedKnown;
    _G.__stub.unitGUID = nil;
    Engine:reset();
end

-- Regression: a createItem step is skipped (no cast requested) when the
-- product is already in bags.
function testDispatchSkipsCreateItemWhenPresent()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.knownSpells = { [27230] = true };
    local savedKnown = _G.__stub.knownSpells;
    Engine:_init();
    Engine.debugBypass = true;
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";

    local orig = ACP.Inventory.countItem;
    ACP.Inventory.countItem = function(_, id) return id == 22105 and 1 or 0; end;

    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "item-skip", steps = {
            { type = "createItem", spellID = 27230, itemID = 22105 },
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
        },
    };

    -- Act
    Engine:executeCurrentStep();

    -- Assert: Master Healthstone already in bags -> step skipped, advanced.
    lu.assertEquals(Engine.stepIndex, 2);

    -- Cleanup
    ACP.Inventory.countItem = orig;
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    _G.__stub.knownSpells = savedKnown;
    Engine:reset();
end

-- Regression: a createItem step with a CASTABLE stored rank is skipped only
-- when THAT rank's stone is in bags — a leftover higher-rank stone must not
-- skip it (steps 1-3 skipped in the user's log). The family-widened
-- expectation applies only to the unlearned-rank fallback.
function testDispatchSkipsCreateItemOnlyForExactRank()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.knownSpells = { [11730] = true };
    local savedKnown = _G.__stub.knownSpells;
    _G.__stub.dead = false;
    _G.__stub.inCombat = false;
    local savedCountdown = ACP.ArenaPrep.countdownEndTime;
    ACP.ArenaPrep.countdownEndTime = nil;
    Engine:_init();
    applyFreshSlotBindings(key);
    Engine.debugBypass = true;
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";

    local inBags = 22105;
    local orig = ACP.Inventory.countItem;
    ACP.Inventory.countItem = function(_, id)
        if (id == ACP.Data.Constants.SOUL_SHARD_ITEM_ID) then
            return 1;
        end

        return id == inBags and 1 or 0;
    end;

    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "exact-rank", steps = {
            { type = "createItem", spellID = 11730, itemID = 19012 },
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
        },
    };

    -- Act 1: Master 22105 in bags but NOT Major 19012 -> the rank-5 step must
    -- NOT skip (it requests the createItem key instead).
    Engine:executeCurrentStep();

    -- Assert
    lu.assertEquals(Engine.stepIndex, 1);
    lu.assertEquals(Engine.state, "RUNNING");
    lu.assertEquals(Engine.waitingForKey, true);

    -- Act 2: the exact Major 19012 in bags -> the SAME step IS skipped.
    Engine:reset();
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";
    inBags = 19012;
    Engine:executeCurrentStep();

    -- Assert
    lu.assertEquals(Engine.stepIndex, 2);

    -- Act 3: the variant the client actually conjures (19013) also skips it.
    Engine:reset();
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";
    inBags = 19013;
    Engine:executeCurrentStep();

    -- Assert
    lu.assertEquals(Engine.stepIndex, 2);

    -- Cleanup
    ACP.Inventory.countItem = orig;
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    ACP.ArenaPrep.countdownEndTime = savedCountdown;
    _G.__stub.knownSpells = savedKnown;
    Engine.slotKeys = {};
    Engine:reset();
    Engine.debugBypass = false;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
end

-- Regression: the global "skip completed steps" setting governs summon steps
-- even when the per-step flag is absent — a pet already out is skipped without
-- an explicit skipIfBuffed on the step (the "Imp already out, don't summon
-- again" bug: the existing predefined workflow's summon steps have no flag).
function testEffectiveSkipSummonHonorsGlobalDefault()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.unitGUID = "Pet-0-6423-1-18-416-1100B8E8E4";
    _G.__stub.knownSpells = { [688] = true };
    local savedKnown = _G.__stub.knownSpells;
    Engine:_init();
    Engine.debugBypass = true;
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";

    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "summon-default", steps = {
            { type = "summon", spellID = 688 }, -- no skipIfBuffed
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
        },
    };

    -- Act
    Engine:executeCurrentStep();

    -- Assert: Imp already out + global default on -> step skipped, advanced.
    lu.assertEquals(Engine.stepIndex, 2);

    -- Cleanup
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    _G.__stub.knownSpells = savedKnown;
    _G.__stub.unitGUID = nil;
    Engine:reset();
end

-- Regression (2026-08-25): the per-step skipIfBuffed flag was REMOVED — the
-- global "skip completed steps" setting alone decides. A legacy
-- skipIfBuffed=false on a saved step must NOT force the cast (it is ignored).
function testEffectiveSkipIgnoresLegacyStepFlag()
    -- Arrange
    Engine:_init();

    local savedSetting = ACP.Settings:get("workflows.skipIfBuffedDefault");
    ACP.Settings:set("workflows.skipIfBuffedDefault", true);

    -- Act + Assert: legacy flags do not override the global setting.
    lu.assertTrue(Engine:effectiveSkip({ type = "summon", spellID = 688, skipIfBuffed = false }));
    lu.assertTrue(Engine:effectiveSkip({ type = "summon", spellID = 688, skipIfBuffed = true }));
    lu.assertTrue(Engine:effectiveSkip({ type = "summon", spellID = 688 }));

    -- Non-skippable step types are never skipped (pet / equipItem).
    lu.assertFalse(Engine:effectiveSkip({ type = "pet", spellID = 27269, skipIfBuffed = true }));
    lu.assertFalse(Engine:effectiveSkip({ type = "equipItem", itemID = 22646 }));

    -- The setting OFF disables skipping regardless of any legacy flag.
    ACP.Settings:set("workflows.skipIfBuffedDefault", false);
    lu.assertFalse(Engine:effectiveSkip({ type = "summon", spellID = 688, skipIfBuffed = true }));
    lu.assertFalse(Engine:effectiveSkip({ type = "cast", spellID = 28189, skipIfBuffed = true }));
    lu.assertFalse(Engine:effectiveSkip({ type = "createItem", spellID = 27230, itemID = 22105, skipIfBuffed = true }));

    -- Cleanup
    ACP.Settings:set("workflows.skipIfBuffedDefault", savedSetting);
    Engine:reset();
end

-- Regression: healthstone ranks 1-5 are historical item-ID pairs and the
-- client conjures ONE variant per rank (rank 5 -> 19013 while the step stores
-- 19012). expandExpectedItems must return the rank's full variant set so the
-- createItem completion check accepts the variant the client actually created.
function testExpandExpectedItemsStoneVariants()
    -- Act: rank-5 Create Healthstone.
    local ids = Engine:expandExpectedItems(11730, 19012);

    -- Assert: both Major variants.
    local found = {};
    for _, id in ipairs(ids) do found[id] = true; end
    lu.assertEquals(#ids, 2);
    lu.assertTrue(found[19012], "19012 accepted");
    lu.assertTrue(found[19013], "19013 accepted");

    -- Rank 6 is a single ID.
    local ids6 = Engine:expandExpectedItems(27230, 22105);
    lu.assertEquals(#ids6, 1);
    lu.assertEquals(ids6[1], 22105);

    -- Non-stone spells fall back to the exact itemID.
    local idsSoul = Engine:expandExpectedItems(693, 22103);
    lu.assertEquals(#idsSoul, 1);
    lu.assertEquals(idsSoul[1], 22103);
end

-- Regression: a pet ability pressed DURING the previous player cast must stay
-- "done" through advance() — the cast-completion transition used to wipe
-- petStepDone, so the armed pet step was re-armed instead of skipped (the user
-- had to press the key twice and the imp re-buffed the player). The press must
-- carry over: the pet step is consumed and the engine lands on the NEXT step.
function testPetStepPressedDuringCastSurvivesAdvance()
    -- Arrange
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    Spellbook:_reset();
    Spellbook:mergeStaticWarlock();
    Spellbook:addStaticFallback();

    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.overrideClicks = {};
    _G.__stub.dead = false;
    _G.__stub.inCombat = false;
    local savedCountdown = ACP.ArenaPrep.countdownEndTime;
    ACP.ArenaPrep.countdownEndTime = nil;
    Engine:_init();
    applyFreshSlotBindings(key);
    Engine.debugBypass = true;
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";
    Engine.waitingForCast = false;
    Engine.waitingForKey = true;
    Engine.waitingForPet = false;
    Engine.pendingPetStep = nil;
    Engine.petStepDone = false;

    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "pet-during-cast", steps = {
            { type = "summon", spellID = 688, spellName = "Summon Imp" },
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
        },
    };

    -- Act 1: the player's cast key was accepted -> the pet step is armed.
    Engine:onKeyPressed();
    lu.assertEquals(Engine.pendingPetStep, 2);

    -- Act 2: the user pressed the key again DURING the cast -> the pet cast
    -- the ability and its effect is verifiable (the buff landed on the target).
    _G.__stub.auraByIndex = { name = "Fire Shield" };
    Engine:onSecurePress(1);
    lu.assertEquals(Engine.petStepDone, true);
    lu.assertNil(Engine.pendingPetStep);

    -- Act 3: the player's cast completes -> advance.
    Engine:onCastComplete();

    -- Assert: the already-cast pet step was consumed (stepIndex 3, the NEXT
    -- pet step armed) instead of re-arming step 2.
    lu.assertEquals(Engine.stepIndex, 3);
    lu.assertEquals(Engine.state, "RUNNING");
    lu.assertEquals(Engine.petStepDone, false);
    lu.assertEquals(Engine.waitingForPet, true);

    -- Cleanup
    _G.__stub.auraByIndex = nil;
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    ACP.ArenaPrep.countdownEndTime = savedCountdown;
    Engine.slotKeys = {};
    Engine:reset();
    Engine.debugBypass = false;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
    _G.__stub.overrideClicks = nil;
end

-- Regression: UNIT_SPELLCAST_SENT and UNIT_SPELLCAST_START both fire for one
-- cast; the second onKeyPressed re-armed the pet step (a live "pet ability
-- armed during cast" was logged twice per cast, 2026-08-22). The
-- waitingForCast guard must make the second event a no-op.
function testOnKeyPressedGuardIgnoresSecondCastEvent()
    -- Arrange: engine already processed the cast (waitingForCast true, pet step
    -- armed), exactly as after SENT.
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    Engine:_init();
    Engine.currentSlot = 1;
    Engine.state = "RUNNING";
    Engine.waitingForCast = true;
    Engine.waitingForKey = true;
    Engine.pendingPetStep = 2;
    Engine.waitingForPet = true;

    -- Act: the second event (START after SENT) calls onKeyPressed again.
    Engine:onKeyPressed();

    -- Assert: the armed cast-wait state is untouched (the guard bailed before
    -- re-arming).
    lu.assertEquals(Engine.waitingForKey, true);
    lu.assertEquals(Engine.waitingForCast, true);
    lu.assertEquals(Engine.pendingPetStep, 2);
    lu.assertEquals(Engine.waitingForPet, true);

    -- Cleanup
    Engine.pendingPetStep = nil;
    Engine.waitingForPet = false;
    Engine.state = "IDLE";
    Engine.currentSlot = nil;
    Engine.waitingForCast = false;
    Engine.waitingForKey = false;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
end

-- Regression: party-targeted casts used to land on the PLAYER because the
-- cast side never resolved the unit (live 2026-08-22: Fire Shield and
-- Unending Breath with target=party1 both buffed the warlock). Player casts
-- now carry the step's target in the secure button's `unit` attribute (the
-- M6 ActionBook pattern on 20506), so the client casts directly on the unit
-- regardless of the current target.
function testRequestKeyCastSetsUnitAttribute()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    Engine:_init();
    applyFreshSlotBindings(key);
    Engine.currentSlot = 1;
    Engine.state = "RUNNING";
    Engine.pendingCastSpellID = 5697;

    local slotButton = Engine.castButtons[1];

    -- Act + Assert: a party-targeted step bakes unit="party1" onto EVERY live
    -- button (the /acp bind hotkey button AND the slot button).
    Engine:requestKeyCast("Unending Breath", { type = "cast", spellID = 5697, target = "party1" });
    lu.assertEquals(Engine.castButton.attributes.unit, "party1");
    lu.assertEquals(Engine.castButton.attributes.spell, 5697);
    lu.assertEquals(slotButton.attributes.unit, "party1");
    lu.assertEquals(slotButton.attributes.spell, 5697);

    -- A self-targeted step sets unit="player" (deterministic self-cast).
    Engine:requestKeyCast("Unending Breath", { type = "cast", spellID = 5697, target = "player" });
    lu.assertEquals(Engine.castButton.attributes.unit, "player");

    -- Untargeted steps (summons/conjures) clear the unit attribute.
    Engine:requestKeyCast("Summon Imp", { type = "summon", spellID = 688 });
    lu.assertNil(Engine.castButton.attributes.unit);

    -- clearKeyCast wipes a stale unit so a later untargeted step cannot
    -- retarget at the old party member.
    Engine:requestKeyCast("Unending Breath", { type = "cast", spellID = 5697, target = "party1" });
    Engine:clearKeyCast();
    lu.assertNil(Engine.castButton.attributes.unit);
    lu.assertEquals(Engine.castButton.attributes.spell, "");
    lu.assertNil(slotButton.attributes.unit);
    lu.assertEquals(slotButton.attributes.spell, "");

    -- Cleanup
    Engine.waitingForKey = false;
    Engine.slotKeys = {};
    Engine:reset();
    Engine.debugBypass = false;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
end

-- Regression: the player's own manual cast fires UNIT_SPELLCAST_SENT too.
-- When the engine is waitingForKey (armed step), a manual cast's SENT with a
-- different spellID must NOT trigger onKeyPressed — the engine would then
-- transition to waitingForCast, the manual cast's STOP would trigger
-- onCastComplete → advance → the workflow STEP IS SKIPPED (live 2026-08-22).
function testSentGuardIgnoresManualCastSpellID()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.dead = false;
    _G.__stub.inCombat = false;
    local savedCountdown = ACP.ArenaPrep.countdownEndTime;
    ACP.ArenaPrep.countdownEndTime = nil;
    Engine:_init();
    applyFreshSlotBindings(key);
    Engine.debugBypass = true;
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";
    Engine.pendingCastSpellID = 27230;
    Engine.waitingForKey = true;
    Engine.waitingForCast = false;

    -- Act: the player manually casts Fel Armor (28189) — SENT fires with a
    -- different spellID.
    ACP.Events:fire("UNIT_SPELLCAST_SENT", "player", nil, nil, 28189);

    -- Assert: the engine was NOT fooled — the step stays armed.
    lu.assertEquals(Engine.waitingForKey, true);
    lu.assertEquals(Engine.waitingForCast, false);

    -- Cleanup
    Engine.pendingCastSpellID = nil;
    Engine.waitingForKey = false;
    Engine.state = "IDLE";
    Engine.currentSlot = nil;
    Engine.slotKeys = {};
    Engine.debugBypass = false;
    ACP.ArenaPrep.countdownEndTime = savedCountdown;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
end

-- Regression: the client silently swallows a pet ability pressed EARLY in the
-- player's cast (live 2026-08-22: Sacrifice at +2 s of a 6 s summon did
-- nothing; the +5 s press fired). The engine must NOT mark the step done on
-- the press itself -- an unverified press keeps the step armed so the user's
-- spam eventually lands the ability; the verify poll marks it done the moment
-- the effect appears.
function testPetPressNotAppliedKeepsArmedUntilVerified()
    -- Arrange
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    Spellbook:_reset();
    Spellbook:mergeStaticWarlock();
    Spellbook:addStaticFallback();

    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.overrideClicks = {};
    _G.__stub.dead = false;
    _G.__stub.inCombat = false;
    local savedCountdown = ACP.ArenaPrep.countdownEndTime;
    ACP.ArenaPrep.countdownEndTime = nil;
    Engine:_init();
    applyFreshSlotBindings(key);
    Engine.debugBypass = true;
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";
    Engine.waitingForCast = false;
    Engine.waitingForKey = true;
    Engine.waitingForPet = false;
    Engine.pendingPetStep = nil;
    Engine.petStepDone = false;

    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "pet-verify", steps = {
            { type = "summon", spellID = 688, spellName = "Summon Imp" },
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" },
        },
    };

    -- Act 1: cast accepted -> the pet step is armed.
    Engine:onKeyPressed();
    lu.assertEquals(Engine.pendingPetStep, 2);

    -- Act 2: the user presses DURING the cast, but the buff is not present
    -- (the early press was swallowed by the client).
    _G.__stub.auraByIndex = nil;
    Engine:onSecurePress(1);

    -- Assert: NOT done -- the step stays armed for the spam.
    lu.assertEquals(Engine.pendingPetStep, 2);
    lu.assertEquals(Engine.petStepDone, false);
    lu.assertEquals(Engine.waitingForPet, true);
    lu.assertEquals(Engine.waitingForKey, true);

    -- Act 3: the buff finally lands (the client applied the late press) ->
    -- the verify poll confirms and marks the step done.
    _G.__stub.auraByIndex = { name = "Fire Shield" };
    H.advance("WorkflowPetVerify");

    -- Assert
    lu.assertNil(Engine.pendingPetStep);
    lu.assertEquals(Engine.petStepDone, true);
    lu.assertEquals(Engine.waitingForPet, false);

    -- Cleanup
    _G.__stub.auraByIndex = nil;
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    ACP.ArenaPrep.countdownEndTime = savedCountdown;
    Engine.slotKeys = {};
    Engine:reset();
    Engine.debugBypass = false;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
    _G.__stub.overrideClicks = nil;
end

-- Regression: Sacrifice verification. The buff signal (the shield on the
-- warlock, matched by NAME) always counts; the Voidwalker-being-consumed
-- signal counts only while the player's cast is still in progress (after the
-- summon completes the NEW pet exists and "pet gone" proves nothing).
function testIsPetAbilityAppliedSacrifice()
    -- Arrange
    _G.__stub.auraByIndex = nil;
    Engine.waitingForCast = true;
    local realUnitExists = _G.UnitExists;
    _G.UnitExists = function(unit) return unit == "pet" or unit == "player"; end;

    -- Act + Assert: no buff, pet still out -> not applied.
    lu.assertFalse(Engine:isPetAbilityApplied({ type = "pet", spellID = 7812, spellName = "Sacrifice" }));

    -- The Voidwalker was consumed during the cast -> applied.
    _G.UnitExists = function(unit) return unit == "player"; end;
    lu.assertTrue(Engine:isPetAbilityApplied({ type = "pet", spellID = 7812, spellName = "Sacrifice" }));

    -- The shield buff also counts regardless of the pet unit.
    _G.UnitExists = realUnitExists;
    _G.__stub.auraByIndex = { name = "Sacrifice" };
    lu.assertTrue(Engine:isPetAbilityApplied({ type = "pet", spellID = 7812, spellName = "Sacrifice" }));

    -- Cleanup
    Engine.waitingForCast = false;
    _G.__stub.auraByIndex = nil;
    _G.UnitExists = realUnitExists;
end

-- Regression: gateSafety paused instant-cast steps (Soul Link, Shadow Ward)
-- in the last seconds before the gates opened — every resume was immediately
-- re-gated, creating an infinite pause loop (live 2026-08-22). Instant steps
-- and steps without a cast time (equipItem, pet abilities) are now exempt.
function testCheckGatesGateSafetySkipsInstantSteps()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.dead = false;
    _G.__stub.inCombat = false;
    _G.__stub.knownSpells = { [5697] = true };
    local savedKnown = _G.__stub.knownSpells;
    local savedCountdown = ACP.ArenaPrep.countdownEndTime;
    _G.__stub.time = 100;
    ACP.ArenaPrep.countdownEndTime = 110; -- 10 s remaining < default 15
    Engine:_init();
    Engine.debugBypass = true;

    -- Assert: an instant-cast buff step passes the gate.
    lu.assertNil(Engine:checkGates({ type = "cast", spellID = 5697, target = "player" }));

    -- A pet step (no cast time) also passes.
    lu.assertNil(Engine:checkGates({ type = "pet", spellID = 27269, target = "player" }));

    -- A cast-time step (Summon Imp) IS gated.
    lu.assertEquals(Engine:checkGates({ type = "summon", spellID = 688 }), "gateSafety");

    -- An equipItem step (no catalog entry = no cast time) passes.
    lu.assertNil(Engine:checkGates({ type = "equipItem", itemID = 22646 }));

    -- Cleanup
    ACP.ArenaPrep.countdownEndTime = savedCountdown;
    _G.__stub.knownSpells = savedKnown;
    Engine.debugBypass = false;
end

-- Regression: the player's own manual cast fires UNIT_SPELLCAST_SENT too.
-- When the engine is waitingForKey (armed step), a manual cast's SENT with a
-- different spellID must NOT trigger onKeyPressed — the engine would then
-- transition to waitingForCast, the manual cast's STOP would trigger
-- onCastComplete → advance → the workflow STEP IS SKIPPED (live 2026-08-22).
function testSentGuardIgnoresManualCastSpellID()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.dead = false;
    _G.__stub.inCombat = false;
    local savedCountdown = ACP.ArenaPrep.countdownEndTime;
    ACP.ArenaPrep.countdownEndTime = nil;
    Engine:_init();
    applyFreshSlotBindings(key);
    Engine.debugBypass = true;
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";
    Engine.pendingCastSpellID = 27230;
    Engine.waitingForKey = true;
    Engine.waitingForCast = false;

    -- Act: the player manually casts Fel Armor (28189) — SENT fires with a
    -- different spellID.
    ACP.Events:fire("UNIT_SPELLCAST_SENT", "player", nil, nil, 28189);

    -- Assert: the engine was NOT fooled — the step stays armed.
    lu.assertEquals(Engine.waitingForKey, true);
    lu.assertEquals(Engine.waitingForCast, false);

    -- Cleanup
    Engine.pendingCastSpellID = nil;
    Engine.waitingForKey = false;
    Engine.state = "IDLE";
    Engine.currentSlot = nil;
    Engine.slotKeys = {};
    Engine.debugBypass = false;
    ACP.ArenaPrep.countdownEndTime = savedCountdown;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
end

-- Regression: a step configured for a party member must not silently cast on
-- the wrong unit when that party slot does not exist (solo test, raid group,
-- member left) — the gate pauses with "noTarget" so the user sees why instead
-- of mis-buffing themselves.
function testCheckGatesRequiresPartyMember()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.dead = false;
    _G.__stub.inCombat = false;
    Engine:_init();
    Engine.debugBypass = true;
    local savedCountdown = ACP.ArenaPrep.countdownEndTime;
    ACP.ArenaPrep.countdownEndTime = nil;
    _G.__stub.partyCount = 0;

    -- Act + Assert: no party member -> both cast and pet steps gate.
    lu.assertEquals(Engine:checkGates({ type = "cast", spellID = 5697, target = "party1" }), "noTarget");
    lu.assertEquals(Engine:checkGates({ type = "pet", spellID = 27269, target = "party1" }), "noTarget");

    -- Self-targeted and untargeted steps are not gated.
    lu.assertNil(Engine:checkGates({ type = "cast", spellID = 132, target = "player" }));
    lu.assertNil(Engine:checkGates({ type = "summon", spellID = 688 }));

    -- With the party member present the gate passes.
    _G.__stub.partyCount = 1;
    lu.assertNil(Engine:checkGates({ type = "cast", spellID = 5697, target = "party1" }));
    lu.assertNil(Engine:checkGates({ type = "pet", spellID = 27269, target = "party1" }));

    -- Cleanup
    _G.__stub.partyCount = 0;
    ACP.ArenaPrep.countdownEndTime = savedCountdown;
    Engine.debugBypass = false;
end

-- Regression: arming a pet step during a SUMMON cast (pet not out yet) made a
-- mid-cast key press execute the pet macro with no pet to route it to — the
-- client treated it as a player cast, interrupted the summon and popped
-- "blocked action" (live 2026-08-22). The arm must be skipped until the pet
-- exists; the pet step then runs standalone after the summon completes.
function testOnKeyPressedDoesNotArmPetStepWithoutPet()
    -- Arrange
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    Spellbook:_reset();
    Spellbook:mergeStaticWarlock();
    Spellbook:addStaticFallback();

    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.overrideClicks = {};

    local realUnitExists = _G.UnitExists;
    _G.UnitExists = function(unit) return unit == "player"; end; -- pet NOT out

    Engine:_init();
    Engine.currentSlot = 1;
    Engine.stepIndex = 1;
    Engine.state = "RUNNING";
    Engine.waitingForCast = false;
    Engine.waitingForKey = true;
    Engine.waitingForPet = false;
    Engine.pendingPetStep = nil;

    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "summon-no-arm", steps = {
            { type = "summon", spellID = 688, spellName = "Summon Imp" },
            { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "party1" },
        },
    };

    -- Act: the summon cast is accepted while the pet is NOT out.
    Engine:onKeyPressed();

    -- Assert: the pet step is NOT armed (the buttons are made inert instead,
    -- so a mid-summon press does nothing instead of interrupting the cast).
    lu.assertNil(Engine.pendingPetStep);
    lu.assertEquals(Engine.waitingForPet, false);
    lu.assertEquals(Engine.waitingForCast, true);
    lu.assertEquals(Engine.castButton.attributes.spell, "");

    -- Cleanup
    _G.UnitExists = realUnitExists;
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    Engine.state = "IDLE";
    Engine.currentSlot = nil;
    Engine.stepIndex = 1;
    Engine.waitingForCast = false;
    Engine.waitingForKey = false;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
    _G.__stub.overrideClicks = nil;
end

-- Regression: the FIRST key press must start the workflow AND begin the first
-- step — not just print a start message (the user's complaint, 2026-08-22).
-- The slot key is permanently click-bound to the slot's secure button; the
-- PreClick hook starts the workflow and arms the first step, and the SAME
-- press's click casts it (ItemRack pattern).
function testPreClickStartsSlotAndArmsFirstStep()
    -- Arrange
    local key = "F9";
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = key };
    _G.__stub.bindingActions = { [key] = "ACP_WORKFLOW1" };
    _G.__stub.dead = false;
    _G.__stub.inCombat = false;
    _G.__stub.knownSpells = { [5697] = true };
    local savedKnown = _G.__stub.knownSpells;
    local savedCountdown = ACP.ArenaPrep.countdownEndTime;
    ACP.ArenaPrep.countdownEndTime = nil;
    Engine:_init();
    applyFreshSlotBindings(key);
    Engine.debugBypass = true;

    local savedDef = ACP.Settings.WorkflowData.definitions[1];
    ACP.Settings.WorkflowData.definitions[1] = {
        enabled = true, name = "one-press", steps = {
            { type = "cast", spellID = 5697, target = "player" },
        },
    };

    -- Act: the key press's PreClick runs BEFORE the button's secure action.
    Engine:onPreClick(1);

    -- Assert: the workflow started AND the first step is armed on the slot
    -- button — the SAME press's click will cast it (one press = start + cast).
    lu.assertEquals(Engine.state, "RUNNING");
    lu.assertEquals(Engine.currentSlot, 1);
    lu.assertEquals(Engine.stepIndex, 1);
    lu.assertEquals(Engine.waitingForKey, true);
    lu.assertEquals(Engine.castButtons[1].attributes.spell, 5697);
    lu.assertEquals(Engine.castButtons[1].attributes.unit, "player");

    -- Cleanup
    ACP.Settings.WorkflowData.definitions[1] = savedDef;
    ACP.ArenaPrep.countdownEndTime = savedCountdown;
    _G.__stub.knownSpells = savedKnown;
    Engine.slotKeys = {};
    Engine:reset();
    Engine.debugBypass = false;
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
end

-- Regression (2026-08-24 fix): a workflow slot can be bound to TWO keys in
-- the Key Bindings UI. applySlotBindings must put the priority override on
-- BOTH — otherwise the second key only fires the ACP_WORKFLOW<i> start
-- action (a no-op while running) and can never cast an armed step.
function testApplySlotBindingsOverridesSecondaryKey()
    -- Arrange: slot 1 bound to F9 (primary) + CTRL-F9 (secondary).
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = "F9" };
    _G.__stub.bindingActions = { ["F9"] = "ACP_WORKFLOW1", ["CTRL-F9"] = "ACP_WORKFLOW1" };
    _G.__stub.overrideClicks = {};
    local origGetBindingKey = _G.GetBindingKey;
    _G.GetBindingKey = function(command)
        if (command == "ACP_WORKFLOW1") then return "F9", "CTRL-F9"; end
        return nil;
    end;

    Engine:_init();
    Engine.slotKeys = {};
    -- Act
    Engine:applySlotBindings();
    -- Restore before asserting (no stub leakage on failure).
    _G.GetBindingKey = origGetBindingKey;

    -- Assert: BOTH keys are overridden to the slot's secure button; the
    -- primary key is remembered for the press prompts.
    local buttonName = ACP.Data.Constants.WORKFLOW_BUTTON_NAME .. "1";
    lu.assertEquals(_G.__stub.overrideClicks["F9"], buttonName);
    lu.assertEquals(_G.__stub.overrideClicks["CTRL-F9"], buttonName);
    lu.assertEquals(Engine.slotKeys[1], "F9");

    -- Cleanup
    Engine.slotKeys = {};
    _G.__stub.bindingKeys = nil;
    _G.__stub.bindingActions = nil;
    _G.__stub.overrideClicks = nil;
end
