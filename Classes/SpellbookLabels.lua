-- ArenaChillPrep — Classes/SpellbookLabels
-- Display-label helpers for the stone-creating spell ranks, extracted from
-- WorkflowSpellbook (refactor Phase 7): stoneStepLabel — the rank-decorated
-- spell label (e.g. "Create Master Healthstone" / "Create Healthstone
-- (rank 5)").

---@type ACP
local _, ACP = ...;

local tostring = _G.tostring;

---@class SpellbookLabels
local SpellbookLabels = {};

---@type SpellbookLabels
ACP.SpellbookLabels = SpellbookLabels;

--- Display label for a stone-creating spell entry: "Create Master Healthstone"
--- for a rank-6 Create Healthstone entry, etc. Falls back to the plain spell
--- name when no rank data is available.
---@param entry table
---@return string
function SpellbookLabels:stoneStepLabel(entry)
    local stone = ACP.Data.Workflows and ACP.Data.Workflows.stoneRanks
        and ACP.Data.Workflows.stoneRanks[entry.spellID];

    if (stone) then
        -- Append the rank explicitly: GetSpellInfo returns only the unranked base
        -- name ("Create Healthstone") on 20506, so the rank must come from the
        -- catalog — otherwise all six ranks show identically in the Add Step list.
        local base = (stone.spellName and stone.spellName ~= "") and stone.spellName or "Create";
        return base .. " (rank " .. tostring(stone.rank) .. ")";
    end

    return entry.name or "Create";
end

return ACP;
