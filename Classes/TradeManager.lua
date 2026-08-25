-- ArenaChillPrep — Classes/TradeManager
-- Low-level trade window automation (dependency-free).
--
-- Flow:
--   startTrade(unit) -> InitiateTrade
--   TRADE_SHOW       -> partner verification, ACP_TRADE_OPENED (the
--                       DeliveryController fills the item queue via
--                       TradePlanner), start FIFO placement queue
--   placement        -> one item per tick: findItemInBags (skip soulbound)
--                       -> UseContainerItem (auto-places into the next slot)
--   ITEM_UNLOCKED    -> re-queue items the game removed (< 0.5 s)
--   completion       -> UI_INFO_MESSAGE == ERR_TRADE_COMPLETE -> ACP_TRADE_COMPLETED
--   TRADE_CLOSED     -> ClearCursor(); failure verdict after 0.5 s if no
--                       completion -> ACP_TRADE_FAILED(reason)
-- Retries with backoff are driven by the DeliveryController (state machine),
-- not here; the retry count is the `tradeRetries` setting.
--
-- NOTE: there is NO auto-accept. AcceptTrade() is restricted on 2.5.x
-- (requires a hardware event) — a programmatic call or button:Click() is
-- silently blocked by the client. The player confirms the trade manually.

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

--- Initiate a trade with `unit`.
--- The outcome is reported via ACP_TRADE_COMPLETED / ACP_TRADE_FAILED.
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

--- Reset the low-level trade state. Called by the DeliveryController when the
--- trade window never opened (open timeout): without this, `trading` would
--- stay true and block every later startTrade. Also used to clean up a stuck
--- placement queue.
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

--- Resolve an item's GUID by bag/slot. On 2.5.5 C_Item.GetItemGUID takes an
--- ItemLocation, not (bag, slot) — create the location first. Returns nil if
--- the item doesn't exist or the location is incomplete
--- (ITEM_UNLOCKED can arrive with a bag-only reference). The ItemLocation /
--- C_Item.GetItemGUID / DoesItemExist APIs are verified present on 20506
--- (/dump 2026-08-24 — the former API-existence guards were always-true and
--- were removed with W15).
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

--- Replace the low-level placement queue with `itemIDs`. The WHAT-to-pass
--- decision (which items, which ranks) lives in ACP.TradePlanner — the
--- orchestrator hands TradeManager a plain item list to place. Called when the
--- trade window opens (ACP_TRADE_OPENED), before the FIFO ticker starts.
---@param itemIDs table
function TradeManager:queueItems(itemIDs)
    self.ItemsToAdd = (type(itemIDs) == "table") and itemIDs or {};
end

--- The unit token of the trade currently in progress (nil when idle).
---@return string|nil
function TradeManager:getPartner()
    return self.partnerUnit;
end

--- Process one queued item (FIFO). Called by the placement ticker.
function TradeManager:processItemQueue()
    -- Never touch items if the window is gone.
    if (not TradeFrame or not TradeFrame:IsShown()) then
        ACP.Utils.Timers:cancel("TradeItemQueue");
        return;
    end

    local itemID = self.ItemsToAdd[1];

    if (not itemID) then
        return; -- queue empty, ticker just idles
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

--- Start the FIFO placement ticker (one item per tick).
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

    -- The trade window opened.
    ACP.Events:register("TradeManager.TRADE_SHOW", "TRADE_SHOW", function()
        -- Record the partner from the window (for a partner-initiated trade we
        -- did not set partnerUnit ourselves).
        if (not self.partnerUnit) then
            self.partnerUnit = UnitName("NPC", true) or "unknown";
        end

        ACP:debugPrint("trade window shown (partner: %s)", tostring(self.partnerUnit));

        -- We initiated this trade: place items as designed.
        if (self.trading) then
            -- Cancel the one-shot open timeout directly AND via the event
            -- (belt and suspenders — never let a stale timer kill a live
            -- trade). ACP_TRADE_OPENED makes the DeliveryController fill the
            -- placement queue (TradePlanner) before the ticker starts.
            ACP.Utils.Timers:cancel("TradeOpen");
            ACP.Events:fire("ACP_TRADE_OPENED", self.partnerUnit);

            self:startItemQueue();
            return;
        end

        -- Inbound trade: someone opened a trade with us. If the controller is
        -- actively prepping, take over the already-open window and deliver the
        -- prep items into it instead of trying to start a second trade.
        if (ACP.DeliveryController:shouldTakeOverInboundTrade()) then
            ACP:debugPrint("taking over inbound trade with %s", tostring(self.partnerUnit));
            self.trading = true;
            ACP.Utils.Timers:cancel("TradeOpen");
            ACP.Events:fire("ACP_TRADE_OPENED", self.partnerUnit);
            self:startItemQueue();
        end
    end);

    -- Trade completed successfully. UI_INFO_MESSAGE on 2.5.5 delivers the
    -- message as the SECOND argument.
    ACP.Events:register("TradeManager.UI_INFO_MESSAGE", "UI_INFO_MESSAGE", function(_, message)
        if (message == ERR_TRADE_COMPLETE) then
            self.tradeCompleted = true;
            ACP:debugPrint("trade completed");
            ACP.Events:fire("ACP_TRADE_COMPLETED");
        end
    end);

    -- Window closed: success arrives as UI_INFO_MESSAGE shortly after, so
    -- delay the failure verdict (TRADE_CLOSED alone means failure, not success).
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
