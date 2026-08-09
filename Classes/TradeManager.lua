-- ArenaChillPrep — Classes/TradeManager
-- Low-level trade window automation (dependency-free port of the patterns
-- proven in Gargul's Classes/TradeWindow.lua on the same client).
--
-- Flow:
--   startTrade(unit) -> InitiateTrade
--   TRADE_SHOW       -> partner verification, start FIFO placement queue
--   placement        -> one item per tick: findItemInBags (skip soulbound)
--                       -> UseContainerItem (auto-places into the next slot)
--   ITEM_UNLOCKED    -> re-queue items the game removed (< 0.5 s)
--   autoAccept       -> TRADE_ACCEPT_UPDATE + TradeFrameTradeButton:Click()
--   completion       -> UI_INFO_MESSAGE == ERR_TRADE_COMPLETE -> ACP_TRADE_COMPLETED
--   TRADE_CLOSED     -> ClearCursor(); failure verdict after 0.5 s if no
--                       completion -> ACP_TRADE_FAILED(reason)
-- Retries with backoff (2/4/8 s, max MAX_TRADE_RETRIES) are driven by the
-- DeliveryController (state machine), not here.

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

    ---@type boolean
    autoAcceptPending = false,
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
    self.autoAcceptPending = false;
    self.ItemsToAdd = {};
    self.ItemsAdded = {};

    ACP:debugPrint("initiating trade with %s", unit);
    ACP.Events:fire("ACP_TRADE_START", unit);

    InitiateTrade(unit);
end

--- Queue an item (by ID) to be placed into the open trade window.
---@param itemID number
function TradeManager:queueItem(itemID)
    tinsert(self.ItemsToAdd, itemID);
end

--- Whether a trade window is currently open / being processed.
---@return boolean
function TradeManager:isTrading()
    return self.trading;
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
    self.autoAcceptPending = false;
    self.ItemsToAdd = {};
    self.ItemsAdded = {};
    ACP.Utils.Timers:cancel("TradeItemQueue");
    ACP.Utils.Timers:cancel("TradeAutoAccept");
    ClearCursor();
end

--- Resolve an item's GUID by bag/slot. On 2.5.5 C_Item.GetItemGUID takes an
--- ItemLocation, not (bag, slot) — create the location first (Gargul does the
--- same). Returns nil if the item doesn't exist or the location is incomplete
--- (ITEM_UNLOCKED can arrive with a bag-only reference).
---@param bag number
---@param slot number
---@return string|nil
function TradeManager:getItemGUID(bag, slot)
    if (not bag or not slot or not _G.ItemLocation or not _G.C_Item or not _G.C_Item.GetItemGUID) then
        return nil;
    end

    local location = _G.ItemLocation:CreateFromBagAndSlot(bag, slot);

    if (not location or (C_Item.DoesItemExist and not C_Item.DoesItemExist(location))) then
        return nil;
    end

    return _G.C_Item.GetItemGUID(location);
end

--- Process one queued item (FIFO). Called by the placement ticker.
function TradeManager:processItemQueue()
    -- Never touch items if the window is gone.
    if (not TradeFrame:IsShown()) then
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
    local _, _, _, _, _, _, itemLink = ACP.Utils.Items:getContainerItemInfo(bag, slot);

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
    useContainerItem(bag, slot);

    -- All queued items placed (for now) — give the game a moment, then
    -- auto-accept if enabled.
    if (#self.ItemsToAdd == 0) then
        self:tryAutoAccept();
    end
end

--- Attempt to click the "Trade" button if auto-accept is enabled and the
--- button is actually clickable (items may still be being added).
function TradeManager:tryAutoAccept()
    if (not self.trading or not TradeFrame:IsShown()) then
        return;
    end

    if (not ACP.Settings:get("autoAccept")) then
        return;
    end

    if (self.autoAcceptPending) then
        return;
    end

    local button = TradeFrameTradeButton;

    if (not button or not button:IsEnabled()) then
        ACP:debugPrint("auto-accept skipped (trade button disabled)");
        return;
    end

    self.autoAcceptPending = true;

    ACP.Utils.Timers:after("TradeAutoAccept", 0.6, function()
        self.autoAcceptPending = false;

        if (not self.trading or not TradeFrame:IsShown()) then
            return;
        end

        if (button:IsEnabled()) then
            ACP:debugPrint("auto-accepting trade");
            button:Click("LeftButton");
        end
    end);
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
        -- If we didn't initiate this trade (manual open), record the partner
        -- from the window so completion is attributed correctly — but do NOT
        -- auto-place items into a window the player opened himself.
        if (not self.partnerUnit) then
            self.partnerUnit = UnitName("NPC", true) or "unknown";
        end

        ACP:debugPrint("trade window shown (partner: %s)", tostring(self.partnerUnit));

        -- Only auto-place if WE initiated this trade.
        if (self.trading) then
            -- Tell the controller the window is up so it cancels its
            -- one-shot open timeout (TRADE_OPEN_TIMEOUT).
            ACP.Events:fire("ACP_TRADE_OPENED", self.partnerUnit);

            self:queueConfiguredItems();
            self:startItemQueue();

            if (#self.ItemsToAdd == 0) then
                -- Nothing to place — auto-accept right away if enabled.
                self:tryAutoAccept();
            end
        end
    end);

    -- Trade completed successfully. UI_INFO_MESSAGE on 2.5.5 delivers the
    -- message as the SECOND argument (Gargul reads _, message — same client).
    ACP.Events:register("TradeManager.UI_INFO_MESSAGE", "UI_INFO_MESSAGE", function(_, message)
        if (message == ERR_TRADE_COMPLETE) then
            self.tradeCompleted = true;
            ACP:debugPrint("trade completed");
            ACP.Events:fire("ACP_TRADE_COMPLETED");
        end
    end);

    -- Trade accepted states: auto-accept (extra trigger; the main one is after
    -- items are placed — see tryAutoAccept).
    ACP.Events:register("TradeManager.TRADE_ACCEPT_UPDATE", "TRADE_ACCEPT_UPDATE", function()
        self:tryAutoAccept();
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
        self.autoAcceptPending = false;
        ACP.Utils.Timers:cancel("TradeItemQueue");
        ACP.Utils.Timers:cancel("TradeAutoAccept");
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

--- Queue the configured items for the current class (from Settings + Inventory).
--- Places `count` items of EVERY selected rank (ranks grouped by catalog
--- `rank`; paired IDs are one rank). The controller only calls this once ALL
--- selected ranks are ready, so each rank has enough items to queue.
function TradeManager:queueConfiguredItems()
    local classItems = ACP.Data.Items.classItems;
    local englishClass = select(2, UnitClass("player"));
    local categories = classItems[englishClass] or {};

    self.ItemsToAdd = {};

    for _, category in ipairs(categories) do
        local settingsKey = category:sub(1, -2);
        local setting = ACP.Settings:get("items." .. settingsKey);

        if (setting and setting.enabled) then
            local needed = setting.count or 1;
            local catalog = ACP.Data.Items[category] or {};
            local queuedByRank = {}; -- rank -> number (how many queued)

            for itemID, enabled in pairs(setting.ranks or {}) do
                if (enabled) then
                    local record = catalog[itemID];

                    if (record) then
                        local rank = record.rank;

                        if (not queuedByRank[rank]) then
                            queuedByRank[rank] = 0;
                        end

                        -- Queue up to the remaining need for this rank, using
                        -- whatever ID of the rank we actually have.
                        local rankNeed = needed - queuedByRank[rank];

                        if (rankNeed > 0) then
                            local count = ACP.Inventory:getCount(itemID);
                            local toAdd = math.min(count, rankNeed);

                            for _ = 1, toAdd do
                                tinsert(self.ItemsToAdd, itemID);
                            end

                            queuedByRank[rank] = queuedByRank[rank] + toAdd;
                        end
                    end
                end
            end
        end
    end

    if (#self.ItemsToAdd > 0) then
        ACP:print("placing %d item(s) into the trade window", #self.ItemsToAdd);
    end
end

return ACP;
