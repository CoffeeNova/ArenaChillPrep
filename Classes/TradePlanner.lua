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
local UnitClass = _G.UnitClass;

---@class TradePlanner
local TradePlanner = {};

---@type TradePlanner
ACP.TradePlanner = TradePlanner;

---@return table
function TradePlanner:getCategories()
    local classItems = ACP.Data.Items.classItems;
    local englishClass = select(2, UnitClass("player"));

    return classItems[englishClass] or {};
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

--- Placement queue: `count` items of EVERY selected rank, ascending rank
--- order. Called only once all selected ranks are ready.
---@return table
function TradePlanner:buildQueue()
    local queue = {};
    local categories = self:getCategories();

    for _, category in ipairs(categories) do
        local settingsKey = category:sub(1, -2);
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
                    if (remaining > 0) then
                        local count = ACP.Inventory:getCount(itemID);
                        local toAdd = math.min(count, remaining);

                        for _ = 1, toAdd do
                            tinsert(queue, itemID);
                        end

                        remaining = remaining - toAdd;
                    end
                end
            end
        end
    end

    if (#queue > 0) then
        ACP:debugPrint("placing %d item(s) into the trade window", #queue);
    end

    return queue;
end

return ACP;
