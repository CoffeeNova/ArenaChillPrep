-- ArenaChillPrep — Tests/Classes/test_workflowrepository.lua
-- Covers Classes/WorkflowRepository.lua: the settings paths, workflowCount,
-- the CRUD operations (addWorkflow/deleteWorkflow/addStep/removeStep/
-- moveStep) and the step factory (buildStep) + findSpell.

local ACP = _G.ACP;
local Repo = ACP.WorkflowRepository;
local H = dofile(_G.__TESTS_ROOT .. "/helpers.lua");

-- The repository persists mutations into ArenaChillPrepCharDB (a reference
-- to Settings.WorkflowData) — nuke it so every test starts from pristine
-- defaults and mutations never leak into other suites.
local function resetSettings()
    _G.ArenaChillPrepCharDB = nil;
    H.resetAll();
end

function testPaths()
    resetSettings();
    lu.assertEquals(Repo:definitionPath(1), "workflows.definitions.1");
    lu.assertEquals(Repo:stepsPath(2), "workflows.definitions.2.steps");
    lu.assertEquals(Repo:stepPath(3, 4), "workflows.definitions.3.steps.4");
end

function testWorkflowCountDefaults()
    resetSettings();
    lu.assertEquals(Repo:workflowCount(), ACP.Data.Constants.WORKFLOW_DEFAULT_SLOTS);
end

function testWorkflowCountClamped()
    resetSettings();
    ACP.Settings:set("workflows.slotCount", 99);
    lu.assertEquals(Repo:workflowCount(), ACP.Data.Constants.WORKFLOW_MAX_SLOTS);
    ACP.Settings:set("workflows.slotCount", 1);
    lu.assertEquals(Repo:workflowCount(), ACP.Data.Constants.WORKFLOW_DEFAULT_SLOTS);
end

function testAddWorkflow()
    resetSettings();
    local slot = Repo:addWorkflow();
    lu.assertEquals(slot, 6);
    lu.assertEquals(ACP.Settings:get("workflows.slotCount"), 6);
    lu.assertEquals(ACP.Settings:get("workflows.definitions.6.enabled"), false);
end

function testAddWorkflowAtLimit()
    resetSettings();
    ACP.Settings:set("workflows.slotCount", ACP.Data.Constants.WORKFLOW_MAX_SLOTS);
    lu.assertNil(Repo:addWorkflow());
end

function testDeleteWorkflowAtFloorResets()
    resetSettings();
    ACP.Settings:set("workflows.definitions.1", { enabled = true, name = "x", steps = { { type = "cast", spellID = 1 } } });
    local count = Repo:deleteWorkflow(1);
    lu.assertEquals(count, ACP.Data.Constants.WORKFLOW_DEFAULT_SLOTS);
    local def = ACP.Settings:get("workflows.definitions.1");
    lu.assertEquals(def.enabled, false);
    lu.assertEquals(def.name, "");
    lu.assertEquals(#def.steps, 0);
end

function testDeleteWorkflowShifts()
    resetSettings();
    ACP.Settings:set("workflows.slotCount", 6);
    ACP.Settings:set("workflows.definitions.6", { enabled = true, name = "six", steps = {} });
    ACP.Settings:set("workflows.definitions.5", { enabled = true, name = "five", steps = {} });
    local count = Repo:deleteWorkflow(5);
    lu.assertEquals(count, 5);
    lu.assertEquals(ACP.Settings:get("workflows.definitions.5.name"), "six");
    lu.assertNil(ACP.Settings:get("workflows.definitions.6"));
end

function testBuildStepCastBuff()
    resetSettings();
    local entry = { spellID = 28176, name = "Fel Armor", category = "buffs", buffSpellID = 28176 };
    local step = Repo:buildStep(entry, nil);
    lu.assertEquals(step.type, "cast");
    lu.assertEquals(step.spellID, 28176);
    lu.assertEquals(step.target, "player");
    lu.assertEquals(step.skipIfBuffed, true); -- skipIfBuffedDefault is true
end

function testBuildStepSummon()
    resetSettings();
    local entry = { spellID = 712, name = "Summon Succubus", category = "summons", isCastTime = true };
    local step = Repo:buildStep(entry, nil);
    lu.assertEquals(step.type, "summon");
    lu.assertNil(step.target);
    lu.assertEquals(step.skipIfBuffed, true);
end

function testBuildStepCreateItem()
    resetSettings();
    local entry = { spellID = 27230, name = "Create Healthstone", category = "createItem", itemID = 22105 };
    local step = Repo:buildStep(entry, nil);
    lu.assertEquals(step.type, "createItem");
    lu.assertEquals(step.itemID, 22105);
    lu.assertEquals(step.skipIfBuffed, true);
end

function testBuildStepPetPartyCastable()
    resetSettings();
    local entry = { spellID = 27269, name = "Fire Shield", category = "pets", isPetSpell = true, canTargetParty = true };
    local step = Repo:buildStep(entry, nil);
    lu.assertEquals(step.type, "pet");
    lu.assertEquals(step.target, "player");
    lu.assertNil(step.skipIfBuffed);
end

function testAddStepEquipItem()
    resetSettings();
    local ok = Repo:addStep(1, "item:22646");
    lu.assertIsTrue(ok);
    local steps = Repo:getSteps(1);
    local step = steps[#steps];
    lu.assertEquals(step.type, "equipItem");
    lu.assertEquals(step.itemID, 22646);
    lu.assertEquals(step.itemName, "Master Spellstone");
    Repo:removeStep(1, #steps);
end

function testAddStepBySpellID()
    resetSettings();
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    local Spellbook = ACP.WorkflowSpellbook;
    Spellbook:_reset();
    Spellbook:mergeStaticWarlock();
    local ok = Repo:addStep(1, 27230);
    lu.assertIsTrue(ok);
    local steps = Repo:getSteps(1);
    local step = steps[#steps];
    lu.assertEquals(step.type, "createItem");
    lu.assertEquals(step.spellID, 27230);
    Repo:removeStep(1, #steps);
    Spellbook:_reset();
end

function testAddStepByGroup()
    resetSettings();
    local Spellbook = ACP.WorkflowSpellbook;
    Spellbook.groupsByName["Test Group"] = {
        key = "Test Group",
        name = "Test Group",
        category = "buffs",
        entries = { { spellID = 1, name = "Test", category = "buffs", buffSpellID = 1 } },
    };
    local ok = Repo:addStep(1, "Test Group");
    lu.assertIsTrue(ok);
    local steps = Repo:getSteps(1);
    lu.assertEquals(steps[#steps].type, "cast");
    Repo:removeStep(1, #steps);
    Spellbook.groupsByName["Test Group"] = nil;
end

function testAddStepUnknownGroup()
    resetSettings();
    local before = #Repo:getSteps(1);
    local ok = Repo:addStep(1, "No Such Group");
    lu.assertIsFalse(ok);
    lu.assertEquals(#Repo:getSteps(1), before);
end

function testRemoveStep()
    resetSettings();
    local before = #Repo:getSteps(1);
    local ok = Repo:removeStep(1, before);
    lu.assertIsTrue(ok);
    lu.assertEquals(#Repo:getSteps(1), before - 1);
end

function testRemoveStepOutOfRange()
    resetSettings();
    local before = #Repo:getSteps(1);
    lu.assertIsFalse(Repo:removeStep(1, before + 5));
    lu.assertEquals(#Repo:getSteps(1), before);
end

function testMoveStep()
    resetSettings();
    local steps = Repo:getSteps(1);
    local first = steps[1];
    local second = steps[2];
    lu.assertIsTrue(Repo:moveStep(1, 1, 1));
    lu.assertEquals(Repo:getSteps(1)[1], second);
    lu.assertEquals(Repo:getSteps(1)[2], first);
    Repo:moveStep(1, 1, 1); -- restore
end

function testMoveStepOutOfRange()
    resetSettings();
    lu.assertIsFalse(Repo:moveStep(1, 1, -1)); -- no step 0
    lu.assertIsFalse(Repo:moveStep(1, #Repo:getSteps(1), 1)); -- past the end
end

function testFindSpellFromCatalog()
    resetSettings();
    local entry, category = Repo:findSpell(688);
    lu.assertNotIsNil(entry);
    lu.assertEquals(entry.name, "Summon Imp");
    lu.assertEquals(category, "summons");
end

function testFindSpellUnknownReturnsNil()
    resetSettings();
    lu.assertNil(Repo:findSpell(123456));
end

function testFindSpellByNameFallback()
    -- A learned rank ID outside the static catalog matches by localized name.
    resetSettings();
    _G.__stub.spellInfo = { [999999] = "Summon Imp" };
    local entry, category = Repo:findSpell(999999);
    lu.assertNotIsNil(entry);
    lu.assertEquals(category, "summons");
    _G.__stub.spellInfo = {};
end

function testAddStepBySpellIDFallsBackToCatalog()
    -- With an EMPTY runtime spellbook the numeric Add Step key falls back to
    -- the static catalog (findSpell).
    resetSettings();
    local Spellbook = ACP.WorkflowSpellbook;
    Spellbook:_reset();
    local ok = Repo:addStep(1, 688);
    lu.assertIsTrue(ok);
    local steps = Repo:getSteps(1);
    lu.assertEquals(steps[#steps].type, "summon");
    Repo:removeStep(1, #steps);
    Spellbook:_reset();
end

return ACP;
