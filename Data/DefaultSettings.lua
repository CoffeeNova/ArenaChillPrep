-- ArenaChillPrep — Data/DefaultSettings
-- Default SavedVariables structure (ArenaChillPrepDB). Deep-merged with the
-- saved data on load, so new keys added in future versions are safe.
---@type ACP
local _, ACP = ...;

ACP.Data = ACP.Data or {};

---@class DefaultSettings
ACP.Data.DefaultSettings = {
    enabled = true, -- Master switch.
    noTradeSameClass = true, -- Skip auto-trade to teammates of the player's own class.
    tradeDelay = 1.5, -- Seconds between the item appearing and opening the trade.
    tradeRetries = 0, -- How many times to silently re-offer a failed trade (Cancel pressed, etc.) before giving up.
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
        slotCount = 5, -- How many slots are visible initially; the UI can add more.
        skipIfBuffedDefault = true, -- Master switch: skip steps whose goal is already met.
        definitions = {
            -- Slots 1-5 ship the five battle-tested Warlock prep workflows
            -- (2s/3s/5s, with/without Sacrifice); every step stores the exact
            -- rank the client conjures on TBC 2.5.5.
            [1] = {
                enabled = true,
                name = "2s with sacrifice",
                steps = {
                    {
                        type = "summon",
                        spellName = "Summon Imp",
                        spellID = 688
                    }, {
                        type = "createItem",
                        spellName = "Create Healthstone",
                        itemID = 22105,
                        spellID = 27230
                    }, {
                        type = "createItem",
                        spellName = "Create Healthstone",
                        itemID = 19012,
                        spellID = 11730
                    }, {
                        type = "pet",
                        target = "player",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "pet",
                        target = "party1",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "createItem",
                        spellName = "Create Spellstone",
                        itemID = 22646,
                        spellID = 28172
                    }, {
                        type = "summon",
                        spellName = "Summon Voidwalker",
                        spellID = 697
                    }, {
                        type = "createItem",
                        spellName = "Create Healthstone",
                        itemID = 22105,
                        spellID = 27230
                    }, {
                        type = "createItem",
                        spellName = "Create Healthstone",
                        itemID = 19012,
                        spellID = 11730
                    }, {
                        type = "equipItem",
                        itemID = 22646,
                        itemName = "Master Spellstone"
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Fel Armor",
                        spellID = 28189
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "party1",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "party1",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "summon",
                        spellName = "Summon Felhunter",
                        spellID = 691
                    }, {
                        type = "pet",
                        spellName = "Sacrifice",
                        spellID = 7812
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Soul Link",
                        spellID = 19028
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Shadow Ward",
                        spellID = 28610
                    }
                }
            },
            [2] = {
                enabled = true,
                name = "2s no sacrifice",
                steps = {
                    {
                        type = "summon",
                        spellName = "Summon Imp",
                        spellID = 688
                    }, {
                        type = "createItem",
                        spellName = "Create Healthstone",
                        itemID = 22105,
                        spellID = 27230
                    }, {
                        type = "createItem",
                        spellName = "Create Healthstone",
                        itemID = 19012,
                        spellID = 11730
                    }, {
                        type = "pet",
                        target = "player",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "pet",
                        target = "party1",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "summon",
                        spellName = "Summon Felhunter",
                        spellID = 691
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Soul Link",
                        spellID = 19028
                    }, {
                        type = "createItem",
                        spellName = "Create Spellstone",
                        itemID = 22646,
                        spellID = 28172
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Fel Armor",
                        spellID = 28189
                    }, {
                        type = "equipItem",
                        itemID = 22646,
                        itemName = "Master Spellstone"
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "party1",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "party1",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Shadow Ward",
                        spellID = 28610
                    }
                }
            },
            [3] = {
                enabled = true,
                name = "3s with sacrifice",
                steps = {
                    {
                        type = "summon",
                        spellName = "Summon Imp",
                        spellID = 688
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Ritual of Souls",
                        spellID = 29893
                    }, {
                        type = "pet",
                        target = "player",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "pet",
                        target = "party1",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "pet",
                        target = "party2",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "summon",
                        spellName = "Summon Voidwalker",
                        spellID = 697
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Fel Armor",
                        spellID = 28189
                    }, {
                        type = "createItem",
                        spellName = "Create Spellstone",
                        itemID = 22646,
                        spellID = 28172
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "equipItem",
                        itemID = 22646,
                        itemName = "Master Spellstone"
                    }, {
                        type = "cast",
                        target = "party1",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "party1",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "party2",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "party2",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "summon",
                        spellName = "Summon Felhunter",
                        spellID = 691
                    }, {
                        type = "pet",
                        spellName = "Sacrifice",
                        spellID = 7812
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Soul Link",
                        spellID = 19028
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Shadow Ward",
                        spellID = 28610
                    }
                }
            },
            [4] = {
                enabled = true,
                name = "3s no sacrifice",
                steps = {
                    {
                        type = "summon",
                        spellName = "Summon Imp",
                        spellID = 688
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Ritual of Souls",
                        spellID = 29893
                    }, {
                        type = "pet",
                        target = "player",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "pet",
                        target = "party1",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "pet",
                        target = "party2",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "summon",
                        spellName = "Summon Felhunter",
                        spellID = 691
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Soul Link",
                        spellID = 19028
                    }, {
                        type = "createItem",
                        spellName = "Create Spellstone",
                        itemID = 22646,
                        spellID = 28172
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Fel Armor",
                        spellID = 28189
                    }, {
                        type = "equipItem",
                        itemID = 22646,
                        itemName = "Master Spellstone"
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "party1",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "party1",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "party2",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "party2",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Shadow Ward",
                        spellID = 28610
                    }
                }
            },
            [5] = {
                enabled = true,
                name = "5s no sacrifice",
                steps = {
                    {
                        type = "summon",
                        spellName = "Summon Imp",
                        spellID = 688
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Ritual of Souls",
                        spellID = 29893
                    }, {
                        type = "pet",
                        target = "player",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "pet",
                        target = "party1",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "pet",
                        target = "party2",
                        spellName = "Fire Shield",
                        spellID = 27269
                    }, {
                        type = "summon",
                        spellName = "Summon Felhunter",
                        spellID = 691
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Soul Link",
                        spellID = 19028
                    }, {
                        type = "createItem",
                        spellName = "Create Spellstone",
                        itemID = 22646,
                        spellID = 28172
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Fel Armor",
                        spellID = 28189
                    }, {
                        type = "equipItem",
                        itemID = 22646,
                        itemName = "Master Spellstone"
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "party1",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "party1",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "party2",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "party2",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "party3",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "party3",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "party4",
                        spellName = "Detect Invisibility",
                        spellID = 132
                    }, {
                        type = "cast",
                        target = "party4",
                        spellName = "Unending Breath",
                        spellID = 5697
                    }, {
                        type = "cast",
                        target = "player",
                        spellName = "Shadow Ward",
                        spellID = 28610
                    }
                }
            }
        }
    }
};

return ACP;
