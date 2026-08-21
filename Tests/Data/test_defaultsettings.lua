-- ArenaChillPrep — Tests/Data/test_defaultsettings.lua
-- Covers Data/DefaultSettings.lua: defaults structure.

local ACP = _G.ACP;
local D = ACP.Data.DefaultSettings;

function testDefaultsMasterSwitch()
    -- Arrange
    -- Act
    -- Assert
    lu.assertIsTrue(D.enabled);
    lu.assertEquals(D.tradeDelay, 1.5);
    lu.assertEquals(D.gateSafetySeconds, 15);
end

function testDefaultsBrackets()
    -- Arrange
    -- Act
    -- Assert
    lu.assertIsTrue(D.brackets["2v2"]);
    lu.assertIsFalse(D.brackets["3v3"]);
    lu.assertIsFalse(D.brackets["5v5"]);
end

function testDefaultsHealthstone()
    -- Arrange
    -- Act
    -- Assert
    lu.assertIsTrue(D.items.healthstone.enabled);
    lu.assertEquals(D.items.healthstone.count, 1);
    lu.assertIsTrue(D.items.healthstone.ranks[19012]);
    lu.assertIsTrue(D.items.healthstone.ranks[19013]);
    lu.assertIsTrue(D.items.healthstone.ranks[22105]);
end

-- Every default step must pass the step schema validator (so the shipped
-- defaults can never break the engine with an invalid step).
function testDefaultsWorkflowStepsValid()
    -- Arrange
    -- Act
    -- Assert
    for slot = 1, 5 do
        local definition = D.workflows.definitions[slot];

        if (type(definition) == "table" and type(definition.steps) == "table") then
            for _, step in ipairs(definition.steps) do
                local ok, err = ACP.Data.Workflows:validateStep(step);
                lu.assertIsTrue(ok, ("slot %d invalid step: %s"):format(slot, tostring(err)));
            end
        end
    end
end

-- Slot 1 mirrors the user's m6 macro: imp, healthstones, spellstone,
-- felhunter, soul link, buffs, equip Master Spellstone.
function testDefaultsWorkflow1Macro()
    -- Arrange
    -- Act
    local def = D.workflows.definitions[1];
    -- Assert
    lu.assertEquals(def.enabled, true);
    lu.assertEquals(def.name, "2s full prep");
    lu.assertEquals(#def.steps, 14);
    lu.assertEquals(def.steps[1].type, "summon");
    lu.assertEquals(def.steps[1].spellID, 688);
    lu.assertEquals(def.steps[2].type, "createItem");
    lu.assertEquals(def.steps[2].spellID, 27230);
    lu.assertEquals(def.steps[2].itemID, 22105);
    lu.assertEquals(def.steps[4].type, "createItem");
    lu.assertEquals(def.steps[4].spellID, 28172);
    lu.assertEquals(def.steps[4].itemID, 22646);
    lu.assertEquals(def.steps[5].spellID, 691);
    lu.assertEquals(def.steps[6].spellID, 19028);
    lu.assertEquals(def.steps[6].skipIfBuffed, true);
    lu.assertEquals(def.steps[9].spellID, 28189);
    lu.assertEquals(def.steps[10].spellID, 5697);
    lu.assertEquals(def.steps[11].spellID, 132);
    lu.assertEquals(def.steps[14].type, "equipItem");
    lu.assertEquals(def.steps[14].itemID, 22646);
    lu.assertEquals(def.steps[14].itemName, "Master Spellstone");
end

-- Slot 2 is the same macro without Soul Link, with a Voidwalker.
function testDefaultsWorkflow2Macro()
    -- Arrange
    -- Act
    local def = D.workflows.definitions[2];
    -- Assert
    lu.assertEquals(def.enabled, false);
    lu.assertEquals(def.name, "Full prep (Voidwalker)");
    lu.assertEquals(#def.steps, 13);
    lu.assertEquals(def.steps[1].spellID, 688);
    lu.assertEquals(def.steps[7].type, "summon");
    lu.assertEquals(def.steps[7].spellID, 697);
    lu.assertEquals(def.steps[13].type, "equipItem");
    lu.assertEquals(def.steps[13].itemID, 22646);
end