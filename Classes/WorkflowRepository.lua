-- ArenaChillPrep — Classes/WorkflowRepository
-- The workflow data layer: dot-path vocabulary for the per-character workflow
-- settings tree (ArenaChillPrepCharDB.workflows, routed through ACP.Settings)
-- PLUS the CRUD operations and the step factory (refactor Phase 6). Single
-- source for the "workflows.definitions.<slot>..." paths that WorkflowUI and
-- WorkflowEngine used to re-type at 12+ sites, and for the step-building
-- business rules the UI used to re-derive (step type / target / skip default
-- inference — the UI now only renders).

---@type ACP
local _, ACP = ...;

local tostring = _G.tostring;
local tonumber = _G.tonumber;
local pairs = _G.pairs;
local ipairs = _G.ipairs;
local pcall = _G.pcall;
local select = _G.select;
local tremove = _G.table.remove;

---@class WorkflowRepository
local WorkflowRepository = {};

---@type WorkflowRepository
ACP.WorkflowRepository = WorkflowRepository;

--- Settings path of a workflow slot definition.
---@param slot number
---@return string
function WorkflowRepository:definitionPath(slot)
    return "workflows.definitions." .. tostring(slot);
end

--- Settings path of a workflow slot's steps array.
---@param slot number
---@return string
function WorkflowRepository:stepsPath(slot)
    return WorkflowRepository:definitionPath(slot) .. ".steps";
end

--- Settings path of a single step.
---@param slot number
---@param index number
---@return string
function WorkflowRepository:stepPath(slot, index)
    return WorkflowRepository:stepsPath(slot) .. "." .. tostring(index);
end

--- Number of workflow slots the character has (clamped to the fixed binding
--- capacity; the UI only renders slots up to this count).
---@return number
function WorkflowRepository:workflowCount()
    local C = ACP.Data.Constants;
    local count = tonumber(ACP.Settings:get("workflows.slotCount")) or C.WORKFLOW_DEFAULT_SLOTS;

    if (count < C.WORKFLOW_DEFAULT_SLOTS) then
        count = C.WORKFLOW_DEFAULT_SLOTS;
    end

    if (count > C.WORKFLOW_MAX_SLOTS) then
        count = C.WORKFLOW_MAX_SLOTS;
    end

    return count;
end

--- The steps array of a workflow slot (empty table when missing).
---@param slot number
---@return table
function WorkflowRepository:getSteps(slot)
    local steps = ACP.Settings:get(self:stepsPath(slot));

    return (type(steps) == "table") and steps or {};
end

--- Add an empty workflow slot (up to WORKFLOW_MAX_SLOTS). Returns the new
--- slot number, or nil at the limit.
---@return number|nil
function WorkflowRepository:addWorkflow()
    local C = ACP.Data.Constants;
    local count = self:workflowCount();

    if (count >= C.WORKFLOW_MAX_SLOTS) then
        return nil;
    end

    local slot = count + 1;
    ACP.Settings:set("workflows.slotCount", slot);
    ACP.Settings:set(self:definitionPath(slot), {
        enabled = false,
        name = "",
        steps = {}
    });

    return slot;
end

--- Delete a workflow slot (data only — key bindings are migrated by
--- WorkflowKeybindController:shiftBindingsAfterDelete). At the
--- WORKFLOW_DEFAULT_SLOTS floor the definition is reset to empty instead of
--- removed; above the floor later slots shift down.
---@param slot number
---@return number newCount  the slot count after the operation
function WorkflowRepository:deleteWorkflow(slot)
    local C = ACP.Data.Constants;
    local count = self:workflowCount();

    if (count <= C.WORKFLOW_DEFAULT_SLOTS) then
        ACP.Settings:set(self:definitionPath(slot), {
            enabled = false,
            name = "",
            steps = {}
        });

        return count;
    end

    for i = slot, count - 1 do
        ACP.Settings:set(self:definitionPath(i),
            ACP.Settings:get(self:definitionPath(i + 1)));
    end

    ACP.Settings:set(self:definitionPath(count), nil);
    ACP.Settings:set("workflows.slotCount", count - 1);

    return count - 1;
end

--- Catalog entry for a spell, preferring the runtime spellbook, then the
--- static catalog (by spellID, then by localized name — a saved step with a
--- non-catalog rank ID would otherwise lose its metadata).
---@param spellID number
---@return table|nil entry
---@return string|nil category
function WorkflowRepository:findSpell(spellID)
    if (ACP.WorkflowSpellbook and ACP.WorkflowSpellbook.getEntry) then
        local entry = ACP.WorkflowSpellbook:getEntry(spellID);

        if (entry) then
            return entry, entry.category;
        end
    end

    local spells = ACP.Data.Workflows and ACP.Data.Workflows.spells;

    if (not spells) then
        return nil;
    end

    -- Match by exact spellID first (covers the catalog's known rank IDs).
    for category, list in pairs(spells) do
        for _, entry in ipairs(list) do
            if (entry.spellID == spellID) then
                entry.category = category;
                return entry, category;
            end
        end
    end

    -- Fallback for a learned rank ID the static catalog does not list (the
    -- scan is class-gated to a limited fallback, so a saved step whose
    -- spellID is a non-catalog rank would otherwise lose its metadata and
    -- render "Not available" for Target/Skip). Match the spell by its
    -- localized name instead, then borrow the catalog entry's behavior.
    if (GetSpellInfo) then
        local ok, name = pcall(GetSpellInfo, spellID);

        if (ok and name) then
            for category, list in pairs(spells) do
                for _, entry in ipairs(list) do
                    if (entry.name == name
                        or (GetSpellInfo and select(1, GetSpellInfo(entry.spellID)) == name)) then
                        entry.category = category;
                        return entry, category;
                    end
                end
            end
        end
    end

    return nil;
end

--- Build a new step from a catalog entry (STEP FACTORY — the business rules
--- the UI used to re-derive): the step type from the category, the default
--- target ("player" for cast steps and party-castable pet steps), the
--- per-step skip flag from the global "skip already-completed steps" default
--- (buff/summon/createItem steps only), and the product itemID.
---@param entry table
---@param group table|nil  the spellbook group (for the name fallback)
---@return table step
function WorkflowRepository:buildStep(entry, group)
    local C = ACP.Data.Constants;
    local category = entry.category or "other";
    local stepType = (category == "summons" and C.WORKFLOW_STEP_SUMMON) or
                         (category == "createItem" and C.WORKFLOW_STEP_CREATE_ITEM) or
                         (entry.isPetSpell and C.WORKFLOW_STEP_PET) or C.WORKFLOW_STEP_CAST;
    local step = {
        type = stepType,
        spellID = entry.spellID,
        spellName = entry.name or (group and group.name)
    };

    if (stepType == C.WORKFLOW_STEP_CAST or (stepType == C.WORKFLOW_STEP_PET and entry.canTargetParty)) then
        step.target = "player";
    end

    -- New buff-cast, summon and createItem steps default their skip flag to the
    -- global "skip already-completed steps" setting. A buff step only gets the
    -- flag when its cast actually applies a tracked buff (entry.buffSpellID).
    if ((stepType == C.WORKFLOW_STEP_CAST and entry.buffSpellID)
        or stepType == C.WORKFLOW_STEP_SUMMON
        or stepType == C.WORKFLOW_STEP_CREATE_ITEM) then
        step.skipIfBuffed = ACP.Settings:get("workflows.skipIfBuffedDefault") == true;
    end

    if (entry.itemID) then
        step.itemID = entry.itemID;
    end

    return step;
end

--- Resolve an Add Step menu key (a spellbook group name, a specific
--- rank/pet spellID, or an "item:<id>" equip-item key) into a NEW step built
--- by the factory. Shared by addStep (append) and replaceStep (in place).
---@param spellKey any
---@return table|nil step
function WorkflowRepository:resolveNewStep(spellKey)
    -- Equip-item entries use the "item:<id>" key convention.
    local equipItemID = tonumber(type(spellKey) == "string" and spellKey:match("^item:(%d+)$") or nil);

    if (equipItemID) then
        local entry = ACP.Data.Workflows and ACP.Data.Workflows:getEquipItem(equipItemID);

        return {
            type = ACP.Data.Constants.WORKFLOW_STEP_EQUIP_ITEM,
            itemID = equipItemID,
            itemName = (entry and entry.name) or nil
        };
    end

    local entry;
    local group;

    if (type(spellKey) == "number") then
        -- A specific rank (stone rank entry) or pet ability selected from the
        -- Add Step list — the entry IS the target, no group resolution needed.
        entry = ACP.WorkflowSpellbook and ACP.WorkflowSpellbook:getEntry(spellKey) or self:findSpell(spellKey);
    else
        group = ACP.WorkflowSpellbook and ACP.WorkflowSpellbook:getGroup(spellKey);

        if (not group or not group.entries or #group.entries == 0) then
            return nil;
        end

        entry = group.entries[#group.entries];
    end

    if (not entry) then
        return nil;
    end

    return self:buildStep(entry, group);
end

--- Append a step to a workflow slot, resolved from the Add Step menu key.
--- Returns whether a step was added.
---@param slot number
---@param spellKey any
---@return boolean changed
function WorkflowRepository:addStep(slot, spellKey)
    local step = self:resolveNewStep(spellKey);

    if (not step) then
        return false;
    end

    local steps = self:getSteps(slot);
    steps[#steps + 1] = step;
    ACP.Settings:persist();
    return true;
end

--- Replace the step at `index` with a NEW step resolved from `spellKey`
--- (the same Add Step menu key convention). The row keeps its position; the
--- new step is rebuilt by the factory, so its type/target/skip come from the
--- defaults of the NEW spell. Returns whether it was replaced.
---@param slot number
---@param index number
---@param spellKey any
---@return boolean changed
function WorkflowRepository:replaceStep(slot, index, spellKey)
    local steps = self:getSteps(slot);

    if (not steps[index]) then
        return false;
    end

    local step = self:resolveNewStep(spellKey);

    if (not step) then
        return false;
    end

    steps[index] = step;
    ACP.Settings:persist();
    return true;
end

--- Remove a step from a workflow slot. Returns whether it was removed.
---@param slot number
---@param index number
---@return boolean changed
function WorkflowRepository:removeStep(slot, index)
    local steps = self:getSteps(slot);

    if (steps[index]) then
        tremove(steps, index);
        ACP.Settings:persist();
        return true;
    end

    return false;
end

--- Swap a step with its neighbor. Returns whether it moved.
---@param slot number
---@param index number
---@param delta number  -1 (up) or +1 (down)
---@return boolean changed
function WorkflowRepository:moveStep(slot, index, delta)
    local steps = self:getSteps(slot);
    local target = index + delta;

    if (not steps[index] or not steps[target]) then
        return false;
    end

    steps[index], steps[target] = steps[target], steps[index];
    ACP.Settings:persist();
    return true;
end

return ACP;
