-- ArenaChillPrep — Classes/WorkflowBindings
-- Registers the in-game Key Bindings entries (ESC -> Key Bindings ->
-- ArenaChillPrep) that START/RESUME each workflow slot. Bindings.xml contains
-- the fixed capacity; the UI exposes five slots initially and can add more.
--
-- NOTE: this is the start/resume key. The per-step CAST key is a SEPARATE
-- mechanism — the engine's hidden secure button bound via /acp bind <key>
-- (SetBindingClick) — because 20506 only allows casting from a real hardware
-- event (verified 2026-08-19). WorkflowEngine:start() already guards all the
-- start/resume cases: no-op while RUNNING, resume while PAUSED (same slot),
-- no-op once DONE, "not in arena prep" outside an arena.

local _, ACP = ...;

local string_format = _G.string.format;

---@class WorkflowBindings
local WorkflowBindings = {
    _initialized = false,
};

---@type WorkflowBindings
ACP.WorkflowBindings = WorkflowBindings;

-- Binding entry names shown in the Key Bindings UI. Must exist at file scope
-- before the player opens the Key Bindings window — the client reads these
-- globals directly (verified pattern on 20506: BetterFishing).
BINDING_HEADER_ACP = "ArenaChillPrep";

for slot = 1, ACP.Data.Constants.WORKFLOW_MAX_SLOTS do
    _G["BINDING_NAME_ACP_WORKFLOW" .. slot] = string_format(ACP.L.workflow.bindingWorkflow, slot);

    -- Capture the loop value for Lua 5.1 closures.
    local boundSlot = slot;
    _G["ACP_WORKFLOW" .. slot] = function()
        ACP.WorkflowEngine:start(boundSlot);
    end;
end

--- Init hook (called from bootstrap). No setup needed — the binding globals
--- and handlers are registered at file scope, and the client persists the
--- player's bindings itself (survives /reload and game restart).
function WorkflowBindings:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    ACP:debugPrint(ACP.L.workflow.bindingsInit, ACP.Data.Constants.WORKFLOW_MAX_SLOTS);
end

return ACP;
