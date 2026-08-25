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
    local stone = ACP.Data.Workflows and ACP.Data.Workflows.stoneRanks
        and ACP.Data.Workflows.stoneRanks[entry.spellID];

    if (stone) then
        -- GetSpellInfo returns only the unranked base name on 20506, so the
        -- rank comes from the catalog.
        local base = (stone.spellName and stone.spellName ~= "") and stone.spellName or "Create";
        return base .. " (rank " .. tostring(stone.rank) .. ")";
    end

    return entry.name or "Create";
end

return ACP;
