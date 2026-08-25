-- ArenaChillPrep — Classes/StateMachine
-- Mixin: init-once guard + validated state writes for both orchestrators.

---@type ACP
local _, ACP = ...;

---@class StateMachine
local StateMachine = {};

---@type StateMachine
ACP.StateMachine = StateMachine;

---@param embedder table
---@return boolean
function StateMachine:initOnce(embedder)
    if (embedder._initialized) then
        return false;
    end

    embedder._initialized = true;
    return true;
end

--- Validated state write with a change-suppression log; `allowed` is the
--- module's state enum (Data/Constants) — an unknown value throws.
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
