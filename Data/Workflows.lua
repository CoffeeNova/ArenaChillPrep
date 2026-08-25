-- ArenaChillPrep — Data/Workflows
-- Warlock workflow spell catalog + target tokens + step schema validator.

---@type ACP
local _, ACP = ...;

local ipairs = _G.ipairs;

---@class Workflows
local Workflows = {
    spells = {
        buffs = {
            { spellID = 28176, name = "Fel Armor",          isCastTime = false, canTargetParty = false, buffSpellID = 28176 },
            { spellID = 28189, name = "Fel Armor",          isCastTime = false, canTargetParty = false, buffSpellID = 28189 },
            -- Max rank only; lower ranks are replaced in the spellbook at 70.
            { spellID = 27260, name = "Demon Armor",        isCastTime = false, canTargetParty = false, buffSpellID = 27260 },
            { spellID = 5697,  name = "Unending Breath",    isCastTime = false, canTargetParty = true,  buffSpellID = 5697 },
            -- Applied aura (25228) shares the name; skip-if-buffed matches by name.
            { spellID = 19028, name = "Soul Link",          isCastTime = false, canTargetParty = false, buffSpellID = 19028 },
            -- Max rank; self-only Magic absorb shield (30 s).
            { spellID = 28610, name = "Shadow Ward",        isCastTime = false, canTargetParty = false, buffSpellID = 28610 },
            { spellID = 132,   name = "Detect Invisibility", isCastTime = false, canTargetParty = true, buffSpellID = 132 },
        },
        summons = {
            { spellID = 688,   name = "Summon Imp",        isCastTime = true, needsShard = false, petEntry = 416 },
            { spellID = 697,   name = "Summon Voidwalker", isCastTime = true, needsShard = true,  petEntry = 1860 },
            { spellID = 712,   name = "Summon Succubus",   isCastTime = true, needsShard = true,  petEntry = 1863 },
            { spellID = 691,   name = "Summon Felhunter",  isCastTime = true, needsShard = true,  petEntry = 417 },
            { spellID = 30146, name = "Summon Felguard",   isCastTime = true, needsShard = true,  petEntry = 17252 },
        },
        -- Pet-cast abilities; pet steps are exempt from the player-casting gate.
        pets = {
            -- 19483 (rank 1) resolves to "Immolation" on 2.5.5 — use the TBC rank 6.
            { spellID = 27269, name = "Fire Shield",  isPetSpell = true, pet = "imp",        isCastTime = false, canTargetParty = true },
            { spellID = 7812,  name = "Sacrifice",    isPetSpell = true, pet = "voidwalker", isCastTime = false, canTargetParty = false },
        },
        createItem = {
            { spellID = 6201,  name = "Create Healthstone", isCastTime = true, needsShard = true, itemID = 19004 },
            -- Ranks coexist: a rank-5 cast really creates a Major stone.
            { spellID = 11730, name = "Create Healthstone", isCastTime = true, needsShard = true, itemID = 19012 },
            { spellID = 27230, name = "Create Healthstone", isCastTime = true, needsShard = true, itemID = 22105 },
            { spellID = 28172, name = "Create Spellstone",  isCastTime = true, needsShard = true, itemID = 22646 },
        },
        utility = {
            { spellID = 29893, name = "Ritual of Souls", isCastTime = true, needsShard = true },
        },
    },

    targets = nil,

    -- Equippable conjured items an `equipItem` step may equip (spellstones).
    equipItems = {
        { itemID = 5522,  name = "Spellstone" },
        { itemID = 13602, name = "Greater Spellstone" },
        { itemID = 13603, name = "Major Spellstone" },
        { itemID = 22646, name = "Master Spellstone" },
    },

    -- Per-rank data for the stone-creating spells; the Add Step menu lists one
    -- entry per rank with the stone's name. Healthstone ranks 1-5 exist as
    -- historical item-ID pairs (the client conjures either variant); Create
    -- Spellstone ships only the TBC max rank.
    stoneRanks = {
        [6201]  = { spellID = 6201,  spellName = "Create Healthstone", itemID = 19004, itemIDs = { 19004, 19005 }, itemName = "Minor Healthstone", rank = 1 },
        [6202]  = { spellID = 6202,  spellName = "Create Healthstone", itemID = 19006, itemIDs = { 19006, 19007 }, itemName = "Lesser Healthstone", rank = 2 },
        [5699]  = { spellID = 5699,  spellName = "Create Healthstone", itemID = 19008, itemIDs = { 19008, 19009 }, itemName = "Healthstone", rank = 3 },
        [11729] = { spellID = 11729, spellName = "Create Healthstone", itemID = 19010, itemIDs = { 19010, 19011 }, itemName = "Greater Healthstone", rank = 4 },
        [11730] = { spellID = 11730, spellName = "Create Healthstone", itemID = 19012, itemIDs = { 19012, 19013 }, itemName = "Major Healthstone", rank = 5 },
        [27230] = { spellID = 27230, spellName = "Create Healthstone", itemID = 22105, itemIDs = { 22105 }, itemName = "Master Healthstone", rank = 6 },
        [28172] = { spellID = 28172, spellName = "Create Spellstone", itemID = 22646, itemIDs = { 22646 }, itemName = "Master Spellstone", rank = 4 },
    },
};

---@type Workflows
ACP.Data.Workflows = Workflows;
Workflows.targets = ACP.Data.Constants.WORKFLOW_TARGETS;

---@param itemID number
---@return table|nil
function Workflows:getEquipItem(itemID)
    for _, entry in ipairs(self.equipItems) do
        if (entry.itemID == itemID) then
            return entry;
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
