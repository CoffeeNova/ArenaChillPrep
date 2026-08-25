-- ArenaChillPrep — Classes/SettingsMigrator
-- Settings migration/normalization pipeline: workflow names, step spellID
-- fixes, placeholder replacement, rank-key normalization, defaults filler.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local tonumber = _G.tonumber;

---@class SettingsMigrator
local SettingsMigrator = {};

---@type SettingsMigrator
ACP.SettingsMigrator = SettingsMigrator;

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

--- Rewrites saved step spellIDs that older catalog data got wrong:
--- 6307 (Imp Blood Pact) → 19028 (Soul Link); Demon Armor rank 1 → TBC max
--- 27260; removed Create Spellstone ranks 1-3 → 28172/22646.
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
                if (type(step) == "table") then
                    if (step.type == ACP.Data.Constants.WORKFLOW_STEP_CAST) then
                        if (step.spellID == 6307) then
                            step.spellID = 19028;
                        elseif (step.spellID == 706) then
                            step.spellID = 27260;
                        end
                    elseif (step.type == ACP.Data.Constants.WORKFLOW_STEP_CREATE_ITEM
                        and (step.spellID == 2362 or step.spellID == 28171 or step.spellID == 28173)) then
                        step.spellID = 28172;
                        step.itemID = 22646;
                    end
                end
            end
        end
    end
end

-- Historical snapshot of the previous placeholder defaults; a saved
-- definition matching these exactly is replaced by the current default.
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

--- Collapses string keys like "19013" into numeric [19013] in every
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

--- Recursively copy default values for keys missing from `target`. Arrays
--- (sequences) are copied only when the whole key is missing — never
--- index-merged.
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
