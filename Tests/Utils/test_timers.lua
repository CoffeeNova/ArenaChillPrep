-- ArenaChillPrep — Tests/Utils/test_timers.lua
-- Covers Utils/Timers.lua: after/interval/cancel + stale-callback guard.
--
-- Other suites swap ACP.Utils.Timers for the sync recorder, so every test
-- here re-installs the REAL Timers module first.
local ACP = _G.ACP;
local Timers = ACP.Utils.Timers;

local function resetTimers()
    ACP.Utils.Timers = Timers;
    Timers.Handles = {};
    _G.__stub.cTimerCallbacks = {};
end

function testAfterRunsCallback()
    -- Arrange
    resetTimers();
    local ran = false;
    -- Act
    Timers:after("T", 1.5, function()
        ran = true;
    end);
    local entry = _G.__stub.cTimerCallbacks[1];
    entry.cb();
    -- Assert
    lu.assertIsTrue(ran);
    lu.assertIsNil(Timers.Handles["T"]);
end

function testAfterCancelPreventsCallback()
    -- Arrange
    resetTimers();
    local ran = false;
    -- Act
    Timers:after("T", 1.5, function()
        ran = true;
    end);
    Timers:cancel("T");
    _G.__stub.cTimerCallbacks[1].cb();
    -- Assert
    lu.assertIsFalse(ran);
end

function testAfterSameNameReplaces()
    -- Arrange
    resetTimers();
    local first = false;
    local second = false;
    -- Act
    Timers:after("T", 1, function()
        first = true;
    end);
    Timers:after("T", 1, function()
        second = true;
    end);
    _G.__stub.cTimerCallbacks[1].cb();
    _G.__stub.cTimerCallbacks[2].cb();
    -- Assert
    lu.assertIsFalse(first);
    lu.assertIsTrue(second);
end

function testIntervalRunsRepeatedly()
    -- Arrange
    resetTimers();
    local count = 0;
    -- Act
    Timers:interval("I", 0.5, function()
        count = count + 1;
    end);
    _G.__stub.cTimerCallbacks[1].cb();
    _G.__stub.cTimerCallbacks[1].cb();
    -- Assert
    lu.assertEquals(count, 2);
end

function testIntervalCancelStops()
    -- Arrange
    resetTimers();
    local count = 0;
    -- Act
    Timers:interval("I", 0.5, function()
        count = count + 1;
    end);
    Timers:cancel("I");
    _G.__stub.cTimerCallbacks[1].cb();
    -- Assert
    lu.assertEquals(count, 0);
end

function testCancelMissingIsNoop()
    -- Arrange
    resetTimers();
    -- Act
    Timers:cancel("Nope");
    -- Assert
    lu.assertIsNil(Timers.Handles["Nope"]);
end
