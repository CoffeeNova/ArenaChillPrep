-- ArenaChillPrep — Classes/Settings
-- SavedVariables wrapper: account settings live in ArenaChillPrepDB while the
-- workflow tree lives in ArenaChillPrepCharDB.workflows. Callers keep using
-- the same dot paths (`workflows.definitions.1.steps`); this module routes
-- those paths to the character-local table.
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
    self:ensureDefaults(self.Data, defaultCopy);

    local characterDB = ArenaChillPrepCharDB or {};
    local savedWorkflows = characterDB.workflows or legacyWorkflows or {};

    -- Replace definitions that are still exactly the old placeholders BEFORE
    -- the merge, so the new m6-macro defaults reach the user without a manual
    -- reset. Runs on the SAVED tree (a merged hybrid would never match).
    self:migratePlaceholderDefinitions(savedWorkflows, workflowDefaults);

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

    self:ensureDefaults(self.WorkflowData, workflowDefaults);

    -- Movement pausing is now unconditional. Remove the obsolete setting from
    -- the character data so it does not linger in the SavedVariables schema.
    self.WorkflowData.pauseOnMove = nil;
    self:migrateWorkflowNames(self.WorkflowData);
    self:migrateStepSpellIDs(self.WorkflowData);

    local slotCount = tonumber(self.WorkflowData.slotCount);
    if (not slotCount) then
        self.WorkflowData.slotCount = ACP.Data.Constants.WORKFLOW_DEFAULT_SLOTS;
    end

    -- Clean up: collapse STRING rank keys into numeric ones. Older versions
    -- wrote "19013" (string) while defaults use [19013] (number) — both ended
    -- up as different keys. A numeric key wins; the string duplicate is
    -- removed so the table is consistent going forward.
    self:normalizeRankKeys(self.Data.items);

    -- Persist so the fixed structure is saved from now on.
    self:persist();
end

--- Migrate the placeholder names shipped by the previous five-slot defaults.
--- User-created names are left untouched.
---@param workflows table
function Settings:migrateWorkflowNames(workflows)
    local definitions = workflows and workflows.definitions;

    if (type(definitions) ~= "table") then
        return;
    end

    local replacements = {
        ["Full prep"] = "2s full prep",
        ["Buffs only"] = "2s no sacrifice",
        ["Stones only"] = "",
        ["Pet only"] = "",
        ["Custom"] = ""
    };

    for _, definition in pairs(definitions) do
        if (type(definition) == "table" and replacements[definition.name] ~= nil) then
            definition.name = replacements[definition.name];
        end
    end
end

--- Rewrite step spellIDs that older catalog data got wrong. 6307 is the Imp's
--- Blood Pact passive, but the old catalog shipped it as "Soul Link" — the
--- user's saved steps (and the UI rows) therefore read "Blood Pact" and the
--- skip check matched the imp's always-on aura, so Soul Link was never cast
--- (verified 2026-08-22; correct Soul Link talent spell = 19028).
---@param workflows table
function Settings:migrateStepSpellIDs(workflows)
    local definitions = workflows and workflows.definitions;

    if (type(definitions) ~= "table") then
        return;
    end

    for _, definition in pairs(definitions) do
        local steps = type(definition) == "table" and definition.steps;

        if (type(steps) == "table") then
            for _, step in ipairs(steps) do
                if (type(step) == "table" and step.type == "cast" and step.spellID == 6307) then
                    step.spellID = 19028;
                end
            end
        end
    end
end

--- The placeholder steps shipped by the previous defaults (before the
--- m6-macro defaults). A saved definition is replaced by the new default when
--- its name AND its steps still match the placeholder exactly — a user-edited
--- workflow never matches and is left untouched.
local OLD_PLACEHOLDER_DEFINITIONS = {
    [1] = {
        name = "2s full prep",
        steps = {
            { type = "cast", spellID = 28176, target = "player", skipIfBuffed = true },
            { type = "summon", spellID = 712 },
            { type = "createItem", spellID = 6201, itemID = 22105 },
        },
    },
    [2] = {
        name = "Prep with a Priest",
        steps = {},
    },
};

--- Deep equality for the placeholder comparison (arrays of flat step tables).
---@param a any
---@param b any
---@return boolean
local function deepEqual(a, b)
    if (a == b) then
        return true;
    end

    if (type(a) ~= "table" or type(b) ~= "table") then
        return false;
    end

    for key, value in pairs(a) do
        if (not deepEqual(value, b[key])) then
            return false;
        end
    end

    for key in pairs(b) do
        if (a[key] == nil) then
            return false;
        end
    end

    return true;
end

--- Replace saved definitions that are still exactly the old placeholders with
--- the NEW defaults (the m6-macro pre-defined steps). Runs after the defaults
--- merge so a fresh profile (no saved definitions) is untouched — its merged
--- definitions are already the new ones, and their steps no longer match.
---@param workflows table
---@param defaults table
function Settings:migratePlaceholderDefinitions(workflows, defaults)
    local definitions = workflows and workflows.definitions;
    local newDefinitions = defaults and defaults.definitions;

    if (type(definitions) ~= "table" or type(newDefinitions) ~= "table") then
        return;
    end

    for slot, placeholder in pairs(OLD_PLACEHOLDER_DEFINITIONS) do
        local definition = definitions[slot];

        if (type(definition) == "table" and definition.name == placeholder.name
            and deepEqual(definition.steps, placeholder.steps)) then
            definitions[slot] = newDefinitions[slot];
        end
    end
end

--- Persist both SavedVariables scopes.
function Settings:persist()
    ArenaChillPrepDB = self.Data;
    ArenaChillPrepCharDB = ArenaChillPrepCharDB or {};
    ArenaChillPrepCharDB.workflows = self.WorkflowData;
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

--- Whether a table is an ARRAY (positive consecutive integer keys only) —
--- e.g. a workflow's `steps` list. Arrays are owned by the saved definition
--- wholesale: missing indices are NEVER filled from defaults (that would
--- prepend default steps to saved ones — a hybrid).
---@param value any
---@return boolean
local function isSequence(value)
    if (type(value) ~= "table") then
        return false;
    end

    local count = 0;

    for key in pairs(value) do
        if (type(key) ~= "number" or key < 1 or key % 1 ~= 0) then
            return false;
        end

        count = count + 1;
    end

    return count == 0 or value[count] ~= nil;
end

--- Recursively copy default values for keys missing from `target`.
--- Arrays (sequences) are only copied when the whole key is missing — their
--- contents are never index-merged.
---@param target table
---@param defaults table
function Settings:ensureDefaults(target, defaults)
    for key, defaultValue in pairs(defaults) do
        if (type(defaultValue) == "table") then
            if (isSequence(defaultValue)) then
                if (target[key] == nil) then
                    target[key] = ACP.Utils.Tables:deepCopy(defaultValue);
                end
            elseif (type(target[key]) ~= "table") then
                target[key] = {};
                self:ensureDefaults(target[key], defaultValue);
            else
                self:ensureDefaults(target[key], defaultValue);
            end
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
--- Re-syncs the options panel if it is loaded.
function Settings:reset()
    local defaults = ACP.Utils.Tables:deepCopy(ACP.Data.DefaultSettings);
    self.WorkflowData = defaults.workflows or {};
    defaults.workflows = nil;
    self.Data = defaults;
    self.WorkflowData.pauseOnMove = nil;
    self:migrateWorkflowNames(self.WorkflowData);
    self:persist();

    if (ACP.OptionsUI and ACP.OptionsUI.refresh) then
        ACP.OptionsUI:refresh();
    end
end

return ACP;
