-- ArenaChillPrep — Tests/Classes/test_events.lua
-- Covers Classes/Events.lua: register/unregister/fire + frame registration.

local ACP = _G.ACP;
local Events = ACP.Events;

local function resetEvents()
    Events.Listeners = {};
    Events.EventByIdentifier = {};
end

function testRegisterAndFire()
    -- Arrange
    resetEvents();
    local received;
    -- Act
    Events:register("id1", "ACP_TEST_EVENT", function(v) received = v; end);
    Events:fire("ACP_TEST_EVENT", 42);
    -- Assert
    lu.assertEquals(received, 42);
end

function testRegisterReturnsIdentifier()
    -- Arrange
    resetEvents();
    -- Act
    local id = Events:register("myId", "ACP_TEST_EVENT", function() end);
    -- Assert
    lu.assertEquals(id, "myId");
end

function testRegisterAutoIdentifier()
    -- Arrange
    resetEvents();
    _G.__stub.time = 123.5;
    -- Act
    local id = Events:register(nil, "ACP_TEST_EVENT", function() end);
    -- Assert
    lu.assertStrContains(id, "ACP_TEST_EVENT");
end

function testUnregisterStopsDelivery()
    -- Arrange
    resetEvents();
    local count = 0;
    local id = Events:register("id1", "ACP_TEST_EVENT", function() count = count + 1; end);
    -- Act
    Events:unregister(id);
    Events:fire("ACP_TEST_EVENT");
    -- Assert
    lu.assertEquals(count, 0);
end

function testUnregisterTable()
    -- Arrange
    resetEvents();
    local count = 0;
    local id1 = Events:register("a", "ACP_TEST_EVENT", function() count = count + 1; end);
    local id2 = Events:register("b", "ACP_TEST_EVENT", function() count = count + 1; end);
    -- Act
    Events:unregister({ id1, id2 });
    Events:fire("ACP_TEST_EVENT");
    -- Assert
    lu.assertEquals(count, 0);
end

function testUnregisterUnknownIsNoop()
    -- Arrange
    resetEvents();
    -- Act
    Events:unregister("nope");
    -- Assert
    lu.assertIsNil(Events.EventByIdentifier["nope"]);
end

function testFireNoListenersIsNoop()
    -- Arrange
    resetEvents();
    -- Act
    Events:fire("ACP_NOTHING");
    -- Assert
    lu.assertIsNil(Events.Listeners["ACP_NOTHING"]);
end

function testRegisterGameEventRegistersOnFrame()
    -- Arrange
    resetEvents();
    local frame = {
        registered = {},
        RegisterEvent = function(self, e) table.insert(self.registered, e); end,
        UnregisterEvent = function() end,
        SetScript = function() end,
    };
    Events._initialized = false;
    -- Act
    Events:_init(frame);
    Events:register("id1", "UNIT_AURA", function() end);
    -- Assert
    lu.assertTableContains(frame.registered, "UNIT_AURA");
end

function testUnregisterLastListenerUnregistersFrame()
    -- Arrange
    resetEvents();
    local frame = {
        registered = {},
        unregistered = {},
        RegisterEvent = function(self, e) table.insert(self.registered, e); end,
        UnregisterEvent = function(self, e) table.insert(self.unregistered, e); end,
        SetScript = function() end,
    };
    Events._initialized = false;
    -- Act
    Events:_init(frame);
    local id = Events:register("id1", "UNIT_AURA", function() end);
    Events:unregister(id);
    -- Assert
    lu.assertTableContains(frame.unregistered, "UNIT_AURA");
end