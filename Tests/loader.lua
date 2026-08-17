-- ArenaChillPrep — Tests/loader.lua
-- Loads every addon module in TOC order through the vararg chain
-- (local _, ACP = ...; return ACP;), mirroring the real load order.
-- The addon root path is passed as the first vararg by run_tests.lua.

local ADDON_ROOT = ...;

local ADDON_NAME = "ArenaChillPrep";
local ACP = {};
_G.ACP = ACP;

local function load(relPath)
    local chunk = assert(loadfile(ADDON_ROOT .. "/" .. relPath));
    chunk(ADDON_NAME, ACP);
end

load("bootstrap.lua");
load("Data/Constants.lua");
load("Data/Items.lua");
load("Data/DefaultSettings.lua");
load("Data/Localization.lua");
load("Utils/Tables.lua");
load("Utils/Items.lua");
load("Utils/Timers.lua");
load("Classes/Events.lua");
load("Classes/Settings.lua");
load("Classes/ArenaPrep.lua");
load("Classes/Inventory.lua");
load("Classes/DeliveryController.lua");
load("Classes/TradeManager.lua");
load("Classes/UI/Widgets.lua");
load("Classes/OptionsUI.lua");

return ACP;