-- ArenaChillPrep — Classes/WorkflowKeybindController
-- Key-binding operations for workflow slots, extracted from WorkflowUI
-- (refactor Phase 6): reading/stealing/clearing a slot's Key Bindings UI
-- key (SetBinding/SaveBindings/conflict-steal) and the binding shift when a
-- workflow is deleted. The UI only calls into this module — it no longer
-- does raw WoW binding I/O itself.

---@type ACP
local _, ACP = ...;

local tostring = _G.tostring;

---@class WorkflowKeybindController
local WorkflowKeybindController = {};

---@type WorkflowKeybindController
ACP.WorkflowKeybindController = WorkflowKeybindController;

--- The Key Bindings UI key bound to a workflow slot command
--- (ACP_WORKFLOW<slot>), or nil when unbound.
---@param slot number
---@return string|nil
function WorkflowKeybindController:getSlotKey(slot)
    local key = GetBindingKey("ACP_WORKFLOW" .. tostring(slot)) or "";
    return (key ~= "") and key or nil;
end

--- Steal `key` from whatever command currently owns it, so binding it to a
--- workflow matches the Key Bindings UI (ESC -> Key Bindings ->
--- ArenaChillPrep): a physical key drives exactly one action.
--- `SetBinding(key, command)` alone does not reliably clear the previous
--- command's claim on 20506, so we explicitly unbind it first. `keepCommand`
--- is skipped (re-binding the same key to the same slot is a no-op
--- otherwise).
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

--- Replace the current binding for a workflow slot. The active binding set is
--- saved immediately; 0 is rejected because SaveBindings(0) crashes on 20506.
--- Returns whether the binding call succeeded (a nil return means the
--- binding was applied; the caller refreshes its UI either way).
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
    -- BOTH keys of the command (2026-08-24 fix): the old `GetBindingKey and
    -- GetBindingKey(command)` form dropped the SECOND return value (the `and`
    -- truncates), so the secondary key was never cleared and kept driving
    -- the old action.
    local old1, old2 = GetBindingKey(command);

    local ok, err = pcall(function()
        -- Steal the chosen key from whatever else it is bound to (another
        -- workflow, a Blizzard default, or another addon) — same as the
        -- in-game Key Bindings menu, so the key no longer drives the old action.
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

--- Shift the key bindings of the slots after a deleted one (ACP_WORKFLOW<i+1>
--- -> ACP_WORKFLOW<i>) so hotkeys stay on the right content. Captures the
--- affected keys BEFORE unbinding anything, then rebinds them one slot down.
--- Returns whether the save succeeded (false when the binding set was not
--- available — the caller reports bindingUnavailable).
---@param slot number  the deleted slot
---@param count number  the slot count BEFORE deletion
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
