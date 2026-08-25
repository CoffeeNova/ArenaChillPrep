-- ArenaChillPrep — Data/MageWorkflows
-- Mage-only workflow data: spell catalog, conjured-item ranks and the five
-- default workflows. Loaded through ACP.Data.classWorkflows().
---@type ACP
local _, ACP = ...;

ACP.Data = ACP.Data or {};

---@class MageWorkflows
ACP.Data.MageWorkflows = {
    spells = {
        buffs = { -- Group-wide intellect buff; cast on self, affects the whole group.
        {
            spellID = 27127,
            name = "Arcane Brilliance",
            isCastTime = false,
            canTargetParty = false,
            buffSpellID = 27127
        }, {
            spellID = 27126,
            name = "Arcane Intellect",
            isCastTime = false,
            canTargetParty = true,
            buffSpellID = 27126
        }, -- Both ranks ship as separate entries (same name) — the rank
        -- field makes the Add Step menu list each one so the player can
        -- pick a specific rank.
        {
            spellID = 33946,
            name = "Amplify Magic",
            isCastTime = false,
            canTargetParty = true,
            buffSpellID = 33946,
            rank = 6
        }, {
            spellID = 1008,
            name = "Amplify Magic",
            isCastTime = false,
            canTargetParty = true,
            buffSpellID = 1008,
            rank = 1
        }, {
            spellID = 33944,
            name = "Dampen Magic",
            isCastTime = false,
            canTargetParty = true,
            buffSpellID = 33944,
            rank = 6
        }, {
            spellID = 604,
            name = "Dampen Magic",
            isCastTime = false,
            canTargetParty = true,
            buffSpellID = 604,
            rank = 1
        }, {
            spellID = 27125,
            name = "Mage Armor",
            isCastTime = false,
            canTargetParty = false,
            buffSpellID = 27125
        }, {
            spellID = 30482,
            name = "Molten Armor",
            isCastTime = false,
            canTargetParty = false,
            buffSpellID = 30482
        }, {
            spellID = 27124,
            name = "Ice Armor",
            isCastTime = false,
            canTargetParty = false,
            buffSpellID = 27124
        }, {
            spellID = 27128,
            name = "Fire Ward",
            isCastTime = false,
            canTargetParty = false,
            buffSpellID = 27128
        }, {
            spellID = 32796,
            name = "Frost Ward",
            isCastTime = false,
            canTargetParty = false,
            buffSpellID = 32796
        }, {
            spellID = 33405,
            name = "Ice Barrier",
            isCastTime = false,
            canTargetParty = false,
            buffSpellID = 33405
        }, {
            spellID = 66,
            name = "Invisibility",
            isCastTime = false,
            canTargetParty = false,
            buffSpellID = 66
        }},
        createItem = { -- Each cast conjures 10 items (ranks 7-9 conjure 10 when learned).
        {
            spellID = 33717,
            name = "Conjure Food",
            isCastTime = true,
            needsShard = false,
            itemID = 22019
        }, {
            spellID = 27090,
            name = "Conjure Water",
            isCastTime = true,
            needsShard = false,
            itemID = 22018
        }, -- Single-rank conjure: one Mana Emerald per cast.
        {
            spellID = 27101,
            name = "Conjure Mana Emerald",
            isCastTime = true,
            needsShard = false,
            itemID = 22044
        }},
        utility = { -- Conjures a table on the ground — no bag item.
        {
            spellID = 43987,
            name = "Ritual of Refreshment",
            isCastTime = true,
            needsShard = false
        }}
    },

    -- Per-rank data for the conjure spells. Unlike healthstones (historical
    -- ID pairs), food/water have a single itemID per rank.
    conjuredRanks = {
        [33717] = {
            spellID = 33717,
            spellName = "Conjure Food",
            category = "food",
            itemID = 22019,
            itemIDs = {22019},
            itemName = "Conjured Croissant",
            rank = 8
        },
        [27090] = {
            spellID = 27090,
            spellName = "Conjure Water",
            category = "water",
            itemID = 22018,
            itemIDs = {22018},
            itemName = "Conjured Glacier Water",
            rank = 9
        }
    },

    defaultDefinitions = {
        [1] = {
            enabled = true,
            name = "2s standard",
            steps = {{
                type = "createItem",
                spellName = "Conjure Water",
                spellID = 27090,
                itemID = 22018
            }, {
                type = "createItem",
                spellName = "Conjure Water",
                spellID = 27090,
                itemID = 22018
            }, {
                type = "createItem",
                spellName = "Conjure Food",
                spellID = 33717,
                itemID = 22019
            }, {
                type = "createItem",
                spellName = "Conjure Food",
                spellID = 33717,
                itemID = 22019
            }, {
                type = "createItem",
                spellName = "Conjure Mana Emerald",
                spellID = 27101,
                itemID = 22044
            }, {
                type = "cast",
                spellName = "Arcane Intellect",
                spellID = 27126,
                target = "player"
            }, {
                type = "cast",
                spellName = "Dampen Magic",
                spellID = 33944,
                target = "player"
            }, {
                type = "cast",
                spellName = "Arcane Intellect",
                spellID = 27126,
                target = "party1"
            }, {
                type = "cast",
                spellName = "Dampen Magic",
                spellID = 33944,
                target = "party1"
            }, {
                type = "createItem",
                spellName = "Conjure Water",
                spellID = 27090,
                itemID = 22018
            }, {
                type = "createItem",
                spellName = "Conjure Water",
                spellID = 27090,
                itemID = 22018
            }, {
                type = "createItem",
                spellName = "Conjure Food",
                spellID = 33717,
                itemID = 22019
            }, {
                type = "createItem",
                spellName = "Conjure Food",
                spellID = 33717,
                itemID = 22019
            }, {
                type = "cast",
                spellName = "Ice Armor",
                spellID = 27124,
                target = "player"
            }, {
                type = "cast",
                spellName = "Ice Barrier",
                spellID = 33405,
                target = "player"
            }, {
                type = "cast",
                spellName = "Frost Ward",
                spellID = 32796,
                target = "player"
            }}
        },
        [2] = {
            enabled = true,
            name = "2s with healer",
            steps = {{
                type = "createItem",
                spellName = "Conjure Water",
                spellID = 27090,
                itemID = 22018
            }, {
                type = "createItem",
                spellName = "Conjure Water",
                spellID = 27090,
                itemID = 22018
            }, {
                type = "createItem",
                spellName = "Conjure Food",
                spellID = 33717,
                itemID = 22019
            }, {
                type = "createItem",
                spellName = "Conjure Food",
                spellID = 33717,
                itemID = 22019
            }, {
                type = "createItem",
                spellName = "Conjure Mana Emerald",
                spellID = 27101,
                itemID = 22044
            }, {
                type = "cast",
                spellName = "Arcane Intellect",
                spellID = 27126,
                target = "player"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "player"
            }, {
                type = "cast",
                spellName = "Arcane Intellect",
                spellID = 27126,
                target = "party1"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "party1"
            }, {
                type = "createItem",
                spellName = "Conjure Water",
                spellID = 27090,
                itemID = 22018
            }, {
                type = "createItem",
                spellName = "Conjure Water",
                spellID = 27090,
                itemID = 22018
            }, {
                type = "createItem",
                spellName = "Conjure Food",
                spellID = 33717,
                itemID = 22019
            }, {
                type = "createItem",
                spellName = "Conjure Food",
                spellID = 33717,
                itemID = 22019
            }, {
                type = "cast",
                spellName = "Ice Armor",
                spellID = 27124,
                target = "player"
            }, {
                type = "cast",
                spellName = "Ice Barrier",
                spellID = 33405,
                target = "player"
            }, {
                type = "cast",
                spellName = "Frost Ward",
                spellID = 32796,
                target = "player"
            }}
        },
        [3] = {
            enabled = true,
            name = "3s standard",
            steps = {{
                type = "cast",
                spellName = "Ritual of Refreshment",
                spellID = 43987,
                target = "player"
            }, {
                type = "createItem",
                spellName = "Conjure Mana Emerald",
                spellID = 27101,
                itemID = 22044
            }, {
                type = "cast",
                spellName = "Arcane Brilliance",
                spellID = 27127,
                target = "player"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "player"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "party1"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "party2"
            }, {
                type = "cast",
                spellName = "Ice Armor",
                spellID = 27124,
                target = "player"
            }, {
                type = "cast",
                spellName = "Frost Ward",
                spellID = 32796,
                target = "player"
            }}
        },
        [4] = {
            enabled = true,
            name = "3s pom pyro",
            steps = {{
                type = "cast",
                spellName = "Ritual of Refreshment",
                spellID = 43987,
                target = "player"
            }, {
                type = "createItem",
                spellName = "Conjure Mana Emerald",
                spellID = 27101,
                itemID = 22044
            }, {
                type = "cast",
                spellName = "Arcane Brilliance",
                spellID = 27127,
                target = "player"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "player"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "party1"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "party2"
            }, {
                type = "cast",
                spellName = "Molten Armor",
                spellID = 30482,
                target = "player"
            }, {
                type = "cast",
                spellName = "Frost Ward",
                spellID = 32796,
                target = "player"
            }}
        },
        [5] = {
            enabled = true,
            name = "5s standard",
            steps = {{
                type = "cast",
                spellName = "Ritual of Refreshment",
                spellID = 43987,
                target = "player"
            }, {
                type = "createItem",
                spellName = "Conjure Mana Emerald",
                spellID = 27101,
                itemID = 22044
            }, {
                type = "cast",
                spellName = "Arcane Brilliance",
                spellID = 27127,
                target = "player"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "player"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "party1"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "party2"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "party3"
            }, {
                type = "cast",
                spellName = "Amplify Magic",
                spellID = 1008,
                target = "party4"
            }, {
                type = "cast",
                spellName = "Ice Armor",
                spellID = 27124,
                target = "player"
            }, {
                type = "cast",
                spellName = "Ice Barrier",
                spellID = 33405,
                target = "player"
            }, {
                type = "cast",
                spellName = "Frost Ward",
                spellID = 32796,
                target = "player"
            }}
        }
    }
};

return ACP;
