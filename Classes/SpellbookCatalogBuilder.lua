-- ArenaChillPrep — Classes/SpellbookCatalogBuilder
-- Runtime catalog assembly: entry building, rank→item mapping, grouping and
-- reads. Operates on the WorkflowSpellbook facade (first argument).

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local pcall = _G.pcall;
local select = _G.select;
local tonumber = _G.tonumber;
local tinsert = _G.tinsert;
local sort = _G.table.sort;
local GetSpellInfo = _G.GetSpellInfo;

--- Rank -> primary itemID from Data/Items (healthstones ranks 1-5 are ID
--- pairs — the LOWER ID is the primary variant).
---@param category string
---@return table<number, number>
local function rankItemIDs(category)
    local results = {};
    local catalog = ACP.Data.Items and ACP.Data.Items[category];

    if (not catalog) then
        return results;
    end

    for itemID, record in pairs(catalog) do
        local rank = record and record.rank;

        if (rank and (not results[rank] or itemID < results[rank])) then
            results[rank] = itemID;
        end
    end

    return results;
end

local HEALTHSTONE_RESULTS = rankItemIDs("healthstones");
local SOULSTONE_RESULTS = rankItemIDs("soulstones");

---@class SpellbookCatalogBuilder
local CatalogBuilder = {};

---@type SpellbookCatalogBuilder
ACP.SpellbookCatalogBuilder = CatalogBuilder;

local function rankNumber(rankText)
    return tonumber(type(rankText) == "string" and rankText:match("(%d+)") or nil) or 0;
end

local function rankResultItem(spellName, rank)
    if (not rank or rank < 1) then
        return nil;
    end

    if (spellName:find("Healthstone")) then
        return HEALTHSTONE_RESULTS[rank];
    end

    if (spellName:find("Soulstone")) then
        return SOULSTONE_RESULTS[rank];
    end

    return nil;
end

---@param spellName string
---@param spellID number|nil
---@return table|nil entry
---@return string|nil category
local function staticMetadata(spellName, spellID)
    local data = ACP.Data.activeClassWorkflows();
    local spells = data and data.spells;

    if (not spells) then
        return nil;
    end

    -- Exact spellID first — same-name rank entries (Amplify Magic 1008/33946)
    -- each carry their own metadata.
    for category, list in pairs(spells) do
        for _, entry in ipairs(list) do
            if (entry.spellID == spellID) then
                return entry, category;
            end
        end
    end

    for category, list in pairs(spells) do
        for _, entry in ipairs(list) do
            local localizedName = GetSpellInfo and select(1, GetSpellInfo(entry.spellID));

            if (entry.name == spellName or localizedName == spellName) then
                return entry, category;
            end
        end
    end

    return nil;
end

---@param spellbook table
function CatalogBuilder:reset(spellbook)
    spellbook.entriesByID = {};
    spellbook.groupsByName = {};
    spellbook.groupsByCategory = {};
    spellbook.available = false;

    for _, category in ipairs(spellbook.categoryOrder) do
        spellbook.groupsByCategory[category] = {};
    end
end

---@param spellbook table
---@param spellID number
---@param spellName string
---@param rankText string|nil
---@param icon any
---@param castTime number|nil
function CatalogBuilder:addEntry(spellbook, spellID, spellName, rankText, icon, castTime)
    if (not spellID or not spellName or spellbook.entriesByID[spellID]) then
        return;
    end

    local metadata, category = staticMetadata(spellName, spellID);
    category = category or "other";
    local rank = rankNumber(rankText);

    -- Buffs with explicit ranks (Amplify/Dampen Magic) carry the rank in the
    -- metadata so the Add Step menu can list each rank separately.
    if (rank == 0 and metadata and metadata.rank) then
        rank = metadata.rank;
    end

    local resultItemID = rankResultItem(spellName, rank) or (metadata and metadata.itemID);

    local entry = {
        spellID = spellID,
        name = spellName,
        rankText = rankText or "",
        rank = rank,
        icon = icon,
        isCastTime = metadata and metadata.isCastTime or ((castTime or 0) > 0),
        canTargetParty = metadata and metadata.canTargetParty or false,
        needsShard = metadata and metadata.needsShard or false,
        buffSpellID = metadata and metadata.buffSpellID,
        itemID = resultItemID,
        category = category,
    };

    spellbook.entriesByID[spellID] = entry;

    -- Stones group by FAMILY so getHighestKnownRank can match all ranks.
    local rankTable = ACP.Data.Workflows and ACP.Data.Workflows:activeRankTable();
    local groupKey = (rankTable and rankTable[spellID]
        and rankTable[spellID].spellName) or spellName;

    local group = spellbook.groupsByName[groupKey];
    if (not group) then
        group = { key = groupKey, name = groupKey, category = category, entries = {} };
        spellbook.groupsByName[groupKey] = group;
        tinsert(spellbook.groupsByCategory[category], group);
    elseif (group.category == "other" and category ~= "other") then
        group.category = category;
    end

    tinsert(group.entries, entry);
end

---@param spellbook table
function CatalogBuilder:finalize(spellbook)
    for _, group in pairs(spellbook.groupsByName) do
        sort(group.entries, function(a, b)
            if (a.rank ~= b.rank) then
                return a.rank < b.rank;
            end

            return a.spellID < b.spellID;
        end);
    end

    for _, category in ipairs(spellbook.categoryOrder) do
        sort(spellbook.groupsByCategory[category], function(a, b)
            return a.name < b.name;
        end);
    end
end

---@param spellbook table
---@return number
function CatalogBuilder:countEntries(spellbook)
    local count = 0;

    for _ in pairs(spellbook.entriesByID) do
        count = count + 1;
    end

    return count;
end

---@param spellbook table
---@param spellID number
---@return table|nil
function CatalogBuilder:getEntry(spellbook, spellID)
    return spellbook.entriesByID[spellID];
end

--- Highest rank of a spell the player actually KNOWS (IsPlayerSpell per
--- candidate — a stored lower rank can be unlearned at high level).
---@param spellbook table
---@param spellName string
---@return table|nil
function CatalogBuilder:getHighestKnownRank(spellbook, spellName)
    local group = spellbook.groupsByName[spellName];

    if (not group) then
        return nil;
    end

    local best, bestRank = nil, -1;

    for _, entry in ipairs(group.entries) do
        local ok, known = pcall(IsPlayerSpell, entry.spellID);
        known = ok and known;

        if (known and entry.rank and entry.rank > bestRank) then
            bestRank = entry.rank;
            best = entry;
        end
    end

    return best;
end

---@param spellbook table
---@param key string
---@return table|nil
function CatalogBuilder:getGroup(spellbook, key)
    return spellbook.groupsByName[key];
end

---@param spellbook table
---@return table<string, table>
function CatalogBuilder:getGroupsByCategory(spellbook)
    return spellbook.groupsByCategory;
end

return ACP;
