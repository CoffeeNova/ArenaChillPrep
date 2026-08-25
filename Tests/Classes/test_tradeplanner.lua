-- ArenaChillPrep — Tests/Classes/test_tradeplanner.lua
-- Covers Classes/TradePlanner.lua: the WHAT-to-pass grouping and the
-- per-category readiness (incl. Mage food/water via settingsKeyFor).

local ACP = _G.ACP;
local Planner = ACP.TradePlanner;

local DefaultUnitClass = _G.UnitClass;

local function withClass(englishClass, fn)
    local origUnitClass = _G.UnitClass;
    _G.UnitClass = function() return englishClass, englishClass end;
    -- Restore even when the wrapped test FAILS — a leaked class stub breaks
    -- every later suite.
    local ok, err = pcall(fn);
    _G.UnitClass = origUnitClass;
    if (not ok) then
        error(err, 2);
    end
end

local function withUnits(playerClass, partnerClass, fn)
    local origUnitClass = _G.UnitClass;
    _G.UnitClass = function(unit)
        if (unit == "player") then
            return playerClass, playerClass;
        end
        return partnerClass, partnerClass;
    end;
    local ok, err = pcall(fn);
    _G.UnitClass = origUnitClass;
    if (not ok) then
        error(err, 2);
    end
end

local function installBags(fake)
    _G.__stub.bags = fake;
    local fakeSlots = function(bag)
        return fake[bag] and #fake[bag] or 0;
    end;
    local fakeInfo = function(bag, slot)
        local e = fake[bag] and fake[bag][slot];
        if (not e) then return nil; end
        return {
            iconFileID = nil, stackCount = e.stackCount, isLocked = false,
            quality = 0, isReadable = false, hasLoot = false, hyperlink = nil,
            isFiltered = false, hasNoValue = false, itemID = e.itemID,
            isBound = e.bound,
        };
    end;
    _G.GetContainerNumSlots = fakeSlots;
    _G.GetContainerItemInfo = fakeInfo;
    _G.C_Container.GetContainerNumSlots = fakeSlots;
    _G.C_Container.GetContainerItemInfo = fakeInfo;
end

function testGetCategories()
    withClass("WARLOCK", function()
        lu.assertItemsEquals(Planner:getCategories(), { "healthstones" });
    end);

    withClass("MAGE", function()
        lu.assertItemsEquals(Planner:getCategories(), { "food", "water" });
    end);

    withClass("HUNTER", function()
        lu.assertItemsEquals(Planner:getCategories(), {});
    end);
end

function testSelectedRanksByGroup()
    local catalog = ACP.Data.Items.healthstones;
    local ranks = { [19012] = true, [19013] = true, [22105] = true };
    local byRank = Planner:selectedRanksByGroup(catalog, ranks);

    lu.assertEquals(#byRank[5], 2, "paired IDs share one rank group");
    lu.assertEquals(#byRank[6], 1);
end

function testCategoryReadyHealthstones()
    local origGetCount = ACP.Inventory.getCount;
    ACP.Inventory.getCount = function(_, itemID)
        if (itemID == 19013) then return 1; end
        return 0;
    end;

    local setting = { count = 1, ranks = { [19012] = true, [19013] = true } };
    lu.assertIsTrue(Planner:categoryReady("healthstones", setting));
    ACP.Inventory.getCount = origGetCount;
end

function testCategoryReadyMageCountThreshold()
    -- The trade opens only when BOTH 20 food AND 20 water are present: the
    -- count is a trigger threshold per rank, not a per-trade placement.
    local origGetCount = ACP.Inventory.getCount;
    ACP.Inventory.getCount = function(_, itemID)
        if (itemID == 22019) then return 10; end
        if (itemID == 22018) then return 20; end
        return 0;
    end;

    local food = { count = 20, ranks = { [22019] = true } };
    local water = { count = 20, ranks = { [22018] = true } };

    lu.assertIsFalse(Planner:categoryReady("food", food), "10 food is below the 20 threshold");
    lu.assertIsTrue(Planner:categoryReady("water", water), "20 water meets the threshold");
    ACP.Inventory.getCount = origGetCount;
end

function testCategoryReadyMageThresholdMetWithStacks()
    -- Stack-aware: 2 stacks of 10 count as 20.
    local origGetCount = ACP.Inventory.getCount;
    ACP.Inventory.getCount = function(_, itemID)
        if (itemID == 22019) then return 20; end
        return 0;
    end;

    local food = { count = 20, ranks = { [22019] = true } };
    lu.assertIsTrue(Planner:categoryReady("food", food));
    ACP.Inventory.getCount = origGetCount;
end

function testBuildQueueMagePlacesCountItems()
    -- Placement queue: one entry per BAG STACK (the client moves a whole
    -- stack per UseContainerItem) — 2 food stacks + 2 water stacks.
    withClass("MAGE", function()
        installBags({
            [0] = {
                { itemID = 22019, stackCount = 10, bound = false },
                { itemID = 22019, stackCount = 10, bound = false },
                { itemID = 22018, stackCount = 10, bound = false },
                { itemID = 22018, stackCount = 10, bound = false },
            },
        });
        ACP.Settings:set("items.food.enabled", true);
        ACP.Settings:set("items.food.count", 20);
        ACP.Settings:set("items.water.enabled", true);
        ACP.Settings:set("items.water.count", 20);

        local queue = Planner:buildQueue();

        lu.assertItemsEquals(queue, { 22019, 22019, 22018, 22018 });
    end);
end

function testBuildQueueStopsAtCountThreshold()
    -- 3 food stacks of 10 with count=20: only the 2 stacks needed to reach
    -- the threshold are queued.
    withClass("MAGE", function()
        installBags({
            [0] = {
                { itemID = 22019, stackCount = 10, bound = false },
                { itemID = 22019, stackCount = 10, bound = false },
                { itemID = 22019, stackCount = 10, bound = false },
            },
        });
        ACP.Settings:set("items.food.enabled", true);
        ACP.Settings:set("items.food.count", 20);
        ACP.Settings:set("items.water.enabled", false);

        local queue = Planner:buildQueue();

        lu.assertEquals(#queue, 2);
    end);
end

function testBuildQueueSkipsSoulboundStacks()
    withClass("MAGE", function()
        installBags({
            [0] = {
                { itemID = 22019, stackCount = 10, bound = true },
                { itemID = 22019, stackCount = 10, bound = false },
            },
        });
        ACP.Settings:set("items.food.enabled", true);
        ACP.Settings:set("items.food.count", 20);
        ACP.Settings:set("items.water.enabled", false);

        local queue = Planner:buildQueue();

        lu.assertEquals(#queue, 1);
    end);
end

function testBuildQueueMageRoguePartnerFoodOnly()
    -- A Rogue partner receives food only — water stacks never enter the queue.
    withUnits("MAGE", "ROGUE", function()
        installBags({
            [0] = {
                { itemID = 22019, stackCount = 10, bound = false },
                { itemID = 22019, stackCount = 10, bound = false },
                { itemID = 22018, stackCount = 10, bound = false },
                { itemID = 22018, stackCount = 10, bound = false },
            },
        });
        ACP.Settings:set("items.food.enabled", true);
        ACP.Settings:set("items.food.count", 20);
        ACP.Settings:set("items.water.enabled", true);
        ACP.Settings:set("items.water.count", 20);

        local queue = Planner:buildQueue("party1");

        lu.assertItemsEquals(queue, { 22019, 22019 });
    end);
end

function testBuildQueueMageManaPartnerFoodAndWater()
    withUnits("MAGE", "PRIEST", function()
        installBags({
            [0] = {
                { itemID = 22019, stackCount = 10, bound = false },
                { itemID = 22019, stackCount = 10, bound = false },
                { itemID = 22018, stackCount = 10, bound = false },
                { itemID = 22018, stackCount = 10, bound = false },
            },
        });
        ACP.Settings:set("items.food.enabled", true);
        ACP.Settings:set("items.food.count", 20);
        ACP.Settings:set("items.water.enabled", true);
        ACP.Settings:set("items.water.count", 20);

        local queue = Planner:buildQueue("party1");

        lu.assertItemsEquals(queue, { 22019, 22019, 22018, 22018 });
    end);
end

function testCategoriesForPartnerManaClasses()
    -- Mana users receive food AND water from a Mage.
    withUnits("MAGE", "SHAMAN", function()
        lu.assertItemsEquals(Planner:categoriesForPartner("party1"), { "food", "water" });
    end);
end

function testCategoriesForPartnerRogueWarriorFoodOnly()
    withUnits("MAGE", "ROGUE", function()
        lu.assertItemsEquals(Planner:categoriesForPartner("party1"), { "food" });
    end);

    withUnits("MAGE", "WARRIOR", function()
        lu.assertItemsEquals(Planner:categoriesForPartner("party1"), { "food" });
    end);
end

function testCategoriesForPartnerWarlockPlayerUnchanged()
    -- Warlock autotrade is untouched: healthstones to every partner, no
    -- partner-class filtering.
    withUnits("WARLOCK", "ROGUE", function()
        lu.assertItemsEquals(Planner:categoriesForPartner("party1"), { "healthstones" });
    end);
end

function testCategoriesForPartnerUnknownClassGetsEverything()
    -- A partner whose class is unknown (nil) receives every category.
    local origUnitClass = _G.UnitClass;
    _G.UnitClass = function(unit)
        if (unit == "player") then return "Mage", "MAGE"; end
        return nil;
    end;
    local ok, err = pcall(function()
        lu.assertItemsEquals(Planner:categoriesForPartner("party1"), { "food", "water" });
    end);
    _G.UnitClass = origUnitClass;
    if (not ok) then error(err, 2); end
end

function testCategoriesForPartnerNoUnitGetsEverything()
    withClass("MAGE", function()
        lu.assertItemsEquals(Planner:categoriesForPartner(nil), { "food", "water" });
    end);
end

_G.UnitClass = DefaultUnitClass;
