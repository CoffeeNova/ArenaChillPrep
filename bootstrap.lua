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

-- Invisible frame that receives raw game events.
ACP.Frame = CreateFrame("Frame", "ArenaChillPrepFrame");

--- Log a message to the default chat frame with the addon prefix.
---@param message string
function ACP:print(message, ...)
    if (message == nil) then
        return;
    end

    DEFAULT_CHAT_FRAME:AddMessage(("|cffb48affACP|r: " .. tostring(message)):format(...));
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
    self.ArenaPrep:_init();
    self.Inventory:_init();
    self.TradeManager:_init();
    self.DeliveryController:_init();
    self.OptionsUI:_init();

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
