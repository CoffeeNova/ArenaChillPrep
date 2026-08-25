-- ArenaChillPrep — Tests/Classes/test_classcatalogdispatch.lua
-- Covers Classes/ClassCatalogDispatch.lua: routing the static-catalog calls
-- to the ACTIVE class's extender.

local ACP = _G.ACP;
local Dispatch = ACP.ClassCatalogDispatch;
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

function testExtendersRegistry()
    lu.assertEquals(Dispatch.extenders["WARLOCK"], ACP.WarlockCatalogExtender);
    lu.assertEquals(Dispatch.extenders["MAGE"], ACP.MageCatalogExtender);
    lu.assertIsNil(Dispatch.extenders["HUNTER"]);
end

function testMergeRoutesToWarlockExtender()
    withClass("WARLOCK", function()
        Dispatch:merge(Spellbook);

        lu.assertNotIsNil(Spellbook:getEntry(27230), "stone rank merged");
        lu.assertNotIsNil(Spellbook:getEntry(27269), "pet ability merged");
        lu.assertIsNil(Spellbook:getEntry(27090), "no Mage conjures for a Warlock");
    end);
end

function testMergeRoutesToMageExtender()
    withClass("MAGE", function()
        Dispatch:merge(Spellbook);

        lu.assertNotIsNil(Spellbook:getEntry(27090), "conjured rank merged");
        lu.assertNotIsNil(Spellbook:getEntry(33717), "conjured rank merged");
        lu.assertIsNil(Spellbook:getEntry(27230), "no Warlock stones for a Mage");
    end);
end

function testFallbackRoutesByClass()
    withClass("MAGE", function()
        Dispatch:addStaticFallback(Spellbook);
        lu.assertIsTrue(Builder:countEntries(Spellbook) > 0);
        lu.assertIsNil(Spellbook:getEntry(688), "no Warlock summons for a Mage");
    end);

    withClass("WARLOCK", function()
        Dispatch:addStaticFallback(Spellbook);
        lu.assertIsTrue(Builder:countEntries(Spellbook) > 0);
        lu.assertIsNil(Spellbook:getEntry(27090), "no Mage conjures for a Warlock");
    end);
end

function testUnknownClassNoop()
    withClass("HUNTER", function()
        Dispatch:merge(Spellbook);
        Dispatch:addStaticFallback(Spellbook);
        lu.assertEquals(Builder:countEntries(Spellbook), 0);
    end);
end

function testWorkflowSpellbookFacadeDelegates()
    -- The facade's mergeStaticWarlock/addStaticFallback now route through the
    -- dispatcher: a Mage gets the Mage catalog through them.
    withClass("MAGE", function()
        Spellbook:mergeStaticWarlock();
        Spellbook:addStaticFallback();

        lu.assertNotIsNil(Spellbook:getEntry(27127), "Mage catalog through the facade");
        lu.assertIsNil(Spellbook:getEntry(688), "no Warlock summons");
    end);
end

_G.UnitClass = DefaultUnitClass;
