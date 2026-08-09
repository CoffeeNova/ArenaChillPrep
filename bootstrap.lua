-- ArenaChillPrep — bootstrap
-- Entry point of the addon: creates the global ACP table, the invisible event
-- frame and initializes every module in dependency order on ADDON_LOADED.
--
-- NOTE: this file is loaded FIRST (see ArenaChillPrep.toc), so it must not
-- reference ACP.Data / ACP.Utils / ACP.Classes at file scope — those are only
-- guaranteed to exist once ADDON_LOADED fires (all TOC files are loaded by then).

---@type string
local ADDON_NAME, ACP = ...;
ACP = ACP or {};

local format = _G.format;
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata;

-- Expose the single global table (docs: "the addon's only global table is ACP").
_G.ACP = ACP;

ACP.name = ADDON_NAME;
ACP.version = GetAddOnMetadata(ADDON_NAME, "Version") or "0.1.0";
ACP._initialized = false;
ACP.enabled = true; -- Master switch. Phase 5 moves it into Settings (ArenaChillPrepDB).
ACP.debug = false;  -- Verbose chat logging, toggled via /acp debug.

ACP.Data = ACP.Data or {};
ACP.Utils = ACP.Utils or {};

-- Invisible frame that receives raw game events. Modules subscribe through
-- ACP.Events:register(...) — nothing registers directly on this frame.
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

--- Initialize every module in strict dependency order (see .github/ARCHITECTURE.md 2.1).
function ACP:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    -- 1. ACP.Data.* is already loaded via the TOC file order.
    -- 2. Event bus first — every other module may subscribe during its _init.
    self.Events:_init(self.Frame);
    -- 3. Settings (SavedVariables wrapper).
    self.Settings:_init();
    -- 4. Arena preparation detection (buff, bracket, remaining time).
    self.ArenaPrep:_init();
    -- 5. Bag scanner / item counters.
    self.Inventory:_init();
    -- 6. Low-level trade window automation.
    self.TradeManager:_init();
    -- 7. Orchestrator — makes all decisions.
    self.DeliveryController:_init();
    -- 8. Interface Options panel + slash commands.
    self.OptionsUI:_init();

    -- Catch the case where the prep buff is already active when the addon loads
    -- (e.g. a /reload inside an arena).
    self.ArenaPrep:checkNow();

    -- Service message (Phase 6: move to debug-only).
    self:print(self.L.loaded, self.version);
end

ACP.Frame:RegisterEvent("ADDON_LOADED");
ACP.Frame:SetScript("OnEvent", function(_, event, addonName)
    if (event == "ADDON_LOADED" and addonName == ADDON_NAME) then
        ACP.Frame:UnregisterEvent("ADDON_LOADED");
        ACP:_init();
    end
end);

-- Pass the table along the vararg chain to the next loaded file.
return ACP;
