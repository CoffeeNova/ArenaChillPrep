-- ArenaChillPrep — Tests/Data/test_workflows.lua
-- Covers Data/Workflows.lua: step schema validation (all step types,
-- including equipItem) and the equippable-item catalog.

local ACP = _G.ACP;
local W = ACP.Data.Workflows;

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
    local step = { type = "cast", spellID = 5697, target = "player", skipIfBuffed = true };
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

function testValidateRejectsBadSkip()
    -- Arrange
    local step = { type = "cast", spellID = 5697, skipIfBuffed = "yes" };
    -- Act
    local ok, err = W:validateStep(step);
    -- Assert
    lu.assertIsFalse(ok);
    lu.assertStrContains(err, "skipIfBuffed");
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

function testStoneRanksHealthstone()
    -- Arrange
    local count = 0;
    for _ in pairs(W.stoneRanks) do count = count + 1; end

    -- Assert
    lu.assertEquals(count, 10);
    lu.assertEquals(W.stoneRanks[27230].itemName, "Master Healthstone");
    lu.assertEquals(W.stoneRanks[11730].itemName, "Major Healthstone");
    lu.assertEquals(W.stoneRanks[2362].itemName, "Spellstone");
    lu.assertEquals(W.stoneRanks[28172].itemName, "Master Spellstone");
end

function testStoneRanksCarryVariantPairs()
    -- Healthstone ranks 1-5 are historical ID pairs (the client conjures one
    -- variant per rank — rank 5 -> 19013, live-verified); rank 6 and the
    -- spellstone ranks are single IDs.
    lu.assertEquals(#W.stoneRanks[6201].itemIDs, 2);
    lu.assertEquals(W.stoneRanks[6201].itemIDs[1], 19004);
    lu.assertEquals(W.stoneRanks[6201].itemIDs[2], 19005);
    lu.assertEquals(#W.stoneRanks[11730].itemIDs, 2);
    lu.assertEquals(W.stoneRanks[11730].itemIDs[1], 19012);
    lu.assertEquals(W.stoneRanks[11730].itemIDs[2], 19013);
    lu.assertEquals(#W.stoneRanks[27230].itemIDs, 1);
    lu.assertEquals(W.stoneRanks[27230].itemIDs[1], 22105);
    lu.assertEquals(#W.stoneRanks[28172].itemIDs, 1);
    lu.assertEquals(W.stoneRanks[28172].itemIDs[1], 22646);
end

function testCreateItemCatalogRankOneExpectsMinorStone()
    -- The rank-1 Create Healthstone catalog entry used to claim itemID 22105
    -- (Master) — a rank-1 step without a stored itemID would then wait for the
    -- wrong stone. It must expect Minor 19004.
    local entry = nil;
    for _, list in pairs(W.spells) do
        for _, e in ipairs(list) do
            if (e.spellID == 6201) then
                entry = e;
            end
        end
    end

    lu.assertNotIsNil(entry);
    lu.assertEquals(entry.itemID, 19004);
end

function testSoulLinkCatalogEntryUses19028()
    -- 6307 is the IMP's Blood Pact passive, not Soul Link (verified against
    -- WeakAurasTemplates TBC data 2026-08-22). The old 6307 entry made the UI
    -- show "Blood Pact" and the skip check match the imp's always-on aura, so
    -- Soul Link was never cast. The catalog must point at 19028.
    local entry = nil;
    for _, list in pairs(W.spells) do
        for _, e in ipairs(list) do
            if (e.name == "Soul Link") then
                entry = e;
            end
        end
    end

    lu.assertNotIsNil(entry);
    lu.assertEquals(entry.spellID, 19028);
    lu.assertEquals(entry.buffSpellID, 19028);
    lu.assertIsFalse(entry.canTargetParty);
end

function testStoneRanksCreateStepLabel()
    -- Arrange / Act / Assert: the rank is appended explicitly (GetSpellInfo
    -- returns the unranked base name on 20506, so the catalog rank disambiguates).
    lu.assertEquals(ACP.WorkflowSpellbook:stoneStepLabel(W.stoneRanks[6201]), "Create Healthstone (rank 1)");
    lu.assertEquals(ACP.WorkflowSpellbook:stoneStepLabel(W.stoneRanks[11730]), "Create Healthstone (rank 5)");
    lu.assertEquals(ACP.WorkflowSpellbook:stoneStepLabel(W.stoneRanks[27230]), "Create Healthstone (rank 6)");
end

function testStaticFallbackGatedByClass()
    -- Arrange
    local Spellbook = ACP.WorkflowSpellbook;
    Spellbook:_reset();

    -- Act
    _G.UnitClass = function() return "Mage", "MAGE" end;
    Spellbook:addStaticFallback();
    local mageCount = 0;
    for _ in pairs(Spellbook.entriesByID) do mageCount = mageCount + 1; end

    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    Spellbook:addStaticFallback();
    local warlockCount = 0;
    for _ in pairs(Spellbook.entriesByID) do warlockCount = warlockCount + 1; end

    -- Assert
    lu.assertEquals(mageCount, 0, "mage must not get the warlock catalog");
    lu.assertIsTrue(warlockCount > 0, "warlock must get the warlock catalog");
end

function testStaticFallbackIncludesPetsAndStoneRanks()
    -- Arrange
    local Spellbook = ACP.WorkflowSpellbook;
    Spellbook:_reset();

    -- Act
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    Spellbook:addStaticFallback();

    -- Assert
    lu.assertIsTrue(Spellbook:getEntry(27269) ~= nil, "Fire Shield present");
    lu.assertIsTrue(Spellbook:getEntry(7812) ~= nil, "Sacrifice present");
    lu.assertIsTrue(Spellbook:getEntry(27230) ~= nil, "Create Healthstone rank 6 present");
    lu.assertEquals(Spellbook:getEntry(27269).category, "pets");
    lu.assertEquals(Spellbook:getEntry(27269).pet, "imp");
    lu.assertEquals(Spellbook:getEntry(27269).canTargetParty, true, "Fire Shield is party-castable");
    lu.assertEquals(Spellbook:getEntry(132).canTargetParty, true, "Detect Invisibility is party-castable");
    lu.assertEquals(Spellbook:getEntry(27230).itemID, 22105);
end

function testGetEquipItem()
    -- Arrange
    -- Act
    local master = W:getEquipItem(22646);
    local missing = W:getEquipItem(99999);
    -- Assert
    lu.assertEquals(master.name, "Master Spellstone");
    lu.assertIsNil(missing);
end

function testEquipItemsCatalog()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(#W.equipItems, 4);
    lu.assertEquals(W.equipItems[1].itemID, 5522);
    lu.assertEquals(W.equipItems[4].itemID, 22646);
end

-- ---- WorkflowSpellbook rebuild (the live spellbook scan was REMOVED
-- 2026-08-24 — the probe-based scan never actually ran. The catalog is
-- rebuilt from the static data: full catalog for a Warlock, empty for other
-- classes.) ----

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
end

-- ---- SpellbookCatalogBuilder / WarlockCatalogExtender (refactor Phase 7) ----

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
    local spells = ACP.Data.Workflows.spells;
    ACP.Data.Workflows.spells = nil;
    ACP.SpellbookCatalogBuilder:addEntry(spellbook, 999007, "Fel Armor", "");
    ACP.Data.Workflows.spells = spells;
    ACP.SpellbookCatalogBuilder:addEntry(spellbook, 999008, "Fel Armor", "");
    local group = ACP.SpellbookCatalogBuilder:getGroup(spellbook, "Fel Armor");
    lu.assertEquals(group.category, "buffs");
    ACP.SpellbookCatalogBuilder:reset(spellbook);
end

function testMergeStaticWarlockGatedForOtherClasses()
    -- Both static extensions are no-ops for a non-Warlock.
    local spellbook = ACP.WorkflowSpellbook;
    ACP.SpellbookCatalogBuilder:reset(spellbook);
    _G.UnitClass = function() return "Mage", "MAGE" end;
    ACP.WarlockCatalogExtender:mergeStaticWarlock(spellbook);
    ACP.WarlockCatalogExtender:addStaticFallback(spellbook);
    lu.assertEquals(ACP.SpellbookCatalogBuilder:countEntries(spellbook), 0);
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    ACP.SpellbookCatalogBuilder:reset(spellbook);
end
