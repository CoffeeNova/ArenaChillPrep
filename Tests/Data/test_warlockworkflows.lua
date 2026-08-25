-- ArenaChillPrep — Tests/Data/test_warlockworkflows.lua
-- Covers Data/WarlockWorkflows.lua: the Warlock spell catalog, stone ranks,
-- equip items and the five default workflows.

local ACP = _G.ACP;
local W = ACP.Data.WarlockWorkflows;

function testSpellsCatalogShape()
    lu.assertNotIsNil(W.spells.buffs);
    lu.assertNotIsNil(W.spells.summons);
    lu.assertNotIsNil(W.spells.pets);
    lu.assertNotIsNil(W.spells.createItem);
    lu.assertNotIsNil(W.spells.utility);
end

function testStoneRanksHealthstone()
    -- Arrange
    local count = 0;
    for _ in pairs(W.stoneRanks) do count = count + 1; end

    -- Assert: 6 healthstone ranks + Create Spellstone rank 4 only (ranks 1-3
    -- were REMOVED 2026-08-25 — no arena use, live tests showed ranks 2-3
    -- upgrade to Master anyway).
    lu.assertEquals(count, 7);
    lu.assertEquals(W.stoneRanks[27230].itemName, "Master Healthstone");
    lu.assertEquals(W.stoneRanks[11730].itemName, "Major Healthstone");
    lu.assertEquals(W.stoneRanks[28172].itemName, "Master Spellstone");
    lu.assertNil(W.stoneRanks[2362], "Create Spellstone rank 1 removed");
    lu.assertNil(W.stoneRanks[28171], "Create Spellstone rank 2 removed");
    lu.assertNil(W.stoneRanks[28173], "Create Spellstone rank 3 removed");
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

function testStoneRanksCarryAutotradeCategory()
    -- The rank entries map to the autotrade catalog category so
    -- WorkflowItemSteps can resolve the count-target setting.
    for _, rank in pairs(W.stoneRanks) do
        lu.assertEquals(rank.category, "healthstones");
    end
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
    -- WeakAurasTemplates TBC data); the catalog ships 19028.
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

function testDemonArmorCatalogEntryIsTbcMaxRank()
    -- Demon Armor used to ship as rank 1 (706), which the 2.5.6 client
    -- replaces in the spellbook at 70 — only the max rank 27260 is castable.
    local entry = nil;
    for _, list in pairs(W.spells) do
        for _, e in ipairs(list) do
            if (e.name == "Demon Armor") then
                entry = e;
            end
        end
    end

    lu.assertNotIsNil(entry);
    lu.assertEquals(entry.spellID, 27260);
    lu.assertEquals(entry.buffSpellID, 27260);
    lu.assertIsFalse(entry.canTargetParty);
end

function testRemovedSpellsAbsentFromCatalog()
    -- Create Soulstone (693) and Ritual of Summoning (698) were REMOVED
    -- (2026-08-25, user decision — no arena use / no such spell on this
    -- client). No spell entry may reference them.
    for _, list in pairs(W.spells) do
        for _, e in ipairs(list) do
            lu.assertNotEquals(e.spellID, 693, "Create Soulstone removed");
            lu.assertNotEquals(e.spellID, 698, "Ritual of Summoning removed");
        end
    end
end

function testStoneRanksCreateStepLabel()
    -- Arrange / Act / Assert: the rank is appended explicitly (GetSpellInfo
    -- returns the unranked base name on 20506, so the catalog rank disambiguates).
    lu.assertEquals(ACP.WorkflowSpellbook:stoneStepLabel(W.stoneRanks[6201]), "Create Healthstone (rank 1)");
    lu.assertEquals(ACP.WorkflowSpellbook:stoneStepLabel(W.stoneRanks[11730]), "Create Healthstone (rank 5)");
    lu.assertEquals(ACP.WorkflowSpellbook:stoneStepLabel(W.stoneRanks[27230]), "Create Healthstone (rank 6)");
end

function testEquipItemsCatalog()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(#W.equipItems, 4);
    lu.assertEquals(W.equipItems[1].itemID, 5522);
    lu.assertEquals(W.equipItems[4].itemID, 22646);
end

function testGetEquipItem()
    -- Arrange
    -- Act
    local master = ACP.Data.Workflows:getEquipItem(22646);
    local missing = ACP.Data.Workflows:getEquipItem(99999);
    -- Assert
    lu.assertNotIsNil(master);
    lu.assertEquals(master.name, "Master Spellstone");
    lu.assertIsNil(missing);
end

function testDefaultDefinitionsFiveSlots()
    for slot = 1, 5 do
        lu.assertNotIsNil(W.defaultDefinitions[slot], ("slot %d"):format(slot));
        lu.assertIsTrue(W.defaultDefinitions[slot].enabled);
        lu.assertIsTrue(type(W.defaultDefinitions[slot].steps) == "table");
        lu.assertIsTrue(#W.defaultDefinitions[slot].steps > 0);
    end

    lu.assertIsNil(W.defaultDefinitions[6]);
end

-- Slot 1 is the user's battle-tested "2s with sacrifice" workflow.
function testDefaultWorkflow1Macro()
    -- Arrange
    -- Act
    local def = W.defaultDefinitions[1];
    -- Assert
    lu.assertEquals(def.enabled, true);
    lu.assertEquals(def.name, "2s with sacrifice");
    lu.assertEquals(#def.steps, 19);
    lu.assertEquals(def.steps[1].type, "summon");
    lu.assertEquals(def.steps[1].spellID, 688);
    lu.assertEquals(def.steps[2].type, "createItem");
    lu.assertEquals(def.steps[2].spellID, 27230);
    lu.assertEquals(def.steps[2].itemID, 22105);
    lu.assertEquals(def.steps[4].type, "pet");
    lu.assertEquals(def.steps[4].spellID, 27269);
    lu.assertEquals(def.steps[4].target, "player");
    lu.assertEquals(def.steps[7].type, "summon");
    lu.assertEquals(def.steps[7].spellID, 697);
    lu.assertEquals(def.steps[10].type, "equipItem");
    lu.assertEquals(def.steps[10].itemID, 22646);
    lu.assertEquals(def.steps[10].itemName, "Master Spellstone");
    lu.assertEquals(def.steps[16].type, "summon");
    lu.assertEquals(def.steps[16].spellID, 691);
    lu.assertEquals(def.steps[17].type, "pet");
    lu.assertEquals(def.steps[17].spellName, "Sacrifice");
    lu.assertEquals(def.steps[17].spellID, 7812);
    lu.assertEquals(def.steps[18].spellID, 19028);
    lu.assertNil(def.steps[18].skipIfBuffed);
    lu.assertEquals(def.steps[19].spellID, 28610);
end

-- Slot 2 is the user's battle-tested "2s no sacrifice" workflow (ships enabled).
function testDefaultWorkflow2Macro()
    -- Arrange
    -- Act
    local def = W.defaultDefinitions[2];
    -- Assert
    lu.assertEquals(def.enabled, true);
    lu.assertEquals(def.name, "2s no sacrifice");
    lu.assertEquals(#def.steps, 15);
    lu.assertEquals(def.steps[1].spellID, 688);
    lu.assertNil(def.steps[1].skipIfBuffed);
    lu.assertEquals(def.steps[6].type, "summon");
    lu.assertEquals(def.steps[6].spellID, 691);
    lu.assertEquals(def.steps[10].type, "equipItem");
    lu.assertEquals(def.steps[10].itemID, 22646);
    lu.assertEquals(def.steps[15].spellID, 28610);
end
