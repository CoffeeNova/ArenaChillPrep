-- ArenaChillPrep — Classes/Settings
-- SavedVariables wrapper (ArenaChillPrepDB): dot-path get/set.
-- On load: deep-merge defaults (Data/DefaultSettings.lua) with the saved
-- data, so new keys added in future versions are safe.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;

---@class Settings
local Settings = {
    _initialized = false,

    ---@type table
    Data = nil,
};

---@type Settings
ACP.Settings = Settings;

function Settings:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    local defaults = ACP.Data.DefaultSettings;
    self.Data = ACP.Utils.Tables:deepMerge(
        ACP.Utils.Tables:shallowCopy(defaults),
        ArenaChillPrepDB or {}
    );

    -- Migration: any key that exists in defaults but is MISSING from the saved
    -- data is filled from defaults. deepMerge only adds new keys, so a user
    -- who saved under an older structure (e.g. items.soulstone before the
    -- healthstone switch) would have nil for items.healthstone — breaking the
    -- controller. Fix: recursively insert missing defaults.
    self:ensureDefaults(self.Data, defaults);

    -- Clean up: collapse STRING rank keys into numeric ones. Older versions
    -- wrote "19013" (string) while defaults use [19013] (number) — both ended
    -- up as different keys. A numeric key wins; the string duplicate is
    -- removed so the table is consistent going forward.
    self:normalizeRankKeys(self.Data.items);

    -- Persist so the fixed structure is saved from now on.
    ArenaChillPrepDB = self.Data;
end

--- Collapse string keys like "19013" into numeric [19013] inside every
--- `items.<category>.ranks` table.
---@param items table|nil
function Settings:normalizeRankKeys(items)
    if (type(items) ~= "table") then
        return;
    end

    for _, categorySettings in pairs(items) do
        if (type(categorySettings) == "table" and type(categorySettings.ranks) == "table") then
            local ranks = categorySettings.ranks;

            for key, value in pairs(ranks) do
                if (type(key) == "string") then
                    local asNumber = tonumber(key);

                    if (asNumber) then
                        -- Numeric key wins if present; otherwise copy the string value.
                        if (ranks[asNumber] == nil) then
                            ranks[asNumber] = value;
                        end

                        ranks[key] = nil;
                    end
                end
            end
        end
    end
end

--- Recursively copy default values for keys missing from `target`.
---@param target table
---@param defaults table
function Settings:ensureDefaults(target, defaults)
    for key, defaultValue in pairs(defaults) do
        if (type(defaultValue) == "table") then
            if (type(target[key]) ~= "table") then
                target[key] = {};
            end

            self:ensureDefaults(target[key], defaultValue);
        elseif (target[key] == nil) then
            target[key] = defaultValue;
        end
    end
end

--- Normalize a dot-path segment: integer-looking segments become numbers so
--- they match numeric table keys (DefaultSettings uses [19013] = true — number;
--- paths built from strings would otherwise hit "19013" — a DIFFERENT key).
---@param segment string
---@return string|number
local function normalizeSegment(segment)
    local asNumber = tonumber(segment);

    if (asNumber and asNumber == math.floor(asNumber)) then
        return asNumber;
    end

    return segment;
end

--- Dot-path getter, e.g. Settings:get("items.healthstone.count").
--- Returns nil for a missing path.
---@param path string
---@return any
function Settings:get(path)
    local current = self.Data;

    for segment in (path or ""):gmatch("[^.]+") do
        current = current and current[normalizeSegment(segment)];
    end

    return current;
end

--- Dot-path setter, e.g. Settings:set("gateSafetySeconds", 15).
--- Intermediate tables are created on demand; the value is written into
--- ArenaChillPrepDB (which SavedVariables persist).
---@param path string
---@param value any
function Settings:set(path, value)
    local segments = {};

    for segment in (path or ""):gmatch("[^.]+") do
        tinsert(segments, normalizeSegment(segment));
    end

    local current = self.Data;

    for i = 1, #segments - 1 do
        local segment = segments[i];
        current[segment] = current[segment] or {};
        current = current[segment];
    end

    current[segments[#segments]] = value;
end

return ACP;
