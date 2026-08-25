-- ArenaChillPrep — Tests/Classes/test_settings.lua
-- Covers Classes/Settings.lua: init merge, dot-path get/set, rank-key
-- normalization, ensureDefaults.

local ACP = _G.ACP;
local Settings = ACP.Settings;
local H = dofile(_G.__TESTS_ROOT .. "/helpers.lua");

-- Pristine copy of the defaults, restored before every test. Settings:_init
-- uses shallowCopy(defaults) which SHARES nested tables — mutating
-- Settings.Data would otherwise corrupt the defaults permanently.
local PristineDefaults = H.deepCopy(ACP.Data.DefaultSettings);

local function freshSettings()
    -- Restore pristine defaults, then re-init from them.
    ACP.Data.DefaultSettings = H.deepCopy(PristineDefaults);
    _G.ArenaChillPrepDB = H.deepCopy(PristineDefaults);
    Settings._initialized = false;
    Settings:_init();
end

function testInitMergesDefaults()
    -- Arrange
    _G.ArenaChillPrepDB = { enabled = false };
    Settings._initialized = false;
    -- Act
    Settings:_init();
    -- Assert
    lu.assertIsFalse(Settings:get("enabled"));
    lu.assertEquals(Settings:get("tradeDelay"), 1.5);
    -- Restore pristine defaults so later suites see a clean DB.
    freshSettings();
end

function testGetMissingPath()
    -- Arrange
    freshSettings();
    -- Act
    local v = Settings:get("nope.missing");
    -- Assert
    lu.assertIsNil(v);
end

function testSetAndGet()
    -- Arrange
    freshSettings();
    -- Act
    Settings:set("gateSafetySeconds", 20);
    -- Assert
    lu.assertEquals(Settings:get("gateSafetySeconds"), 20);
    freshSettings();
end

function testSetCreatesIntermediateTables()
    -- Arrange
    freshSettings();
    -- Act
    Settings:set("items.healthstone.count", 3);
    -- Assert
    lu.assertEquals(Settings:get("items.healthstone.count"), 3);
    freshSettings();
end

function testSetNumericSegment()
    -- Arrange
    freshSettings();
    -- Act
    Settings:set("items.healthstone.ranks.19004", true);
    -- Assert
    lu.assertIsTrue(Settings:get("items.healthstone.ranks.19004"));
    lu.assertIsTrue(Settings.Data.items.healthstone.ranks[19004]);
    freshSettings();
end

function testNormalizeRankKeys()
    -- Arrange
    freshSettings();
    Settings.Data.items.healthstone.ranks["22105"] = true;
    Settings.Data.items.healthstone.ranks[22105] = nil;
    -- Act
    Settings:normalizeRankKeys(Settings.Data.items);
    -- Assert
    lu.assertIsTrue(Settings.Data.items.healthstone.ranks[22105]);
    lu.assertIsNil(Settings.Data.items.healthstone.ranks["22105"]);
    freshSettings();
end

function testNormalizeRankKeysNumericWins()
    -- Arrange
    freshSettings();
    Settings.Data.items.healthstone.ranks["22105"] = false;
    Settings.Data.items.healthstone.ranks[22105] = true;
    -- Act
    Settings:normalizeRankKeys(Settings.Data.items);
    -- Assert
    lu.assertIsTrue(Settings.Data.items.healthstone.ranks[22105]);
    freshSettings();
end

function testNormalizeRankKeysNonTable()
    -- Arrange
    freshSettings();
    -- Act
    Settings:normalizeRankKeys(nil);
    Settings:normalizeRankKeys("not a table");
    -- Assert
    lu.assertIsTrue(true);
end

function testEnsureDefaultsFillsMissing()
    -- Arrange
    freshSettings();
    local target = { enabled = false };
    -- Act
    Settings:ensureDefaults(target, { enabled = true, tradeDelay = 1.5, items = { healthstone = { count = 1 } } });
    -- Assert
    lu.assertIsFalse(target.enabled);
    lu.assertEquals(target.tradeDelay, 1.5);
    lu.assertEquals(target.items.healthstone.count, 1);
end

function testMigratePlaceholderDefinitions()
    -- Arrange: a character saved under the OLD placeholder defaults.
    _G.ArenaChillPrepCharDB = {
        workflows = {
            enabled = true,
            slotCount = 5,
            skipIfBuffedDefault = true,
            definitions = {
                [1] = {
                    enabled = true,
                    name = "2s full prep",
                    steps = {
                        { type = "cast", spellID = 28176, target = "player", skipIfBuffed = true },
                        { type = "summon", spellID = 712 },
                        { type = "createItem", spellID = 6201, itemID = 22105 }
                    }
                },
                [2] = { enabled = false, name = "Prep with a Priest", steps = {} }
            }
        }
    };
    Settings._initialized = false;
    -- Act
    Settings:_init();
    -- Assert: both placeholders were replaced by the new default workflows.
    local def1 = Settings:get("workflows.definitions.1");
    lu.assertEquals(def1.name, "2s with sacrifice");
    lu.assertEquals(#def1.steps, 19);
    lu.assertEquals(def1.steps[1].type, "summon");
    lu.assertEquals(def1.steps[1].spellID, 688);
    lu.assertEquals(def1.steps[17].spellName, "Sacrifice");
    lu.assertEquals(def1.steps[19].spellID, 28610);
    local def2 = Settings:get("workflows.definitions.2");
    lu.assertEquals(def2.name, "2s no sacrifice");
    lu.assertEquals(#def2.steps, 15);
    lu.assertEquals(def2.steps[6].spellID, 691);
    freshSettings();
end

function testMigrateSkipsEditedDefinitions()
    -- Arrange: a user-edited workflow must never be replaced by the migration.
    _G.ArenaChillPrepCharDB = {
        workflows = {
            definitions = {
                [1] = { enabled = true, name = "my custom", steps = { { type = "cast", spellID = 5697 } } }
            }
        }
    };
    Settings._initialized = false;
    -- Act
    Settings:_init();
    -- Assert
    local def1 = Settings:get("workflows.definitions.1");
    lu.assertEquals(def1.name, "my custom");
    lu.assertEquals(#def1.steps, 1);
    lu.assertEquals(def1.steps[1].spellID, 5697);
    freshSettings();
end

function testMigrateStepSpellIDsRewritesSoulLink()
    -- Arrange: a character saved a Soul Link step with the old mislabeled
    _G.ArenaChillPrepCharDB = {
        workflows = {
            definitions = {
                [3] = {
                    enabled = true,
                    name = "test",
                    steps = {
                        { type = "cast", spellID = 6307, spellName = "Soul Link", target = "player", skipIfBuffed = true },
                        { type = "cast", spellID = 706, spellName = "Demon Armor", target = "player" },
                        { type = "createItem", spellID = 2362, spellName = "Create Spellstone", itemID = 5522 },
                        { type = "pet", spellID = 27269, spellName = "Fire Shield", target = "player" }
                    }
                }
            }
        }
    };
    Settings._initialized = false;
    -- Act
    Settings:_init();
    -- Assert
    local def3 = Settings:get("workflows.definitions.3");
    lu.assertEquals(def3.steps[1].spellID, 19028);
    lu.assertEquals(def3.steps[1].spellName, "Soul Link");
    lu.assertEquals(def3.steps[2].spellID, 27260);
    lu.assertEquals(def3.steps[3].spellID, 28172);
    lu.assertEquals(def3.steps[3].itemID, 22646);
    lu.assertEquals(def3.steps[4].spellID, 27269);
    -- Cleanup: drop the injected character DB so later suites see no residue.
    _G.ArenaChillPrepCharDB = nil;
    freshSettings();
end

function testResetRestoresDefaults()
    -- Arrange
    freshSettings();
    Settings:set("tradeDelay", 4);
    Settings:set("enabled", false);
    Settings:set("items.healthstone.ranks.19012", false);
    -- Act
    Settings:reset();
    -- Assert
    lu.assertEquals(Settings:get("tradeDelay"), 1.5);
    lu.assertIsTrue(Settings:get("enabled"));
    lu.assertIsTrue(Settings:get("items.healthstone.ranks.19012"));
    lu.assertEquals(_G.ArenaChillPrepDB.tradeDelay, 1.5);
    -- The reset Data must not share nested tables with the defaults.
    Settings.Data.items.healthstone.ranks[19012] = false;
    lu.assertIsTrue(ACP.Data.DefaultSettings.items.healthstone.ranks[19012]);
    freshSettings();
end

function testMigrateWorkflowNamesReplacesPlaceholderNames()
    -- The placeholder-name replacement (SettingsMigrator) — user-created
    -- names must stay untouched.
    local workflows = { definitions = { { name = "Full prep" }, { name = "Custom" }, { name = "Keep Me" } } };
    ACP.SettingsMigrator:migrateWorkflowNames(workflows);
    lu.assertEquals(workflows.definitions[1].name, "2s full prep");
    lu.assertEquals(workflows.definitions[2].name, "");
    lu.assertEquals(workflows.definitions[3].name, "Keep Me");
end

-- Restore pure defaults after the suite so later suites see a clean DB.
function teardownSuite()
    freshSettings();
end
