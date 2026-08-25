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
    lu.assertItemsEquals(Items.classItems["MAGE"], { "food", "water" });
end

function testMagePartnerCategories()
    -- Mana users take food AND water; Rogues/Warriors take food only.
    for _, class in ipairs({ "PRIEST", "PALADIN", "WARLOCK", "DRUID", "HUNTER", "SHAMAN" }) do
        lu.assertItemsEquals(Items.magePartnerCategories[class], { "food", "water" }, class);
    end

    lu.assertItemsEquals(Items.magePartnerCategories["ROGUE"], { "food" });
    lu.assertItemsEquals(Items.magePartnerCategories["WARRIOR"], { "food" });
end

function testItemsFoodWaterCatalog()
    -- Mage conjured items: one ID per rank.
    lu.assertEquals(Items.food[22019].id, 22019);
    lu.assertEquals(Items.food[22019].rank, 8);
    lu.assertEquals(Items.food[22019].name, "Conjured Croissant");
    lu.assertEquals(Items.water[22018].id, 22018);
    lu.assertEquals(Items.water[22018].rank, 9);
    lu.assertEquals(Items.water[22018].name, "Conjured Glacier Water");
end

function testSettingsKeyFor()
    -- Explicit map for every known category; the trailing-"s" strip is the
    -- fallback for unknown ones ("food" → "foo" would silently break the
    -- autotrade settings).
    lu.assertEquals(Items:settingsKeyFor("healthstones"), "healthstone");
    lu.assertEquals(Items:settingsKeyFor("food"), "food");
    lu.assertEquals(Items:settingsKeyFor("water"), "water");
    lu.assertEquals(Items:settingsKeyFor("totems"), "totem");
end

function testCountRanges()
    -- Only the Mage categories have a count slider range (10-60 step 10);
    -- Warlock healthstone keeps its fixed count (no slider).
    lu.assertEquals(Items.countRanges.food.min, 10);
    lu.assertEquals(Items.countRanges.food.max, 60);
    lu.assertEquals(Items.countRanges.food.step, 10);
    lu.assertEquals(Items.countRanges.water.min, 10);
    lu.assertEquals(Items.countRanges.water.max, 60);
    lu.assertEquals(Items.countRanges.water.step, 10);
    lu.assertIsNil(Items.countRanges.healthstones);
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