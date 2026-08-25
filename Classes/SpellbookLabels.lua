-- ArenaChillPrep — Classes/SpellbookLabels
-- Rank-decorated display labels for stone-creating spell entries.

---@type ACP
local _, ACP = ...;

local tostring = _G.tostring;

---@class SpellbookLabels
local SpellbookLabels = {};

---@type SpellbookLabels
ACP.SpellbookLabels = SpellbookLabels;

--- "Create Healthstone (rank 5)" etc. Falls back to the plain name.
---@param entry table
---@return string
function SpellbookLabels:stoneStepLabel(entry)
    local rankTable = ACP.Data.Workflows and ACP.Data.Workflows:activeRankTable();
    local stone = rankTable and rankTable[entry.spellID];

    if (stone) then
        -- GetSpellInfo returns only the unranked base name on 20506, so the
        -- rank comes from the catalog.
        local base = (stone.spellName and stone.spellName ~= "") and stone.spellName or "Create";
        return base .. " (rank " .. tostring(stone.rank) .. ")";
    end

    return entry.name or "Create";
end

--- Rank-decorated label for buff entries carrying an explicit rank
--- (Amplify/Dampen Magic: each rank is a separate Add Step entry).
---@param entry table
---@return string
function SpellbookLabels:rankStepLabel(entry)
    if (entry.rank and entry.rank > 0) then
        return (entry.name or "Spell") .. " (rank " .. tostring(entry.rank) .. ")";
    end

    return entry.name or "Spell";
end

return ACP;
