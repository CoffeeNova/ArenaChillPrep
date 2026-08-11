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