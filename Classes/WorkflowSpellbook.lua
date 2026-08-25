-- ArenaChillPrep — Classes/WorkflowSpellbook
-- Runtime spell catalog for the Workflow editor — a facade over
-- SpellbookCatalogBuilder (assembly/reads), WarlockCatalogExtender
-- (class-gated static fallback + pet/stone extras) and SpellbookLabels.
-- Built from the STATIC data only; other classes get an empty catalog.

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
        -- The ADDON_LOADED rebuild runs before the class is known — rebuild
        -- on login and on spellbook changes.
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

-- Delegates to the extracted modules (they operate on `self`).

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

function Spellbook:mergeStaticWarlock()
    return ACP.WarlockCatalogExtender:mergeStaticWarlock(self);
end

function Spellbook:addStaticFallback()
    return ACP.WarlockCatalogExtender:addStaticFallback(self);
end

function Spellbook:stoneStepLabel(entry)
    return ACP.SpellbookLabels:stoneStepLabel(entry);
end

return ACP;
