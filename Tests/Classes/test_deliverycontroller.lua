-- ArenaChillPrep — Tests/Classes/test_deliverycontroller.lua
-- Covers Classes/DeliveryController.lua: state machine, bracket gate,
-- givenTo, gate safety, retries, combat deferral.
--
-- The REAL ArenaPrep/Inventory methods are driven through _G.__stub and
-- module state (no method overrides → no cross-suite leakage). Only
-- ACP.Utils.Timers is swapped for the synchronous recorder and restored.
--
-- IMPORTANT: installStubs() copies State into the module state, so it must
-- be called AFTER setting the State fields (at the end of Arrange).

local ACP = _G.ACP;
local DC = ACP.DeliveryController;
local H = dofile(_G.__TESTS_ROOT .. "/helpers.lua");

-- ---- stubs ----
local State = {
    PartyCount = 0, Bracket = nil, Remaining = nil, BuffActive = false,
    Dead = false, InCombat = false, Counts = {}, LastTradeUnit = nil,
};

local OrigTimers = ACP.Utils.Timers;
local OrigInitiateTrade = _G.InitiateTrade;

local function installStubs()
    _G.__stub.inInstance = { true, "arena" };
    _G.__stub.inCombat = State.InCombat;
    _G.__stub.dead = State.Dead;
    _G.__stub.unitIsUnit = false;
    _G.__stub.partyCount = State.PartyCount;
    -- Stub startTrade directly (bypasses the real method's `trading` guard,
    -- which would otherwise leak state between tests).
    ACP.TradeManager.startTrade = function(_, unit) State.LastTradeUnit = unit; end;
    ACP.Utils.Timers = H.SyncTimers;
    -- Drive the real ArenaPrep through its state fields.
    ACP.ArenaPrep.bracket = State.Bracket;
    ACP.ArenaPrep.buffActive = State.BuffActive;
    ACP.ArenaPrep.countdownEndTime = State.Remaining and (_G.__stub.time + State.Remaining) or nil;
    ACP.ArenaPrep.buffExpirationTime = nil;
    -- Drive the real Inventory through its Counts cache.
    ACP.Inventory.Counts = State.Counts;
end

local function restoreStubs()
    ACP.Utils.Timers = OrigTimers;
    _G.InitiateTrade = OrigInitiateTrade;
end

local function resetController()
    DC:reset();
    H.SyncTimers.Handles = {};
    State.LastTradeUnit = nil;
end

local function readyCounts()
    return { [22105] = 1, [19012] = 1 };
end

-- ---- tests ----

function testSetState()
    -- Arrange
    DC.state = "IDLE";
    -- Act
    DC:setState("ACTIVE");
    -- Assert
    lu.assertEquals(DC.state, "ACTIVE");
end

function testReset()
    -- Arrange
    DC.state = "TRADING";
    DC.givenTo = { party1 = true };
    DC.currentPartner = "party1";
    DC.retryCount = 2;
    H.SyncTimers.Handles["TradeDelay"] = { cb = function() end };
    -- Act
    DC:reset();
    -- Assert
    lu.assertEquals(DC.state, "IDLE");
    lu.assertEquals(DC:givenCount(), 0);
    lu.assertIsNil(DC.currentPartner);
    lu.assertEquals(DC.retryCount, 0);
    lu.assertIsFalse(H.hasTimer("TradeDelay"));
end

function testBracketEnabled()
    -- Arrange
    ACP.Settings:set("brackets.2v2", true);
    ACP.Settings:set("brackets.3v3", false);
    -- Act
    -- Assert
    lu.assertIsTrue(DC:bracketEnabled("2v2"));
    lu.assertIsFalse(DC:bracketEnabled("3v3"));
end

function testGivenCount()
    -- Arrange
    DC.givenTo = { party1 = true, party2 = true };
    -- Act
    -- Assert
    lu.assertEquals(DC:givenCount(), 2);
end

function testGetCategories()
    -- Arrange
    local origUnitClass = _G.UnitClass;
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    -- Act
    local categories = DC:getCategories();
    -- Assert
    lu.assertItemsEquals(categories, { "healthstones" });
    _G.UnitClass = origUnitClass;
end

function testCategoryReady()
    -- Arrange
    State.Counts = readyCounts();
    local setting = { count = 1, ranks = { [19012] = true, [22105] = true } };
    installStubs();
    -- Act
    local ready = DC:categoryReady("healthstones", setting);
    -- Assert
    lu.assertIsTrue(ready);
end

function testCategoryReadyNotEnough()
    -- Arrange
    State.Counts = { [22105] = 1 };
    local setting = { count = 1, ranks = { [19012] = true, [22105] = true } };
    installStubs();
    -- Act
    local ready = DC:categoryReady("healthstones", setting);
    -- Assert
    lu.assertIsFalse(ready);
end

function testCategoryReadyNoSelection()
    -- Arrange
    State.Counts = readyCounts();
    local setting = { count = 1, ranks = {} };
    installStubs();
    -- Act
    local ready = DC:categoryReady("healthstones", setting);
    -- Assert
    lu.assertIsFalse(ready);
end

function testItemsReady()
    -- Arrange
    State.Counts = readyCounts();
    ACP.Settings:set("items.healthstone.enabled", true);
    installStubs();
    -- Act
    local ready = DC:itemsReady();
    -- Assert
    lu.assertIsTrue(ready);
end

function testItemsReadyDisabled()
    -- Arrange
    State.Counts = readyCounts();
    ACP.Settings:set("items.healthstone.enabled", false);
    installStubs();
    -- Act
    local ready = DC:itemsReady();
    -- Assert
    lu.assertIsFalse(ready);
    ACP.Settings:set("items.healthstone.enabled", true);
end

function testFindPartner()
    -- Arrange
    State.PartyCount = 2;
    DC.givenTo = {};
    installStubs();
    -- Act
    local partner = DC:findPartner();
    -- Assert
    lu.assertEquals(partner, "party1");
end

function testFindPartnerSkipsGiven()
    -- Arrange
    State.PartyCount = 2;
    DC.givenTo = { party1 = true };
    installStubs();
    -- Act
    local partner = DC:findPartner();
    -- Assert
    lu.assertEquals(partner, "party2");
end

function testFindPartnerNone()
    -- Arrange
    State.PartyCount = 0;
    DC.givenTo = {};
    installStubs();
    -- Act
    local partner = DC:findPartner();
    -- Assert
    lu.assertIsNil(partner);
end

function testFindPartnerSkipsSameClass()
    -- Arrange: all party members share the player's class and the
    -- "do not trade to same class" setting is on → no eligible partner.
    local origUnitClass = _G.UnitClass;
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    State.PartyCount = 2;
    DC.givenTo = {};
    installStubs();
    ACP.Settings:set("noTradeSameClass", true);
    -- Act
    local partner = DC:findPartner();
    -- Assert
    lu.assertIsNil(partner);
    _G.UnitClass = origUnitClass;
end

function testFindPartnerSameClassAllowedWhenDisabled()
    -- Arrange: same setup but the setting is off → partners are eligible.
    State.PartyCount = 2;
    DC.givenTo = {};
    installStubs();
    ACP.Settings:set("noTradeSameClass", false);
    -- Act
    local partner = DC:findPartner();
    -- Assert
    lu.assertEquals(partner, "party1");
    ACP.Settings:set("noTradeSameClass", true);
end

function testCanStartTrade()
    -- Arrange
    ACP.Settings:set("enabled", true);
    ACP.Settings:set("gateSafetySeconds", 15);
    State.Remaining = 45;
    State.Dead = false;
    State.InCombat = false;
    installStubs();
    -- Act
    local ok = DC:canStartTrade();
    -- Assert
    lu.assertIsTrue(ok);
end

function testCanStartTradeDisabled()
    -- Arrange
    ACP.Settings:set("enabled", false);
    installStubs();
    -- Act
    local ok = DC:canStartTrade();
    -- Assert
    lu.assertIsFalse(ok);
    ACP.Settings:set("enabled", true);
end

function testCanStartTradeGateSafety()
    -- Arrange
    ACP.Settings:set("enabled", true);
    ACP.Settings:set("gateSafetySeconds", 15);
    State.Remaining = 10;
    installStubs();
    -- Act
    local ok = DC:canStartTrade();
    -- Assert
    lu.assertIsFalse(ok);
end

function testCanStartTradeDead()
    -- Arrange
    ACP.Settings:set("enabled", true);
    State.Remaining = 45;
    State.Dead = true;
    installStubs();
    -- Act
    local ok = DC:canStartTrade();
    -- Assert
    lu.assertIsFalse(ok);
    State.Dead = false;
end

function testCanStartTradeCombat()
    -- Arrange
    ACP.Settings:set("enabled", true);
    State.Remaining = 45;
    State.InCombat = true;
    installStubs();
    -- Act
    local ok = DC:canStartTrade();
    -- Assert
    lu.assertIsFalse(ok);
    State.InCombat = false;
end

function testOnBuffGainedDisabledBracket()
    -- Arrange
    State.PartyCount = 2;
    State.Bracket = "3v3";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    ACP.Settings:set("brackets.3v3", false);
    installStubs();
    resetController();
    -- Act
    DC:onBuffGained();
    -- Assert
    lu.assertEquals(DC.state, "IDLE");
    lu.assertIsFalse(H.hasTimer("TradeDelay"));
end

function testOnBuffGainedSchedulesTrade()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    -- Act
    DC:onBuffGained();
    -- Assert
    lu.assertEquals(DC.state, "ACTIVE");
    lu.assertIsTrue(H.hasTimer("TradeDelay"));
end

function testOnBuffGainedUnknownBracketDefers()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = nil;
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    -- Act
    DC:onBuffGained();
    -- Assert
    lu.assertEquals(DC.state, "ACTIVE");
    lu.assertIsTrue(H.hasTimer("DeliveryCheck"));
end

function testTradeDelayFiresStartTrade()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    DC:onBuffGained();
    -- Act
    H.advance("TradeDelay");
    -- Assert
    lu.assertEquals(DC.state, "TRADING");
    lu.assertEquals(State.LastTradeUnit, "party1");
    lu.assertIsTrue(H.hasTimer("TradeOpen"));
end

function testOpenTimeoutFailsAndRetries()
    -- Arrange
    ACP.Settings:set("tradeRetries", 3);
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    DC:onBuffGained();
    H.advance("TradeDelay");
    -- Act
    H.advance("TradeOpen");
    -- Assert
    lu.assertEquals(DC.state, "ACTIVE");
    lu.assertIsTrue(H.hasTimer("TradeRetry"));
end

function testTradeCompletedMarksGiven()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    DC:onBuffGained();
    H.advance("TradeDelay");
    DC.currentPartner = "party1";
    -- Act
    DC:onTradeCompleted();
    -- Assert
    lu.assertIsTrue(DC.givenTo["party1"]);
    lu.assertEquals(DC.state, "DONE");
end

function testTradeCompletedManualNameNormalized()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    _G.UnitName = function(unit)
        if (unit == "party1") then return "Alice"; end
        return "Player";
    end;
    ACP.TradeManager.partnerUnit = "Alice";
    -- Act
    DC:onTradeCompleted();
    -- Assert
    lu.assertIsTrue(DC.givenTo["party1"]);
    _G.UnitName = function() return "Player" end;
end

function testTradeCompletedBuffLostStaysIdle()
    -- Arrange
    State.BuffActive = false;
    installStubs();
    resetController();
    DC.currentPartner = "party1";
    -- Act
    DC:onTradeCompleted();
    -- Assert
    lu.assertEquals(DC.state, "IDLE");
end

function testOnTradeFailedRetries()
    -- Arrange
    ACP.Settings:set("tradeRetries", 3);
    installStubs();
    resetController();
    DC:setState("TRADING");
    -- Act
    DC:onTradeFailed("closed");
    -- Assert
    lu.assertEquals(DC.state, "ACTIVE");
    lu.assertEquals(DC.retryCount, 1);
    lu.assertIsTrue(H.hasTimer("TradeRetry"));
end

function testOnTradeFailedStrayIgnored()
    -- Arrange
    installStubs();
    resetController();
    DC:setState("IDLE");
    -- Act
    DC:onTradeFailed("closed");
    -- Assert
    lu.assertEquals(DC.state, "IDLE");
    lu.assertIsFalse(H.hasTimer("TradeRetry"));
end

function testOnTradeFailedGivesUpAfterMax()
    -- Arrange
    installStubs();
    resetController();
    DC:setState("TRADING");
    DC.retryCount = 3;
    -- Act
    DC:onTradeFailed("closed");
    -- Assert
    lu.assertEquals(DC.retryCount, 0);
    lu.assertIsFalse(H.hasTimer("TradeRetry"));
end

function testOnCombatStartCancelsPending()
    -- Arrange
    installStubs();
    resetController();
    H.SyncTimers.Handles["TradeDelay"] = { cb = function() end };
    H.SyncTimers.Handles["TradeRetry"] = { cb = function() end };
    -- Act
    DC:onCombatStart();
    -- Assert
    lu.assertIsFalse(H.hasTimer("TradeDelay"));
    lu.assertIsFalse(H.hasTimer("TradeRetry"));
end

function testOnCombatEndResumes()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    DC:setState("ACTIVE");
    -- Act
    DC:onCombatEnd();
    -- Assert
    lu.assertIsTrue(H.hasTimer("TradeDelay"));
end

function testOnItemsChanged()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    DC:setState("ACTIVE");
    -- Act
    DC:onItemsChanged();
    -- Assert
    lu.assertIsTrue(H.hasTimer("TradeDelay"));
end

function testOnItemsChangedNotActive()
    -- Arrange
    installStubs();
    resetController();
    DC:setState("IDLE");
    -- Act
    DC:onItemsChanged();
    -- Assert
    lu.assertIsFalse(H.hasTimer("TradeDelay"));
end

function testShouldTakeOverInboundTrade()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.InCombat = false;
    installStubs();
    resetController();
    ACP.Settings:set("noTradeSameClass", false);
    DC:setState("ACTIVE");
    _G.UnitName = function(unit)
        if (unit == "party1") then return "Alice"; end
        return "Player";
    end;
    ACP.TradeManager.partnerUnit = "Alice";
    -- Act
    local ok = DC:shouldTakeOverInboundTrade();
    -- Assert
    lu.assertIsTrue(ok);
    ACP.Settings:set("noTradeSameClass", true);
    _G.UnitName = function() return "Player" end;
end

function testShouldTakeOverInboundTradeSameClassBlocked()
    -- Arrange
    local origUnitClass = _G.UnitClass;
    _G.UnitClass = function() return "Warlock", "WARLOCK" end;
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.InCombat = false;
    installStubs();
    resetController();
    ACP.Settings:set("noTradeSameClass", true);
    DC:setState("ACTIVE");
    _G.UnitName = function(unit)
        if (unit == "party1") then return "Alice"; end
        return "Player";
    end;
    ACP.TradeManager.partnerUnit = "Alice";
    -- Act: Alice shares the player's class (WARLOCK stub) → take-over blocked.
    local ok = DC:shouldTakeOverInboundTrade();
    -- Assert
    lu.assertIsFalse(ok);
    _G.UnitName = function() return "Player" end;
    _G.UnitClass = origUnitClass;
end

function testShouldTakeOverInboundTradeNotActive()
    -- Arrange
    installStubs();
    resetController();
    DC:setState("IDLE");
    ACP.TradeManager.partnerUnit = "Alice";
    -- Act
    local ok = DC:shouldTakeOverInboundTrade();
    -- Assert
    lu.assertIsFalse(ok);
end

function testShouldTakeOverInboundTradeNonTeammate()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    installStubs();
    resetController();
    DC:setState("ACTIVE");
    ACP.TradeManager.partnerUnit = "Stranger";
    -- Act
    local ok = DC:shouldTakeOverInboundTrade();
    -- Assert
    lu.assertIsFalse(ok);
end

function testShouldTakeOverInboundTradeCombat()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.InCombat = true;
    installStubs();
    resetController();
    DC:setState("ACTIVE");
    ACP.TradeManager.partnerUnit = "Alice";
    -- Act
    local ok = DC:shouldTakeOverInboundTrade();
    -- Assert
    lu.assertIsFalse(ok);
    State.InCombat = false;
end

function testOnTradeOpenedInbound()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    DC:setState("ACTIVE");
    ACP.TradeManager.partnerUnit = "Alice";
    H.SyncTimers.Handles["TradeDelay"] = { cb = function() end };
    -- Act
    DC:onTradeOpened("Alice");
    -- Assert
    lu.assertEquals(DC.currentPartner, "Alice");
    lu.assertEquals(DC.state, "TRADING");
    lu.assertIsFalse(H.hasTimer("TradeDelay"));
end

function testOnItemsChangedTradingRefillsQueue()
    -- Arrange
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    DC:setState("TRADING");
    _G.__stub.tradeFrameShown = true;
    ACP.Settings:set("items.healthstone.enabled", true);
    ACP.Settings:set("items.healthstone.count", 1);
    local origGetCount = ACP.Inventory.getCount;
    ACP.Inventory.getCount = function(_, itemID)
        if (itemID == 22105) then return 1; end
        return 0;
    end;
    -- Act
    DC:onItemsChanged();
    -- Assert
    lu.assertEquals(#ACP.TradeManager.ItemsToAdd, 1);
    ACP.Inventory.getCount = origGetCount;
    _G.__stub.tradeFrameShown = false;
end

-- ---- event-driven handlers (registered in _init) ----

local function reinitDC()
    H.resetAll();
    DC._initialized = false;
    DC:_init();
end

function testBuffGainedEvent()
    -- Arrange
    reinitDC();
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    -- Act
    ACP.Events:fire("ACP_BUFF_GAINED");
    -- Assert
    lu.assertEquals(DC.state, "ACTIVE");
    lu.assertIsTrue(H.hasTimer("TradeDelay"));
end

function testBuffLostEvent()
    -- Arrange
    reinitDC();
    installStubs();
    resetController();
    DC:setState("TRADING");
    -- Act
    ACP.Events:fire("ACP_BUFF_LOST");
    -- Assert
    lu.assertEquals(DC.state, "IDLE");
end

function testItemsChangedEvent()
    -- Arrange
    reinitDC();
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    DC:setState("ACTIVE");
    -- Act
    ACP.Events:fire("ACP_ITEMS_CHANGED");
    -- Assert
    lu.assertIsTrue(H.hasTimer("TradeDelay"));
end

function testTradeCompletedEvent()
    -- Arrange
    reinitDC();
    installStubs();
    resetController();
    DC.currentPartner = "party1";
    State.BuffActive = true;
    -- Act
    ACP.Events:fire("ACP_TRADE_COMPLETED");
    -- Assert
    lu.assertIsTrue(DC.givenTo["party1"]);
end

function testTradeOpenedEventCancelsTimeout()
    -- Arrange
    reinitDC();
    installStubs();
    resetController();
    H.SyncTimers.Handles["TradeOpen"] = { cb = function() end };
    -- Act
    ACP.Events:fire("ACP_TRADE_OPENED");
    -- Assert
    lu.assertIsFalse(H.hasTimer("TradeOpen"));
end

function testTradeFailedEvent()
    -- Arrange
    reinitDC();
    installStubs();
    resetController();
    ACP.Settings:set("tradeRetries", 3);
    DC:setState("TRADING");
    -- Act
    ACP.Events:fire("ACP_TRADE_FAILED", "closed");
    -- Assert
    lu.assertEquals(DC.state, "ACTIVE");
    lu.assertIsTrue(H.hasTimer("TradeRetry"));
end

function testCombatStartEvent()
    -- Arrange
    reinitDC();
    installStubs();
    resetController();
    H.SyncTimers.Handles["TradeDelay"] = { cb = function() end };
    -- Act
    ACP.Events:fire("PLAYER_REGEN_DISABLED");
    -- Assert
    lu.assertIsFalse(H.hasTimer("TradeDelay"));
end

function testCombatEndEvent()
    -- Arrange
    reinitDC();
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    DC:setState("ACTIVE");
    -- Act
    ACP.Events:fire("PLAYER_REGEN_ENABLED");
    -- Assert
    lu.assertIsTrue(H.hasTimer("TradeDelay"));
end

function testGroupRosterUpdateEvent()
    -- Arrange
    reinitDC();
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    installStubs();
    resetController();
    DC:setState("ACTIVE");
    -- Act
    ACP.Events:fire("GROUP_ROSTER_UPDATE");
    -- Assert
    lu.assertIsTrue(H.hasTimer("TradeDelay"));
end

function testGroupRosterUpdateNotActive()
    -- Arrange
    reinitDC();
    installStubs();
    resetController();
    DC:setState("IDLE");
    -- Act
    ACP.Events:fire("GROUP_ROSTER_UPDATE");
    -- Assert
    lu.assertIsFalse(H.hasTimer("TradeDelay"));
end

function testCheckReadyNotActive()
    -- Arrange
    installStubs();
    resetController();
    DC:setState("IDLE");
    -- Act
    DC:checkReady();
    -- Assert
    lu.assertIsFalse(H.hasTimer("TradeDelay"));
end

function testCheckReadyPileUpGuard()
    -- Arrange
    installStubs();
    resetController();
    DC:setState("ACTIVE");
    H.SyncTimers.Handles["TradeDelay"] = { cb = function() end };
    -- Act
    DC:checkReady();
    -- Assert
    lu.assertIsTrue(H.hasTimer("TradeDelay"));
end

function testCheckReadyDisabledBracketDropsToIdle()
    -- Arrange
    State.Bracket = "3v3";
    ACP.Settings:set("brackets.3v3", false);
    installStubs();
    resetController();
    DC:setState("ACTIVE");
    -- Act
    DC:checkReady();
    -- Assert
    lu.assertEquals(DC.state, "IDLE");
    -- Restore the default (Settings.Data shares defaults.brackets).
    ACP.Settings:set("brackets.3v3", false);
end

function testCheckReadyNoPartnerNoItems()
    -- Arrange
    State.PartyCount = 0;
    State.Bracket = "2v2";
    State.Counts = {};
    installStubs();
    resetController();
    DC:setState("ACTIVE");
    -- Act
    DC:checkReady();
    -- Assert
    lu.assertEquals(DC.state, "ACTIVE");
    lu.assertIsFalse(H.hasTimer("TradeDelay"));
end

function testStartCheckTicker()
    -- Arrange
    installStubs();
    resetController();
    -- Act
    DC:startCheckTicker();
    -- Assert
    lu.assertIsTrue(H.hasTimer("DeliveryCheck"));
end

function testStartCheckTickerStopsWhenNotActive()
    -- Arrange
    installStubs();
    resetController();
    DC:setState("IDLE");
    -- Act
    DC:startCheckTicker();
    H.advance("DeliveryCheck");
    -- Assert
    lu.assertIsFalse(H.hasTimer("DeliveryCheck"));
end

-- Restore the real timers after the whole suite (luaunit runs teardownSuite
-- once at the end of the run).
function teardownSuite()
    restoreStubs();
end