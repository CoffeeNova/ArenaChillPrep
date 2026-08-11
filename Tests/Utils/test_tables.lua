-- ArenaChillPrep — Tests/Utils/test_tables.lua
-- Covers Utils/Tables.lua: deepMerge + shallowCopy.

local ACP = _G.ACP;
local Tables = ACP.Utils.Tables;

function testDeepMergeAddsNewKeys()
    -- Arrange
    local target = { a = 1 };
    local source = { b = 2 };
    -- Act
    Tables:deepMerge(target, source);
    -- Assert
    lu.assertEquals(target.a, 1);
    lu.assertEquals(target.b, 2);
end

function testDeepMergeOverwritesScalars()
    -- Arrange
    local target = { a = 1 };
    local source = { a = 2 };
    -- Act
    Tables:deepMerge(target, source);
    -- Assert
    lu.assertEquals(target.a, 2);
end

function testDeepMergeRecursesTables()
    -- Arrange
    local target = { items = { count = 1 } };
    local source = { items = { ranks = { [22105] = true } } };
    -- Act
    Tables:deepMerge(target, source);
    -- Assert
    lu.assertEquals(target.items.count, 1);
    lu.assertIsTrue(target.items.ranks[22105]);
end

function testDeepMergeReturnsTarget()
    -- Arrange
    local target = {};
    -- Act
    local result = Tables:deepMerge(target, { x = 1 });
    -- Assert
    lu.assertIs(result, target);
end

function testShallowCopy()
    -- Arrange
    local source = { a = 1, nested = { b = 2 } };
    -- Act
    local copy = Tables:shallowCopy(source);
    -- Assert
    lu.assertEquals(copy.a, 1);
    lu.assertIs(copy.nested, source.nested);
    lu.assertNotIs(copy, source);
end