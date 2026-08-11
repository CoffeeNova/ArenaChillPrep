-- ArenaChillPrep — Data/Constants
-- Static constants: buff ID, timings, bracket map. No game calls at file scope.

---@type ACP
local _, ACP = ...;

ACP.Data = ACP.Data or {};

---@class Constants
ACP.Data.Constants = {
    -- Arena Preparation buff (spell ID, stable across locales).
    ARENA_PREP_SPELL_ID = 32727,

    -- Total prep duration in TBC arenas (the countdown messages run 60 → 0).
    -- Used to seed the gate countdown when the buff is gained before the
    -- first countdown message is seen (e.g. /reload inside an arena).
    ARENA_PREP_SECONDS = 60,

    -- Localized arena countdown messages (CHAT_MSG_BG_SYSTEM_NEUTRAL) mapped
    -- to seconds until the gates open. Verified working list on 2.5.5.
    -- enUS + ruRU — the locales we support; extend for more locales if needed.
    ARENA_COUNTDOWN_MESSAGES = {
        -- English (enUS / default)
        ["One minute until the Arena battle begins!"] = 60,
        ["Thirty seconds until the Arena battle begins!"] = 30,
        ["Fifteen seconds until the Arena battle begins!"] = 15,
        ["The Arena battle has begun!"] = 0,

        -- Russian (ruRU)
        ["Одна минута до начала боя на арене!"] = 60,
        ["Тридцать секунд до начала боя на арене!"] = 30,
        ["Пятнадцать секунд до начала боя на арене!"] = 15,
        ["До начала боя на арене осталось 15 секунд."] = 15,
        ["Битва на арене началась!"] = 0,
        ["Бой начался!"] = 0,
    },

    -- Max trade attempts per item batch before giving up silently.
    MAX_TRADE_RETRIES = 3,

    -- Seconds to wait for the trade window to open before calling back as failed.
    TRADE_OPEN_TIMEOUT = 1.0,

    -- Seconds between placing items into the open trade window (FIFO queue tick).
    -- Placing items too fast makes the game silently remove them.
    TRADE_ITEM_TICK = 0.15,

    -- Retry backoff schedule, in seconds (index 1..MAX_TRADE_RETRIES).
    RETRY_BACKOFF = { 2, 4, 8 },

    -- Arena bracket by party size inside the arena (group is locked once inside).
    BRACKET_BY_SIZE = {
        [2] = "2v2",
        [3] = "3v3",
        [5] = "5v5",
    },

    -- Number of bags to scan: backpack (0) + 4 bags (1..4).
    NUM_BAGS = 5,

    -- Safety ticker interval while the prep buff is active.
    -- UNIT_AURA does not always fire when the buff fades on TBC — known quirk.
    BUFF_CHECK_TICK = 1.0,
};

return ACP;
