-- ArenaChillPrep — Utils/Timers
-- Named timers over C_Timer. On this client a C_Timer handle's Cancel() does
-- NOT reliably stop the timer, so each entry carries an `active` flag and
-- must still be the entry registered under its name when the callback runs.

---@type ACP
local _, ACP = ...;

local C_Timer_After = _G.C_Timer and _G.C_Timer.After;
local C_Timer_NewTicker = _G.C_Timer and _G.C_Timer.NewTicker;

---@class Timers
local Timers = {
    ---@type table<string, {active: boolean, handle: table|nil}>
    Handles = {},
};

--- Run `callback` once after `delay` seconds, stored under `name`.
---@param name string
---@param delay number
---@param callback function
---@return table
function Timers:after(name, delay, callback)
    self:cancel(name);

    local entry = { active = true, handle = nil };
    self.Handles[name] = entry;

    entry.handle = C_Timer_After(delay, function()
        -- The C_Timer can fire even after cancel on this client — the
        -- `active` flag + entry identity are the source of truth.
        if (not entry.active or self.Handles[name] ~= entry) then
            return;
        end

        self.Handles[name] = nil;
        callback();
    end);

    return entry;
end

--- Run `callback` every `period` seconds, stored under `name`.
---@param name string
---@param period number
---@param callback function
---@return table
function Timers:interval(name, period, callback)
    self:cancel(name);

    local entry = { active = true, handle = nil };
    self.Handles[name] = entry;

    entry.handle = C_Timer_NewTicker(period, function()
        if (not entry.active or self.Handles[name] ~= entry) then
            return;
        end

        callback();
    end);

    return entry;
end

--- Cancel a named timer if it exists. The entry is removed and flagged so a
--- stale C_Timer firing afterwards is a no-op; handle:Cancel() is best-effort.
---@param name string
function Timers:cancel(name)
    local entry = self.Handles[name];

    if (entry) then
        entry.active = false;
        self.Handles[name] = nil;

        if (entry.handle and entry.handle.Cancel) then
            entry.handle:Cancel();
        end
    end
end

ACP.Utils = ACP.Utils or {};
ACP.Utils.Timers = Timers;

return ACP;
