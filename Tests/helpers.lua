-- ArenaChillPrep — Tests/helpers.lua
-- Shared test infrastructure: a synchronous timer recorder (callbacks are
-- stored, never run implicitly — tests advance them explicitly) and a deep
-- copy for snapshotting settings.
--
-- IMPORTANT: this file is dofile'd by every suite. It returns a SINGLETON
-- (cached on _G) so all suites share the same SyncTimers table — otherwise
-- one suite's `ACP.Utils.Timers = H.SyncTimers` would point at a different
-- recorder than another suite's assertions.

if (_G.__TEST_HELPERS) then
    return _G.__TEST_HELPERS;
end

local H = {};

--- Timer recorder: after/interval store the callback; cancel removes it.
H.SyncTimers = {
    Handles = {},
    after = function(_, name, delay, cb)
        H.SyncTimers.Handles[name] = { cb = cb, delay = delay };
    end,
    interval = function(_, name, period, cb)
        H.SyncTimers.Handles[name] = { cb = cb, period = period };
    end,
    cancel = function(_, name)
        H.SyncTimers.Handles[name] = nil;
    end,
};

--- Run a recorded timer callback synchronously (and remove it).
---@param name string
---@return boolean
function H.advance(name)
    local handle = H.SyncTimers.Handles[name];
    if (not handle) then
        return false;
    end
    H.SyncTimers.Handles[name] = nil;
    handle.cb();
    return true;
end

---@param name string
---@return boolean
function H.hasTimer(name)
    return H.SyncTimers.Handles[name] ~= nil;
end

--- Recursive copy (deepMerge shares nested tables — unusable for snapshots).
--- Reuses the production Utils/Tables:deepCopy (same semantics).
---@param t table
---@return table
function H.deepCopy(t)
    return _G.ACP.Utils.Tables:deepCopy(t);
end

--- Re-load an addon module file through the vararg chain (used to re-capture
--- file-scope globals, e.g. to exercise a fallback branch).
---@param relPath string
function H.reloadModule(relPath)
    local chunk = assert(loadfile(_G.__ADDON_ROOT .. "/" .. relPath));
    chunk("ArenaChillPrep", _G.ACP);
end

--- Reset ALL modules to a clean, initialized state. Event-driven tests fire
--- events that cascade to other modules (e.g. BAG_UPDATE → ACP_ITEMS_CHANGED
--- → DeliveryController), so every event test must start from a clean slate.
function H.resetAll()
    local ACP = _G.ACP;
    ACP.Events.Listeners = {};
    ACP.Events.EventByIdentifier = {};
    ACP.Events._initialized = false;
    ACP.Events:_init(ACP.Frame);
    _G.ArenaChillPrepDB = H.deepCopy(ACP.Data.DefaultSettings);
    ACP.Settings._initialized = false;
    ACP.Settings:_init();
    ACP.ArenaPrep._initialized = false;
    ACP.ArenaPrep:_init();
    ACP.Inventory._initialized = false;
    ACP.Inventory:_init();
    ACP.TradeManager._initialized = false;
    ACP.TradeManager:_init();
    ACP.DeliveryController._initialized = false;
    ACP.DeliveryController:_init();
    H.SyncTimers.Handles = {};
end

_G.__TEST_HELPERS = H;
return H;