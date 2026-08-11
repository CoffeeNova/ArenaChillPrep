-- ArenaChillPrep — Data/DefaultSettings
-- Default SavedVariables structure (ArenaChillPrepDB). Deep-merged with the
-- saved data on load, so new keys added in future versions are safe.

---@type ACP
local _, ACP = ...;

ACP.Data = ACP.Data or {};

---@class DefaultSettings
ACP.Data.DefaultSettings = {
    enabled = true,               -- Master switch.
    tradeDelay = 1.5,             -- Seconds between the item appearing and opening the trade.
    gateSafetySeconds = 15,       -- Stop all trading N seconds before the gates open.
    brackets = {                  -- Which arena brackets auto-trade is active in.
        ["2v2"] = true,           -- Default: 2v2 only.
        ["3v3"] = false,
        ["5v5"] = false,
    },
    items = {
        healthstone = {
            enabled = true,       -- Pass healthstones.
            count = 1,            -- How many per trade.
            ranks = {             -- Which ranks to consider (by itemID).
                [19012] = true,   -- Major Healthstone (variant 1).
                [19013] = true,   -- Major Healthstone (variant 2).
                [22105] = true,   -- Master Healthstone (TBC max rank).
            },
        },
    },
};

return ACP;
