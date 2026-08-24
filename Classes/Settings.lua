-- ArenaChillPrep — Classes/Settings
-- SavedVariables wrapper: account settings live in ArenaChillPrepDB while the
-- workflow tree lives in ArenaChillPrepCharDB.workflows. Callers keep using
-- the same dot paths (`workflows.definitions.1.steps`); this module routes
-- those paths to the character-local table.
--
-- REFACTOR (Phase 7, 2026-08-24): the migration/normalization pipeline
-- (name/ID migrations, placeholder replacement, rank-key normalization,
-- defaults filler) moved to Classes/SettingsMigrator.lua — Settings keeps
-- only the dot-path store + the init orchestration.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
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
    -- scope. It is migrated into the current character profile below.
    local saved = ACP.Utils.Tables:deepCopy(ArenaChillPrepDB or {});
    local legacyWorkflows = saved.workflows;
    saved.workflows = nil;

    -- DEEP copy of the defaults as the merge base: if nested tables were
    -- shared (shallowCopy), a later Settings:set would write THROUGH the
    -- shared reference and permanently corrupt ACP.Data.DefaultSettings
    -- (and with it "Reset to defaults"). Keep the live Data fully detached.
    self.Data = ACP.Utils.Tables:deepMerge(defaultCopy, saved);

    -- Migration: any key that exists in defaults but is MISSING from the saved
    -- data is filled from defaults. deepMerge only adds new keys, so a user
    -- who saved under an older structure (e.g. items.soulstone before the
    -- healthstone switch) would have nil for items.healthstone — breaking the
    -- controller. Fix: recursively insert missing defaults.
    ACP.SettingsMigrator:ensureDefaults(self.Data, defaultCopy);

    local characterDB = ArenaChillPrepCharDB or {};
    local savedWorkflows = characterDB.workflows or legacyWorkflows or {};

    -- Replace definitions that are still exactly the old placeholders BEFORE
    -- the merge, so the new m6-macro defaults reach the user without a manual
    -- reset. Runs on the SAVED tree (a merged hybrid would never match).
    ACP.SettingsMigrator:migratePlaceholderDefinitions(savedWorkflows, workflowDefaults);

    -- Workflow merge is per-slot REPLACE, not deepMerge: a saved definition
    -- fully wins over the default one. deepMerge would index-merge the steps
    -- ARRAYS and prepend old steps to the new default steps (a hybrid).
    -- Keys missing from a saved definition are filled by ensureDefaults.
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

    -- Movement pausing is now unconditional. Remove the obsolete setting from
    -- the character data so it does not linger in the SavedVariables schema.
    self.WorkflowData.pauseOnMove = nil;
    ACP.SettingsMigrator:migrateWorkflowNames(self.WorkflowData);
    ACP.SettingsMigrator:migrateStepSpellIDs(self.WorkflowData);

    local slotCount = tonumber(self.WorkflowData.slotCount);
    if (not slotCount) then
        self.WorkflowData.slotCount = ACP.Data.Constants.WORKFLOW_DEFAULT_SLOTS;
    end

    -- Clean up: collapse STRING rank keys into numeric ones. Older versions
    -- wrote "19013" (string) while defaults use [19013] (number) — both ended
    -- up as different keys. A numeric key wins; the string duplicate is
    -- removed so the table is consistent going forward.
    ACP.SettingsMigrator:normalizeRankKeys(self.Data.items);

    -- Persist so the fixed structure is saved from now on.
    self:persist();
end

--- Persist both SavedVariables scopes.
function Settings:persist()
    ArenaChillPrepDB = self.Data;
    ArenaChillPrepCharDB = ArenaChillPrepCharDB or {};
    ArenaChillPrepCharDB.workflows = self.WorkflowData;
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

--- Dot-path getter, e.g. Settings:get("items.healthstone.count"). The
--- `workflows` root is routed to the current character's profile.
--- Returns nil for a missing path.
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

--- Dot-path setter, e.g. Settings:set("gateSafetySeconds", 15). The
--- `workflows` root is routed to the current character's profile.
--- Intermediate tables are created on demand; account paths persist in
--- ArenaChillPrepDB and workflow paths persist in ArenaChillPrepCharDB.
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

--- Reset all settings to the defaults (used by the "Reset to defaults" button
--- in the General subcategory). A DEEP copy is used so the live Data never
--- shares nested tables with ACP.Data.DefaultSettings.
--- Consumers (OptionsUI) refresh via the ACP_SETTINGS_RESET event — no
--- reverse data → UI call (W6).
function Settings:reset()
    local defaults = ACP.Utils.Tables:deepCopy(ACP.Data.DefaultSettings);
    self.WorkflowData = defaults.workflows or {};
    defaults.workflows = nil;
    self.Data = defaults;
    self.WorkflowData.pauseOnMove = nil;
    ACP.SettingsMigrator:migrateWorkflowNames(self.WorkflowData);
    self:persist();

    ACP.Events:fire("ACP_SETTINGS_RESET");
end

-- ---------------------------------------------------------------------------
-- Delegates to the migration pipeline (Classes/SettingsMigrator.lua). These
-- keep the facade's public surface stable (the test suite calls them).
-- ---------------------------------------------------------------------------

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
