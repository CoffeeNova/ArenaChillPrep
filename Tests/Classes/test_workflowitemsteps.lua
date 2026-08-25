-- ArenaChillPrep — Tests/Classes/test_workflowitemsteps.lua
-- Covers the Mage count-target goal-met logic in Classes/WorkflowItemSteps.lua
-- (isItemAlreadyPresent / expandExpectedItems / resolveExpectedItems).

local ACP = _G.ACP;
local Engine = ACP.WorkflowEngine;

local DefaultUnitClass = _G.UnitClass;

local function withMage(fn)
    local origUnitClass = _G.UnitClass;
    _G.UnitClass = function() return "Mage", "MAGE" end;
    -- Restore even when the wrapped test FAILS — a leaked class stub breaks
    -- every later suite.
    local ok, err = pcall(fn);
    _G.UnitClass = origUnitClass;
    if (not ok) then
        error(err, 2);
    end
end

local function withCounts(counts)
    local orig = ACP.Inventory.countItem;
    ACP.Inventory.countItem = function(_, id)
        return counts[id] or 0;
    end;

    return function()
        ACP.Inventory.countItem = orig;
    end;
end

local function savedWaterSetting()
    return {
        enabled = ACP.Settings:get("items.water.enabled"),
        count = ACP.Settings:get("items.water.count"),
    };
end

local function restoreWaterSetting(snapshot)
    ACP.Settings:set("items.water.enabled", snapshot.enabled);
    ACP.Settings:set("items.water.count", snapshot.count);
end

function testIsItemAlreadyPresentCountTarget()
    -- The conjure step's goal is the COUNT TARGET: two identical Conjure
    -- Water steps conjure 10+10 while the skip only fires at 20.
    withMage(function()
        _G.__stub.knownSpells = { [27090] = true };
        local snapshot = savedWaterSetting();
        local restoreCounts = withCounts({ [22018] = 10 });

        lu.assertFalse(Engine:isItemAlreadyPresent(
            { type = "createItem", spellID = 27090, itemID = 22018 }),
            "10 water below the 20 threshold");

        restoreCounts();
        local restoreCounts2 = withCounts({ [22018] = 20 });
        lu.assertTrue(Engine:isItemAlreadyPresent(
            { type = "createItem", spellID = 27090, itemID = 22018 }),
            "20 water meets the threshold");

        restoreCounts2();
        restoreWaterSetting(snapshot);
        _G.__stub.knownSpells = {};
    end);
end

function testIsItemAlreadyPresentCountTargetRespectsSetting()
    -- The threshold is the SETTING's count: set 10 → a single conjure (10)
    -- satisfies the second step.
    withMage(function()
        _G.__stub.knownSpells = { [27090] = true };
        local snapshot = savedWaterSetting();
        ACP.Settings:set("items.water.count", 10);
        local restoreCounts = withCounts({ [22018] = 10 });

        lu.assertTrue(Engine:isItemAlreadyPresent(
            { type = "createItem", spellID = 27090, itemID = 22018 }));

        restoreCounts();
        restoreWaterSetting(snapshot);
        _G.__stub.knownSpells = {};
    end);
end

function testIsItemAlreadyPresentDisabledCategoryFallsBack()
    -- A DISABLED autotrade category falls back to the old "any variant
    -- present" behavior (a single conjured item satisfies the step).
    withMage(function()
        _G.__stub.knownSpells = { [27090] = true };
        local snapshot = savedWaterSetting();
        ACP.Settings:set("items.water.enabled", false);
        local restoreCounts = withCounts({ [22018] = 1 });

        lu.assertTrue(Engine:isItemAlreadyPresent(
            { type = "createItem", spellID = 27090, itemID = 22018 }));

        restoreCounts();
        restoreWaterSetting(snapshot);
        _G.__stub.knownSpells = {};
    end);
end

function testWarlockStonesKeepAnyPresentBehavior()
    -- Warlock stones map to items.healthstone.count = 1 → "≥ 1 present" is
    -- exactly the old "any variant present" behavior (no Warlock change).
    local origUnitClass = _G.UnitClass;
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    _G.__stub.knownSpells = { [27230] = true };
    local snapshot = {
        enabled = ACP.Settings:get("items.healthstone.enabled"),
        count = ACP.Settings:get("items.healthstone.count"),
    };
    ACP.Settings:set("items.healthstone.count", 1);
    local restoreCounts = withCounts({ [22105] = 1 });

    lu.assertTrue(Engine:isItemAlreadyPresent(
        { type = "createItem", spellID = 27230, itemID = 22105 }));

    restoreCounts();
    ACP.Settings:set("items.healthstone.count", snapshot.count);
    ACP.Settings:set("items.healthstone.enabled", snapshot.enabled);
    _G.__stub.knownSpells = {};
    _G.UnitClass = origUnitClass;
end

function testExpandExpectedItemsMageConjured()
    withMage(function()
        local ids = Engine:expandExpectedItems(27090, 22018);
        lu.assertEquals(#ids, 1);
        lu.assertEquals(ids[1], 22018);

        local food = Engine:expandExpectedItems(33717, 22019);
        lu.assertEquals(food[1], 22019);
    end);
end

function testResolveExpectedItemsMageFamily()
    withMage(function()
        local ids = Engine:resolveExpectedItems(27090, 22018);
        lu.assertEquals(#ids, 1);
        lu.assertEquals(ids[1], 22018);
    end);
end

_G.UnitClass = DefaultUnitClass;
