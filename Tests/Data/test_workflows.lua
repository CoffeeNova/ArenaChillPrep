-- ArenaChillPrep — Tests/Data/test_workflows.lua
-- Covers Data/Workflows.lua: the generic step schema validator and the
-- class-gated static-catalog rebuild (Warlock catalog data lives in
-- test_warlockworkflows.lua, Mage in test_mageworkflows.lua).

local ACP = _G.ACP;
local W = ACP.Data.Workflows;

-- Capture the stub's UnitClass so we can restore it after the class-specific
-- tests below (they override _G.UnitClass and must not leak into later suites).
local DefaultUnitClass = _G.UnitClass;

function testIsValidTarget()
    -- Arrange
    -- Act
    -- Assert
    lu.assertIsTrue(W:isValidTarget("player"));
    lu.assertIsTrue(W:isValidTarget("party2"));
    lu.assertIsFalse(W:isValidTarget("arena1"));
    lu.assertIsFalse(W:isValidTarget(nil));
end

function testValidateCastStep()
    -- Arrange
    local step = { type = "cast", spellID = 5697, target = "player" };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsTrue(ok);
    lu.assertIsNil(err);
end

function testValidateSummonStep()
    -- Arrange
    local step = { type = "summon", spellID = 688 };
    -- Act
    local ok = W:validateStep(step);
    -- Assert
    lu.assertIsTrue(ok);
end

function testValidateCreateItemStep()
    -- Arrange
    local step = { type = "createItem", spellID = 27230, itemID = 22105 };
    -- Act
    local ok = W:validateStep(step);
    -- Assert
    lu.assertIsTrue(ok);
end

function testValidateEquipItemStep()
    -- Arrange
    local step = { type = "equipItem", itemID = 22646, itemName = "Master Spellstone" };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsTrue(ok);
    lu.assertIsNil(err);
end

function testValidateEquipItemWithoutItemName()
    -- Arrange
    local step = { type = "equipItem", itemID = 22646 };
    -- Act
    local ok = W:validateStep(step);
    -- Assert
    lu.assertIsTrue(ok);
end

function testValidateEquipItemRequiresItemID()
    -- Arrange
    local step = { type = "equipItem", itemName = "Master Spellstone" };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsFalse(ok);
    lu.assertStrContains(err, "itemID");
end

function testValidateEquipItemRejectsBadItemName()
    -- Arrange
    local step = { type = "equipItem", itemID = 22646, itemName = 42 };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsFalse(ok);
    lu.assertStrContains(err, "itemName");
end

function testValidateRejectsNonTable()
    -- Arrange
    -- Act
    local ok, err = W:validateStep("nope");
    -- Assert
    lu.assertIsFalse(ok);
    lu.assertStrContains(err, "table");
end

function testValidateRejectsUnknownType()
    -- Arrange
    local step = { type = "jump", spellID = 1 };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsFalse(ok);
    lu.assertStrContains(err, "jump");
end

function testValidateRejectsBadSpellID()
    -- Arrange
    local step = { type = "cast", spellID = "5697" };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsFalse(ok);
    lu.assertStrContains(err, "spellID");
end

function testValidateRejectsBadTarget()
    -- Arrange
    local step = { type = "cast", spellID = 5697, target = "bogus" };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsFalse(ok);
    lu.assertStrContains(err, "bogus");
end

function testValidateToleratesLegacySkipFlag()
    -- The per-step skipIfBuffed flag was REMOVED (2026-08-25) — saved data may
    -- still carry it and must stay valid.
    local step = { type = "cast", spellID = 5697, skipIfBuffed = "yes" };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsTrue(ok);
    lu.assertIsNil(err);
end

function testValidateCreateItemRequiresItemID()
    -- Arrange
    local step = { type = "createItem", spellID = 27230 };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsFalse(ok);
    lu.assertStrContains(err, "itemID");
end

function testValidatePetStep()
    -- Arrange
    local step = { type = "pet", spellID = 27269, spellName = "Fire Shield" };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsTrue(ok);
    lu.assertIsNil(err);
end

function testValidatePetStepRequiresSpellID()
    -- Arrange
    local step = { type = "pet" };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsFalse(ok);
    lu.assertStrContains(err, "spellID");
end

-- ---- class-gated static fallback (dispatched per class) ----

function testStaticFallbackGatedByClass()
    -- Each class gets ITS OWN catalog: a Mage sees the Mage spells, never the
    -- Warlock ones (and vice versa). The override is restored BEFORE the
    -- asserts so a failure cannot leak the stub into later suites.
    local origUnitClass = _G.UnitClass;
    local Spellbook = ACP.WorkflowSpellbook;

    Spellbook:_reset();
    _G.UnitClass = function() return "Mage", "MAGE" end;
    Spellbook:addStaticFallback();
    local mageCount = ACP.SpellbookCatalogBuilder:countEntries(Spellbook);
    local mageHasWarlockSpell = Spellbook:getEntry(688) ~= nil or Spellbook:getEntry(27230) ~= nil;
    local mageHasOwnSpells = Spellbook:getEntry(27090) ~= nil and Spellbook:getEntry(33717) ~= nil
        and Spellbook:getEntry(27127) ~= nil;

    Spellbook:_reset();
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    Spellbook:addStaticFallback();
    local warlockCount = ACP.SpellbookCatalogBuilder:countEntries(Spellbook);
    local warlockHasMageSpell = Spellbook:getEntry(27090) ~= nil or Spellbook:getEntry(27127) ~= nil;
    local warlockHasOwnSpells = Spellbook:getEntry(688) ~= nil and Spellbook:getEntry(27230) ~= nil;

    _G.UnitClass = origUnitClass;

    lu.assertIsTrue(mageCount > 0, "mage must get the mage catalog");
    lu.assertIsTrue(mageHasOwnSpells, "mage catalog carries conjures + buffs");
    lu.assertIsFalse(mageHasWarlockSpell, "mage must never get warlock spells");
    lu.assertIsTrue(warlockCount > 0, "warlock must get the warlock catalog");
    lu.assertIsTrue(warlockHasOwnSpells, "warlock catalog carries summons + stones");
    lu.assertIsFalse(warlockHasMageSpell, "warlock must never get mage spells");
end

function testStaticFallbackUnknownClassEmpty()
    -- An unsupported class gets an empty Add Step catalog.
    local origUnitClass = _G.UnitClass;
    local Spellbook = ACP.WorkflowSpellbook;

    Spellbook:_reset();
    _G.UnitClass = function() return "Hunter", "HUNTER" end;
    Spellbook:addStaticFallback();
    local count = ACP.SpellbookCatalogBuilder:countEntries(Spellbook);
    _G.UnitClass = origUnitClass;

    lu.assertEquals(count, 0);
end

function testStaticFallbackIncludesPetsAndStoneRanks()
    -- Arrange
    local origUnitClass = _G.UnitClass;
    local Spellbook = ACP.WorkflowSpellbook;
    Spellbook:_reset();

    -- Act
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    Spellbook:addStaticFallback();

    local fireShield = Spellbook:getEntry(27269);
    local sacrifice = Spellbook:getEntry(7812);
    local masterStone = Spellbook:getEntry(27230);
    local detect = Spellbook:getEntry(132);
    _G.UnitClass = origUnitClass;

    -- Assert
    lu.assertNotIsNil(fireShield, "Fire Shield present");
    lu.assertNotIsNil(sacrifice, "Sacrifice present");
    lu.assertNotIsNil(masterStone, "Create Healthstone rank 6 present");
    lu.assertEquals(fireShield.category, "pets");
    lu.assertEquals(fireShield.pet, "imp");
    lu.assertEquals(fireShield.canTargetParty, true, "Fire Shield is party-castable");
    lu.assertEquals(detect.canTargetParty, true, "Detect Invisibility is party-castable");
    lu.assertEquals(masterStone.itemID, 22105);
end

function testStaticFallbackMageCategories()
    -- Arrange
    local origUnitClass = _G.UnitClass;
    local Spellbook = ACP.WorkflowSpellbook;
    Spellbook:_reset();

    -- Act: merge (conjured ranks, sets rank/itemID) then the full fallback —
    -- the same order WorkflowSpellbook:scan() uses.
    _G.UnitClass = function() return "Mage", "MAGE" end;
    Spellbook:mergeStaticWarlock();
    Spellbook:addStaticFallback();

    local water = Spellbook:getEntry(27090);
    local food = Spellbook:getEntry(33717);
    local intellect = Spellbook:getEntry(27126);
    local ritual = Spellbook:getEntry(43987);
    _G.UnitClass = origUnitClass;

    -- Assert: conjured entries land in createItem with itemIDs + ranks.
    lu.assertEquals(water.category, "createItem");
    lu.assertEquals(water.itemID, 22018);
    lu.assertEquals(water.rank, 9);
    lu.assertEquals(food.category, "createItem");
    lu.assertEquals(food.itemID, 22019);
    lu.assertEquals(food.rank, 8);
    lu.assertEquals(intellect.category, "buffs");
    lu.assertEquals(ritual.category, "utility");
end

-- ---- WorkflowSpellbook rebuild (the live spellbook scan was REMOVED
--     2026-08-24 — the catalog is built from the static data only) ----

local function spellbookGroup(category, name)
    for _, group in ipairs(ACP.WorkflowSpellbook.groupsByCategory[category] or {}) do
        if (group.name == name) then
            return group;
        end
    end

    return nil;
end

local function clearSpellbookStubs()
    _G.__stub.spellInfo = {};
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
end

function testRebuildFillsStaticCatalogForWarlock()
    -- Arrange: a warlock (the live-client scenario — the catalog comes from
    -- the static data).
    clearSpellbookStubs();

    -- Act
    ACP.WorkflowSpellbook:scan();

    -- Assert: the full static catalog fills every section, with the pets +
    -- stone ranks merged first (the "current set").
    lu.assertNotIsNil(ACP.WorkflowSpellbook:getEntry(28176), "Fel Armor buff present");
    lu.assertNotIsNil(ACP.WorkflowSpellbook:getEntry(688), "Summon Imp present");
    lu.assertNotIsNil(spellbookGroup("buffs", "Fel Armor"));
    lu.assertNotIsNil(spellbookGroup("summons", "Summon Imp"));
    lu.assertNotIsNil(spellbookGroup("utility", "Ritual of Souls"));
    lu.assertNotIsNil(ACP.WorkflowSpellbook:getEntry(27269), "Fire Shield pet present");
    lu.assertNotIsNil(ACP.WorkflowSpellbook:getEntry(27230), "Master Healthstone rank present");
    -- Shadow Ward (self-only buff) is part of the static catalog and appears in
    -- the Buffs section.
    local sw = spellbookGroup("buffs", "Shadow Ward");
    lu.assertNotIsNil(sw, "Shadow Ward buff present");
    lu.assertEquals(ACP.WorkflowSpellbook:getEntry(28610).canTargetParty, false, "Shadow Ward is self-only");

    -- Tear down
    clearSpellbookStubs();
    _G.UnitClass = DefaultUnitClass;
end

function testRebuildFillsStaticCatalogForMage()
    -- Arrange: a Mage gets the Mage catalog with both Amplify/Dampen ranks.
    _G.__stub.spellInfo = {};
    _G.UnitClass = function() return "Mage", "MAGE" end;

    -- Act
    ACP.WorkflowSpellbook:scan();

    -- Assert
    lu.assertNotIsNil(ACP.WorkflowSpellbook:getEntry(27090), "Conjure Water present");
    lu.assertNotIsNil(ACP.WorkflowSpellbook:getEntry(33717), "Conjure Food present");
    lu.assertNotIsNil(ACP.WorkflowSpellbook:getEntry(27127), "Arcane Brilliance present");
    lu.assertNotIsNil(ACP.WorkflowSpellbook:getEntry(1008), "Amplify Magic rank 1 present");
    lu.assertNotIsNil(ACP.WorkflowSpellbook:getEntry(33946), "Amplify Magic max rank present");
    lu.assertNotIsNil(spellbookGroup("buffs", "Arcane Brilliance"));
    lu.assertNotIsNil(spellbookGroup("createItem", "Conjure Water"));
    lu.assertNotIsNil(spellbookGroup("utility", "Ritual of Refreshment"));
    lu.assertIsNil(ACP.WorkflowSpellbook:getEntry(688), "no Warlock summons for a Mage");

    -- Tear down
    clearSpellbookStubs();
    _G.UnitClass = DefaultUnitClass;
end

-- ---- SpellbookCatalogBuilder ----

function testCatalogBuilderRankResultHealthstone()
    -- A rank-suffixed Create Healthstone entry resolves its item via the
    -- rank→item map (rank 5 → Major Healthstone 19012).
    local spellbook = ACP.WorkflowSpellbook;
    ACP.SpellbookCatalogBuilder:addEntry(spellbook, 999001, "Create Healthstone", "Rank 5");
    local entry = ACP.SpellbookCatalogBuilder:getEntry(spellbook, 999001);
    lu.assertEquals(entry.itemID, 19012);
    lu.assertEquals(entry.category, "createItem");
    ACP.SpellbookCatalogBuilder:reset(spellbook);
end

function testCatalogBuilderRankResultSoulstone()
    local spellbook = ACP.WorkflowSpellbook;
    ACP.SpellbookCatalogBuilder:addEntry(spellbook, 999002, "Create Soulstone", "Rank 5");
    local entry = ACP.SpellbookCatalogBuilder:getEntry(spellbook, 999002);
    lu.assertEquals(entry.itemID, 22103);
    ACP.SpellbookCatalogBuilder:reset(spellbook);
end

function testCatalogBuilderDuplicateNameCategoryUpgrade()
    -- A name added WITHOUT metadata (catalog unavailable) first lands in
    -- "other"; a later add with the catalog present upgrades the group's
    -- category to the metadata's.
    local spellbook = ACP.WorkflowSpellbook;
    ACP.SpellbookCatalogBuilder:reset(spellbook);
    local warlockData = ACP.Data.WarlockWorkflows;
    local spells = warlockData.spells;
    warlockData.spells = nil;
    ACP.SpellbookCatalogBuilder:addEntry(spellbook, 999007, "Fel Armor", "");
    warlockData.spells = spells;
    ACP.SpellbookCatalogBuilder:addEntry(spellbook, 999008, "Fel Armor", "");
    local group = ACP.SpellbookCatalogBuilder:getGroup(spellbook, "Fel Armor");
    lu.assertEquals(group.category, "buffs");
    ACP.SpellbookCatalogBuilder:reset(spellbook);
end

function testMergeStaticWarlockGatedForOtherClasses()
    -- Both static extensions are no-ops for a non-Warlock.
    local origUnitClass = _G.UnitClass;
    local spellbook = ACP.WorkflowSpellbook;
    ACP.SpellbookCatalogBuilder:reset(spellbook);
    _G.UnitClass = function() return "Mage", "MAGE" end;
    ACP.WarlockCatalogExtender:mergeStaticWarlock(spellbook);
    ACP.WarlockCatalogExtender:addStaticFallback(spellbook);
    local count = ACP.SpellbookCatalogBuilder:countEntries(spellbook);
    _G.UnitClass = origUnitClass;

    lu.assertEquals(count, 0);
    ACP.SpellbookCatalogBuilder:reset(spellbook);
end

-- Restore the stub's UnitClass for subsequent suites (see DefaultUnitClass).
_G.UnitClass = DefaultUnitClass;
