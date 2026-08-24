-- ArenaChillPrep — Classes/StateMachine
-- Tiny mixin for the orchestrator state machines (DeliveryController,
-- WorkflowEngine): an init-once guard and state writes with a
-- change-suppression log + enum validation. Modules embed it with one-line
-- wrappers so their call sites keep the method syntax (self:setState(value)).

---@type ACP
local _, ACP = ...;

---@class StateMachine
local StateMachine = {};

---@type StateMachine
ACP.StateMachine = StateMachine;

--- Initialize the embedder once; returns false when already initialized.
---@param embedder table
---@return boolean
function StateMachine:initOnce(embedder)
    if (embedder._initialized) then
        return false;
    end

    embedder._initialized = true;
    return true;
end

--- Write the state with a change-suppression log and enum validation.
--- `allowed` is the module's state enum table (Data/Constants WORKFLOW_STATE /
--- DELIVERY_STATE) — an unknown value throws: a typo silently corrupting the
--- state machine is worse than a visible error.
---@param embedder table
---@param newState string
---@param allowed table
function StateMachine:setState(embedder, newState, allowed)
    if (allowed and not allowed[newState]) then
        error(("ACP.StateMachine: invalid state %q"):format(tostring(newState)), 2);
    end

    if (embedder.state ~= newState) then
        ACP:debugPrint("state: %s -> %s", embedder.state, newState);
        embedder.state = newState;
    end
end

return ACP;
