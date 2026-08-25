-- ArenaChillPrep — Classes/Inventory
-- Bag scanner and stack-aware item counters for the tracked (class-passable)
-- itemIDs; fires ACP_ITEMS_CHANGED when a tracked count changes.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;

---@class Inventory
local Inventory = {
    _initialized = false,

    ---@type table<number, boolean>
    trackedItemIDs = {},

    ---@type table<number, number>
    Counts = {},
};

---@type Inventory
ACP.Inventory = Inventory;

-- Called at init and again on PLAYER_LOGIN: UnitClass("player") is nil during
-- ADDON_LOADED, which would leave the tracked set empty.
function Inventory:_buildTrackedItems()
    local classItems = ACP.Data.Items.classItems;
    local englishClass = select(2, UnitClass("player"));

    wipe(self.trackedItemIDs);

    for _, category in pairs(classItems[englishClass] or {}) do
        for itemID in pairs(ACP.Data.Items[category] or {}) do
            self.trackedItemIDs[itemID] = true;
        end
    end

    ACP:debugPrint("tracked items rebuilt (class: %s, count: %d)", tostring(englishClass), self:getTrackedCount());
end

---@return number
function Inventory:getTrackedCount()
    local count = 0;

    for _ in pairs(self.trackedItemIDs) do
        count = count + 1;
    end

    return count;
end

function Inventory:_recountAll()
    for itemID in pairs(self.trackedItemIDs) do
        local count = self:countItem(itemID);

        if (self.Counts[itemID] ~= count) then
            self.Counts[itemID] = count;
            ACP:debugPrint("item %d count changed -> %d", itemID, count);
            ACP.Events:fire("ACP_ITEMS_CHANGED", itemID, count);
        end
    end
end

---@param itemID number
---@return number
function Inventory:countItem(itemID)
    local count = 0;
    local numBags = ACP.Data.Constants.NUM_BAGS;

    for bag = 0, numBags - 1 do
        local numSlots = ACP.Utils.Items:getContainerNumSlots(bag);

        for slot = 1, numSlots do
            local bagItemID, stackCount = ACP.Utils.Items:getItemData(bag, slot);

            if (bagItemID == itemID) then
                count = count + (stackCount or 1);
            end
        end
    end

    return count;
end

function Inventory:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    self:_buildTrackedItems();

    ACP.Events:register("Inventory.PLAYER_LOGIN", "PLAYER_LOGIN", function()
        self:_buildTrackedItems();
        self:_recountAll();
    end);

    ACP.Events:register("Inventory.BAG_UPDATE", "BAG_UPDATE", function()
        self:_recountAll();
    end);

    ACP.Events:register("Inventory.BAG_UPDATE_DELAYED", "BAG_UPDATE_DELAYED", function()
        self:_recountAll();
    end);

    self:_recountAll();
end

---@param itemID number
---@return number
function Inventory:getCount(itemID)
    return self.Counts[itemID] or 0;
end

--- First bag slot holding `itemID`, skipping soulbound items.
---@param itemID number
---@return number|nil bag, number|nil slot
function Inventory:findItem(itemID)
    return ACP.Utils.Items:findItemInBags(itemID, true);
end

return ACP;
