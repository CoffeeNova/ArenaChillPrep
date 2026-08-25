-- ArenaChillPrep — Data/Workflows
-- Generic workflow schema (targets, step validator, equip-item lookup) +
-- the class-data registry. Class-specific catalogs live in
-- WarlockWorkflows.lua / MageWorkflows.lua behind ACP.Data.classWorkflows().

---@type ACP
local _, ACP = ...;

local ipairs = _G.ipairs;
local select = _G.select;

---@class Workflows
local Workflows = {
    targets = nil,
};

local CLASS_WORKFLOWS = {
    [ACP.Data.Constants.CLASS_WARLOCK] = ACP.Data.WarlockWorkflows,
    [ACP.Data.Constants.CLASS_MAGE] = ACP.Data.MageWorkflows,
};

--- Active class's workflow data (spells, rank tables, defaults), or nil for
--- unknown classes / before the character is loaded.
---@param englishClass string|nil
---@return table|nil
function ACP.Data.classWorkflows(englishClass)
    return CLASS_WORKFLOWS[englishClass];
end

--- The player's class workflow data at call time.
---@return table|nil
function ACP.Data.activeClassWorkflows()
    return ACP.Data.classWorkflows(select(2, UnitClass("player")));
end

--- Rank→item table of the given class data (conjured ranks or stone ranks).
---@param data table|nil
---@return table|nil
function Workflows:rankedCreates(data)
    return data and (data.conjuredRanks or data.stoneRanks);
end

--- Rank→item table of the active class.
---@return table|nil
function Workflows:activeRankTable()
    return self:rankedCreates(ACP.Data.activeClassWorkflows());
end

---@type Workflows
ACP.Data.Workflows = Workflows;
Workflows.targets = ACP.Data.Constants.WORKFLOW_TARGETS;

---@param itemID number
---@return table|nil
function Workflows:getEquipItem(itemID)
    local data = ACP.Data.activeClassWorkflows();
    local equipItems = data and data.equipItems;

    if (equipItems) then
        for _, entry in ipairs(equipItems) do
            if (entry.itemID == itemID) then
                return entry;
            end
        end
    end

    return nil;
end

---@param token any
---@return boolean
function Workflows:isValidTarget(token)
    for _, allowed in ipairs(self.targets) do
        if (allowed == token) then
            return true;
        end
    end

    return false;
end

---@param step any
---@return boolean ok
---@return string|nil errorMessage
function Workflows:validateStep(step)
    if (type(step) ~= "table") then
        return false, ACP.L.workflow.errNotTable;
    end

    local C = ACP.Data.Constants;
    local stepType = step.type;

    if (stepType ~= C.WORKFLOW_STEP_CAST
        and stepType ~= C.WORKFLOW_STEP_SUMMON
        and stepType ~= C.WORKFLOW_STEP_CREATE_ITEM
        and stepType ~= C.WORKFLOW_STEP_EQUIP_ITEM
        and stepType ~= C.WORKFLOW_STEP_PET) then
        return false, ACP.L.workflow.errBadType:format(tostring(stepType));
    end

    if (stepType == C.WORKFLOW_STEP_EQUIP_ITEM) then
        if (type(step.itemID) ~= "number") then
            return false, ACP.L.workflow.errBadItemID;
        end

        if (step.itemName ~= nil and type(step.itemName) ~= "string") then
            return false, ACP.L.workflow.errBadItemName;
        end

        return true;
    end

    if (type(step.spellID) ~= "number") then
        return false, ACP.L.workflow.errBadSpellID;
    end

    if (stepType == C.WORKFLOW_STEP_CAST) then
        if (step.target ~= nil and not self:isValidTarget(step.target)) then
            return false, ACP.L.workflow.errBadTarget:format(tostring(step.target));
        end
    elseif (stepType == C.WORKFLOW_STEP_CREATE_ITEM) then
        if (type(step.itemID) ~= "number") then
            return false, ACP.L.workflow.errBadItemID;
        end
    end

    return true;
end

return ACP;
