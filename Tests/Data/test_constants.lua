-- ArenaChillPrep — Tests/Data/test_constants.lua
-- Covers Data/Constants.lua: static values.

local ACP = _G.ACP;
local C = ACP.Data.Constants;

function testConstantsPrepSpell()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(C.ARENA_PREP_SPELL_ID, 32727);
    lu.assertEquals(C.ARENA_PREP_SECONDS, 60);
end

function testConstantsCountdownMessages()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(C.ARENA_COUNTDOWN_MESSAGES["One minute until the Arena battle begins!"], 60);
    lu.assertEquals(C.ARENA_COUNTDOWN_MESSAGES["Thirty seconds until the Arena battle begins!"], 30);
    lu.assertEquals(C.ARENA_COUNTDOWN_MESSAGES["The Arena battle has begun!"], 0);
    lu.assertEquals(C.ARENA_COUNTDOWN_MESSAGES["Битва на арене началась!"], 0);
end

function testConstantsTrade()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(C.TRADE_OPEN_TIMEOUT, 1.0);
    lu.assertEquals(C.TRADE_ITEM_TICK, 0.15);
    lu.assertEquals(C.RETRY_BACKOFF, { 2, 4, 8, 12, 16 });
end

function testConstantsBrackets()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(C.BRACKET_BY_SIZE[2], "2v2");
    lu.assertEquals(C.BRACKET_BY_SIZE[3], "3v3");
    lu.assertEquals(C.BRACKET_BY_SIZE[5], "5v5");
    lu.assertIsNil(C.BRACKET_BY_SIZE[4]);
end

function testConstantsBagsAndTick()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(C.NUM_BAGS, 5);
    lu.assertEquals(C.BUFF_CHECK_TICK, 1.0);
end

function testConstantsWorkflowSteps()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(C.WORKFLOW_STEP_CAST, "cast");
    lu.assertEquals(C.WORKFLOW_STEP_SUMMON, "summon");
    lu.assertEquals(C.WORKFLOW_STEP_CREATE_ITEM, "createItem");
    lu.assertEquals(C.WORKFLOW_STEP_EQUIP_ITEM, "equipItem");
    lu.assertEquals(C.WORKFLOW_DEFAULT_SLOTS, 5);
    lu.assertEquals(C.WORKFLOW_MAX_SLOTS, 20);
end