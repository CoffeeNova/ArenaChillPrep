-- ArenaChillPrep — Classes/TradePlanner
-- WHAT to pass: which items of which selected ranks to queue for the open
-- trade window, and whether a category's selected ranks are all ready.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local select = _G.select;
local tinsert = _G.tinsert;
local sort = _G.table.sort;

---@class TradePlanner
local TradePlanner = {};

---@type TradePlanner
ACP.TradePlanner = TradePlanner;

---@return table
function TradePlanner:getCategories()
    local classItems = ACP.Data.Items.classItems;
    -- Read at call time: the class is unknown at ADDON_LOADED and tests
    -- override the stub per scenario.
    local englishClass = select(2, _G.UnitClass("player"));

    return classItems[englishClass] or {};
end

--- Categories the current class trades to `partnerUnit`. A Mage gives water
--- only to mana-using partner classes (Data.Items.magePartnerCategories —
--- Rogues and Warriors take food only); every other class (incl. Warlock)
--- trades all of its categories to everyone. Partners of unlisted classes
--- (or no partner at all) receive everything.
---@param partnerUnit string|nil
---@return table
function TradePlanner:categoriesForPartner(partnerUnit)
    local englishClass = select(2, _G.UnitClass("player"));
    local categories = ACP.Data.Items.classItems[englishClass] or {};

    if (englishClass ~= ACP.Data.Constants.CLASS_MAGE or not partnerUnit) then
        return categories;
    end

    local partnerClass = select(2, _G.UnitClass(partnerUnit));
    local allowed = partnerClass and ACP.Data.Items.magePartnerCategories[partnerClass];

    if (not allowed) then
        return categories;
    end

    local result = {};

    for _, category in ipairs(categories) do
        for _, allowedCategory in ipairs(allowed) do
            if (category == allowedCategory) then
                tinsert(result, category);
                break;
            end
        end
    end

    return result;
end

--- Selected ranks grouped by catalog `rank` (paired IDs like 19012/19013
--- share one rank group).
---@param catalog table
---@param ranks table|nil
---@return table<number, table>
function TradePlanner:selectedRanksByGroup(catalog, ranks)
    local byRank = {};

    for itemID, enabled in pairs(ranks or {}) do
        if (enabled) then
            local record = catalog[itemID];

            if (record) then
                local rank = record.rank;
                byRank[rank] = byRank[rank] or {};
                tinsert(byRank[rank], itemID);
            end
        end
    end

    return byRank;
end

--- Whether ALL selected ranks of an enabled category are ready (paired IDs
--- count as ONE rank — the sum of their counts must reach `setting.count`).
---@param category string
---@param setting table
---@return boolean
function TradePlanner:categoryReady(category, setting)
    local needed = setting.count or 1;
    local catalog = ACP.Data.Items[category] or {};
    local byRank = self:selectedRanksByGroup(catalog, setting.ranks);
    local anySelected = false;

    for rank, ids in pairs(byRank) do
        anySelected = true;

        local rankCount = 0;

        for _, itemID in ipairs(ids) do
            rankCount = rankCount + ACP.Inventory:getCount(itemID);
        end

        ACP:debugPrint("itemsReady: category=%s rank=%d count=%d needed=%d",
            category, rank, rankCount, needed);

        if (rankCount < needed) then
            return false;
        end
    end

    return anySelected;
end

--- Placement queue for `partnerUnit`: one entry per BAG STACK (the client
--- moves a whole stack per UseContainerItem), ascending rank order, limited
--- to the stacks needed to reach `count`. Called once all selected ranks of
--- the partner's categories are ready.
---@param partnerUnit string|nil
---@return table
function TradePlanner:buildQueue(partnerUnit)
    local queue = {};
    local categories = self:categoriesForPartner(partnerUnit);

    for _, category in ipairs(categories) do
        local settingsKey = ACP.Data.Items:settingsKeyFor(category);
        local setting = ACP.Settings:get("items." .. settingsKey);

        if (setting and setting.enabled) then
            local needed = setting.count or 1;
            local catalog = ACP.Data.Items[category] or {};
            local byRank = self:selectedRanksByGroup(catalog, setting.ranks);
            local ranks = {};

            for rank in pairs(byRank) do
                tinsert(ranks, rank);
            end

            sort(ranks);

            for _, rank in ipairs(ranks) do
                local remaining = needed;

                for _, itemID in ipairs(byRank[rank]) do
                    local slots = ACP.Utils.Items:findItemSlots(itemID, true);

                    for _, stack in ipairs(slots) do
                        if (remaining <= 0) then
                            break;
                        end

                        tinsert(queue, itemID);
                        remaining = remaining - stack.count;
                    end

                    if (remaining <= 0) then
                        break;
                    end
                end
            end
        end
    end

    if (#queue > 0) then
        ACP:debugPrint("placing %d stack(s) into the trade window", #queue);
    end

    return queue;
end

return ACP;
