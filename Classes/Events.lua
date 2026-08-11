-- ArenaChillPrep — Classes/Events
-- Minimal event bus. The addon's frame dispatches
-- raw game events to subscribers; modules use fire() for internal events
-- (ACP_BUFF_GAINED, ACP_ITEMS_CHANGED, ACP_TRADE_*, ...).

---@type ACP
local _, ACP = ...;

local tinsert = _G.tinsert;
local tremove = _G.tremove;
local GetTime = _G.GetTime;

---@class Events
local Events = {
    _initialized = false,

    ---@type Frame
    Frame = nil,

    ---@type table<string, table<number, {identifier: string, callback: function}>>
    Listeners = {},

    ---@type table<string, string>
    EventByIdentifier = {},
};

---@type Events
ACP.Events = Events;

--- Attach the event bus to the addon's frame.
---@param frame Frame
function Events:_init(frame)
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    self.Frame = frame;
    self.Frame:SetScript("OnEvent", function(_, event, ...)
        self:fire(event, ...);
    end);
end

--- Subscribe `callback` to `event` under a unique `identifier`.
--- Returns the identifier, so the caller can unsubscribe later.
--- Real game events are registered on the addon's frame; internal events
--- (prefixed ACP_) are fired manually via Events:fire and never registered.
---@param identifier string
---@param event string
---@param callback function
---@return string
function Events:register(identifier, event, callback)
    if (not self.Listeners[event]) then
        self.Listeners[event] = {};

        if (event:sub(1, 4) ~= "ACP_") then
            self.Frame:RegisterEvent(event);
        end
    end

    if (not identifier) then
        identifier = ("%s:%s"):format(event, tostring(GetTime()));
    end

    self.EventByIdentifier[identifier] = event;
    tinsert(self.Listeners[event], { identifier = identifier, callback = callback });

    return identifier;
end

--- Unsubscribe by identifier (a single one or an array of them).
---@param identifier string|table
function Events:unregister(identifier)
    if (type(identifier) == "table") then
        for _, id in ipairs(identifier) do
            self:unregister(id);
        end

        return;
    end

    local event = self.EventByIdentifier[identifier];

    if (not event) then
        return;
    end

    local listeners = self.Listeners[event];

    if (listeners) then
        for i = #listeners, 1, -1 do
            if (listeners[i].identifier == identifier) then
                tremove(listeners, i);
                break;
            end
        end

        -- Last listener for this event removed → stop receiving the game event.
        if (#listeners == 0) then
            self.Listeners[event] = nil;

            if (event:sub(1, 4) ~= "ACP_") then
                self.Frame:UnregisterEvent(event);
            end
        end
    end

    self.EventByIdentifier[identifier] = nil;
end

--- Fire an internal event; all subscribers receive the payload arguments.
---@param event string
function Events:fire(event, ...)
    local listeners = self.Listeners[event];

    if (not listeners) then
        return;
    end

    for _, listener in ipairs(listeners) do
        listener.callback(...);
    end
end

return ACP;
