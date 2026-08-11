-- ArenaChillPrep — Tests/Classes/test_arenaprep.lua
-- Covers Classes/ArenaPrep.lua: buff scan, countdown, remaining time,
-- bracket, party size, partner lookup.

local ACP = _G.ACP;
local ArenaPrep = ACP.ArenaPrep;
local H = dofile(_G.__TESTS_ROOT .. "/helpers.lua");

local function resetArenaPrep()
    ArenaPrep.buffActive = false;
    ArenaPrep.buffExpirationTime = nil;
    ArenaPrep.countdownEndTime = nil;
    ArenaPrep.bracket = nil;
    ACP.Utils.Timers.Handles = {};
    _G.__stub.cTimerCallbacks = {};
end

function testScanBuffPrimary()
    -- Arrange
    _G.__stub.aura = { expirationTime = 100 };
    -- Act
    local active, exp = ArenaPrep:scanBuff();
    -- Assert
    lu.assertIsTrue(active);
    lu.assertEquals(exp, 100);
end

function testScanBuffAbsent()
    -- Arrange
    _G.__stub.aura = nil;
    -- Act
    local active = ArenaPrep:scanBuff();
    -- Assert
    lu.assertIsFalse(active);
end

function testScanBuffFallback()
    -- Arrange: reload the module so it captures the nil primary lookup.
    _G.C_UnitAuras.GetPlayerAuraBySpellID = nil;
    _G.__stub.auraByIndex = { spellId = 32727, expirationTime = 50 };
    local H = dofile(_G.__TESTS_ROOT .. "/helpers.lua");
    H.reloadModule("Classes/ArenaPrep.lua");
    local Reloaded = ACP.ArenaPrep;
    -- Act
    local active, exp = Reloaded:scanBuff();
    -- Assert
    lu.assertIsTrue(active);
    lu.assertEquals(exp, 50);
    -- Restore the primary lookup + reload again so the module is pristine.
    _G.C_UnitAuras.GetPlayerAuraBySpellID = function() return _G.__stub.aura end;
    H.reloadModule("Classes/ArenaPrep.lua");
    -- Re-apply the runner's init so event registrations survive.
    ACP.ArenaPrep:_init();
end

function testCheckNowGainFiresEvent()
    -- Arrange
    resetArenaPrep();
    _G.__stub.aura = { expirationTime = 100 };
    _G.__stub.inInstance = { true, "arena" };
    _G.__stub.partyCount = 1;
    local gained = false;
    ACP.Events:register("t.gain", "ACP_BUFF_GAINED", function() gained = true; end);
    -- Act
    ArenaPrep:checkNow();
    -- Assert
    lu.assertIsTrue(gained);
    lu.assertIsTrue(ArenaPrep:isActive());
    lu.assertEquals(ArenaPrep.bracket, "2v2");
    ACP.Events:unregister("t.gain");
end

function testCheckNowLossFiresEvent()
    -- Arrange
    resetArenaPrep();
    ArenaPrep.buffActive = true;
    _G.__stub.aura = nil;
    local lost = false;
    ACP.Events:register("t.lost", "ACP_BUFF_LOST", function() lost = true; end);
    -- Act
    ArenaPrep:checkNow();
    -- Assert
    lu.assertIsTrue(lost);
    lu.assertIsFalse(ArenaPrep:isActive());
    ACP.Events:unregister("t.lost");
end

function testHandleCountdownMessage()
    -- Arrange
    resetArenaPrep();
    _G.__stub.time = 100;
    -- Act
    ArenaPrep:handleCountdownMessage("Thirty seconds until the Arena battle begins!");
    -- Assert
    lu.assertEquals(ArenaPrep.countdownEndTime, 130);
end

function testHandleCountdownUnknownMessage()
    -- Arrange
    resetArenaPrep();
    -- Act
    ArenaPrep:handleCountdownMessage("gibberish");
    -- Assert
    lu.assertIsNil(ArenaPrep.countdownEndTime);
end

function testGetRemainingTimeFromCountdown()
    -- Arrange
    resetArenaPrep();
    _G.__stub.time = 100;
    ArenaPrep.countdownEndTime = 130;
    -- Act
    local remaining = ArenaPrep:getRemainingTime();
    -- Assert
    lu.assertEquals(remaining, 30);
end

function testGetRemainingTimeClamped()
    -- Arrange
    resetArenaPrep();
    _G.__stub.time = 200;
    ArenaPrep.countdownEndTime = 130;
    -- Act
    local remaining = ArenaPrep:getRemainingTime();
    -- Assert
    lu.assertEquals(remaining, 0);
end

function testGetRemainingTimeFromAura()
    -- Arrange
    resetArenaPrep();
    _G.__stub.time = 100;
    ArenaPrep.buffExpirationTime = 120;
    -- Act
    local remaining = ArenaPrep:getRemainingTime();
    -- Assert
    lu.assertEquals(remaining, 20);
end

function testGetRemainingTimeUnknown()
    -- Arrange
    resetArenaPrep();
    -- Act
    local remaining = ArenaPrep:getRemainingTime();
    -- Assert
    lu.assertIsNil(remaining);
end

function testIsInArena()
    -- Arrange
    _G.__stub.inInstance = { true, "arena" };
    -- Act
    -- Assert
    lu.assertIsTrue(ArenaPrep:isInArena());
    _G.__stub.inInstance = { true, "party" };
    lu.assertIsFalse(ArenaPrep:isInArena());
end

function testGetInstanceType()
    -- Arrange
    _G.__stub.inInstance = { true, "arena" };
    -- Act
    -- Assert
    lu.assertEquals(ArenaPrep:getInstanceType(), "arena");
end

function testGetPartySize()
    -- Arrange
    _G.__stub.partyCount = 2;
    -- Act
    -- Assert
    lu.assertEquals(ArenaPrep:getPartySize(), 2);
end

function testFindPartyUnitByName()
    -- Arrange
    _G.__stub.partyCount = 2;
    _G.UnitName = function(unit)
        if (unit == "party1") then return "Alice"; end
        if (unit == "party2") then return "Bob"; end
        return "Player";
    end;
    -- Act
    local unit = ArenaPrep:findPartyUnitByName("Bob");
    -- Assert
    lu.assertEquals(unit, "party2");
    _G.UnitName = function() return "Player" end;
end

function testFindPartyUnitByNameMissing()
    -- Arrange
    _G.__stub.partyCount = 1;
    _G.UnitName = function() return "Player" end;
    -- Act
    local unit = ArenaPrep:findPartyUnitByName("Nobody");
    -- Assert
    lu.assertIsNil(unit);
end

function testComputeBracket()
    -- Arrange
    _G.__stub.inInstance = { true, "arena" };
    _G.__stub.partyCount = 2;
    -- Act
    local bracket = ArenaPrep:computeBracket();
    -- Assert
    lu.assertEquals(bracket, "3v3");
end

function testComputeBracketOutsideArena()
    -- Arrange
    _G.__stub.inInstance = { false, "none" };
    -- Act
    local bracket = ArenaPrep:computeBracket();
    -- Assert
    lu.assertIsNil(bracket);
end

-- ---- event-driven handlers (registered in _init) ----

local function reinitArenaPrep()
    H.resetAll();
    ArenaPrep._initialized = false;
    ArenaPrep:_init();
end

function testUnitAuraEventFiresCheckNow()
    -- Arrange
    reinitArenaPrep();
    resetArenaPrep();
    _G.__stub.aura = { expirationTime = 100 };
    _G.__stub.inInstance = { true, "arena" };
    _G.__stub.partyCount = 1;
    -- Act
    ACP.Events:fire("UNIT_AURA", "player");
    -- Assert
    lu.assertIsTrue(ArenaPrep:isActive());
end

function testUnitAuraEventOtherUnitIgnored()
    -- Arrange
    reinitArenaPrep();
    resetArenaPrep();
    _G.__stub.aura = { expirationTime = 100 };
    -- Act
    ACP.Events:fire("UNIT_AURA", "party1");
    -- Assert
    lu.assertIsFalse(ArenaPrep:isActive());
end

function testPlayerEnteringWorldFiresCheckNow()
    -- Arrange
    reinitArenaPrep();
    resetArenaPrep();
    _G.__stub.aura = { expirationTime = 100 };
    _G.__stub.inInstance = { true, "arena" };
    _G.__stub.partyCount = 1;
    -- Act
    ACP.Events:fire("PLAYER_ENTERING_WORLD");
    -- Assert
    lu.assertIsTrue(ArenaPrep:isActive());
end

function testCountdownMessageEvent()
    -- Arrange
    reinitArenaPrep();
    resetArenaPrep();
    _G.__stub.time = 100;
    -- Act
    ACP.Events:fire("CHAT_MSG_BG_SYSTEM_NEUTRAL", "Thirty seconds until the Arena battle begins!");
    -- Assert
    lu.assertEquals(ArenaPrep.countdownEndTime, 130);
end

function testStartTickerSchedulesInterval()
    -- Arrange
    resetArenaPrep();
    ACP.Utils.Timers.Handles = {};
    -- Act
    ArenaPrep:startTicker();
    -- Assert
    lu.assertNotIsNil(ACP.Utils.Timers.Handles["ArenaPrepTick"]);
end

function testStopTickerCancels()
    -- Arrange
    resetArenaPrep();
    ACP.Utils.Timers.Handles["ArenaPrepTick"] = { cb = function() end };
    -- Act
    ArenaPrep:stopTicker();
    -- Assert
    lu.assertIsNil(ACP.Utils.Timers.Handles["ArenaPrepTick"]);
end

function testCheckNowStartsTickerWhenActive()
    -- Arrange
    resetArenaPrep();
    _G.__stub.aura = { expirationTime = 100 };
    _G.__stub.inInstance = { true, "arena" };
    _G.__stub.partyCount = 1;
    -- Act
    ArenaPrep:checkNow();
    -- Assert
    lu.assertNotIsNil(ACP.Utils.Timers.Handles["ArenaPrepTick"]);
end

function testCheckNowStopsTickerWhenInactive()
    -- Arrange
    resetArenaPrep();
    _G.__stub.aura = nil;
    ACP.Utils.Timers.Handles["ArenaPrepTick"] = { cb = function() end };
    -- Act
    ArenaPrep:checkNow();
    -- Assert
    lu.assertIsNil(ACP.Utils.Timers.Handles["ArenaPrepTick"]);
end

function testComputeBracketMismatchLogs()
    -- Arrange
    _G.__stub.inInstance = { true, "arena" };
    _G.__stub.partyCount = 2;
    _G.GetNumArenaOpponents = function() return 4 end; -- 5v5 vs partySize 3
    _G.__stub.chatMessages = {};
    ACP.debug = true;
    -- Act
    local bracket = ArenaPrep:computeBracket();
    -- Assert
    lu.assertEquals(bracket, "3v3");
    lu.assertEquals(#_G.__stub.chatMessages, 1);
    ACP.debug = false;
    _G.GetNumArenaOpponents = function() return 0 end;
end