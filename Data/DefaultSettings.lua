-- ArenaChillPrep — Data/DefaultSettings
-- Default SavedVariables structure (ArenaChillPrepDB). Deep-merged with the
-- saved data on load, so new keys added in future versions are safe.
---@type ACP
local _, ACP = ...;

ACP.Data = ACP.Data or {};

---@class DefaultSettings
ACP.Data.DefaultSettings = {
    enabled = true, -- Master switch.
    tradeDelay = 1.5, -- Seconds between the item appearing and opening the trade.
    gateSafetySeconds = 15, -- Stop all trading N seconds before the gates open.
    brackets = { -- Which arena brackets auto-trade is active in.
        ["2v2"] = true, -- Default: 2v2 only.
        ["3v3"] = false,
        ["5v5"] = false
    },
    items = {
        healthstone = {
            enabled = true, -- Pass healthstones.
            count = 1, -- How many per trade.
            ranks = { -- Which ranks to consider (by itemID).
                [19012] = true, -- Major Healthstone (variant 1).
                [19013] = true, -- Major Healthstone (variant 2).
                [22105] = true -- Master Healthstone (TBC max rank).
            }
        }
    },
    workflows = {
        enabled = true, -- Master workflow switch (General tab).
        slotCount = 5, -- Five slots are visible initially; the UI can add more.
        skipIfBuffedDefault = true, -- Default skipIfBuffed for new buff steps.
        definitions = {
            -- Step schema: { type, spellID, spellName?, target?, skipIfBuffed?,
            -- itemID? } (+ { type="equipItem", itemID, itemName? }).
            -- Runtime spellbook scanning stores the exact selected rank ID.
            --
            -- Slots 1-2 are the user's m6 arena-prep macros translated into
            -- steps (verified spell IDs: 27230 = Create Healthstone Rank 6 ->
            -- Master Healthstone 22105; 28172 = Create Spellstone Rank 4 ->
            -- Master Spellstone 22646; 28189 = Fel Armor Rank 2; 132 = Detect
            -- Invisibility). "Create Healthstone(Rank 5)" macro entries are
            -- stored as the max rank 27230/22105 to match the Master stone the
            -- m6 macro creates (on TBC 2.5.5 the ranks coexist — the client
            -- does NOT auto-upgrade old-rank casts). Duplicate createItem
            -- steps complete instantly once the item is in bags (goal-met
            -- fast path), so the macro's spam-duplicates need only one press.
            [1] = {
                enabled = true,
                name = "2s full prep",
                steps = { -- /cast [nopet] Summon Imp (688).
                {
                    type = "summon",
                    spellID = 688
                }, -- /castsequence: Create Healthstone -> Master Healthstone (x2 entries).
                {
                    type = "createItem",
                    spellID = 27230,
                    itemID = 22105
                }, {
                    type = "createItem",
                    spellID = 27230,
                    itemID = 22105
                }, -- Create Spellstone -> Master Spellstone.
                {
                    type = "createItem",
                    spellID = 28172,
                    itemID = 22646
                }, -- Summon Felhunter.
                {
                    type = "summon",
                    spellID = 691
                }, -- Soul Link (talent rank 2, instant self-buff).
                {
                    type = "cast",
                    spellID = 19028,
                    target = "player",
                    skipIfBuffed = true
                }, -- Create Healthstone -> Master Healthstone (x2 entries; fast-pathed once in bags).
                {
                    type = "createItem",
                    spellID = 27230,
                    itemID = 22105
                }, {
                    type = "createItem",
                    spellID = 27230,
                    itemID = 22105
                }, -- Fel Armor (rank 2).
                {
                    type = "cast",
                    spellID = 28189,
                    target = "player",
                    skipIfBuffed = true
                }, -- Unending Breath (x2 macro entries; second auto-skips when buffed).
                {
                    type = "cast",
                    spellID = 5697,
                    target = "player",
                    skipIfBuffed = true
                }, -- Detect Invisibility (x2 macro entries; second auto-skips when buffed).
                {
                    type = "cast",
                    spellID = 132,
                    target = "player",
                    skipIfBuffed = true
                }, {
                    type = "cast",
                    spellID = 5697,
                    target = "player",
                    skipIfBuffed = true
                }, {
                    type = "cast",
                    spellID = 132,
                    target = "player",
                    skipIfBuffed = true
                }, -- /equip Master Spellstone.
                {
                    type = "equipItem",
                    itemID = 22646,
                    itemName = "Master Spellstone"
                }}
            },
            [2] = {
                enabled = false,
                name = "Full prep (Voidwalker)",
                steps = { -- Same m6 flow without Soul Link; Voidwalker instead of Felhunter.
                {
                    type = "summon",
                    spellID = 688
                }, -- Create Healthstone -> Master Healthstone (x2 entries).
                {
                    type = "createItem",
                    spellID = 27230,
                    itemID = 22105
                }, {
                    type = "createItem",
                    spellID = 27230,
                    itemID = 22105
                }, -- Create Spellstone -> Master Spellstone.
                {
                    type = "createItem",
                    spellID = 28172,
                    itemID = 22646
                }, -- Create Healthstone -> Master Healthstone (x2 entries).
                {
                    type = "createItem",
                    spellID = 27230,
                    itemID = 22105
                }, {
                    type = "createItem",
                    spellID = 27230,
                    itemID = 22105
                }, -- Summon Voidwalker.
                {
                    type = "summon",
                    spellID = 697
                }, -- Fel Armor (rank 2).
                {
                    type = "cast",
                    spellID = 28189,
                    target = "player",
                    skipIfBuffed = true
                }, -- Unending Breath + Detect Invisibility (x2 macro entries each).
                {
                    type = "cast",
                    spellID = 5697,
                    target = "player",
                    skipIfBuffed = true
                }, {
                    type = "cast",
                    spellID = 132,
                    target = "player",
                    skipIfBuffed = true
                }, {
                    type = "cast",
                    spellID = 5697,
                    target = "player",
                    skipIfBuffed = true
                }, {
                    type = "cast",
                    spellID = 132,
                    target = "player",
                    skipIfBuffed = true
                }, -- /equip Master Spellstone.
                {
                    type = "equipItem",
                    itemID = 22646,
                    itemName = "Master Spellstone"
                }}
            },
            [3] = {
                enabled = false,
                name = "",
                steps = {}
            },
            [4] = {
                enabled = false,
                name = "",
                steps = {}
            },
            [5] = {
                enabled = false,
                name = "",
                steps = {}
            }
        }
    }
};

return ACP;
