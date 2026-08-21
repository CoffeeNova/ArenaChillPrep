-- ArenaChillPrep — Classes/WorkflowSpellbook
-- Runtime spell catalog for the Workflow editor. The old UI exposed only the
-- small static Warlock catalog from Data/Workflows.lua. This module scans the
-- player's actual spellbook on 20506, groups learned ranks by localized spell
-- name and keeps the exact spellID for every rank so the editor can store the
-- rank the player selected.
--
-- Static catalog entries remain metadata only: they identify special behavior
-- (summon, createItem, buff, reagent) for known spells. Unknown learned spells
-- are still exposed as generic cast steps instead of being hidden.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local pcall = _G.pcall;
local select = _G.select;
local tonumber = _G.tonumber;
local tostring = _G.tostring;
local tinsert = _G.tinsert;
local sort = _G.table.sort;
local GetSpellInfo = _G.GetSpellInfo;
local IsPassiveSpell = _G.IsPassiveSpell;
local UnitClass = _G.UnitClass;
local Enum = _G.Enum;
local C_SpellBook = _G.C_SpellBook;

-- CLASS_WARLOCK is NOT a global on TBC Anniversary FrameXML (retail-only
-- constant) — same guard as Data/Items.lua.
local CLASS_WARLOCK = _G.CLASS_WARLOCK or "WARLOCK";

local HEALTHSTONE_RESULTS = { 19004, 19006, 19008, 19010, 19012, 22105 };
local SOULSTONE_RESULTS = { 16892, 16893, 16894, 16895, 22103 };

-- 20506 exposes both legacy globals and the backported C_SpellBook namespace
-- depending on the client build. Both are probed at CALL time (not load time —
-- the globals may not exist at ADDON_LOADED). The legacy API takes a STRING
-- bookType where "spell"/"pet" is the TBC form (BOOKTYPE_SPELL — the verified
-- 20506 addons M6/NovaSpellRankChecker/WeakAuras all pass "spell"; "player" is
-- the retail form and makes the legacy scan return nothing on this client); the
-- modern C_SpellBook API takes the numeric Enum.SpellBookSpellBank value. Each
-- path passes the bank form it expects.
local SPELLBOOK_SPELL_STR = "spell";
local SPELLBOOK_PLAYER_ENUM = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0;

local function spellTypeIsSpell(spellType)
    return spellType == "SPELL" or spellType == 1;
end

-- Legacy-path probes (string bank).
local function legacyTabCount()
    return _G.GetNumSpellTabs and pcall(_G.GetNumSpellTabs);
end

local function legacyTabInfo(tab)
    return _G.GetSpellTabInfo and pcall(_G.GetSpellTabInfo, tab);
end

local function legacyItemInfo(slot, bank)
    return _G.GetSpellBookItemInfo and pcall(_G.GetSpellBookItemInfo, slot, bank);
end

local function legacyItemName(slot, bank)
    return _G.GetSpellBookItemName and pcall(_G.GetSpellBookItemName, slot, bank);
end

-- Modern-path probes (numeric enum bank).
local function modernTabCount()
    return C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and pcall(C_SpellBook.GetNumSpellBookSkillLines);
end

local function modernTabInfo(tab)
    if (not (C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo)) then
        return nil;
    end

    local ok, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, tab);

    if (not ok or not info) then
        return nil;
    end

    return true, info.name, info.iconID, info.itemIndexOffset, info.numSpellBookItems, info.isGuild, info.specID;
end

local function modernItemInfo(slot, bank)
    if (not (C_SpellBook and C_SpellBook.GetSpellBookItemInfo)) then
        return nil;
    end

    -- The 20506 backport returns the retail-style object { itemType, actionID }
    -- (M6 TenEnv pattern). Guard against a 2-value tuple (legacy shape) too —
    -- indexing a number outside the pcall would throw and kill the whole scan.
    local ok, a, b = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank);

    if (not ok or not a) then
        return nil;
    end

    if (type(a) == "table") then
        return true, a.itemType, a.spellID or a.actionID;
    end

    return true, a, b;
end

local function modernItemName(slot, bank)
    if (not (C_SpellBook and C_SpellBook.GetSpellBookItemName)) then
        return nil;
    end

    return pcall(C_SpellBook.GetSpellBookItemName, slot, bank);
end

---@class WorkflowSpellbook
local Spellbook = {
    _initialized = false,
    available = false,
    entriesByID = {},
    groupsByName = {},
    groupsByCategory = {},
    categoryOrder = { "buffs", "summons", "createItem", "utility", "pets", "other" },
};

ACP.WorkflowSpellbook = Spellbook;

local function spellTypeIsSpell(spellType)
    return spellType == "SPELL" or spellType == 1;
end

--- The player's English class token ("WARLOCK", "MAGE", ...). Nil before the
--- character is loaded (UnitClass("player") is unreliable during ADDON_LOADED).
---@return string|nil
local function playerEnglishClass()
    return _G.UnitClass and select(2, _G.UnitClass("player"));
end

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

function Spellbook:_reset()
    self.entriesByID = {};
    self.groupsByName = {};
    self.groupsByCategory = {};
    self.available = false;

    for _, category in ipairs(self.categoryOrder) do
        self.groupsByCategory[category] = {};
    end
end

--- Add one learned spellbook entry to the runtime catalog.
---@param spellID number
---@param spellName string
---@param rankText string|nil
---@param icon any
---@param castTime number|nil
function Spellbook:addEntry(spellID, spellName, rankText, icon, castTime)
    if (not spellID or not spellName or self.entriesByID[spellID]) then
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

    self.entriesByID[spellID] = entry;

    -- Stones are grouped by FAMILY ("Create Healthstone"), not the
    -- rank-suffixed localized spell name the scan reports, so
    -- getHighestKnownRank can match the whole family regardless of which rank
    -- name the scan produced. Non-stone spells keep their own group name.
    local groupKey = (ACP.Data.Workflows and ACP.Data.Workflows.stoneRanks
        and ACP.Data.Workflows.stoneRanks[spellID]
        and ACP.Data.Workflows.stoneRanks[spellID].spellName) or spellName;

    local group = self.groupsByName[groupKey];
    if (not group) then
        group = { key = groupKey, name = groupKey, category = category, entries = {} };
        self.groupsByName[groupKey] = group;
        tinsert(self.groupsByCategory[category], group);
    elseif (group.category == "other" and category ~= "other") then
        -- A duplicate localized name matched known metadata later in the scan.
        group.category = category;
    end

    tinsert(group.entries, entry);
end

--- Merge the Warlock-specific static entries (pet abilities and the full rank
--- list of the stone-creating spells) into the catalog. Called after every scan
--- for a confirmed Warlock — these spells are pet/grunt-learned abilities that
--- the player's own spellbook scan can never produce (Fire Shield / Sacrifice)
--- or that are known only at one rank (the stone ranks are listed so the user
--- can pick any rank). Skips IDs already present from the real scan.
function Spellbook:mergeStaticWarlock()
    if (playerEnglishClass() ~= CLASS_WARLOCK) then
        return;
    end

    local spells = ACP.Data.Workflows and ACP.Data.Workflows.spells;
    local stoneRanks = ACP.Data.Workflows and ACP.Data.Workflows.stoneRanks;

    if (spells) then
        for category, list in pairs(spells) do
            if (category == "pets") then
                for _, source in ipairs(list) do
                    if (not self.entriesByID[source.spellID]) then
                        self:addEntry(source.spellID, source.name, "", nil, source.isCastTime and 1 or 0);
                        local entry = self.entriesByID[source.spellID];

                        if (entry) then
                            entry.category = category;
                            entry.isPetSpell = true;
                            entry.pet = source.pet;
                            entry.isCastTime = source.isCastTime;
                        end
                    end
                end
            end
        end
    end

    if (stoneRanks) then
        for spellID, rank in pairs(stoneRanks) do
            if (not self.entriesByID[spellID]) then
                self:addEntry(spellID, rank.spellName or "Create", "", nil, 1);
                local entry = self.entriesByID[spellID];

                if (entry) then
                    entry.category = "createItem";
                    entry.itemID = rank.itemID;
                    entry.rank = rank.rank;
                    entry.isCastTime = true;
                    entry.needsShard = true;
                end
            end
        end
    end
end

--- Static fallback used by tests/clients where the spellbook API is not ready.
--- Only populates for a confirmed Warlock: the catalog is Warlock-specific, so
--- injecting it for any other class (e.g. a Mage at ADDON_LOADED) would pollute
--- the Add Step list with spells that character can never cast. When the class
--- is not known yet (pre-login) the fallback stays empty — the PLAYER_LOGIN
--- re-scan fills the catalog from the real spellbook.
function Spellbook:addStaticFallback()
    if (playerEnglishClass() ~= CLASS_WARLOCK) then
        return;
    end

    local spells = ACP.Data.Workflows and ACP.Data.Workflows.spells;

    if (not spells) then
        return;
    end

    for category, list in pairs(spells) do
        for _, source in ipairs(list) do
            self:addEntry(source.spellID, source.name, "", nil, source.isCastTime and 1 or 0);
            local entry = self.entriesByID[source.spellID];

            if (entry) then
                entry.category = category;
                entry.canTargetParty = source.canTargetParty;
                entry.needsShard = source.needsShard;
                entry.buffSpellID = source.buffSpellID;
                entry.itemID = source.itemID;
                entry.isCastTime = source.isCastTime;
                entry.isPetSpell = source.isPetSpell;
                entry.pet = source.pet;
            end
        end
    end
end

--- Display name of a stone rank entry, e.g. "Master Healthstone" for
--- { itemName = "Master Healthstone", rank = 6 }. Falls back to "Spell N" when
--- the rank data is missing.
---@param rank table|nil
---@return string
function Spellbook:stoneName(rank)
    if (type(rank) == "table" and type(rank.itemName) == "string" and rank.itemName ~= "") then
        return rank.itemName;
    end

    return "Spell";
end

--- Display label for a stone-creating spell entry: "Create Master Healthstone"
--- for a rank-6 Create Healthstone entry, etc. Falls back to the plain spell
--- name when no rank data is available.
---@param entry table
---@return string
function Spellbook:stoneStepLabel(entry)
    local stone = ACP.Data.Workflows and ACP.Data.Workflows.stoneRanks
        and ACP.Data.Workflows.stoneRanks[entry.spellID];

    if (stone) then
        -- Append the rank explicitly: GetSpellInfo returns only the unranked base
        -- name ("Create Healthstone") on 20506, so the rank must come from the
        -- catalog — otherwise all six ranks show identically in the Add Step list.
        local base = (stone.spellName and stone.spellName ~= "") and stone.spellName or "Create";
        return base .. " (rank " .. tostring(stone.rank) .. ")";
    end

    return entry.name or "Create";
end

--- Scan one spellbook path (legacy globals with string bank, or C_SpellBook
--- with the numeric enum bank). Adds entries for every learned non-passive
--- spell. Returns true when at least one spell was found.
---@param modern boolean
---@return boolean
function Spellbook:scanBook(modern)
    local okTabs, count;

    if (modern) then
        okTabs, count = modernTabCount();
    else
        okTabs, count = legacyTabCount();
    end

    if (not okTabs) then
        return false;
    end

    if (not (okTabs and count and count > 0)) then
        return false;
    end

    local bank = modern and SPELLBOOK_PLAYER_ENUM or SPELLBOOK_SPELL_STR;

    for tab = 1, count do
        local okTab, _, _, offset, numItems = (modern and modernTabInfo or legacyTabInfo)(tab);

        if (okTab and offset ~= nil and numItems and numItems > 0) then
            for slot = offset + 1, offset + numItems do
                local okInfo, spellType, spellID = (modern and modernItemInfo or legacyItemInfo)(slot, bank);

                if (okInfo and spellTypeIsSpell(spellType) and spellID) then
                    local passive = false;

                    if (IsPassiveSpell) then
                        local okPassive, result = pcall(IsPassiveSpell, slot, bank);
                        passive = okPassive and result == true;
                    end

                    if (not passive) then
                        local okName, spellName, rankText = (modern and modernItemName or legacyItemName)(slot, bank);

                        if (not okName or not spellName) then
                            local okInfo2, fallbackName, fallbackRank = GetSpellInfo and pcall(GetSpellInfo, spellID);
                            spellName = okInfo2 and fallbackName or nil;
                            rankText = okInfo2 and fallbackRank or rankText;
                        end

                        if (spellName) then
                            self:addEntry(spellID, spellName, rankText);
                        end
                    end
                end
            end
        end
    end

    return next(self.entriesByID) ~= nil;
end

--- Scan all active player spellbook tabs. Tries the legacy API first, then
--- the backported C_SpellBook API. When both return nothing (spellbook not
--- loaded yet, e.g. at ADDON_LOADED) the class-gated static fallback fills the
--- catalog for Warlocks. Logs the path that succeeded so a scan that still
--- finds nothing on a specific client is self-diagnosing.
function Spellbook:scan()
    self:_reset();

    local ok = self:scanBook(false);

    if (not ok) then
        ok = self:scanBook(true);
    end

    -- Warlock-only static entries (pet abilities + stone ranks) are merged in
    -- ALWAYS for a warlock — the scan can never produce pet abilities and only
    -- knows one rank of a stone spell.
    if (playerEnglishClass() == CLASS_WARLOCK) then
        self:mergeStaticWarlock();
    end

    -- Full static catalog fallback for the pre-login / API-unavailable case
    -- (the real scan found nothing). Keyed on `ok` — did the REAL scan find any
    -- spell — not on entriesByID being empty AFTER mergeStaticWarlock: that
    -- merge always leaves pet abilities + stone ranks, so the old check never
    -- fired and a Warlock with an empty scan lost the buffs/summons/utility
    -- sections entirely. addStaticFallback is class-gated internally, so a
    -- non-Warlock with an empty scan keeps an empty catalog.
    if (not ok) then
        self:addStaticFallback();
    end

    ACP:debugPrint("workflow spellbook scan: legacy=%s modern=%s found=%d",
        tostring(ok), tostring(not ok and next(self.entriesByID) ~= nil), self:countEntries());

    for _, group in pairs(self.groupsByName) do
        sort(group.entries, function(a, b)
            if (a.rank ~= b.rank) then
                return a.rank < b.rank;
            end

            return a.spellID < b.spellID;
        end);
    end

    for _, category in ipairs(self.categoryOrder) do
        sort(self.groupsByCategory[category], function(a, b)
            return a.name < b.name;
        end);
    end

    self.available = next(self.entriesByID) ~= nil;
    return self.entriesByID;
end

---@return number
function Spellbook:countEntries()
    local count = 0;

    for _ in pairs(self.entriesByID) do
        count = count + 1;
    end

    return count;
end

---@param spellID number
---@return table|nil
function Spellbook:getEntry(spellID)
    return self.entriesByID[spellID];
end

--- Highest KNOWN rank of a spell, resolved by name. A stored lower rank can be
--- UNLEARNED at high level (the client replaces it with the max rank), so the
--- engine must cast the rank the player actually has. Each candidate rank's
--- spellID is confirmed with IsPlayerSpell (the static merge adds every rank to
--- the catalog, but only the trained ones are castable). Returns nil when the
--- spell name has no known rank.
---@param spellName string
---@return table|nil
function Spellbook:getHighestKnownRank(spellName)
    local group = self.groupsByName[spellName];

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

---@param key string
---@return table|nil
function Spellbook:getGroup(key)
    return self.groupsByName[key];
end

---@return table<string, table>
function Spellbook:getGroupsByCategory()
    return self.groupsByCategory;
end

function Spellbook:_refreshUI()
    if (ACP.WorkflowUI and ACP.WorkflowUI.isBuilt) then
        ACP.WorkflowUI:refresh();
    end
end

function Spellbook:_init()
    if (self._initialized) then
        return;
    end

    self._initialized = true;
    self:scan();

    if (ACP.Events) then
        -- The initial scan runs at ADDON_LOADED when the character (and its
        -- spellbook) is not loaded yet — re-scan once the character is ready
        -- and again whenever the spellbook changes.
        ACP.Events:register("WorkflowSpellbook.PLAYER_LOGIN", "PLAYER_LOGIN", function()
            self:scan();
            self:_refreshUI();
        end);
        ACP.Events:register("WorkflowSpellbook.SPELLS_CHANGED", "SPELLS_CHANGED", function()
            self:scan();
            self:_refreshUI();
        end);
    end
end

return ACP;
