-- ArenaChillPrep — Data/Localization
-- UI strings. L has a metatable fallback to the key itself when a translation
-- is missing, so a missing string never crashes and is easy to spot in chat.

---@type ACP
local _, ACP = ...;

local GetLocale = _G.GetLocale;

ACP.Data = ACP.Data or {};

local locale = GetLocale();
local DefaultLocale = "enUS";

local strings = {
    enUS = {
        loaded = "v%s loaded",
        status = "initialized: %s, state: %s",
        help = "ArenaChillPrep commands: status, enable, disable, debug, help",
        unknownCommand = "Unknown command: %s. Type /acp help",
        enabled = "Addon enabled",
        disabled = "Addon disabled",
        debugToggled = "Debug logging: %s",

        -- Options panel
        panelTitle = "ArenaChillPrep",
        generalSection = "General",
        autotradeSection = "Autotrade",
        generalHeader = "General",
        enabledLabel = "Enable auto-trade during arena preparation",
        enabledTooltip = "Master switch. When off, no trades are initiated during arena preparation.",
        bracketsHeader = "Arena brackets",
        bracket2v2Tooltip = "Enable auto-trade in the 2v2 bracket (currently active)",
        bracket3v3Tooltip = "Enable auto-trade in the 3v3 bracket (disabled in this version)",
        bracket5v5Tooltip = "Enable auto-trade in the 5v5 bracket (disabled in this version)",
        ranksLabel = "Ranks to pass",
        rankTooltip = "Pass %s healthstones to your partner during arena preparation",
        timingHeader = "Timing",
        tradeDelayLabel = "Trade delay (seconds):",
        tradeDelayTooltip = "Seconds between the item appearing in your bags and the trade window opening",
        gateSafetyLabel = "Stop trading N seconds before the gates open:",
        gateSafetyTooltip = "Stop initiating trades N seconds before the gates open",
        resetButton = "Reset to defaults",
        resetTooltip = "Restore all settings to their default values",
        ranks = {
            "Minor", "Lesser", "Healthstone", "Greater", "Major", "Master",
        },
    },
    ruRU = {
        loaded = "v%s загружен",
        status = "initialized: %s, state: %s",
        help = "ArenaChillPrep команды: status, enable, disable, debug, help",
        unknownCommand = "Неизвестная команда: %s. Введите /acp help",
        enabled = "Аддон включён",
        disabled = "Аддон выключен",
        debugToggled = "Отладка: %s",

        -- Options panel
        panelTitle = "ArenaChillPrep",
        generalSection = "Общие",
        autotradeSection = "Автообмен",
        generalHeader = "Общие",
        enabledLabel = "Авто-обмен во время подготовки к арене",
        enabledTooltip = "Главный переключатель. Когда выключен, обмен во время подготовки к арене не инициируется.",
        bracketsHeader = "Брекеты арены",
        bracket2v2Tooltip = "Авто-обмен в брекете 2v2 (активен сейчас)",
        bracket3v3Tooltip = "Авто-обмен в брекете 3v3 (отключено в этой версии)",
        bracket5v5Tooltip = "Авто-обмен в брекете 5v5 (отключено в этой версии)",
        ranksLabel = "Ранги для передачи",
        rankTooltip = "Передавать %s камни здоровья партнёру во время подготовки к арене",
        timingHeader = "Тайминги",
        tradeDelayLabel = "Задержка обмена (секунды):",
        tradeDelayTooltip = "Секунды между появлением предмета в сумках и открытием окна обмена",
        gateSafetyLabel = "Прекратить обмен за N секунд до открытия ворот:",
        gateSafetyTooltip = "Прекратить инициировать обмен за N секунд до открытия ворот",
        resetButton = "Сбросить настройки",
        resetTooltip = "Вернуть все настройки к значениям по умолчанию",
        ranks = {
            "Малый", "Меньший", "Обычный", "Большой", "Крупный", "Мастер",
        },
    },
};

---@class Localization
local L = setmetatable({}, {
    __index = function(_, key)
        local table_ = strings[locale] or strings[DefaultLocale];
        local value = table_[key];

        if (value == nil) then
            -- Missing translation — fall back to the key so it stands out.
            return tostring(key);
        end

        return value;
    end,
});

ACP.Data.Localization = L;
-- Convenience alias used by modules (bootstrap, slash commands, UI).
ACP.L = L;

return ACP;
