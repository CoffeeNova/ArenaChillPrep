-- ArenaChillPrep — Data/WarlockWorkflows
-- Warlock-only workflow data: spell catalog, equip items, stone ranks and
-- the five default workflows. Loaded through ACP.Data.classWorkflows().

---@type ACP
local _, ACP = ...;

ACP.Data = ACP.Data or {};

---@class WarlockWorkflows
ACP.Data.WarlockWorkflows = {
    spells = {
        buffs = {
            { spellID = 28176, name = "Fel Armor",          isCastTime = false, canTargetParty = false, buffSpellID = 28176 },
            { spellID = 28189, name = "Fel Armor",          isCastTime = false, canTargetParty = false, buffSpellID = 28189 },
            -- Max rank only; lower ranks are replaced in the spellbook at 70.
            { spellID = 27260, name = "Demon Armor",        isCastTime = false, canTargetParty = false, buffSpellID = 27260 },
            { spellID = 5697,  name = "Unending Breath",    isCastTime = false, canTargetParty = true,  buffSpellID = 5697 },
            -- Applied aura (25228) shares the name; skip-if-buffed matches by name.
            { spellID = 19028, name = "Soul Link",          isCastTime = false, canTargetParty = false, buffSpellID = 19028 },
            -- Max rank; self-only Magic absorb shield (30 s).
            { spellID = 28610, name = "Shadow Ward",        isCastTime = false, canTargetParty = false, buffSpellID = 28610 },
            { spellID = 132,   name = "Detect Invisibility", isCastTime = false, canTargetParty = true, buffSpellID = 132 },
        },
        summons = {
            { spellID = 688,   name = "Summon Imp",        isCastTime = true, needsShard = false, petEntry = 416 },
            { spellID = 697,   name = "Summon Voidwalker", isCastTime = true, needsShard = true,  petEntry = 1860 },
            { spellID = 712,   name = "Summon Succubus",   isCastTime = true, needsShard = true,  petEntry = 1863 },
            { spellID = 691,   name = "Summon Felhunter",  isCastTime = true, needsShard = true,  petEntry = 417 },
            { spellID = 30146, name = "Summon Felguard",   isCastTime = true, needsShard = true,  petEntry = 17252 },
        },
        -- Pet-cast abilities; pet steps are exempt from the player-casting gate.
        pets = {
            -- 19483 (rank 1) resolves to "Immolation" on 2.5.5 — use the TBC rank 6.
            { spellID = 27269, name = "Fire Shield",  isPetSpell = true, pet = "imp",        isCastTime = false, canTargetParty = true },
            { spellID = 7812,  name = "Sacrifice",    isPetSpell = true, pet = "voidwalker", isCastTime = false, canTargetParty = false },
        },
        createItem = {
            { spellID = 6201,  name = "Create Healthstone", isCastTime = true, needsShard = true, itemID = 19004 },
            -- Ranks coexist: a rank-5 cast really creates a Major stone.
            { spellID = 11730, name = "Create Healthstone", isCastTime = true, needsShard = true, itemID = 19012 },
            { spellID = 27230, name = "Create Healthstone", isCastTime = true, needsShard = true, itemID = 22105 },
            { spellID = 28172, name = "Create Spellstone",  isCastTime = true, needsShard = true, itemID = 22646 },
        },
        utility = {
            { spellID = 29893, name = "Ritual of Souls", isCastTime = true, needsShard = true },
        },
    },

    -- Equippable conjured items an `equipItem` step may equip (spellstones).
    equipItems = {
        { itemID = 5522,  name = "Spellstone" },
        { itemID = 13602, name = "Greater Spellstone" },
        { itemID = 13603, name = "Major Spellstone" },
        { itemID = 22646, name = "Master Spellstone" },
    },

    -- Per-rank data for the stone-creating spells; the Add Step menu lists one
    -- entry per rank with the stone's name. Healthstone ranks 1-5 exist as
    -- historical item-ID pairs (the client conjures either variant); Create
    -- Spellstone ships only the TBC max rank.
    stoneRanks = {
        [6201]  = { spellID = 6201,  spellName = "Create Healthstone", category = "healthstones", itemID = 19004, itemIDs = { 19004, 19005 }, itemName = "Minor Healthstone", rank = 1 },
        [6202]  = { spellID = 6202,  spellName = "Create Healthstone", category = "healthstones", itemID = 19006, itemIDs = { 19006, 19007 }, itemName = "Lesser Healthstone", rank = 2 },
        [5699]  = { spellID = 5699,  spellName = "Create Healthstone", category = "healthstones", itemID = 19008, itemIDs = { 19008, 19009 }, itemName = "Healthstone", rank = 3 },
        [11729] = { spellID = 11729, spellName = "Create Healthstone", category = "healthstones", itemID = 19010, itemIDs = { 19010, 19011 }, itemName = "Greater Healthstone", rank = 4 },
        [11730] = { spellID = 11730, spellName = "Create Healthstone", category = "healthstones", itemID = 19012, itemIDs = { 19012, 19013 }, itemName = "Major Healthstone", rank = 5 },
        [27230] = { spellID = 27230, spellName = "Create Healthstone", category = "healthstones", itemID = 22105, itemIDs = { 22105 }, itemName = "Master Healthstone", rank = 6 },
        [28172] = { spellID = 28172, spellName = "Create Spellstone", category = "healthstones", itemID = 22646, itemIDs = { 22646 }, itemName = "Master Spellstone", rank = 4 },
    },

    defaultDefinitions = {
        [1] = { enabled = true, name = "2s with sacrifice", steps = { { type = "summon", spellName = "Summon Imp", spellID = 688 }, { type = "createItem", spellName = "Create Healthstone", spellID = 27230, itemID = 22105 }, { type = "createItem", spellName = "Create Healthstone", spellID = 11730, itemID = 19012 }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "player" }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "party1" }, { type = "createItem", spellName = "Create Spellstone", spellID = 28172, itemID = 22646 }, { type = "summon", spellName = "Summon Voidwalker", spellID = 697 }, { type = "createItem", spellName = "Create Healthstone", spellID = 27230, itemID = 22105 }, { type = "createItem", spellName = "Create Healthstone", spellID = 11730, itemID = 19012 }, { type = "equipItem", itemID = 22646, itemName = "Master Spellstone" }, { type = "cast", spellName = "Fel Armor", spellID = 28189, target = "player" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "player" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "player" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "party1" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "party1" }, { type = "summon", spellName = "Summon Felhunter", spellID = 691 }, { type = "pet", spellName = "Sacrifice", spellID = 7812 }, { type = "cast", spellName = "Soul Link", spellID = 19028, target = "player" }, { type = "cast", spellName = "Shadow Ward", spellID = 28610, target = "player" } } },
        [2] = { enabled = true, name = "2s no sacrifice", steps = { { type = "summon", spellName = "Summon Imp", spellID = 688 }, { type = "createItem", spellName = "Create Healthstone", spellID = 27230, itemID = 22105 }, { type = "createItem", spellName = "Create Healthstone", spellID = 11730, itemID = 19012 }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "player" }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "party1" }, { type = "summon", spellName = "Summon Felhunter", spellID = 691 }, { type = "cast", spellName = "Soul Link", spellID = 19028, target = "player" }, { type = "createItem", spellName = "Create Spellstone", spellID = 28172, itemID = 22646 }, { type = "cast", spellName = "Fel Armor", spellID = 28189, target = "player" }, { type = "equipItem", itemID = 22646, itemName = "Master Spellstone" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "player" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "player" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "party1" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "party1" }, { type = "cast", spellName = "Shadow Ward", spellID = 28610, target = "player" } } },
        [3] = { enabled = true, name = "3s with sacrifice", steps = { { type = "summon", spellName = "Summon Imp", spellID = 688 }, { type = "cast", spellName = "Ritual of Souls", spellID = 29893, target = "player" }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "player" }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "party1" }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "party2" }, { type = "summon", spellName = "Summon Voidwalker", spellID = 697 }, { type = "cast", spellName = "Fel Armor", spellID = 28189, target = "player" }, { type = "createItem", spellName = "Create Spellstone", spellID = 28172, itemID = 22646 }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "player" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "player" }, { type = "equipItem", itemID = 22646, itemName = "Master Spellstone" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "party1" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "party1" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "party2" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "party2" }, { type = "summon", spellName = "Summon Felhunter", spellID = 691 }, { type = "pet", spellName = "Sacrifice", spellID = 7812 }, { type = "cast", spellName = "Soul Link", spellID = 19028, target = "player" }, { type = "cast", spellName = "Shadow Ward", spellID = 28610, target = "player" } } },
        [4] = { enabled = true, name = "3s no sacrifice", steps = { { type = "summon", spellName = "Summon Imp", spellID = 688 }, { type = "cast", spellName = "Ritual of Souls", spellID = 29893, target = "player" }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "player" }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "party1" }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "party2" }, { type = "summon", spellName = "Summon Felhunter", spellID = 691 }, { type = "cast", spellName = "Soul Link", spellID = 19028, target = "player" }, { type = "createItem", spellName = "Create Spellstone", spellID = 28172, itemID = 22646 }, { type = "cast", spellName = "Fel Armor", spellID = 28189, target = "player" }, { type = "equipItem", itemID = 22646, itemName = "Master Spellstone" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "player" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "player" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "party1" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "party1" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "party2" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "party2" }, { type = "cast", spellName = "Shadow Ward", spellID = 28610, target = "player" } } },
        [5] = { enabled = true, name = "5s no sacrifice", steps = { { type = "summon", spellName = "Summon Imp", spellID = 688 }, { type = "cast", spellName = "Ritual of Souls", spellID = 29893, target = "player" }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "player" }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "party1" }, { type = "pet", spellName = "Fire Shield", spellID = 27269, target = "party2" }, { type = "summon", spellName = "Summon Felhunter", spellID = 691 }, { type = "cast", spellName = "Soul Link", spellID = 19028, target = "player" }, { type = "createItem", spellName = "Create Spellstone", spellID = 28172, itemID = 22646 }, { type = "cast", spellName = "Fel Armor", spellID = 28189, target = "player" }, { type = "equipItem", itemID = 22646, itemName = "Master Spellstone" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "player" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "player" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "party1" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "party1" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "party2" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "party2" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "party3" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "party3" }, { type = "cast", spellName = "Detect Invisibility", spellID = 132, target = "party4" }, { type = "cast", spellName = "Unending Breath", spellID = 5697, target = "party4" }, { type = "cast", spellName = "Shadow Ward", spellID = 28610, target = "player" } } },
    },
};

return ACP;
