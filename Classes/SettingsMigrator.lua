-- ArenaChillPrep — Classes/SettingsMigrator
-- The settings migration/normalization pipeline, extracted from Settings
-- (refactor Phase 7): workflow-name migration, step spellID fixes, the
-- placeholder-definition replacement, rank-key normalization and the
-- recursive defaults filler. Settings keeps the dot-path store + the
-- orchestration; the migrations live here.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local tonumber = _G.tonumber;

---@class SettingsMigrator
local SettingsMigrator = {};

---@type SettingsMigrator
ACP.SettingsMigrator = SettingsMigrator;

--- Migrate the placeholder names shipped by the previous five-slot defaults.
--- User-created names are left untouched.
---@param workflows table
function SettingsMigrator:migrateWorkflowNames(workflows)
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
function SettingsMigrator:migrateStepSpellIDs(workflows)
    local definitions = workflows and workflows.definitions;

    if (type(definitions) ~= "table") then
        return;
    end

    for _, definition in pairs(definitions) do
        local steps = type(definition) == "table" and definition.steps;

        if (type(steps) == "table") then
            for _, step in ipairs(steps) do
                if (type(step) == "table" and step.type == ACP.Data.Constants.WORKFLOW_STEP_CAST and step.spellID == 6307) then
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
function SettingsMigrator:migratePlaceholderDefinitions(workflows, defaults)
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

--- Collapse string keys like "19013" into numeric [19013] inside every
--- `items.<category>.ranks` table.
---@param items table|nil
function SettingsMigrator:normalizeRankKeys(items)
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
function SettingsMigrator:ensureDefaults(target, defaults)
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

return ACP;
