-- ArenaChillPrep — Tests/Data/test_items.lua
-- Covers Data/Items.lua: healthstone catalog + class mapping.

local ACP = _G.ACP;
local Items = ACP.Data.Items;

function testItemsHealthstoneCatalog()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(Items.healthstones[19004].rank, 1);
    lu.assertEquals(Items.healthstones[19005].rank, 1);
    lu.assertEquals(Items.healthstones[19012].rank, 5);
    lu.assertEquals(Items.healthstones[19013].rank, 5);
    lu.assertEquals(Items.healthstones[22105].rank, 6);
    lu.assertEquals(Items.healthstones[22105].name, "Master Healthstone");
end

function testItemsClassMapping()
    -- Arrange
    -- Act
    -- Assert
    lu.assertItemsEquals(Items.classItems["WARLOCK"], { "healthstones" });
end

function testItemsEveryIdHasRecord()
    -- Arrange
    local ids = { 19004, 19005, 19006, 19007, 19008, 19009, 19010, 19011, 19012, 19013, 22105 };
    -- Act
    -- Assert
    for _, id in ipairs(ids) do
        lu.assertNotIsNil(Items.healthstones[id], "missing record for " .. id);
    end
end