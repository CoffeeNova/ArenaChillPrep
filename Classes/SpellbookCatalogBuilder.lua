-- ArenaChillPrep — Classes/SpellbookCatalogBuilder
-- Runtime spell catalog assembly, extracted from WorkflowSpellbook
-- (refactor Phase 7): the entriesByID / groupsByName / groupsByCategory
-- tables (owned by the WorkflowSpellbook facade), entry building (metadata
-- enrichment + stone rank→item mapping), group finalizing (rank sorting) and
-- the read API. Every function takes the SPELLBOOK as its first argument.

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

--- Rank -> primary itemID map derived from the Data/Items catalog (the single
--- source of truth for stone rank→item data). For a rank with a historical ID
--- PAIR (healthstones 1-5) the LOWER ID is the primary variant — the same one
--- the old hardcoded tables used.
---@param category string  catalog key ("healthstones" | "soulstones")
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

--- Find the static metadata entry matching a localized or catalog spell name.
---@param spellName string
---@return table|nil entry
---@return string|nil category
local function staticMetadata(spellName)
    local spells = ACP.Data.Workflows and ACP.Data.Workflows.spells;

    if (not spells) then
        return nil;
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

--- Wipe the runtime catalog (the facade owns the tables).
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

--- Add one learned spellbook entry to the runtime catalog.
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

    local metadata, category = staticMetadata(spellName);
    category = category or "other";
    local rank = rankNumber(rankText);
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

    -- Stones are grouped by FAMILY ("Create Healthstone"), not the
    -- rank-suffixed localized spell name the scan reports, so
    -- getHighestKnownRank can match the whole family regardless of which rank
    -- name the scan produced. Non-stone spells keep their own group name.
    local groupKey = (ACP.Data.Workflows and ACP.Data.Workflows.stoneRanks
        and ACP.Data.Workflows.stoneRanks[spellID]
        and ACP.Data.Workflows.stoneRanks[spellID].spellName) or spellName;

    local group = spellbook.groupsByName[groupKey];
    if (not group) then
        group = { key = groupKey, name = groupKey, category = category, entries = {} };
        spellbook.groupsByName[groupKey] = group;
        tinsert(spellbook.groupsByCategory[category], group);
    elseif (group.category == "other" and category ~= "other") then
        -- A duplicate localized name matched known metadata later in the scan.
        group.category = category;
    end

    tinsert(group.entries, entry);
end

--- Sort the runtime catalog after a scan: group entries by rank ascending
--- (spellID as tiebreaker) and the per-category group lists by name.
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

--- Highest KNOWN rank of a spell, resolved by name. A stored lower rank can be
--- UNLEARNED at high level (the client replaces it with the max rank), so the
--- engine must cast the rank the player actually has. Each candidate rank's
--- spellID is confirmed with IsPlayerSpell (the static merge adds every rank to
--- the catalog, but only the trained ones are castable). Returns nil when the
--- spell name has no known rank.
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
