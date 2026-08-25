-- ArenaChillPrep — Classes/WarlockCatalogExtender
-- Class-gated static catalog extensions: pet abilities + stone ranks
-- (mergeStaticWarlock) and the full static fallback (addStaticFallback).

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local select = _G.select;

-- CLASS_WARLOCK is not a global on TBC FrameXML (retail-only constant).
local CLASS_WARLOCK = ACP.Data.Constants.CLASS_WARLOCK;

---@class WarlockCatalogExtender
local WarlockCatalogExtender = {};

---@type WarlockCatalogExtender
ACP.WarlockCatalogExtender = WarlockCatalogExtender;

---@return string|nil
local function playerEnglishClass()
    return _G.UnitClass and select(2, _G.UnitClass("player"));
end

---@return boolean
function WarlockCatalogExtender:isWarlock()
    return playerEnglishClass() == CLASS_WARLOCK;
end

---@param spellbook table
function WarlockCatalogExtender:mergeStaticWarlock(spellbook)
    if (not self:isWarlock()) then
        return;
    end

    local spells = ACP.Data.Workflows and ACP.Data.Workflows.spells;
    local stoneRanks = ACP.Data.Workflows and ACP.Data.Workflows.stoneRanks;

    if (spells) then
        for category, list in pairs(spells) do
            if (category == "pets") then
                for _, source in ipairs(list) do
                    if (not spellbook.entriesByID[source.spellID]) then
                        ACP.SpellbookCatalogBuilder:addEntry(spellbook, source.spellID, source.name, "", nil, source.isCastTime and 1 or 0);
                        local entry = spellbook.entriesByID[source.spellID];

                        if (entry) then
                            entry.category = category;
                            entry.isPetSpell = true;
                            entry.pet = source.pet;
                            entry.isCastTime = source.isCastTime;
                        end
                    end
                end
            end
        end
    end

    if (stoneRanks) then
        for spellID, rank in pairs(stoneRanks) do
            if (not spellbook.entriesByID[spellID]) then
                ACP.SpellbookCatalogBuilder:addEntry(spellbook, spellID, rank.spellName or "Create", "", nil, 1);
                local entry = spellbook.entriesByID[spellID];

                if (entry) then
                    entry.category = "createItem";
                    entry.itemID = rank.itemID;
                    entry.rank = rank.rank;
                    entry.isCastTime = true;
                    entry.needsShard = true;
                end
            end
        end
    end
end

--- Full static fallback (tests / pre-login): Warlocks get the whole catalog,
--- other classes get nothing.
---@param spellbook table
function WarlockCatalogExtender:addStaticFallback(spellbook)
    if (not self:isWarlock()) then
        return;
    end

    local spells = ACP.Data.Workflows and ACP.Data.Workflows.spells;

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
