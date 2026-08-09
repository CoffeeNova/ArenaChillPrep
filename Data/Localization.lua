-- ArenaChillPrep — Data/Localization
-- UI strings. L has a metatable fallback to the key itself when a translation
-- is missing (same pattern as Gargul's Gargul_L), so a missing string never
-- crashes and is easy to spot in chat.

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
        generalHeader = "General",
        enabledLabel = "Enable auto-trade during arena preparation",
        autoAcceptLabel = "Auto-accept trades",
        autoAcceptTooltip = "Automatically click \"Trade\" after placing items.",
        bracketsHeader = "Arena brackets",
        bracketsTooltip = "Which arena brackets auto-trade is active in.",
        ranksLabel = "Ranks to pass",
        timingHeader = "Timing",
        tradeDelayLabel = "Trade delay (seconds):",
        gateSafetyLabel = "Stop trading N seconds before the gates open:",
        autotradeSection = "Autotrade",
        ranks = {
            "Minor", "Lesser", "Healthstone", "Greater", "Major", "Master",
        },
        categoryNames = {
            healthstone = "Healthstones",
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
        generalHeader = "Общие",
        enabledLabel = "Авто-обмен во время подготовки к арене",
        autoAcceptLabel = "Авто-принятие обмена",
        autoAcceptTooltip = "Автоматически нажимать «Обмен» после размещения предметов.",
        bracketsHeader = "Брекеты арены",
        bracketsTooltip = "В каких брекетах арены активен авто-обмен.",
        ranksLabel = "Ранги для передачи",
        timingHeader = "Тайминги",
        tradeDelayLabel = "Задержка обмена (секунды):",
        gateSafetyLabel = "Прекратить обмен за N секунд до открытия ворот:",
        autotradeSection = "Автообмен",
        ranks = {
            "Малый", "Меньший", "Обычный", "Большой", "Крупный", "Мастер",
        },
        categoryNames = {
            healthstone = "Камни здоровья",
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
