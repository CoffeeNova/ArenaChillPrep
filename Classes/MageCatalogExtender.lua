-- ArenaChillPrep — Classes/MageCatalogExtender
-- Class-gated static catalog extensions: conjured ranks (mergeStaticMage) and
-- the full static fallback (addStaticFallback).

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local select = _G.select;

-- CLASS_MAGE is not a global on TBC FrameXML (retail-only constant).
local CLASS_MAGE = ACP.Data.Constants.CLASS_MAGE;

---@class MageCatalogExtender
local MageCatalogExtender = {};

---@type MageCatalogExtender
ACP.MageCatalogExtender = MageCatalogExtender;

---@return string|nil
local function playerEnglishClass()
    return _G.UnitClass and select(2, _G.UnitClass("player"));
end

---@return boolean
function MageCatalogExtender:isMage()
    return playerEnglishClass() == CLASS_MAGE;
end

---@param spellbook table
function MageCatalogExtender:merge(spellbook)
    return self:mergeStaticMage(spellbook);
end

---@param spellbook table
function MageCatalogExtender:mergeStaticMage(spellbook)
    if (not self:isMage()) then
        return;
    end

    local conjuredRanks = ACP.Data.Workflows and ACP.Data.Workflows:rankedCreates(
        ACP.Data.classWorkflows(CLASS_MAGE));

    if (not conjuredRanks) then
        return;
    end

    for spellID, rank in pairs(conjuredRanks) do
        if (not spellbook.entriesByID[spellID]) then
            ACP.SpellbookCatalogBuilder:addEntry(spellbook, spellID, rank.spellName or "Create", "", nil, 1);
            local entry = spellbook.entriesByID[spellID];

            if (entry) then
                entry.category = "createItem";
                entry.itemID = rank.itemID;
                entry.rank = rank.rank;
                entry.isCastTime = true;
            end
        end
    end
end

--- Full static fallback (tests / pre-login): Mages get the whole catalog,
--- other classes get nothing.
---@param spellbook table
function MageCatalogExtender:addStaticFallback(spellbook)
    if (not self:isMage()) then
        return;
    end

    local data = ACP.Data.classWorkflows(CLASS_MAGE);
    local spells = data and data.spells;

    if (not spells) then
        return;
    end

    for category, list in pairs(spells) do
        for _, source in ipairs(list) do
            ACP.SpellbookCatalogBuilder:addEntry(spellbook, source.spellID, source.name, "", nil, source.isCastTime and 1 or 0);
            local entry = spellbook.entriesByID[source.spellID];

            if (entry) then
                entry.category = category;
                entry.canTargetParty = source.canTargetParty;
                entry.needsShard = source.needsShard;
                entry.buffSpellID = source.buffSpellID;
                entry.itemID = source.itemID;
                entry.isCastTime = source.isCastTime;
                entry.isPetSpell = source.isPetSpell;
                entry.pet = source.pet;
            end
        end
    end
end

return ACP;
