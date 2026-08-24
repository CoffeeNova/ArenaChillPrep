-- ArenaChillPrep — Classes/WorkflowSpellbook
-- Runtime spell catalog for the Workflow editor — FACADE (refactor Phase 7).
-- The catalog is assembled from the STATIC data only: the live spellbook
-- scan was REMOVED (2026-08-24, user decision) — the probe-based scan never
-- actually ran (`X and pcall(...)` truncates pcall's second value), and the
-- working-scan variant had been rejected earlier for exposing every learned
-- spell in the Add Step list. For a Warlock the class-gated static fallback
-- fills the whole catalog; other classes get an empty catalog (no hardcoded
-- lists). The catalog still groups ranks by localized spell name and keeps
-- the exact spellID for every rank.
--
-- The concerns were extracted into:
--   SpellbookCatalogBuilder   — catalog assembly + rank metadata + reads
--   WarlockCatalogExtender    — class-gated static fallback + pet/stone extras
--   SpellbookLabels           — stoneStepLabel
-- The facade owns the catalog tables and the rebuild orchestration; the
-- delegating methods below keep its public surface stable.

---@type ACP
local _, ACP = ...;

---@class WorkflowSpellbook
local Spellbook = {
    _initialized = false,
    available = false,
    entriesByID = {},
    groupsByName = {},
    groupsByCategory = {},
    categoryOrder = { "buffs", "summons", "createItem", "utility", "pets", "other" },
};

ACP.WorkflowSpellbook = Spellbook;

--- Rebuild the catalog: wipe it, then fill it from the static data. For a
--- Warlock the pet abilities + stone ranks are merged first (mergeStaticWarlock)
--- and the full static catalog fills the rest (addStaticFallback); both are
--- class-gated, so other classes keep an empty catalog. Returns entriesByID.
function Spellbook:scan()
    ACP.SpellbookCatalogBuilder:reset(self);

    ACP.WarlockCatalogExtender:mergeStaticWarlock(self);
    ACP.WarlockCatalogExtender:addStaticFallback(self);

    ACP:debugPrint("workflow spellbook catalog rebuilt: found=%d",
        ACP.SpellbookCatalogBuilder:countEntries(self));

    ACP.SpellbookCatalogBuilder:finalize(self);

    self.available = next(self.entriesByID) ~= nil;
    return self.entriesByID;
end

--- Notify consumers that the runtime catalog changed. The Workflow editor
--- (when built) listens for ACP_SPELLBOOK_CHANGED — an event instead of a
--- reverse call into WorkflowUI (W6).
function Spellbook:_refreshUI()
    ACP.Events:fire("ACP_SPELLBOOK_CHANGED");
end

function Spellbook:_init()
    if (self._initialized) then
        return;
    end

    self._initialized = true;
    self:scan();

    if (ACP.Events) then
        -- The initial rebuild runs at ADDON_LOADED when the character (and its
        -- class) is not known yet — rebuild once the character is ready and
        -- again whenever the spellbook changes.
        ACP.Events:register("WorkflowSpellbook.PLAYER_LOGIN", "PLAYER_LOGIN", function()
            self:scan();
            self:_refreshUI();
        end);
        ACP.Events:register("WorkflowSpellbook.SPELLS_CHANGED", "SPELLS_CHANGED", function()
            self:scan();
            self:_refreshUI();
        end);
    end
end

-- ---------------------------------------------------------------------------
-- Delegates to the extracted modules. These keep the facade's public surface
-- stable (WorkflowEngine / WorkflowUI / WorkflowRepository / the test suite
-- call through it), while the implementations live in their own modules
-- operating on `self` (the spellbook).
-- ---------------------------------------------------------------------------

-- Catalog assembly + reads (Classes/SpellbookCatalogBuilder.lua)
function Spellbook:_reset()
    return ACP.SpellbookCatalogBuilder:reset(self);
end

function Spellbook:addEntry(spellID, spellName, rankText, icon, castTime)
    return ACP.SpellbookCatalogBuilder:addEntry(self, spellID, spellName, rankText, icon, castTime);
end

function Spellbook:countEntries()
    return ACP.SpellbookCatalogBuilder:countEntries(self);
end

function Spellbook:getEntry(spellID)
    return ACP.SpellbookCatalogBuilder:getEntry(self, spellID);
end

function Spellbook:getHighestKnownRank(spellName)
    return ACP.SpellbookCatalogBuilder:getHighestKnownRank(self, spellName);
end

function Spellbook:getGroup(key)
    return ACP.SpellbookCatalogBuilder:getGroup(self, key);
end

function Spellbook:getGroupsByCategory()
    return ACP.SpellbookCatalogBuilder:getGroupsByCategory(self);
end

-- Warlock static extensions (Classes/WarlockCatalogExtender.lua)
function Spellbook:mergeStaticWarlock()
    return ACP.WarlockCatalogExtender:mergeStaticWarlock(self);
end

function Spellbook:addStaticFallback()
    return ACP.WarlockCatalogExtender:addStaticFallback(self);
end

-- Display labels (Classes/SpellbookLabels.lua)
function Spellbook:stoneStepLabel(entry)
    return ACP.SpellbookLabels:stoneStepLabel(entry);
end

return ACP;
