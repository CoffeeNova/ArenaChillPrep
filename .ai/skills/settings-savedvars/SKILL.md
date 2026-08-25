---
name: settings-savedvars
description: Patterns and pitfalls for this addon's settings system (ArenaChillPrepDB): dot-path get/set, numeric vs string keys, defaults migration, and the rank-keys cleanup. Use whenever touching Settings.lua, DefaultSettings.lua, or reading settings values (especially `items.<category>.ranks.<itemID>`).
---

# Settings & SavedVariables

## Structure

- Global: `ArenaChillPrepDB` (SavedVariables in the TOC).
- Access ONLY via `ACP.Settings:get(path)` / `:set(path, value)` — never touch `ArenaChillPrepDB` directly except in `setSetting()` (which also persists `ArenaChillPrepDB = ACP.Settings.Data`) and in `Settings:_init`.
- Defaults live in `Data/DefaultSettings.lua`; `Settings:_init` does:
  1. `deepMerge(deepCopy(defaults), ArenaChillPrepDB or {})` — saved wins; the merge base is a **deep** copy so the live `Data` never shares nested tables with `ACP.Data.DefaultSettings` (a shallow copy let `Settings:set` write THROUGH the shared reference and permanently corrupt the defaults — and with it "Reset to defaults");
  2. `ensureDefaults(Data, defaults)` — fills keys MISSING from saved (migration);
  3. `normalizeRankKeys(items)` — collapses string rank keys into numeric;
  4. `ArenaChillPrepDB = self.Data` — persist the fixed structure.
- `Settings:reset()` — `self.Data = Tables:deepCopy(ACP.Data.DefaultSettings)` (pristine, thanks to the deep merge base), persists the DB and calls `ACP.OptionsUI:refresh()` when present. Used by the "Reset to defaults" button in the General subcategory.

## The number-vs-string key trap (IMPORTANT)

In Lua, `[19013]` (number) and `["19013"]` (string) are **different table keys**. `DefaultSettings` uses numeric keys; a naive dot-path get/set builds string segments → reads/writes the STRING key, while defaults sit under the NUMBER key. Symptoms seen live:
- rank checkboxes never reflected defaults;
- toggling "didn't save" (wrote the string key; the numeric default stayed true);
- `/dump ArenaChillPrepDB.items.healthstone.ranks` showed BOTH `[19013]=true` and `["19013"]=false`.

**Fix (already in `Settings.lua`)**: `normalizeSegment(segment)` converts integer-looking path segments to numbers in BOTH `get` and `set`:
```lua
local function normalizeSegment(segment)
    local n = tonumber(segment);
    if (n and n == math.floor(n)) then return n; end
    return segment;
end
```
And `normalizeRankKeys(items)` collapses old string keys on load (numeric wins, string removed).

**Always use numeric keys in DefaultSettings** and expect `Settings:get("items.healthstone.ranks.22105")` to hit the numeric key.

## Category key mapping (plural vs singular)

Catalog/classItems use the PLURAL key (`healthstones`); settings use the SINGULAR (`items.healthstone`). Map through **`ACP.Data.Items:settingsKeyFor(category)`** — an EXPLICIT map (`settingsKeyByCategory = { healthstones = "healthstone", food = "food", water = "water" }`) with the old trailing-"s" strip as the fallback for unknown keys:
```lua
local settingsKey = ACP.Data.Items:settingsKeyFor(category);
local setting = ACP.Settings:get("items." .. settingsKey);
```
Do NOT use `category:sub(1, -2)` directly — it breaks for non-plural keys (`"food"` → `"foo"`, `"water"` → `"wate"`), which silently never matched the autotrade settings (fixed 2026-08-25 in OptionsUI / DeliveryController / TradePlanner). Getting the mapping wrong produced `itemsReady: category=healthstones setting missing or disabled` — a classic silent bug.

## Class-scoped workflow defaults (v0.2)

`DefaultSettings.workflows.definitions` is EMPTY; the 5 default workflows live per class in `Data/WarlockWorkflows.defaultDefinitions` / `Data/MageWorkflows.defaultDefinitions` and are filled (deep-copied) by `SettingsMigrator:applyClassDefaults(workflows, englishClass)` when definitions are empty (Settings:_init + PLAYER_LOGIN re-run + Settings:reset). Fresh Mage characters get the Mage defaults; per-character SavedVariables never mix classes.

## Migration (`ensureDefaults`)

Recursively copies DEFAULT values for keys MISSING from saved data (does NOT overwrite existing values — user choices win):
```lua
function Settings:ensureDefaults(target, defaults)
    for key, defaultValue in pairs(defaults) do
        if (type(defaultValue) == "table") then
            if (type(target[key]) ~= "table") then target[key] = {}; end
            self:ensureDefaults(target[key], defaultValue);
        elseif (target[key] == nil) then
            target[key] = defaultValue;
        end
    end
end
```
This is how new settings (e.g. a new rank default) reach users who already have a SavedVariables file.

## Rank logic (by rank, not by itemID)

`items.healthstone.ranks` maps itemID → boolean. Paired itemIDs (19012/19013) are ONE rank (Major). All rank logic groups by the catalog `rank` field:
- `DeliveryController:categoryReady` — sums counts of all selected IDs of a rank; ALL selected ranks must be ready;
- `TradeManager:queueConfiguredItems` — queues `count` of EVERY selected rank;
- `OptionsUI:rankIsEnabled(settingsKey, rank)` — enabled if ANY itemID of that rank is true.

## Current defaults (v0.2)

```lua
items.healthstone = {
    enabled = true,
    count = 1,                       -- per selected rank per trade (no UI slider)
    ranks = { [19012]=true, [19013]=true, [22105]=true },  -- Major + Master
}
items.food = {                       -- Mage: Conjured Croissant 22019
    enabled = true,
    count = 20,                      -- trigger threshold; slider 10-60 step 10 (Data/Items.countRanges)
    ranks = { [22019]=true },
}
items.water = {                      -- Mage: Conjured Glacier Water 22018
    enabled = true,
    count = 20,
    ranks = { [22018]=true },
}
```
`count` is the TRIGGER threshold (await N before opening the trade), not a per-trade placement number. `DeliveryController:itemsReady` requires ALL enabled categories to hit their targets (a Mage needs 20 food AND 20 water); Warlock (one category) is unchanged. The count sliders appear only for categories with a `countRanges` entry.

## Setting values from UI

`setSetting(path, value)` in OptionsUI writes through Settings AND persists the DB. Sliders use `getter`/`setter` closures; checkboxes use `getter() == true`. All control values re-sync from Settings in `OptionsUI:refresh()` (called on panel open).
