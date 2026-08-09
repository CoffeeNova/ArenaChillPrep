-- ArenaChillPrep — Utils/Timers
-- Named timers over C_Timer (available on TBC Anniversary, Interface 20506).
-- Mirrors Gargul's GL:after / GL:interval / GL:cancel call sites so future
-- code reads identically, but without Ace. Each timer is registered under a
-- name; starting a timer with the same name cancels the previous one.

---@type ACP
local _, ACP = ...;

local C_Timer_After = _G.C_Timer and _G.C_Timer.After;
local C_Timer_NewTicker = _G.C_Timer and _G.C_Timer.NewTicker;

---@class Timers
local Timers = {
    ---@type table<string, table>
    Handles = {},
};

--- Run `callback` once after `delay` seconds, stored under `name`.
---@param name string
---@param delay number
---@param callback function
function Timers:after(name, delay, callback)
    self:cancel(name);

    self.Handles[name] = C_Timer_After(delay, function()
        self.Handles[name] = nil;
        callback();
    end);

    return self.Handles[name];
end

--- Run `callback` every `period` seconds, stored under `name`.
---@param name string
---@param period number
---@param callback function
function Timers:interval(name, period, callback)
    self:cancel(name);

    self.Handles[name] = C_Timer_NewTicker(period, callback);

    return self.Handles[name];
end

--- Cancel a named timer if it exists.
---@param name string
function Timers:cancel(name)
    local handle = self.Handles[name];

    if (handle) then
        handle:Cancel();
        self.Handles[name] = nil;
    end
end

ACP.Utils = ACP.Utils or {};
ACP.Utils.Timers = Timers;

return ACP;
