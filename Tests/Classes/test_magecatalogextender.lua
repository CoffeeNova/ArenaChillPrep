-- ArenaChillPrep — Tests/Classes/test_magecatalogextender.lua
-- Covers Classes/MageCatalogExtender.lua: the class-gated Mage catalog
-- extensions (mergeStaticMage + addStaticFallback).

local ACP = _G.ACP;
local Extender = ACP.MageCatalogExtender;
local Builder = ACP.SpellbookCatalogBuilder;
local Spellbook = ACP.WorkflowSpellbook;

local DefaultUnitClass = _G.UnitClass;

local function withClass(englishClass, fn)
    local origUnitClass = _G.UnitClass;
    _G.UnitClass = function() return englishClass, englishClass end;
    Builder:reset(Spellbook);
    -- Restore even when the wrapped test FAILS — a leaked class stub breaks
    -- every later suite.
    local ok, err = pcall(fn);
    _G.UnitClass = origUnitClass;
    if (not ok) then
        error(err, 2);
    end
end

function testIsMage()
    local origUnitClass = _G.UnitClass;
    _G.UnitClass = function() return "Mage", "MAGE" end;
    lu.assertIsTrue(Extender:isMage());
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    lu.assertIsFalse(Extender:isMage());
    _G.UnitClass = origUnitClass;
end

function testMergeStaticMageAddsConjuredRanks()
    withClass("MAGE", function()
        Extender:mergeStaticMage(Spellbook);

        local water = Spellbook:getEntry(27090);
        local food = Spellbook:getEntry(33717);

        lu.assertNotIsNil(water, "Conjure Water merged");
        lu.assertEquals(water.category, "createItem");
        lu.assertEquals(water.itemID, 22018);
        lu.assertEquals(water.rank, 9);
        lu.assertIsTrue(water.isCastTime);
        lu.assertNotIsNil(food, "Conjure Food merged");
        lu.assertEquals(food.itemID, 22019);
        lu.assertEquals(food.rank, 8);
    end);
end

function testMergeStaticMageGatedForOtherClasses()
    withClass("WARLOCK", function()
        Extender:mergeStaticMage(Spellbook);
        lu.assertEquals(Builder:countEntries(Spellbook), 0);
    end);
end

function testAddStaticFallbackFillsMageCatalog()
    withClass("MAGE", function()
        Extender:addStaticFallback(Spellbook);

        lu.assertEquals(Builder:countEntries(Spellbook), 17);
        lu.assertNotIsNil(Spellbook:getEntry(27127), "Arcane Brilliance");
        lu.assertNotIsNil(Spellbook:getEntry(27126), "Arcane Intellect");
        lu.assertNotIsNil(Spellbook:getEntry(1008), "Amplify Magic rank 1");
        lu.assertNotIsNil(Spellbook:getEntry(33946), "Amplify Magic max rank");
        lu.assertNotIsNil(Spellbook:getEntry(604), "Dampen Magic rank 1");
        lu.assertNotIsNil(Spellbook:getEntry(33944), "Dampen Magic max rank");
        lu.assertNotIsNil(Spellbook:getEntry(27125), "Mage Armor");
        lu.assertNotIsNil(Spellbook:getEntry(30482), "Molten Armor");
        lu.assertNotIsNil(Spellbook:getEntry(27124), "Ice Armor");
        lu.assertNotIsNil(Spellbook:getEntry(27128), "Fire Ward");
        lu.assertNotIsNil(Spellbook:getEntry(32796), "Frost Ward");
        lu.assertNotIsNil(Spellbook:getEntry(33405), "Ice Barrier");
        lu.assertNotIsNil(Spellbook:getEntry(66), "Invisibility");
        lu.assertNotIsNil(Spellbook:getEntry(33717), "Conjure Food");
        lu.assertNotIsNil(Spellbook:getEntry(27090), "Conjure Water");
        lu.assertNotIsNil(Spellbook:getEntry(27101), "Conjure Mana Emerald");
        lu.assertNotIsNil(Spellbook:getEntry(43987), "Ritual of Refreshment");
        lu.assertIsNil(Spellbook:getEntry(7301), "Frost Armor removed");
        lu.assertEquals(Spellbook:getEntry(27101).itemID, 22044);
        lu.assertEquals(Spellbook:getEntry(27101).category, "createItem");
    end);
end

function testAmplifyDampenEntriesCarryRank()
    -- The rank field drives the per-rank Add Step listing.
    withClass("MAGE", function()
        Extender:addStaticFallback(Spellbook);

        lu.assertEquals(Spellbook:getEntry(1008).rank, 1);
        lu.assertEquals(Spellbook:getEntry(33946).rank, 6);
        lu.assertEquals(Spellbook:getEntry(604).rank, 1);
        lu.assertEquals(Spellbook:getEntry(33944).rank, 6);
        lu.assertEquals(Spellbook:getEntry(1008).category, "buffs");
    end);
end

function testAddStaticFallbackGatedForOtherClasses()
    withClass("WARLOCK", function()
        Extender:addStaticFallback(Spellbook);
        lu.assertEquals(Builder:countEntries(Spellbook), 0);
    end);
end

function testMageEntriesCarryMetadata()
    withClass("MAGE", function()
        Extender:addStaticFallback(Spellbook);

        lu.assertEquals(Spellbook:getEntry(27126).canTargetParty, true);
        lu.assertEquals(Spellbook:getEntry(27127).canTargetParty, false);
        lu.assertEquals(Spellbook:getEntry(27126).category, "buffs");
        lu.assertEquals(Spellbook:getEntry(33717).category, "createItem");
        lu.assertEquals(Spellbook:getEntry(33717).itemID, 22019);
        lu.assertIsFalse(Spellbook:getEntry(33717).needsShard);
        lu.assertEquals(Spellbook:getEntry(43987).category, "utility");
    end);
end

_G.UnitClass = DefaultUnitClass;
