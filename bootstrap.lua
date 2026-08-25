-- ArenaChillPrep — bootstrap
-- Entry point: creates the global ACP table, the event frame, and initializes
-- modules in dependency order on ADDON_LOADED.

---@type string
local ADDON_NAME, ACP = ...;
ACP = ACP or {};

local DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME;
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata;

-- Expose the single global table.
_G.ACP = ACP;

ACP.name = ADDON_NAME;
ACP.version = GetAddOnMetadata(ADDON_NAME, "Version") or "0.1.0";
ACP._initialized = false;
ACP.debug = false;

ACP.Data = ACP.Data or {};
ACP.Utils = ACP.Utils or {};

-- In-memory ring buffer for chat output (survives until /reload; the
-- "blocked addon" popup can make chat un-copyable, so /acp dumplog reprints it).
ACP.DEBUG_LOG_MAX = 200;
ACP.DebugLog = {};

-- Invisible frame that receives raw game events.
ACP.Frame = CreateFrame("Frame", "ArenaChillPrepFrame");

--- Append a formatted line to the in-memory debug log (ring buffer).
---@param text string
function ACP:log(text)
    if (type(text) ~= "string") then
        text = tostring(text);
    end

    table.insert(self.DebugLog, text);

    if (#self.DebugLog > self.DEBUG_LOG_MAX) then
        table.remove(self.DebugLog, 1);
    end
end

--- Log a message to the default chat frame with the addon prefix.
---@param message string
function ACP:print(message, ...)
    if (message == nil) then
        return;
    end

    local text = ("|cffb48affACP|r: " .. tostring(message)):format(...);
    DEFAULT_CHAT_FRAME:AddMessage(text);
    self:log(text);
end

--- Log a message to chat only when debug mode is on.
---@param message string
function ACP:debugPrint(message, ...)
    if (not self.debug) then
        return;
    end

    self:print(message, ...);
end

--- Initialize every module in strict dependency order.
function ACP:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    self.Events:_init(self.Frame);
    self.Settings:_init();
    if (self.WorkflowSpellbook and self.WorkflowSpellbook._init) then
        self.WorkflowSpellbook:_init();
    end
    self.ArenaPrep:_init();
    self.Inventory:_init();
    self.TradeManager:_init();
    self.WorkflowEngine:_init();
    self.DeliveryController:_init();
    self.WorkflowBindings:_init();
    self.OptionsUI:_init();
    self.Welcome:_init();

    -- Handle /reload inside an arena.
    self.ArenaPrep:checkNow();

    self:debugPrint(self.L.loaded, self.version);
end

ACP.Frame:RegisterEvent("ADDON_LOADED");
ACP.Frame:SetScript("OnEvent", function(_, event, addonName)
    if (event == "ADDON_LOADED" and addonName == ADDON_NAME) then
        ACP.Frame:UnregisterEvent("ADDON_LOADED");
        ACP:_init();
    end
end);

return ACP;
