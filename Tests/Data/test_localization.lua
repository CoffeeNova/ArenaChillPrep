-- ArenaChillPrep — Tests/Data/test_localization.lua
-- Covers Data/Localization.lua: L metatable fallback.

local ACP = _G.ACP;
local L = ACP.L;

function testLocalizationKnownKey()
    -- Arrange
    -- Act
    -- Assert
    lu.assertStrContains(L.loaded, "loaded");
    lu.assertEquals(L.panelTitle, "ArenaChillPrep");
end

function testLocalizationMissingKeyFallsBack()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(L.definitelyMissingKey, "definitelyMissingKey");
end

function testLocalizationRanks()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(L.ranks[1], "Minor");
    lu.assertEquals(L.ranks[6], "Master");
end