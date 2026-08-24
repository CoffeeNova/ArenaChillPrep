-- ArenaChillPrep — Tests/Classes/test_trademanager.lua
-- Covers Classes/TradeManager.lua: startTrade, cancel, getItemGUID,
-- processItemQueue, queueItems (the queue itself is built by
-- Classes/TradePlanner.lua).

local ACP = _G.ACP;
local TM = ACP.TradeManager;
local H = dofile(_G.__TESTS_ROOT .. "/helpers.lua");

-- TradeManager calls ACP.Utils.Timers (cancel/after/interval) — use the
-- synchronous recorder so no real timers run.
ACP.Utils.Timers = H.SyncTimers;

-- The DeliveryController suite stubs startTrade; capture the real one so
-- the startTrade tests exercise the actual method.
local RealStartTrade = TM.startTrade;

local function resetTM()
    TM.trading = false;
    TM.partnerUnit = nil;
    TM.tradeCompleted = false;
    TM.ItemsToAdd = {};
    TM.ItemsAdded = {};
    H.SyncTimers.Handles = {};
end

function testStartTrade()
    -- Arrange
    resetTM();
    TM.startTrade = RealStartTrade;
    local initiated = false;
    _G.InitiateTrade = function() initiated = true; end;
    -- Act
    TM:startTrade("party1");
    -- Assert
    lu.assertIsTrue(TM.trading);
    lu.assertEquals(TM.partnerUnit, "party1");
    lu.assertIsTrue(initiated);
end

function testStartTradeWhileTradingNoop()
    -- Arrange
    resetTM();
    TM.startTrade = RealStartTrade;
    TM.trading = true;
    local initiated = false;
    _G.InitiateTrade = function() initiated = true; end;
    -- Act
    TM:startTrade("party2");
    -- Assert
    lu.assertIsFalse(initiated);
end

function testCancel()
    -- Arrange
    resetTM();
    TM.trading = true;
    TM.partnerUnit = "party1";
    TM.ItemsToAdd = { 19012 };
    H.SyncTimers.Handles["TradeItemQueue"] = { cb = function() end };
    local cleared = false;
    _G.ClearCursor = function() cleared = true; end;
    -- Act
    TM:cancel();
    -- Assert
    lu.assertIsFalse(TM.trading);
    lu.assertIsNil(TM.partnerUnit);
    lu.assertEquals(#TM.ItemsToAdd, 0);
    lu.assertIsFalse(H.hasTimer("TradeItemQueue"));
    lu.assertIsTrue(cleared);
end

function testCancelWhenNotTradingNoop()
    -- Arrange
    resetTM();
    -- Act
    TM:cancel();
    -- Assert
    lu.assertIsFalse(TM.trading);
end

function testGetItemGUID()
    -- Arrange
    _G.C_Item.GetItemGUID = function() return "guid-123" end;
    _G.C_Item.DoesItemExist = function() return true end;
    -- Act
    local guid = TM:getItemGUID(0, 1);
    -- Assert
    lu.assertEquals(guid, "guid-123");
end

function testGetItemGUIDMissingArgs()
    -- Arrange
    -- Act
    local guid = TM:getItemGUID(nil, 1);
    -- Assert
    lu.assertIsNil(guid);
end

function testProcessItemQueue()
    -- Arrange
    resetTM();
    _G.__stub.tradeFrameShown = true;
    TM.ItemsToAdd = { 19012 };
    _G.C_Item.GetItemGUID = function() return "guid-1" end;
    _G.C_Item.DoesItemExist = function() return true end;
    _G.__stub.bags = {
        [0] = { { itemID = 19012, stackCount = 1, bound = false } },
    };
    local fakeSlots = function(bag) return _G.__stub.bags[bag] and #_G.__stub.bags[bag] or 0 end;
    local fakeInfo = function(bag, slot)
        local e = _G.__stub.bags[bag] and _G.__stub.bags[bag][slot];
        if (not e) then return nil; end
        return {
            iconFileID = nil, stackCount = e.stackCount, isLocked = false,
            quality = 0, isReadable = false, hasLoot = false, hyperlink = nil,
            isFiltered = false, hasNoValue = false, itemID = e.itemID,
            isBound = e.bound,
        };
    end;
    -- findItemInBags prefers the GLOBAL GetContainerNumSlots; getItemData
    -- prefers C_Container.GetContainerItemInfo — override all four.
    _G.GetContainerNumSlots = fakeSlots;
    _G.GetContainerItemInfo = fakeInfo;
    _G.C_Container.GetContainerNumSlots = fakeSlots;
    _G.C_Container.GetContainerItemInfo = fakeInfo;
    local used = false;
    _G.UseContainerItem = function() used = true; end;
    -- Act
    TM:processItemQueue();
    -- Assert
    lu.assertIsTrue(used);
    lu.assertEquals(#TM.ItemsToAdd, 0);
    lu.assertNotIsNil(TM.ItemsAdded["guid-1"]);
end

function testProcessItemQueueWindowClosed()
    -- Arrange
    resetTM();
    _G.__stub.tradeFrameShown = false;
    TM.ItemsToAdd = { 19012 };
    H.SyncTimers.Handles["TradeItemQueue"] = { cb = function() end };
    -- Act
    TM:processItemQueue();
    -- Assert
    lu.assertIsFalse(H.hasTimer("TradeItemQueue"));
end

function testProcessItemQueueEmpty()
    -- Arrange
    resetTM();
    _G.__stub.tradeFrameShown = true;
    TM.ItemsToAdd = {};
    -- Act
    TM:processItemQueue();
    -- Assert
    lu.assertEquals(#TM.ItemsToAdd, 0);
end

function testQueueItemsFromPlanner()
    -- Arrange
    resetTM();
    ACP.Settings:set("items.healthstone.enabled", true);
    ACP.Settings:set("items.healthstone.count", 1);
    local origGetCount = ACP.Inventory.getCount;
    ACP.Inventory.getCount = function(_, itemID)
        if (itemID == 19012 or itemID == 19013) then return 1; end
        if (itemID == 22105) then return 1; end
        return 0;
    end;
    -- Act
    TM:queueItems(ACP.TradePlanner:buildQueue());
    -- Assert
    lu.assertEquals(#TM.ItemsToAdd, 2);
    ACP.Inventory.getCount = origGetCount;
end

function testQueueItemsFromPlannerDisabled()
    -- Arrange
    resetTM();
    ACP.Settings:set("items.healthstone.enabled", false);
    -- Act
    TM:queueItems(ACP.TradePlanner:buildQueue());
    -- Assert
    lu.assertEquals(#TM.ItemsToAdd, 0);
    ACP.Settings:set("items.healthstone.enabled", true);
end

function testQueueItemsFromPlannerCount()
    -- Arrange
    resetTM();
    ACP.Settings:set("items.healthstone.enabled", true);
    ACP.Settings:set("items.healthstone.count", 2);
    local origGetCount = ACP.Inventory.getCount;
    ACP.Inventory.getCount = function(_, itemID)
        if (itemID == 22105) then return 2; end
        return 0;
    end;
    -- Act
    TM:queueItems(ACP.TradePlanner:buildQueue());
    -- Assert
    lu.assertEquals(#TM.ItemsToAdd, 2);
    ACP.Settings:set("items.healthstone.count", 1);
    ACP.Inventory.getCount = origGetCount;
end

-- ---- event-driven handlers (registered in _init) ----

-- The Events suite wipes the bus; re-register the TradeManager handlers.
local function reinitTM()
    H.resetAll();
    TM._initialized = false;
    TM:_init();
end

function testTradeShowManualRecordsPartner()
    -- Arrange
    reinitTM();
    resetTM();
    TM.trading = false;
    _G.UnitName = function() return "Alice" end;
    -- Act
    ACP.Events:fire("TRADE_SHOW");
    -- Assert
    lu.assertEquals(TM.partnerUnit, "Alice");
    _G.UnitName = function() return "Player" end;
end

function testTradeShowAutoPlaces()
    -- Arrange
    reinitTM();
    resetTM();
    TM.trading = true;
    TM.partnerUnit = "party1";
    ACP.Settings:set("items.healthstone.enabled", true);
    ACP.Settings:set("items.healthstone.count", 1);
    local origGetCount = ACP.Inventory.getCount;
    ACP.Inventory.getCount = function(_, itemID)
        if (itemID == 22105) then return 1; end
        return 0;
    end;
    local opened = false;
    ACP.Events:register("t.opened", "ACP_TRADE_OPENED", function() opened = true; end);
    -- Act
    ACP.Events:fire("TRADE_SHOW");
    -- Assert
    lu.assertIsTrue(opened);
    lu.assertIsTrue(H.hasTimer("TradeItemQueue"));
    lu.assertEquals(#TM.ItemsToAdd, 1);
    ACP.Events:unregister("t.opened");
    ACP.Inventory.getCount = origGetCount;
end

function testTradeShowInboundTakesOver()
    -- Arrange
    reinitTM();
    resetTM();
    TM.trading = false;
    _G.UnitName = function(unit)
        if (unit == "party1") then return "Alice"; end
        return "Player";
    end;
    ACP.Settings:set("items.healthstone.enabled", true);
    ACP.Settings:set("items.healthstone.count", 1);
    local origGetCount = ACP.Inventory.getCount;
    ACP.Inventory.getCount = function(_, itemID)
        if (itemID == 22105) then return 1; end
        return 0;
    end;
    -- Pretend the controller is actively prepping a teammate trade.
    ACP.DeliveryController.shouldTakeOverInboundTrade = function() return true; end;
    local opened = false;
    ACP.Events:register("t.opened", "ACP_TRADE_OPENED", function() opened = true; end);
    -- Act
    ACP.Events:fire("TRADE_SHOW");
    -- Assert
    lu.assertIsTrue(TM.trading);
    lu.assertIsTrue(opened);
    lu.assertIsTrue(H.hasTimer("TradeItemQueue"));
    lu.assertEquals(#TM.ItemsToAdd, 1);
    ACP.Events:unregister("t.opened");
    ACP.Inventory.getCount = origGetCount;
    _G.UnitName = function() return "Player" end;
end

function testTradeShowInboundNotTakenOver()
    -- Arrange
    reinitTM();
    resetTM();
    TM.trading = false;
    _G.UnitName = function() return "Alice" end;
    ACP.DeliveryController.shouldTakeOverInboundTrade = function() return false; end;
    -- Act
    ACP.Events:fire("TRADE_SHOW");
    -- Assert
    lu.assertIsFalse(TM.trading);
    lu.assertIsFalse(H.hasTimer("TradeItemQueue"));
    _G.UnitName = function() return "Player" end;
end

function testUiInfoMessageCompletes()
    -- Arrange
    reinitTM();
    resetTM();
    local completed = false;
    ACP.Events:register("t.completed", "ACP_TRADE_COMPLETED", function() completed = true; end);
    -- Act
    ACP.Events:fire("UI_INFO_MESSAGE", nil, _G.ERR_TRADE_COMPLETE);
    -- Assert
    lu.assertIsTrue(TM.tradeCompleted);
    lu.assertIsTrue(completed);
    ACP.Events:unregister("t.completed");
end

function testUiInfoMessageOtherIgnored()
    -- Arrange
    reinitTM();
    resetTM();
    -- Act
    ACP.Events:fire("UI_INFO_MESSAGE", nil, "Some other message");
    -- Assert
    lu.assertIsFalse(TM.tradeCompleted);
end

function testTradeClosedSchedulesVerdict()
    -- Arrange
    reinitTM();
    resetTM();
    TM.trading = true;
    TM.ItemsToAdd = { 19012 };
    local cleared = false;
    _G.ClearCursor = function() cleared = true; end;
    -- Act
    ACP.Events:fire("TRADE_CLOSED");
    -- Assert
    lu.assertIsFalse(TM.trading);
    lu.assertIsTrue(cleared);
    lu.assertIsTrue(H.hasTimer("TradeClosedCheck"));
end

function testTradeClosedWhenNotTradingIgnored()
    -- Arrange
    reinitTM();
    resetTM();
    TM.trading = false;
    -- Act
    ACP.Events:fire("TRADE_CLOSED");
    -- Assert
    lu.assertIsFalse(H.hasTimer("TradeClosedCheck"));
end

function testTradeClosedVerdictFailure()
    -- Arrange
    reinitTM();
    resetTM();
    TM.trading = true;
    ACP.Events:fire("TRADE_CLOSED");
    local failed = false;
    ACP.Events:register("t.failed", "ACP_TRADE_FAILED", function() failed = true; end);
    -- Act
    H.advance("TradeClosedCheck");
    -- Assert
    lu.assertIsTrue(failed);
    lu.assertIsNil(TM.partnerUnit);
    ACP.Events:unregister("t.failed");
end

function testTradeClosedVerdictSuccess()
    -- Arrange
    reinitTM();
    resetTM();
    TM.trading = true;
    TM.tradeCompleted = true;
    ACP.Events:fire("TRADE_CLOSED");
    -- Act
    H.advance("TradeClosedCheck");
    -- Assert
    lu.assertIsFalse(TM.tradeCompleted);
    lu.assertIsNil(TM.partnerUnit);
end

function testItemUnlockedRequeues()
    -- Arrange
    reinitTM();
    resetTM();
    _G.__stub.time = 100;
    TM.ItemsAdded["guid-9"] = { itemID = 19012, timestamp = 100 };
    _G.C_Item.GetItemGUID = function() return "guid-9" end;
    _G.C_Item.DoesItemExist = function() return true end;
    -- Act
    ACP.Events:fire("ITEM_UNLOCKED", 0, 1);
    -- Assert
    lu.assertEquals(#TM.ItemsToAdd, 1);
    lu.assertEquals(TM.ItemsToAdd[1], 19012);
    lu.assertIsNil(TM.ItemsAdded["guid-9"]);
end

function testItemUnlockedTooOldNotRequeued()
    -- Arrange
    reinitTM();
    resetTM();
    _G.__stub.time = 100;
    TM.ItemsAdded["guid-9"] = { itemID = 19012, timestamp = 99 };
    _G.C_Item.GetItemGUID = function() return "guid-9" end;
    _G.C_Item.DoesItemExist = function() return true end;
    -- Act
    ACP.Events:fire("ITEM_UNLOCKED", 0, 1);
    -- Assert
    lu.assertEquals(#TM.ItemsToAdd, 0);
end