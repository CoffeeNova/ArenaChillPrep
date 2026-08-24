-- ArenaChillPrep — Data/Items
-- Static item catalog + class → items mapping. Currently: Warlock →
-- healthstones (auto-trade) + soulstones (workflow rank data). Future
-- categories: food, water, totems, ...
--
-- Healthstone IDs (verified against the TBC item database): each rank has a
-- PAIR of IDs — historical duplicates. Both IDs of a
-- rank must be tracked (a player may hold either).

---@type ACP
local _, ACP = ...;

-- CLASS_WARLOCK is NOT defined as a global on TBC Anniversary FrameXML
-- (retail-only constant). Guarded single source lives in Data/Constants.
local CLASS_WARLOCK = ACP.Data.Constants.CLASS_WARLOCK;

ACP.Data = ACP.Data or {};

---@class Items
ACP.Data.Items = {
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

    classItems = {
        [CLASS_WARLOCK] = { "healthstones" },
    },
};

return ACP;
