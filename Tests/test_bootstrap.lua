-- ArenaChillPrep — Tests/test_bootstrap.lua
-- Covers bootstrap.lua: ACP table, print/debugPrint, _init order.

local ACP = _G.ACP;

function testBootstrapGlobalTable()
    -- Arrange
    -- Act
    -- Assert
    lu.assertEquals(type(ACP), "table");
    lu.assertEquals(ACP.name, "ArenaChillPrep");
    lu.assertEquals(ACP.version, "0.1.0");
    lu.assertIsFalse(ACP._initialized);
end

function testBootstrapPrint()
    -- Arrange
    _G.__stub.chatMessages = {};
    -- Act
    ACP:print("hello %s", "world");
    -- Assert
    lu.assertEquals(#_G.__stub.chatMessages, 1);
    lu.assertStrContains(_G.__stub.chatMessages[1], "hello world");
end

function testBootstrapDebugPrintSilentWhenOff()
    -- Arrange
    ACP.debug = false;
    _G.__stub.chatMessages = {};
    -- Act
    ACP:debugPrint("hidden");
    -- Assert
    lu.assertEquals(#_G.__stub.chatMessages, 0);
end

function testBootstrapDebugPrintWhenOn()
    -- Arrange
    ACP.debug = true;
    _G.__stub.chatMessages = {};
    -- Act
    ACP:debugPrint("visible");
    -- Assert
    lu.assertEquals(#_G.__stub.chatMessages, 1);
    ACP.debug = false;
end

function testBootstrapInitRunsModules()
    -- Arrange
    ACP._initialized = false;
    local order = {};
    local orig = {};
    for _, name in ipairs({ "Events", "Settings", "ArenaPrep", "Inventory", "TradeManager", "DeliveryController", "OptionsUI" }) do
        orig[name] = ACP[name]._init;
        ACP[name]._init = function(self)
            table.insert(order, name);
        end;
    end
    local origCheckNow = ACP.ArenaPrep.checkNow;
    ACP.ArenaPrep.checkNow = function() end;
    -- Act
    ACP:_init();
    -- Assert
    lu.assertEquals(order, { "Events", "Settings", "ArenaPrep", "Inventory", "TradeManager", "DeliveryController", "OptionsUI" });
    lu.assertIsTrue(ACP._initialized);
    -- restore
    for name, fn in pairs(orig) do ACP[name]._init = fn; end
    ACP.ArenaPrep.checkNow = origCheckNow;
    ACP._initialized = false;
end

function testBootstrapInitIdempotent()
    -- Arrange
    ACP._initialized = true;
    local called = false;
    local orig = ACP.Events._init;
    ACP.Events._init = function() called = true; end;
    -- Act
    ACP:_init();
    -- Assert
    lu.assertIsFalse(called);
    ACP.Events._init = orig;
    ACP._initialized = false;
end

function testBootstrapAddonLoadedEvent()
    -- Arrange: re-run bootstrap on a fresh frame so its OnEvent handler is
    -- captured (the runner's Events:_init overwrote ACP.Frame's OnEvent).
    local chunk = assert(loadfile(_G.__ADDON_ROOT .. "/bootstrap.lua"));
    local origFrame = ACP.Frame;
    chunk("ArenaChillPrep", ACP);
    local handler = ACP.Frame.scripts.OnEvent;
    ACP.Frame = origFrame;
    ACP._initialized = false;
    local origInit = ACP._init;
    local ran = false;
    ACP._init = function() ran = true; end;
    -- Act
    handler(nil, "ADDON_LOADED", "ArenaChillPrep");
    -- Assert
    lu.assertIsTrue(ran);
    ACP._init = origInit;
    ACP._initialized = false;
end

function testBootstrapAddonLoadedOtherIgnored()
    -- Arrange: re-run bootstrap on a fresh frame (see above).
    local chunk = assert(loadfile(_G.__ADDON_ROOT .. "/bootstrap.lua"));
    local origFrame = ACP.Frame;
    chunk("ArenaChillPrep", ACP);
    local handler = ACP.Frame.scripts.OnEvent;
    ACP.Frame = origFrame;
    ACP._initialized = false;
    local origInit = ACP._init;
    local ran = false;
    ACP._init = function() ran = true; end;
    -- Act
    handler(nil, "ADDON_LOADED", "SomeOtherAddon");
    -- Assert
    lu.assertIsFalse(ran);
    ACP._init = origInit;
    ACP._initialized = false;
end