-- ArenaChillPrep — Data/Items
-- Static item catalog + class → items mapping. Healthstone ranks 1-5 are
-- historical ID pairs — both IDs of a rank must be tracked.

---@type ACP
local _, ACP = ...;

-- Not a global on TBC FrameXML (retail-only constant).
local CLASS_WARLOCK = ACP.Data.Constants.CLASS_WARLOCK;
local CLASS_MAGE = ACP.Data.Constants.CLASS_MAGE;
local CLASS_PRIEST = ACP.Data.Constants.CLASS_PRIEST;
local CLASS_PALADIN = ACP.Data.Constants.CLASS_PALADIN;
local CLASS_DRUID = ACP.Data.Constants.CLASS_DRUID;
local CLASS_HUNTER = ACP.Data.Constants.CLASS_HUNTER;
local CLASS_SHAMAN = ACP.Data.Constants.CLASS_SHAMAN;
local CLASS_ROGUE = ACP.Data.Constants.CLASS_ROGUE;
local CLASS_WARRIOR = ACP.Data.Constants.CLASS_WARRIOR;

ACP.Data = ACP.Data or {};

---@class Items
local Items = {
    healthstones = {
        -- Minor (lvl 10)
        [19004] = { id = 19004, rank = 1, name = "Minor Healthstone" },
        [19005] = { id = 19005, rank = 1, name = "Minor Healthstone" },
        -- Lesser (lvl 22)
        [19006] = { id = 19006, rank = 2, name = "Lesser Healthstone" },
        [19007] = { id = 19007, rank = 2, name = "Lesser Healthstone" },
        -- Healthstone (lvl 34)
        [19008] = { id = 19008, rank = 3, name = "Healthstone" },
        [19009] = { id = 19009, rank = 3, name = "Healthstone" },
        -- Greater (lvl 46)
        [19010] = { id = 19010, rank = 4, name = "Greater Healthstone" },
        [19011] = { id = 19011, rank = 4, name = "Greater Healthstone" },
        -- Major (lvl 58)
        [19012] = { id = 19012, rank = 5, name = "Major Healthstone" },
        [19013] = { id = 19013, rank = 5, name = "Major Healthstone" },
        -- Master (lvl 70, TBC max rank)
        [22105] = { id = 22105, rank = 6, name = "Master Healthstone" },
    },
    -- Soulstones (Warlock, one ID per rank). Single source for the
    -- WorkflowSpellbook rank→item map (rankResultItem).
    soulstones = {
        [16892] = { id = 16892, rank = 1, name = "Minor Soulstone" },
        [16893] = { id = 16893, rank = 2, name = "Lesser Soulstone" },
        [16894] = { id = 16894, rank = 3, name = "Soulstone" },
        [16895] = { id = 16895, rank = 4, name = "Greater Soulstone" },
        [22103] = { id = 22103, rank = 5, name = "Major Soulstone" },
    },

    -- Mage conjured items (one ID per rank; conjured at 10 per cast).
    food = {
        [22019] = { id = 22019, rank = 8, name = "Conjured Croissant" },
    },
    water = {
        [22018] = { id = 22018, rank = 9, name = "Conjured Glacier Water" },
    },

    classItems = {
        [CLASS_WARLOCK] = { "healthstones" },
        [CLASS_MAGE] = { "food", "water" },
    },

    -- Mage conjured categories per PARTNER class (autotrade filter): mana
    -- users take food AND water, Rogues/Warriors take food only. Unlisted
    -- partner classes receive everything. Warlock healthstones are
    -- unaffected — this table only filters the MAGE's categories.
    magePartnerCategories = {
        [CLASS_PRIEST] = { "food", "water" },
        [CLASS_PALADIN] = { "food", "water" },
        [CLASS_WARLOCK] = { "food", "water" },
        [CLASS_DRUID] = { "food", "water" },
        [CLASS_HUNTER] = { "food", "water" },
        [CLASS_SHAMAN] = { "food", "water" },
        [CLASS_ROGUE] = { "food" },
        [CLASS_WARRIOR] = { "food" },
    },

    -- Explicit plural → singular mapping. The generic `sub(1, -2)` trick
    -- breaks for non-plural keys ("food" → "foo").
    settingsKeyByCategory = {
        healthstones = "healthstone",
        food = "food",
        water = "water",
    },

    -- Per-category "how many items to await before trading" slider ranges.
    -- Categories without an entry have no count slider (fixed count).
    countRanges = {
        food = { min = 10, max = 60, step = 10 },
        water = { min = 10, max = 60, step = 10 },
    },
};

---@type Items
ACP.Data.Items = Items;

--- Settings key (singular) for a plural catalog key. Falls back to the old
--- trailing-"s" strip for unknown categories.
---@param category string
---@return string
function Items:settingsKeyFor(category)
    return Items.settingsKeyByCategory[category] or category:sub(1, -2);
end

return ACP;
