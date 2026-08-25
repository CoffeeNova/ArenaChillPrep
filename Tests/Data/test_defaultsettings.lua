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
    lu.assertEquals(D.tradeRetries, 0);
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

function testDefaultsFoodWater()
    -- Mage autotrade defaults: enabled, count 20 (trigger threshold), single
    -- rank each.
    lu.assertIsTrue(D.items.food.enabled);
    lu.assertEquals(D.items.food.count, 20);
    lu.assertIsTrue(D.items.food.ranks[22019]);
    lu.assertIsTrue(D.items.water.enabled);
    lu.assertEquals(D.items.water.count, 20);
    lu.assertIsTrue(D.items.water.ranks[22018]);
end

function testDefaultsDefinitionsEmpty()
    -- Workflow definitions ship per CLASS (WarlockWorkflows/MageWorkflows) and
    -- are filled by SettingsMigrator:applyClassDefaults at login; the generic
    -- defaults keep an empty table.
    lu.assertEquals(D.workflows.slotCount, 5);
    lu.assertIsTrue(D.workflows.enabled);
    lu.assertIsTrue(D.workflows.skipIfBuffedDefault);
    lu.assertIsTrue(type(D.workflows.definitions) == "table");
    lu.assertIsNil(next(D.workflows.definitions));
end

-- Every default step of BOTH classes must pass the step schema validator (so
-- the shipped defaults can never break the engine with an invalid step).
function testDefaultsWorkflowStepsValid()
    -- Arrange
    local classDatas = {
        ACP.Data.WarlockWorkflows.defaultDefinitions,
        ACP.Data.MageWorkflows.defaultDefinitions,
    };

    -- Act / Assert
    for _, definitions in ipairs(classDatas) do
        for slot = 1, 5 do
            local definition = definitions[slot];

            if (type(definition) == "table" and type(definition.steps) == "table") then
                for _, step in ipairs(definition.steps) do
                    local ok, err = ACP.Data.Workflows:validateStep(step);
                    lu.assertIsTrue(ok, ("slot %d invalid step: %s"):format(slot, tostring(err)));
                end
            end
        end
    end
end