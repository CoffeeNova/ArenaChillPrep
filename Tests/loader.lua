-- ArenaChillPrep — Tests/loader.lua

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
load("Data/Workflows.lua");
load("Utils/Tables.lua");
load("Utils/Items.lua");
load("Utils/Timers.lua");
load("Classes/Events.lua");
load("Classes/Settings.lua");
load("Classes/SettingsMigrator.lua");
load("Classes/WorkflowRepository.lua");
load("Classes/WorkflowKeybindController.lua");
load("Classes/TradePlanner.lua");
load("Classes/StateMachine.lua");
load("Classes/Preconditions.lua");
load("Classes/SpellbookCatalogBuilder.lua");
load("Classes/WarlockCatalogExtender.lua");
load("Classes/SpellbookLabels.lua");
load("Classes/ArenaPrep.lua");
load("Classes/Inventory.lua");
load("Classes/DeliveryController.lua");
load("Classes/TradeManager.lua");
load("Classes/WorkflowSpellbook.lua");
load("Classes/WorkflowEngine.lua");
load("Classes/WorkflowCastController.lua");
load("Classes/PetAbilityCaster.lua");
load("Classes/WorkflowItemSteps.lua");
load("Classes/WorkflowBindings.lua");
load("Classes/UI/Widgets.lua");
load("Classes/OptionsUI.lua");

return ACP;
