-- ArenaChillPrep — Classes/Settings
-- SavedVariables wrapper: account settings in ArenaChillPrepDB, the workflow
-- tree in ArenaChillPrepCharDB.workflows (routed by the same dot paths).

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local select = _G.select;
local tinsert = _G.tinsert;

---@class Settings
local Settings = {
    _initialized = false,

    ---@type table
    Data = nil,

    ---@type table
    WorkflowData = nil
};

---@type Settings
ACP.Settings = Settings;

function Settings:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    local defaults = ACP.Data.DefaultSettings;
    local defaultCopy = ACP.Utils.Tables:deepCopy(defaults);
    local workflowDefaults = defaultCopy.workflows or {};
    defaultCopy.workflows = nil;

    -- Remove the old account-wide workflow branch before merging the account
    -- scope; it is migrated into the character profile below.
    local saved = ACP.Utils.Tables:deepCopy(ArenaChillPrepDB or {});
    local legacyWorkflows = saved.workflows;
    saved.workflows = nil;

    -- Deep copy as the merge base — a shallow copy would let Settings:set
    -- write through into ACP.Data.DefaultSettings and corrupt "Reset".
    self.Data = ACP.Utils.Tables:deepMerge(defaultCopy, saved);
    ACP.SettingsMigrator:ensureDefaults(self.Data, defaultCopy);

    local characterDB = ArenaChillPrepCharDB or {};
    local savedWorkflows = characterDB.workflows or legacyWorkflows or {};

    -- Replace untouched placeholders BEFORE the merge (on the saved tree).
    -- The replacement is the Warlock class defaults (Warlock-era snapshot).
    ACP.SettingsMigrator:migratePlaceholderDefinitions(savedWorkflows);

    -- Per-slot REPLACE merge: a saved definition wins wholesale (deepMerge
    -- would index-merge the steps arrays into hybrids).
    self.WorkflowData = ACP.Utils.Tables:deepCopy(workflowDefaults);

    for slot, savedDefinition in pairs(savedWorkflows.definitions or {}) do
        if (type(savedDefinition) == "table") then
            self.WorkflowData.definitions[slot] = ACP.Utils.Tables:deepCopy(savedDefinition);
        end
    end

    for key, value in pairs(savedWorkflows) do
        if (key ~= "definitions") then
            self.WorkflowData[key] = (type(value) == "table") and ACP.Utils.Tables:deepCopy(value) or value;
        end
    end

    ACP.SettingsMigrator:ensureDefaults(self.WorkflowData, workflowDefaults);

    -- Movement pausing is unconditional; drop the obsolete setting.
    self.WorkflowData.pauseOnMove = nil;
    ACP.SettingsMigrator:migrateWorkflowNames(self.WorkflowData);
    ACP.SettingsMigrator:migrateStepSpellIDs(self.WorkflowData);

    local slotCount = tonumber(self.WorkflowData.slotCount);
    if (not slotCount) then
        self.WorkflowData.slotCount = ACP.Data.Constants.WORKFLOW_DEFAULT_SLOTS;
    end

    ACP.SettingsMigrator:normalizeRankKeys(self.Data.items);

    -- The class is unknown at ADDON_LOADED; PLAYER_LOGIN re-runs this once
    -- UnitClass is available (fresh characters have empty definitions).
    ACP.SettingsMigrator:applyClassDefaults(self.WorkflowData, select(2, UnitClass("player")));

    if (ACP.Events) then
        ACP.Events:register("Settings.PLAYER_LOGIN", "PLAYER_LOGIN", function()
            ACP.SettingsMigrator:applyClassDefaults(self.WorkflowData, select(2, UnitClass("player")));
        end);
    end

    self:persist();
end

function Settings:persist()
    ArenaChillPrepDB = self.Data;
    ArenaChillPrepCharDB = ArenaChillPrepCharDB or {};
    ArenaChillPrepCharDB.workflows = self.WorkflowData;
end

--- Integer-looking segments become numbers so paths hit numeric table keys
--- (defaults use [19013], not "19013").
---@param segment string
---@return string|number
local function normalizeSegment(segment)
    local asNumber = tonumber(segment);

    if (asNumber and asNumber == math.floor(asNumber)) then
        return asNumber;
    end

    return segment;
end

---@param path string
---@return any
function Settings:get(path)
    local segments = {};

    for segment in (path or ""):gmatch("[^.]+") do
        tinsert(segments, normalizeSegment(segment));
    end

    local current = self.Data;
    local first = 1;

    if (segments[1] == "workflows") then
        current = self.WorkflowData;
        first = 2;
    end

    for i = first, #segments do
        current = current and current[segments[i]];
    end

    return current;
end

---@param path string
---@param value any
function Settings:set(path, value)
    local segments = {};

    for segment in (path or ""):gmatch("[^.]+") do
        tinsert(segments, normalizeSegment(segment));
    end

    local current = self.Data;
    local first = 1;

    if (segments[1] == "workflows") then
        current = self.WorkflowData;
        first = 2;
    end

    for i = first, #segments - 1 do
        local segment = segments[i];
        current[segment] = current[segment] or {};
        current = current[segment];
    end

    current[segments[#segments]] = value;
    self:persist();
end

--- Restore a deep copy of the defaults; consumers refresh via
--- ACP_SETTINGS_RESET.
function Settings:reset()
    local defaults = ACP.Utils.Tables:deepCopy(ACP.Data.DefaultSettings);
    self.WorkflowData = defaults.workflows or {};
    defaults.workflows = nil;
    self.Data = defaults;
    self.WorkflowData.pauseOnMove = nil;
    ACP.SettingsMigrator:migrateWorkflowNames(self.WorkflowData);
    ACP.SettingsMigrator:applyClassDefaults(self.WorkflowData, select(2, UnitClass("player")));
    self:persist();

    ACP.Events:fire("ACP_SETTINGS_RESET");
end

-- Delegates to the migration pipeline (Classes/SettingsMigrator.lua).

---@param target table
---@param defaults table
function Settings:ensureDefaults(target, defaults)
    return ACP.SettingsMigrator:ensureDefaults(target, defaults);
end

---@param items table|nil
function Settings:normalizeRankKeys(items)
    return ACP.SettingsMigrator:normalizeRankKeys(items);
end

return ACP;
