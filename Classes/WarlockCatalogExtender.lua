-- ArenaChillPrep — Classes/WarlockCatalogExtender
-- The Warlock-specific static catalog extensions, extracted from
-- WorkflowSpellbook (refactor Phase 7): the class gate, the pet-ability +
-- stone-rank merge (mergeStaticWarlock) and the full static fallback for the
-- pre-login / API-unavailable case (addStaticFallback).

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local select = _G.select;

-- CLASS_WARLOCK is NOT a global on TBC Anniversary FrameXML (retail-only
-- constant) — guarded single source lives in Data/Constants.
local CLASS_WARLOCK = ACP.Data.Constants.CLASS_WARLOCK;

---@class WarlockCatalogExtender
local WarlockCatalogExtender = {};

---@type WarlockCatalogExtender
ACP.WarlockCatalogExtender = WarlockCatalogExtender;

--- The player's English class token ("WARLOCK", "MAGE", ...). Nil before the
--- character is loaded (UnitClass("player") is unreliable during ADDON_LOADED).
---@return string|nil
local function playerEnglishClass()
    return _G.UnitClass and select(2, _G.UnitClass("player"));
end

--- Whether the player is a confirmed Warlock (the static catalog is
--- Warlock-specific — injecting it for any other class would pollute the
--- Add Step list with spells that character can never cast).
---@return boolean
function WarlockCatalogExtender:isWarlock()
    return playerEnglishClass() == CLASS_WARLOCK;
end

--- Merge the Warlock-specific static entries (pet abilities and the full rank
--- list of the stone-creating spells) into the catalog. Called after every scan
--- for a confirmed Warlock — these spells are pet/grunt-learned abilities that
--- the player's own spellbook scan can never produce (Fire Shield / Sacrifice)
--- or that are known only at one rank (the stone ranks are listed so the user
--- can pick any rank). Skips IDs already present from the real scan.
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

--- Static fallback used by tests/clients where the spellbook API is not ready.
--- Only populates for a confirmed Warlock: the catalog is Warlock-specific, so
--- injecting it for any other class (e.g. a Mage at ADDON_LOADED) would pollute
--- the Add Step list with spells that character can never cast. When the class
--- is not known yet (pre-login) the fallback stays empty — the PLAYER_LOGIN
--- re-scan fills the catalog from the real spellbook.
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
