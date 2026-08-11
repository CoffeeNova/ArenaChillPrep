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

-- Restore pure defaults after the suite so later suites see a clean DB.
function teardownSuite()
    freshSettings();
end