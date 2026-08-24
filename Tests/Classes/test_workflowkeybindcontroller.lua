-- ArenaChillPrep — Tests/Classes/test_workflowkeybindcontroller.lua
-- Covers Classes/WorkflowKeybindController.lua: getSlotKey, setSlotKey
-- (bind/steal/clear/unsafe-key rejection) and shiftBindingsAfterDelete.

local ACP = _G.ACP;
local KC = ACP.WorkflowKeybindController;
local H = dofile(_G.__TESTS_ROOT .. "/helpers.lua");

-- The binding stubs keep mutable state in _G.__stub — every test starts from
-- a clean binding table so no keys leak across tests.
local function resetBindings()
    _G.__stub.bindingKeys = {};
    _G.__stub.bindingActions = {};
    _G.__stub.bindings = {};
end

function testGetSlotKeyUnbound()
    resetBindings();
    lu.assertNil(KC:getSlotKey(1));
end

function testGetSlotKeyBound()
    resetBindings();
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = "F9" };
    lu.assertEquals(KC:getSlotKey(1), "F9");
end

function testSetSlotKeyBindsAndSteals()
    resetBindings();
    _G.__stub.bindingKeys = { ["SOMECOMMAND"] = "F9" };
    _G.__stub.bindingActions = { ["F9"] = "SOMECOMMAND" };
    local ok = KC:setSlotKey(1, "F9");
    lu.assertIsTrue(ok);
    lu.assertEquals(_G.__stub.bindingKeys["ACP_WORKFLOW1"], "F9");
    lu.assertEquals(_G.__stub.bindingActions["F9"], "ACP_WORKFLOW1");
    lu.assertNil(_G.__stub.bindingKeys["SOMECOMMAND"]);
end

function testSetSlotKeyClears()
    resetBindings();
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = "F9" };
    _G.__stub.bindingActions = { ["F9"] = "ACP_WORKFLOW1" };
    local ok = KC:setSlotKey(1, nil);
    lu.assertIsTrue(ok);
    lu.assertNil(_G.__stub.bindingKeys["ACP_WORKFLOW1"]);
    lu.assertNil(_G.__stub.bindingActions["F9"]);
end

function testSetSlotKeyRejectsUnsafe()
    resetBindings();
    local ok = KC:setSlotKey(1, "SOME BAD KEY WITH SPACES");
    lu.assertIsFalse(ok);
    lu.assertNil(_G.__stub.bindingKeys["ACP_WORKFLOW1"]);
end

function testShiftBindingsAfterDelete()
    resetBindings();
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW2"] = "F6", ["ACP_WORKFLOW3"] = "F7" };
    local ok = KC:shiftBindingsAfterDelete(1, 3);
    lu.assertIsTrue(ok);
    lu.assertEquals(_G.__stub.bindingKeys["ACP_WORKFLOW1"], "F6");
    lu.assertEquals(_G.__stub.bindingKeys["ACP_WORKFLOW2"], "F7");
    lu.assertNil(_G.__stub.bindingKeys["ACP_WORKFLOW3"]);
end

function testSetSlotKeyNoBindingApi()
    resetBindings();
    local orig = _G.SetBinding;
    _G.SetBinding = nil;
    local ok = KC:setSlotKey(1, "F9");
    lu.assertIsFalse(ok);
    _G.SetBinding = orig;
end

function testSetSlotKeyBindingSetNotLoaded()
    resetBindings();
    local orig = _G.GetCurrentBindingSet;
    _G.GetCurrentBindingSet = function() return 0 end;
    local ok = KC:setSlotKey(1, "F9");
    lu.assertIsFalse(ok);
    _G.GetCurrentBindingSet = orig;
end

function testSetSlotKeyClearsBothKeys()
    -- Regression (2026-08-24 fix): the old `GetBindingKey and
    -- GetBindingKey(command)` form dropped the second return value, so the
    -- SECONDARY key was never cleared. Both keys must be unbound.
    resetBindings();
    local orig = _G.GetBindingKey;
    _G.GetBindingKey = function(command)
        if (command == "ACP_WORKFLOW1") then return "F9", "CTRL-F9"; end
        return nil;
    end;
    _G.__stub.bindingKeys = { ["ACP_WORKFLOW1"] = "F9" };
    _G.__stub.bindingActions = { ["F9"] = "ACP_WORKFLOW1", ["CTRL-F9"] = "ACP_WORKFLOW1" };
    local ok = KC:setSlotKey(1, nil);
    -- Restore the global BEFORE asserting — a failing assert must not leak the
    -- override into the next tests.
    _G.GetBindingKey = orig;
    lu.assertIsTrue(ok);
    lu.assertNil(_G.__stub.bindingKeys["ACP_WORKFLOW1"]);
    lu.assertNil(_G.__stub.bindingActions["F9"]);
    lu.assertNil(_G.__stub.bindingActions["CTRL-F9"]);
end

function testShiftBindingsAfterDeleteTwoKeys()
    -- shiftBindingsAfterDelete captures BOTH keys per command (no truncation
    -- there) — pin the SetBinding call sequence: unbind both, rebind both one
    -- slot down.
    resetBindings();
    local orig = _G.GetBindingKey;
    _G.GetBindingKey = function(command)
        if (command == "ACP_WORKFLOW2") then return "F6", "CTRL-F6"; end
        return nil;
    end;
    local calls = {};
    local origSet = _G.SetBinding;
    _G.SetBinding = function(key, command)
        tinsert(calls, { key = key, command = command });
    end;
    local ok = KC:shiftBindingsAfterDelete(1, 2);
    _G.GetBindingKey = orig;
    _G.SetBinding = origSet;
    lu.assertIsTrue(ok);
    lu.assertEquals(#calls, 4);
    lu.assertEquals(calls[1].key, "F6");
    lu.assertNil(calls[1].command);
    lu.assertEquals(calls[2].key, "CTRL-F6");
    lu.assertNil(calls[2].command);
    lu.assertEquals(calls[3].key, "F6");
    lu.assertEquals(calls[3].command, "ACP_WORKFLOW1");
    lu.assertEquals(calls[4].key, "CTRL-F6");
    lu.assertEquals(calls[4].command, "ACP_WORKFLOW1");
end

function testShiftBindingsNoBindingApi()
    resetBindings();
    local orig = _G.SetBinding;
    _G.SetBinding = nil;
    lu.assertIsFalse(KC:shiftBindingsAfterDelete(1, 2));
    _G.SetBinding = orig;
end

return ACP;
