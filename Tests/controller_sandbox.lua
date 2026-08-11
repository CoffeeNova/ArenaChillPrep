-- ArenaChillPrep — Tests/controller_sandbox.lua
-- In-game sandbox: verifies the DeliveryController's DECISION
-- logic without touching real bags, groups or trade windows:
--   - bracket gate (default 2v2 only vs 3v3; enabling 3v3 starts trading)
--   - givenTo: 2v2 — one trade per prep; 3v3 — the second batch goes to the
--     OTHER partner (both when it is pre-crafted before the first trade
--     completes and when it is crafted afterwards)
--   - gate safety: crafting inside the last gateSafetySeconds → no trade
--   - trade-open timeout: window never opens → ACP_TRADE_FAILED("timeout")
--     → controller back to ACTIVE with a retry scheduled
--   - stray failure after a reset → ignored (stays IDLE, no post-gate trade)
--   - death check: no trade while UnitIsDeadOrGhost, resumes after revival
--
-- Usage: uncomment `Tests/inventory_sandbox.lua` AND
-- `Tests/controller_sandbox.lua` in ArenaChillPrep.toc and reload, then run:
--   /run ACP.Tests:run()
-- (run() executes the inventory sandbox first, then this controller sandbox.)
--
-- Everything is synchronous: ACP.Utils.Timers is replaced with a recorder
-- ("after"/"interval" store the callback, nothing runs on its own); the test
-- advances timers explicitly (Tests:advance(name)) for full determinism.
--
-- NOTE: it must load AFTER Classes/DeliveryController.lua (TOC order).
-- Do NOT ship this file in a release TOC.

---@type ACP
local _, ACP = ...;

ACP.Tests = ACP.Tests or {};

local Tests = ACP.Tests;

--- Recursive copy (deepMerge shares nested tables — unusable for snapshotting).
---@param t table
---@return table
local function deepCopy(t)
    local copy = {};

    for k, v in pairs(t) do
        copy[k] = (type(v) == "table") and deepCopy(v) or v;
    end

    return copy;
end

--- Synchronous timer recorder: callbacks are stored, never executed implicitly.
local SyncTimers = {
    Handles = {},
    after = function(_, name, delay, cb)
        SyncTimers.Handles[name] = { cb = cb, delay = delay };
    end,
    interval = function(_, name, period, cb)
        SyncTimers.Handles[name] = { cb = cb, period = period };
    end,
    cancel = function(_, name)
        SyncTimers.Handles[name] = nil;
    end,
};

--- Shared check helper (also defined by inventory_sandbox.lua when loaded).
if (not Tests.check) then
    ---@param label string
    ---@param expected any
    ---@param actual any
    function Tests:check(label, expected, actual)
        local ok = expected == actual;
        ACP:print(("%s %s | expected=%s actual=%s"):format(ok and "PASS" or "FAIL", label, tostring(expected), tostring(actual)));
    end
end

--- Test state (filled per case).
---@class ControllerTestState
local State = {
    PartyCount = 0,
    Bracket = nil,
    Remaining = nil,
    BuffActive = false,
    Dead = false,
    Counts = {},
    LastTradeUnit = nil,
};

--- Save and override everything the controller reads.
function Tests:installControllerStubs()
    self.Orig = {
        UnitClass = _G.UnitClass,
        GetNumPartyMembers = _G.GetNumPartyMembers,
        UnitExists = _G.UnitExists,
        UnitIsUnit = _G.UnitIsUnit,
        UnitAffectingCombat = _G.UnitAffectingCombat,
        UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost,
        Timers = ACP.Utils.Timers,
        settingsData = deepCopy(ACP.Settings.Data),
        startTrade = ACP.TradeManager.startTrade,
        apIsInArena = ACP.ArenaPrep.isInArena,
        apIsActive = ACP.ArenaPrep.isActive,
        apGetRemainingTime = ACP.ArenaPrep.getRemainingTime,
        apGetBracket = ACP.ArenaPrep.getBracket,
        invGetCount = ACP.Inventory.getCount,
    };

    _G.UnitClass = function()
        return "WARLOCK", "WARLOCK";
    end;

    _G.GetNumPartyMembers = function()
        return State.PartyCount;
    end;

    _G.UnitExists = function(unit)
        local n = tonumber((unit or ""):match("^party(%d+)$"));

        return n ~= nil and n <= State.PartyCount;
    end;

    _G.UnitIsUnit = function()
        return false;
    end;

    _G.UnitAffectingCombat = function()
        return false;
    end;

    _G.UnitIsDeadOrGhost = function()
        return State.Dead;
    end;

    ACP.Utils.Timers = SyncTimers;

    ACP.TradeManager.startTrade = function(_, unit)
        State.LastTradeUnit = unit;
    end;

    ACP.ArenaPrep.isInArena = function()
        return true;
    end;

    ACP.ArenaPrep.isActive = function()
        return State.BuffActive;
    end;

    ACP.ArenaPrep.getRemainingTime = function()
        return State.Remaining;
    end;

    ACP.ArenaPrep.getBracket = function()
        return State.Bracket;
    end;

    ACP.Inventory.getCount = function(_, itemID)
        return State.Counts[itemID] or 0;
    end;
end

--- Restore everything saved by installControllerStubs.
function Tests:restoreControllerStubs()
    _G.UnitClass = self.Orig.UnitClass;
    _G.GetNumPartyMembers = self.Orig.GetNumPartyMembers;
    _G.UnitExists = self.Orig.UnitExists;
    _G.UnitIsUnit = self.Orig.UnitIsUnit;
    _G.UnitAffectingCombat = self.Orig.UnitAffectingCombat;
    _G.UnitIsDeadOrGhost = self.Orig.UnitIsDeadOrGhost;
    ACP.Utils.Timers = self.Orig.Timers;
    ACP.Settings.Data = self.Orig.settingsData;
    ArenaChillPrepDB = ACP.Settings.Data;
    ACP.TradeManager.startTrade = self.Orig.startTrade;
    ACP.ArenaPrep.isInArena = self.Orig.apIsInArena;
    ACP.ArenaPrep.isActive = self.Orig.apIsActive;
    ACP.ArenaPrep.getRemainingTime = self.Orig.apGetRemainingTime;
    ACP.ArenaPrep.getBracket = self.Orig.apGetBracket;
    ACP.Inventory.getCount = self.Orig.invGetCount;
    self.Orig = nil;
end

--- Run a recorded timer callback synchronously (and remove it).
---@param name string
---@return boolean
function Tests:advance(name)
    local handle = SyncTimers.Handles[name];

    if (not handle) then
        return false;
    end

    SyncTimers.Handles[name] = nil;
    handle.cb();
    return true;
end

---@param name string
---@return boolean
function Tests:hasTimer(name)
    return SyncTimers.Handles[name] ~= nil;
end

--- Wipe controller state + timers between cases.
function Tests:resetController()
    ACP.DeliveryController:reset();
    SyncTimers.Handles = {};
    State.LastTradeUnit = nil;
end

--- Default "items ready" setup: one Master + one Major (default ranks).
local function readyCounts()
    return { [22105] = 1, [19012] = 1 };
end

function Tests:testBracketGate()
    -- Default settings: only 2v2 is enabled. 3v3 arena → no trade, IDLE.
    State.PartyCount = 2;
    State.Bracket = "3v3";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    ACP.Settings:set("brackets.3v3", false);

    self:resetController();
    ACP.DeliveryController:onBuffGained();
    self:check("bracket gate: 3v3 disabled -> IDLE", "IDLE", ACP.DeliveryController.state);
    self:check("bracket gate: no trade scheduled", false, self:hasTimer("TradeDelay"));

    -- Enable 3v3 → trading starts with party1.
    ACP.Settings:set("brackets.3v3", true);
    ACP.DeliveryController:onBuffGained();
    self:check("bracket gate: 3v3 enabled -> ACTIVE", "ACTIVE", ACP.DeliveryController.state);
    self:check("bracket gate: trade scheduled", true, self:hasTimer("TradeDelay"));
    self:advance("TradeDelay");
    self:check("bracket gate: trade with party1", "party1", State.LastTradeUnit);

    self:resetController();
end

function Tests:testGivenTo2v2()
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();

    self:resetController();
    ACP.DeliveryController:onBuffGained();
    self:check("2v2: trade scheduled", true, self:hasTimer("TradeDelay"));
    self:advance("TradeDelay");
    self:check("2v2: trade with party1", "party1", State.LastTradeUnit);
    self:check("2v2: open timeout armed", true, self:hasTimer("TradeOpen"));

    -- Window opens (cancels the timeout) and the trade completes.
    ACP.Events:fire("ACP_TRADE_OPENED");
    self:check("2v2: timeout cancelled after open", false, self:hasTimer("TradeOpen"));
    ACP.Events:fire("ACP_TRADE_COMPLETED");
    self:check("2v2: DONE after first trade", "DONE", ACP.DeliveryController.state);

    -- A second stone crafted → must NOT re-open a trade with party1.
    State.Counts = { [22105] = 2, [19012] = 2 };
    ACP.Events:fire("ACP_ITEMS_CHANGED");
    self:check("2v2: still DONE after second stone", "DONE", ACP.DeliveryController.state);
    self:check("2v2: no second trade", false, self:hasTimer("TradeDelay"));

    self:resetController();
end

function Tests:testGivenTo3v3()
    ACP.Settings:set("brackets.3v3", true);
    State.PartyCount = 2;
    State.Bracket = "3v3";
    State.Remaining = 45;
    State.BuffActive = true;

    -- Variant A: the second batch is ALREADY in bags when trade 1 completes.
    State.Counts = readyCounts();
    self:resetController();
    ACP.DeliveryController:onBuffGained();
    self:advance("TradeDelay");
    self:check("3v3: first trade with party1", "party1", State.LastTradeUnit);

    State.Counts = { [22105] = 2, [19012] = 2 }; -- second batch ready
    ACP.Events:fire("ACP_TRADE_OPENED");
    ACP.Events:fire("ACP_TRADE_COMPLETED");
    self:check("3v3: ACTIVE, next partner pending", "ACTIVE", ACP.DeliveryController.state);
    self:check("3v3: second trade scheduled", true, self:hasTimer("TradeDelay"));
    self:advance("TradeDelay");
    self:check("3v3: second trade with party2", "party2", State.LastTradeUnit);
    self:resetController();

    -- Variant B: the second batch is crafted AFTER trade 1 completes.
    State.Counts = readyCounts();
    self:resetController();
    ACP.DeliveryController:onBuffGained();
    self:advance("TradeDelay");
    ACP.Events:fire("ACP_TRADE_OPENED");
    State.Counts = {}; -- items placed → gone from bags
    ACP.Events:fire("ACP_TRADE_COMPLETED");
    self:check("3v3 (post-craft): ACTIVE after first trade", "ACTIVE", ACP.DeliveryController.state);
    self:check("3v3 (post-craft): no trade yet (items gone)", false, self:hasTimer("TradeDelay"));

    State.Counts = readyCounts(); -- player crafts the second batch
    ACP.Events:fire("ACP_ITEMS_CHANGED");
    self:check("3v3 (post-craft): trade scheduled after craft", true, self:hasTimer("TradeDelay"));
    self:advance("TradeDelay");
    self:check("3v3 (post-craft): second trade with party2", "party2", State.LastTradeUnit);
    self:resetController();

    ACP.Settings:set("brackets.3v3", false);
end

function Tests:testGateSafety()
    ACP.Settings:set("gateSafetySeconds", 15);
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.BuffActive = true;
    State.Remaining = 10; -- inside the last 15 s
    State.Counts = readyCounts();

    self:resetController();
    ACP.DeliveryController:onBuffGained();
    self:check("gate safety: stays ACTIVE", "ACTIVE", ACP.DeliveryController.state);
    self:check("gate safety: no trade scheduled", false, self:hasTimer("TradeDelay"));

    self:resetController();
end

function Tests:testOpenTimeout()
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();

    self:resetController();
    ACP.DeliveryController:onBuffGained();
    self:advance("TradeDelay");
    self:check("timeout: TRADING", "TRADING", ACP.DeliveryController.state);
    self:check("timeout: TradeOpen armed", true, self:hasTimer("TradeOpen"));

    -- The window never opens → the timeout fires and schedules a retry.
    self:advance("TradeOpen");
    self:check("timeout: back to ACTIVE", "ACTIVE", ACP.DeliveryController.state);
    self:check("timeout: retry scheduled", true, self:hasTimer("TradeRetry"));

    self:resetController();
end

function Tests:testStrayFailure()
    -- A failure verdict arriving after a reset (window closed after the buff
    -- faded / gates opened) must be ignored — the controller stays IDLE.
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 0;
    State.BuffActive = false;
    State.Counts = readyCounts();

    self:resetController();
    ACP.Events:fire("ACP_TRADE_FAILED", "closed");
    self:check("stray failure: stays IDLE", "IDLE", ACP.DeliveryController.state);
    self:check("stray failure: no retry scheduled", false, self:hasTimer("TradeRetry"));

    self:resetController();
end

function Tests:testDeathCheck()
    State.PartyCount = 1;
    State.Bracket = "2v2";
    State.Remaining = 45;
    State.BuffActive = true;
    State.Counts = readyCounts();
    State.Dead = true;

    self:resetController();
    ACP.DeliveryController:onBuffGained();
    self:check("death: no trade while dead", false, self:hasTimer("TradeDelay"));

    -- Revival → the next readiness poll resumes.
    State.Dead = false;
    ACP.Events:fire("ACP_ITEMS_CHANGED");
    self:check("death: trade scheduled after revive", true, self:hasTimer("TradeDelay"));

    self:resetController();
    State.Dead = false;
end

--- Run the controller sandbox checks.
function Tests:runController()
    ACP:print("== ArenaChillPrep controller sandbox ==");

    self:installControllerStubs();

    self:testBracketGate();
    self:testGivenTo2v2();
    self:testGivenTo3v3();
    self:testGateSafety();
    self:testOpenTimeout();
    self:testStrayFailure();
    self:testDeathCheck();

    self:restoreControllerStubs();
    ACP:print("== controller sandbox done ==");
end

-- When the inventory sandbox loads first, make /run ACP.Tests:run() run both.
if (Tests.run) then
    local originalRun = Tests.run;

    function Tests:run()
        originalRun(self);
        self:runController();
    end
end

return ACP;
