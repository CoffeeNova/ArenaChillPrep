-- ArenaChillPrep — Classes/Inventory
-- Bag scanner and item counters (stack-aware).
--
-- Scans bags 0..4 (ACP.Data.Constants.NUM_BAGS), counting stackCount
-- (healthstones stack up to 10). Tracks the itemIDs the current class can pass
-- (from ACP.Data.Items.classItems). On BAG_UPDATE / BAG_UPDATE_DELAYED the
-- counts are refreshed and ACP_ITEMS_CHANGED fires for any tracked item
-- whose count changed.
-- findItem delegates to Utils/Items.findItemInBags (port of Gargul's
-- GL:findBagIdAndSlotForItem, simplified).

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

--- Build the set of tracked itemIDs for the current class from the catalog.
--- Called at init and again on PLAYER_LOGIN: UnitClass("player") can be nil
--- during ADDON_LOADED (character not loaded yet), which would leave the
--- tracked set empty and every counter at 0.
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

--- Number of tracked itemIDs (diagnostics).
---@return number
function Inventory:getTrackedCount()
    local count = 0;

    for _ in pairs(self.trackedItemIDs) do
        count = count + 1;
    end

    return count;
end

--- Recount every tracked item. Fires ACP_ITEMS_CHANGED for each item whose
--- count changed (so listeners react only to real changes, not spam).
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

--- Count a single item across all bags (stack-aware).
---@param itemID number
---@return number
function Inventory:countItem(itemID)
    local count = 0;
    local numBags = ACP.Data.Constants.NUM_BAGS;

    for bag = 0, numBags - 1 do
        local numSlots = ACP.Utils.Items:getContainerNumSlots(bag);

        for slot = 1, numSlots do
            local _, stackCount, _, _, _, _, _, _, _, bagItemID = ACP.Utils.Items:getContainerItemInfo(bag, slot);

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

    -- The player class is only reliable after login; rebuild then.
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

    -- Initial fill so getCount() is meaningful before the first BAG_UPDATE.
    self:_recountAll();
end

--- Total count of `itemID` across all bags (stack-aware, cached).
---@param itemID number
---@return number
function Inventory:getCount(itemID)
    return self.Counts[itemID] or 0;
end

--- First location of `itemID` in the bags, skipping soulbound items
--- (bound = 11th container value). Returns bag, slot or nil.
---@param itemID number
---@return number|nil bag, number|nil slot
function Inventory:findItem(itemID)
    return ACP.Utils.Items:findItemInBags(itemID, true);
end

return ACP;
