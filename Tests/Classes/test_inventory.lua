-- ArenaChillPrep — Tests/Classes/test_inventory.lua
-- Covers Classes/Inventory.lua: tracked items, counting, recount, findItem.

local ACP = _G.ACP;
local Inventory = ACP.Inventory;
local H = dofile(_G.__TESTS_ROOT .. "/helpers.lua");

local function installBags(fake)
    -- Utils/Items prefers the GLOBAL GetContainerNumSlots but C_Container
    -- for GetContainerItemInfo (which returns a TABLE) — override all four.
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
    local fakeLegacyInfo = function(bag, slot)
        local e = fake[bag] and fake[bag][slot];
        if (not e) then return nil; end
        return nil, e.stackCount, false, 0, false, false, nil, false, false, e.itemID, e.bound;
    end;
    _G.GetContainerNumSlots = fakeSlots;
    _G.GetContainerItemInfo = fakeLegacyInfo;
    _G.C_Container.GetContainerNumSlots = fakeSlots;
    _G.C_Container.GetContainerItemInfo = fakeInfo;
end

function testBuildTrackedItems()
    -- Arrange
    Inventory.trackedItemIDs = {};
    -- Act
    Inventory:_buildTrackedItems();
    -- Assert
    lu.assertEquals(Inventory:getTrackedCount(), 11);
    lu.assertIsTrue(Inventory.trackedItemIDs[19004]);
    lu.assertIsTrue(Inventory.trackedItemIDs[22105]);
end

function testCountItemStackAware()
    -- Arrange
    installBags({
        [0] = { { itemID = 19004, stackCount = 5, bound = false } },
        [1] = { { itemID = 19004, stackCount = 3, bound = false } },
    });
    -- Act
    local count = Inventory:countItem(19004);
    -- Assert
    lu.assertEquals(count, 8);
end

function testCountItemAbsent()
    -- Arrange
    installBags({ [0] = { { itemID = 19006, stackCount = 1, bound = false } } });
    -- Act
    local count = Inventory:countItem(19009);
    -- Assert
    lu.assertEquals(count, 0);
end

function testRecountAllFiresOnChange()
    -- Arrange
    installBags({ [0] = { { itemID = 19004, stackCount = 2, bound = false } } });
    Inventory.trackedItemIDs = { [19004] = true };
    Inventory.Counts = { [19004] = 1 };
    local fired = false;
    ACP.Events:register("t.recount", "ACP_ITEMS_CHANGED", function() fired = true; end);
    -- Act
    Inventory:_recountAll();
    -- Assert
    lu.assertIsTrue(fired);
    lu.assertEquals(Inventory:getCount(19004), 2);
    ACP.Events:unregister("t.recount");
end

function testRecountAllNoFireWhenSame()
    -- Arrange
    installBags({ [0] = { { itemID = 19004, stackCount = 2, bound = false } } });
    Inventory.trackedItemIDs = { [19004] = true };
    Inventory.Counts = { [19004] = 2 };
    local fired = false;
    ACP.Events:register("t.recount2", "ACP_ITEMS_CHANGED", function() fired = true; end);
    -- Act
    Inventory:_recountAll();
    -- Assert
    lu.assertIsFalse(fired);
    ACP.Events:unregister("t.recount2");
end

function testGetCountCached()
    -- Arrange
    Inventory.Counts = { [19004] = 7 };
    -- Act
    -- Assert
    lu.assertEquals(Inventory:getCount(19004), 7);
    lu.assertEquals(Inventory:getCount(99999), 0);
end

function testFindItem()
    -- Arrange
    installBags({
        [0] = { { itemID = 19004, stackCount = 1, bound = true } },
        [1] = { { itemID = 19004, stackCount = 1, bound = false } },
    });
    -- Act
    local bag, slot = Inventory:findItem(19004);
    -- Assert
    lu.assertEquals(bag, 1);
    lu.assertEquals(slot, 1);
end

-- ---- event-driven handlers (registered in _init) ----

local function reinitInventory()
    H.resetAll();
    Inventory._initialized = false;
    Inventory:_init();
end

function testPlayerLoginEventRebuilds()
    -- Arrange
    reinitInventory();
    Inventory.trackedItemIDs = {};
    -- Act
    ACP.Events:fire("PLAYER_LOGIN");
    -- Assert
    lu.assertEquals(Inventory:getTrackedCount(), 11);
end

function testBagUpdateEventRecounts()
    -- Arrange
    reinitInventory();
    installBags({ [0] = { { itemID = 19004, stackCount = 2, bound = false } } });
    Inventory.trackedItemIDs = { [19004] = true };
    Inventory.Counts = {};
    -- Act
    ACP.Events:fire("BAG_UPDATE");
    -- Assert
    lu.assertEquals(Inventory:getCount(19004), 2);
end

function testBagUpdateDelayedEventRecounts()
    -- Arrange
    reinitInventory();
    installBags({ [0] = { { itemID = 19004, stackCount = 3, bound = false } } });
    Inventory.trackedItemIDs = { [19004] = true };
    Inventory.Counts = {};
    -- Act
    ACP.Events:fire("BAG_UPDATE_DELAYED");
    -- Assert
    lu.assertEquals(Inventory:getCount(19004), 3);
end