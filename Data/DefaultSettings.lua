-- ArenaChillPrep — Data/DefaultSettings
-- Default SavedVariables structure (ArenaChillPrepDB). Deep-merged with the
-- saved data on load, so new keys added in future versions are safe.
---@type ACP
local _, ACP = ...;

ACP.Data = ACP.Data or {};

---@class DefaultSettings
ACP.Data.DefaultSettings = {
    enabled = true, -- Master switch.
    welcomeSeen = false, -- First-run welcome popup was shown (account-wide).
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
        },
        food = {
            enabled = true,
            count = 20, -- Trigger threshold: trade once 20 conjured food are in bags.
            ranks = {
                [22019] = true -- Conjured Croissant.
            }
        },
        water = {
            enabled = true,
            count = 20, -- Trigger threshold: trade once 20 conjured water are in bags.
            ranks = {
                [22018] = true -- Conjured Glacier Water.
            }
        }
    },
    workflows = {
        enabled = true, -- Master workflow switch (General tab).
        slotCount = 5, -- How many slots are visible initially; the UI can add more.
        skipIfBuffedDefault = true, -- Master switch: skip steps whose goal is already met.
        -- Class-specific default workflows ship in Data/WarlockWorkflows.lua /
        -- Data/MageWorkflows.lua and are filled per character by
        -- SettingsMigrator:applyClassDefaults (the player's class is not known
        -- at ADDON_LOADED).
        definitions = {}
    }
};

return ACP;
