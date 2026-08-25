-- ArenaChillPrep — Classes/TradeManager
-- Low-level trade window automation. No auto-accept: AcceptTrade() is
-- restricted on 2.5.x — the player confirms the trade manually.
-- Retries are driven by the DeliveryController.

---@type ACP
local _, ACP = ...;

local tinsert = _G.tinsert;
local tremove = _G.tremove;
local GetTime = _G.GetTime;
local TradeFrame = _G.TradeFrame;
local ERR_TRADE_COMPLETE = _G.ERR_TRADE_COMPLETE;

---@class TradeManager
local TradeManager = {
    _initialized = false,

    ---@type boolean
    trading = false,

    ---@type string|nil
    partnerUnit = nil,

    ---@type boolean
    tradeCompleted = false,

    ---@type table
    ItemsToAdd = {},

    ---@type table<string, {itemLink: string|nil, itemID: number, timestamp: number}>
    ItemsAdded = {},
};

---@type TradeManager
ACP.TradeManager = TradeManager;

--- Outcome is reported via ACP_TRADE_COMPLETED / ACP_TRADE_FAILED.
---@param unit string
function TradeManager:startTrade(unit)
    if (self.trading) then
        return;
    end

    self.trading = true;
    self.partnerUnit = unit;
    self.tradeCompleted = false;
    self.ItemsToAdd = {};
    self.ItemsAdded = {};

    ACP:debugPrint("initiating trade with %s", unit);

    InitiateTrade(unit);
end

--- Reset the low-level trade state (otherwise `trading` would block every
--- later startTrade).
function TradeManager:cancel()
    if (not self.trading) then
        return;
    end

    self.trading = false;
    self.partnerUnit = nil;
    self.tradeCompleted = false;
    self.ItemsToAdd = {};
    self.ItemsAdded = {};
    ACP.Utils.Timers:cancel("TradeItemQueue");
    ClearCursor();
end

--- Item GUID by bag/slot. On 2.5.5 C_Item.GetItemGUID takes an ItemLocation;
--- ITEM_UNLOCKED can arrive with a bag-only reference.
---@param bag number
---@param slot number
---@return string|nil
function TradeManager:getItemGUID(bag, slot)
    if (not bag or not slot) then
        return nil;
    end

    local location = _G.ItemLocation:CreateFromBagAndSlot(bag, slot);

    if (not location or (C_Item.DoesItemExist and not C_Item.DoesItemExist(location))) then
        return nil;
    end

    return C_Item.GetItemGUID(location);
end

--- Replace the placement queue (the WHAT is decided by TradePlanner).
---@param itemIDs table
function TradeManager:queueItems(itemIDs)
    self.ItemsToAdd = (type(itemIDs) == "table") and itemIDs or {};
end

---@return string|nil
function TradeManager:getPartner()
    return self.partnerUnit;
end

function TradeManager:processItemQueue()
    if (not TradeFrame or not TradeFrame:IsShown()) then
        ACP.Utils.Timers:cancel("TradeItemQueue");
        return;
    end

    local itemID = self.ItemsToAdd[1];

    if (not itemID) then
        return;
    end

    tremove(self.ItemsToAdd, 1);

    local bag, slot = ACP.Inventory:findItem(itemID);

    if (not bag or not TradeFrame:IsShown()) then
        return; -- item not found (soulbound?) or window closed
    end

    local itemGUID = self:getItemGUID(bag, slot);
    local _, _, _, itemLink = ACP.Utils.Items:getItemData(bag, slot);

    if (itemGUID) then
        self.ItemsAdded[itemGUID] = {
            itemID = itemID,
            itemLink = itemLink,
            timestamp = GetTime(),
        };
    end

    ACP:debugPrint("placing item %d (bag %d, slot %d)", itemID, bag, slot);

    -- UseContainerItem with the window open auto-places into the next slot.
    local useContainerItem = _G.UseContainerItem or (C_Container and C_Container.UseContainerItem);

    if (not useContainerItem) then
        return;
    end

    useContainerItem(bag, slot);
end

function TradeManager:startItemQueue()
    ACP.Utils.Timers:cancel("TradeItemQueue");

    ACP.Utils.Timers:interval("TradeItemQueue", ACP.Data.Constants.TRADE_ITEM_TICK, function()
        self:processItemQueue();
    end);
end

function TradeManager:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    ACP.Events:register("TradeManager.TRADE_SHOW", "TRADE_SHOW", function()
        -- A partner-initiated trade did not set partnerUnit ourselves.
        if (not self.partnerUnit) then
            self.partnerUnit = UnitName("NPC", true) or "unknown";
        end

        ACP:debugPrint("trade window shown (partner: %s)", tostring(self.partnerUnit));

        if (self.trading) then
            ACP.Utils.Timers:cancel("TradeOpen");
            ACP.Events:fire("ACP_TRADE_OPENED", self.partnerUnit);

            self:startItemQueue();
            return;
        end

        -- Inbound trade: take over the already-open window when prepping.
        if (ACP.DeliveryController:shouldTakeOverInboundTrade()) then
            ACP:debugPrint("taking over inbound trade with %s", tostring(self.partnerUnit));
            self.trading = true;
            ACP.Utils.Timers:cancel("TradeOpen");
            ACP.Events:fire("ACP_TRADE_OPENED", self.partnerUnit);
            self:startItemQueue();
        end
    end);

    -- UI_INFO_MESSAGE delivers the message as the SECOND argument on 2.5.5.
    ACP.Events:register("TradeManager.UI_INFO_MESSAGE", "UI_INFO_MESSAGE", function(_, message)
        if (message == ERR_TRADE_COMPLETE) then
            self.tradeCompleted = true;
            ACP:debugPrint("trade completed");
            ACP.Events:fire("ACP_TRADE_COMPLETED");
        end
    end);

    -- Window closed: success arrives as UI_INFO_MESSAGE shortly after, so
    -- delay the failure verdict.
    ACP.Events:register("TradeManager.TRADE_CLOSED", "TRADE_CLOSED", function()
        -- Dedupe: a second TRADE_CLOSED for the same window (client quirk)
        -- must not schedule another verdict.
        if (not self.trading) then
            return;
        end

        self.trading = false;
        ACP.Utils.Timers:cancel("TradeItemQueue");
        self.ItemsToAdd = {};
        self.ItemsAdded = {};
        ClearCursor();

        ACP.Utils.Timers:after("TradeClosedCheck", 1.0, function()
            if (self.tradeCompleted) then
                self.tradeCompleted = false;
                self.partnerUnit = nil;
                return;
            end

            ACP:debugPrint("trade window closed without completion");
            ACP.Events:fire("ACP_TRADE_FAILED", "closed");
            self.partnerUnit = nil;
        end);
    end);

    -- The game can silently remove items added too rapidly — re-queue them.
    ACP.Events:register("TradeManager.ITEM_UNLOCKED", "ITEM_UNLOCKED", function(bag, slot)
        local itemGUID = self:getItemGUID(bag, slot);

        if (itemGUID and self.ItemsAdded[itemGUID]) then
            if (GetTime() - self.ItemsAdded[itemGUID].timestamp <= 0.5) then
                tinsert(self.ItemsToAdd, self.ItemsAdded[itemGUID].itemID);
            end

            self.ItemsAdded[itemGUID] = nil;
        end
    end);
end

return ACP;
