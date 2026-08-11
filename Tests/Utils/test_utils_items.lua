-- ArenaChillPrep — Tests/Utils/test_utils_items.lua
-- Covers Utils/Items.lua: container shims, getItemData, findItemInBags.

local ACP = _G.ACP;
local Items = ACP.Utils.Items;

local function installBags(fake)
    -- Arrange: fake = { [bag] = { [slot] = { itemID, stackCount, bound } } }
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

function testGetContainerNumSlots()
    -- Arrange
    installBags({ [0] = { {}, {} } });
    -- Act
    local n = Items:getContainerNumSlots(0);
    -- Assert
    lu.assertEquals(n, 2);
end

function testGetContainerNumSlotsEmpty()
    -- Arrange
    installBags({});
    -- Act
    local n = Items:getContainerNumSlots(3);
    -- Assert
    lu.assertEquals(n, 0);
end

function testGetItemData()
    -- Arrange
    installBags({ [0] = { { itemID = 19004, stackCount = 5, bound = false } } });
    -- Act
    local itemID, stackCount, bound = Items:getItemData(0, 1);
    -- Assert
    lu.assertEquals(itemID, 19004);
    lu.assertEquals(stackCount, 5);
    lu.assertIsFalse(bound);
end

function testFindItemInBags()
    -- Arrange
    installBags({
        [0] = { { itemID = 19006, stackCount = 1, bound = false } },
        [1] = { { itemID = 19004, stackCount = 1, bound = false } },
    });
    -- Act
    local bag, slot = Items:findItemInBags(19004);
    -- Assert
    lu.assertEquals(bag, 1);
    lu.assertEquals(slot, 1);
end

function testFindItemSkipsSoulbound()
    -- Arrange
    installBags({
        [0] = { { itemID = 19004, stackCount = 1, bound = true } },
        [1] = { { itemID = 19004, stackCount = 1, bound = false } },
    });
    -- Act
    local bag = Items:findItemInBags(19004, true);
    -- Assert
    lu.assertEquals(bag, 1);
end

function testFindItemMissing()
    -- Arrange
    installBags({ [0] = { { itemID = 19004, stackCount = 1, bound = false } } });
    -- Act
    local bag, slot = Items:findItemInBags(99999);
    -- Assert
    lu.assertIsNil(bag);
    lu.assertIsNil(slot);
end

function testGetContainerNumSlotsNoApi()
    -- Arrange: remove both container APIs → shim returns 0.
    local origGlobal = _G.GetContainerNumSlots;
    local origC = _G.C_Container.GetContainerNumSlots;
    _G.GetContainerNumSlots = nil;
    _G.C_Container.GetContainerNumSlots = nil;
    -- Act
    local n = Items:getContainerNumSlots(0);
    -- Assert
    lu.assertEquals(n, 0);
    _G.GetContainerNumSlots = origGlobal;
    _G.C_Container.GetContainerNumSlots = origC;
end

function testGetContainerItemInfoLegacyFallback()
    -- Arrange: remove C_Container → legacy global tuple is used.
    local origC = _G.C_Container.GetContainerItemInfo;
    _G.C_Container.GetContainerItemInfo = nil;
    _G.__stub.bags = { [0] = { { itemID = 19004, stackCount = 5, bound = false } } };
    _G.GetContainerItemInfo = function(bag, slot)
        local e = _G.__stub.bags[bag] and _G.__stub.bags[bag][slot];
        if (not e) then return nil; end
        return nil, e.stackCount, false, 0, false, false, nil, false, false, e.itemID, e.bound;
    end;
    -- Act
    local itemID, stackCount = Items:getItemData(0, 1);
    -- Assert
    lu.assertEquals(itemID, 19004);
    lu.assertEquals(stackCount, 5);
    _G.C_Container.GetContainerItemInfo = origC;
end

function testGetContainerItemInfoNoApi()
    -- Arrange: remove both APIs → nil.
    local origGlobal = _G.GetContainerItemInfo;
    local origC = _G.C_Container.GetContainerItemInfo;
    _G.GetContainerItemInfo = nil;
    _G.C_Container.GetContainerItemInfo = nil;
    -- Act
    local info = Items:getContainerItemInfo(0, 1);
    -- Assert
    lu.assertIsNil(info);
    _G.GetContainerItemInfo = origGlobal;
    _G.C_Container.GetContainerItemInfo = origC;
end