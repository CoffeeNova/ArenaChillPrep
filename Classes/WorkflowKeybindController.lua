-- ArenaChillPrep — Classes/WorkflowKeybindController
-- Workflow slot key I/O for the UI: SetBinding/SaveBindings, conflict-steal
-- and the binding shift after a workflow deletion.

---@type ACP
local _, ACP = ...;

local tostring = _G.tostring;

---@class WorkflowKeybindController
local WorkflowKeybindController = {};

---@type WorkflowKeybindController
ACP.WorkflowKeybindController = WorkflowKeybindController;

---@param slot number
---@return string|nil
function WorkflowKeybindController:getSlotKey(slot)
    local key = GetBindingKey("ACP_WORKFLOW" .. tostring(slot)) or "";
    return (key ~= "") and key or nil;
end

--- Steal `key` from whatever command currently owns it (SetBinding alone does
--- not reliably clear the previous command's claim on 20506).
---@param key string|nil
---@param keepCommand string
local function unbindConflictingKey(key, keepCommand)
    if (key == nil or key == "" or not GetBindingAction or not SetBinding) then
        return;
    end

    local current = GetBindingAction(key);

    if (current and current ~= "" and current ~= keepCommand) then
        SetBinding(key, nil);
    end
end

--- Replace a slot's binding; SaveBindings(0) crashes on 20506, so the binding
--- set must be 1|2.
---@param slot number
---@param key string|nil
---@return boolean ok
function WorkflowKeybindController:setSlotKey(slot, key)
    if (not SetBinding or not SaveBindings or not GetCurrentBindingSet or not GetBindingKey) then
        ACP:print(ACP.L.workflow.bindingUnavailable);
        return false;
    end

    if (key and key ~= "" and not ACP.UI.isSafeBindingKey(key)) then
        ACP:print(ACP.L.workflow.bindingInvalid);
        return false;
    end

    local command = "ACP_WORKFLOW" .. tostring(slot);
    -- Both keys of the command (a command can be bound to two keys).
    local old1, old2 = GetBindingKey(command);

    local ok, err = pcall(function()
        unbindConflictingKey(key, command);

        if (old1) then
            SetBinding(old1, nil);
        end
        if (old2) then
            SetBinding(old2, nil);
        end
        if (key and key ~= "") then
            SetBinding(key, command);
        end

        local bindingSet = GetCurrentBindingSet();

        if (bindingSet == 1 or bindingSet == 2) then
            SaveBindings(bindingSet);
        else
            error("binding set not loaded");
        end
    end);

    if (not ok) then
        ACP:print(ACP.L.workflow.bindingUnavailable);
    end

    return ok;
end

--- Shift the keys of the slots after a deleted one so hotkeys stay on the
--- right content. Captures the affected keys before unbinding anything.
---@param slot number
---@param count number
---@return boolean ok
function WorkflowKeybindController:shiftBindingsAfterDelete(slot, count)
    if (not SetBinding or not SaveBindings or not GetCurrentBindingSet or not GetBindingKey) then
        return false;
    end

    local keys = {};
    local keys2 = {};

    for i = slot, count do
        local key1, key2 = GetBindingKey("ACP_WORKFLOW" .. tostring(i));
        keys[i] = key1;
        keys2[i] = key2;
    end

    local ok = pcall(function()
        for i = slot, count do
            if (keys[i]) then
                SetBinding(keys[i], nil);
            end
            if (keys2[i]) then
                SetBinding(keys2[i], nil);
            end
        end

        for i = slot, count - 1 do
            local command = "ACP_WORKFLOW" .. tostring(i);
            if (keys[i + 1]) then
                SetBinding(keys[i + 1], command);
            end
            if (keys2[i + 1]) then
                SetBinding(keys2[i + 1], command);
            end
        end

        local bindingSet = GetCurrentBindingSet();

        if (bindingSet == 1 or bindingSet == 2) then
            SaveBindings(bindingSet);
        else
            error("binding set not loaded");
        end
    end);

    return ok;
end

return ACP;
