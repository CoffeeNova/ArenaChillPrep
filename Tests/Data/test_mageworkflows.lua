-- ArenaChillPrep — Tests/Data/test_mageworkflows.lua
-- Covers Data/MageWorkflows.lua: the Mage spell catalog, conjured ranks and
-- the five default workflows.

local ACP = _G.ACP;
local M = ACP.Data.MageWorkflows;

function testSpellsCatalogShape()
    lu.assertNotIsNil(M.spells.buffs);
    lu.assertNotIsNil(M.spells.createItem);
    lu.assertNotIsNil(M.spells.utility);
    lu.assertIsNil(M.spells.summons, "Mage has no summons");
    lu.assertIsNil(M.spells.pets, "Mage has no pet abilities");
    lu.assertIsNil(M.equipItems, "Mage has no equippable conjured items");
end

function testBuffsCatalog()
    local count = 0;

    for _, entry in ipairs(M.spells.buffs) do
        count = count + 1;
        lu.assertIsFalse(entry.isCastTime, entry.name .. " must be instant");
        lu.assertNotNil(entry.buffSpellID, entry.name .. " must carry buffSpellID");
    end

    lu.assertEquals(count, 13);
end

function testAmplifyDampenBothRanksShip()
    -- Both ranks of Amplify/Dampen Magic ship as separate entries (same
    -- name) with a rank field so the Add Step menu lists each one.
    local function ranks(name)
        local found = {};

        for _, entry in ipairs(M.spells.buffs) do
            if (entry.name == name) then
                found[#found + 1] = { id = entry.spellID, rank = entry.rank };
            end
        end

        return found;
    end

    local amplify = ranks("Amplify Magic");
    local dampen = ranks("Dampen Magic");

    lu.assertEquals(#amplify, 2);
    lu.assertEquals(amplify[1].id, 33946);
    lu.assertEquals(amplify[1].rank, 6);
    lu.assertEquals(amplify[2].id, 1008);
    lu.assertEquals(amplify[2].rank, 1);

    lu.assertEquals(#dampen, 2);
    lu.assertEquals(dampen[1].id, 33944);
    lu.assertEquals(dampen[1].rank, 6);
    lu.assertEquals(dampen[2].id, 604);
    lu.assertEquals(dampen[2].rank, 1);
end

function testUserVerifiedBuffs()
    -- IDs live-verified by the user (2026-08-25): Molten Armor 30482,
    -- Invisibility 66; Frost Armor was REPLACED by Ice Armor (rank 5).
    local function entry(spellID)
        for _, e in ipairs(M.spells.buffs) do
            if (e.spellID == spellID) then
                return e;
            end
        end

        return nil;
    end

    lu.assertNotIsNil(entry(30482), "Molten Armor 30482");
    lu.assertEquals(entry(30482).name, "Molten Armor");
    lu.assertNotIsNil(entry(66), "Invisibility 66");
    lu.assertEquals(entry(66).name, "Invisibility");
    lu.assertNotIsNil(entry(27124), "Ice Armor 27124");
    lu.assertEquals(entry(27124).name, "Ice Armor");
    lu.assertIsNil(entry(7301), "Frost Armor removed");
    lu.assertIsNil(entry(34913), "Molten Armor 34913 removed");
    lu.assertIsNil(entry(32612), "Invisibility 32612 removed");
end

function testPartyCastableBuffs()
    -- Arcane Intellect / Amplify / Dampen are party-targeted; armors, wards
    -- and barriers are self-only.
    local function partyCastable(name)
        for _, entry in ipairs(M.spells.buffs) do
            if (entry.spellID == name) then
                return entry.canTargetParty;
            end
        end

        return nil;
    end

    lu.assertIsTrue(partyCastable(27126), "Arcane Intellect");
    lu.assertIsTrue(partyCastable(33946), "Amplify Magic");
    lu.assertIsTrue(partyCastable(33944), "Dampen Magic");
    lu.assertIsFalse(partyCastable(27127), "Arcane Brilliance is group-wide");
    lu.assertIsFalse(partyCastable(27125), "Mage Armor");
    lu.assertIsFalse(partyCastable(33405), "Ice Barrier");
end

function testCreateItemCatalog()
    local function entry(spellID)
        for _, e in ipairs(M.spells.createItem) do
            if (e.spellID == spellID) then
                return e;
            end
        end

        return nil;
    end

    local food = entry(33717);
    local water = entry(27090);
    local emerald = entry(27101);

    lu.assertNotIsNil(food);
    lu.assertEquals(food.name, "Conjure Food");
    lu.assertEquals(food.itemID, 22019);
    lu.assertIsTrue(food.isCastTime);
    lu.assertIsFalse(food.needsShard);

    lu.assertNotIsNil(water);
    lu.assertEquals(water.name, "Conjure Water");
    lu.assertEquals(water.itemID, 22018);
    lu.assertIsTrue(water.isCastTime);
    lu.assertIsFalse(water.needsShard);

    lu.assertNotIsNil(emerald, "Conjure Mana Emerald");
    lu.assertEquals(emerald.name, "Conjure Mana Emerald");
    lu.assertEquals(emerald.itemID, 22044);
    lu.assertIsTrue(emerald.isCastTime);
    lu.assertIsFalse(emerald.needsShard);
    lu.assertEquals(#M.spells.createItem, 3);
end

function testUtilityRitualOfRefreshment()
    -- Conjures a table on the ground (like Ritual of Souls) — no bag item.
    local ritual = M.spells.utility[1];

    lu.assertEquals(ritual.spellID, 43987);
    lu.assertEquals(ritual.name, "Ritual of Refreshment");
    lu.assertIsNil(ritual.itemID);
end

function testConjuredRanks()
    -- Single itemID per rank (unlike healthstone ID pairs); the category
    -- maps to the autotrade settings key.
    lu.assertEquals(M.conjuredRanks[33717].spellName, "Conjure Food");
    lu.assertEquals(M.conjuredRanks[33717].category, "food");
    lu.assertEquals(M.conjuredRanks[33717].itemID, 22019);
    lu.assertEquals(M.conjuredRanks[33717].itemIDs[1], 22019);
    lu.assertEquals(#M.conjuredRanks[33717].itemIDs, 1);
    lu.assertEquals(M.conjuredRanks[33717].itemName, "Conjured Croissant");
    lu.assertEquals(M.conjuredRanks[33717].rank, 8);

    lu.assertEquals(M.conjuredRanks[27090].spellName, "Conjure Water");
    lu.assertEquals(M.conjuredRanks[27090].category, "water");
    lu.assertEquals(M.conjuredRanks[27090].itemID, 22018);
    lu.assertEquals(M.conjuredRanks[27090].itemName, "Conjured Glacier Water");
    lu.assertEquals(M.conjuredRanks[27090].rank, 9);
end

function testDefaultDefinitionsFiveSlots()
    for slot = 1, 5 do
        lu.assertNotIsNil(M.defaultDefinitions[slot], ("slot %d"):format(slot));
        lu.assertIsTrue(M.defaultDefinitions[slot].enabled);
        lu.assertIsTrue(#M.defaultDefinitions[slot].steps > 0);
    end

    lu.assertIsNil(M.defaultDefinitions[6]);
end

function testDefaultWorkflowsOpenings()
    -- 2v2 slots open with 2x water + 2x food (10 per cast → 20 = the default
    -- autotrade count); 3s/5s slots open with the Ritual of Refreshment cast.
    for slot = 1, 2 do
        local steps = M.defaultDefinitions[slot].steps;
        lu.assertEquals(steps[1].type, "createItem", ("slot %d step 1"):format(slot));
        lu.assertEquals(steps[1].spellID, 27090);
        lu.assertEquals(steps[2].spellID, 27090);
        lu.assertEquals(steps[3].spellID, 33717);
        lu.assertEquals(steps[4].spellID, 33717);
    end

    for slot = 3, 5 do
        local first = M.defaultDefinitions[slot].steps[1];
        lu.assertEquals(first.type, "cast", ("slot %d step 1"):format(slot));
        lu.assertEquals(first.spellID, 43987);
        lu.assertEquals(first.target, "player");
    end
end

function testDefaultWorkflowNames()
    lu.assertEquals(M.defaultDefinitions[1].name, "2s standard");
    lu.assertEquals(M.defaultDefinitions[2].name, "2s with healer");
    lu.assertEquals(M.defaultDefinitions[3].name, "3s standard");
    lu.assertEquals(M.defaultDefinitions[4].name, "3s pom pyro");
    lu.assertEquals(M.defaultDefinitions[5].name, "5s standard");
end

function testClassWorkflowsAccessor()
    lu.assertEquals(ACP.Data.classWorkflows("MAGE"), M);
    lu.assertEquals(ACP.Data.classWorkflows("WARLOCK"), ACP.Data.WarlockWorkflows);
    lu.assertIsNil(ACP.Data.classWorkflows("HUNTER"));
    lu.assertIsNil(ACP.Data.classWorkflows(nil));
end

function testClassDataIsolation()
    -- Editing one class's data never touches the other.
    local function hasSpellName(data, name)
        for _, list in pairs(data.spells) do
            for _, entry in ipairs(list) do
                if (entry.name == name) then
                    return true;
                end
            end
        end

        return false;
    end

    lu.assertIsFalse(hasSpellName(M, "Summon Imp"), "Mage has no Warlock summons");
    lu.assertIsFalse(hasSpellName(M, "Create Healthstone"), "Mage has no Warlock stones");
    lu.assertIsFalse(hasSpellName(ACP.Data.WarlockWorkflows, "Conjure Water"), "Warlock has no Mage conjures");
    lu.assertIsFalse(hasSpellName(ACP.Data.WarlockWorkflows, "Arcane Intellect"), "Warlock has no Mage buffs");
end
