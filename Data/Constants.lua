-- ArenaChillPrep — Data/Constants
-- Static constants: buff ID, timings, bracket map, workflow state enums.

---@type ACP
local _, ACP = ...;

ACP.Data = ACP.Data or {};

---@class Constants
ACP.Data.Constants = {
    -- Not globals on TBC FrameXML (retail-only constants).
    CLASS_WARLOCK = _G.CLASS_WARLOCK or "WARLOCK",
    CLASS_MAGE = _G.CLASS_MAGE or "MAGE",
    CLASS_PRIEST = _G.CLASS_PRIEST or "PRIEST",
    CLASS_PALADIN = _G.CLASS_PALADIN or "PALADIN",
    CLASS_DRUID = _G.CLASS_DRUID or "DRUID",
    CLASS_HUNTER = _G.CLASS_HUNTER or "HUNTER",
    CLASS_SHAMAN = _G.CLASS_SHAMAN or "SHAMAN",
    CLASS_ROGUE = _G.CLASS_ROGUE or "ROGUE",
    CLASS_WARRIOR = _G.CLASS_WARRIOR or "WARRIOR",

    GATE_SAFETY_DEFAULT = 15,

    -- Arena Preparation buff (stable across locales).
    ARENA_PREP_SPELL_ID = 32727,

    -- Seeds the gate countdown when the buff is gained before the first
    -- countdown message (e.g. /reload inside an arena).
    ARENA_PREP_SECONDS = 60,

    -- Localized countdown messages (CHAT_MSG_BG_SYSTEM_NEUTRAL) → seconds
    -- until the gates open. enUS + ruRU.
    ARENA_COUNTDOWN_MESSAGES = {
        ["One minute until the Arena battle begins!"] = 60,
        ["Thirty seconds until the Arena battle begins!"] = 30,
        ["Fifteen seconds until the Arena battle begins!"] = 15,
        ["The Arena battle has begun!"] = 0,

        ["Одна минута до начала боя на арене!"] = 60,
        ["Тридцать секунд до начала боя на арене!"] = 30,
        ["Пятнадцать секунд до начала боя на арене!"] = 15,
        ["До начала боя на арене осталось 15 секунд."] = 15,
        ["Битва на арене началась!"] = 0,
        ["Бой начался!"] = 0,
    },

    TRADE_OPEN_TIMEOUT = 1.0,

    -- Placing items too fast makes the game silently remove them.
    TRADE_ITEM_TICK = 0.15,

    -- Retry backoff schedule (seconds) by 1-based retry number; the count is
    -- the `tradeRetries` setting, indices beyond this table fall back to 8 s.
    RETRY_BACKOFF = { 2, 4, 8, 12, 16 },

    -- Arena bracket by party size inside an arena (group is locked once inside).
    BRACKET_BY_SIZE = {
        [2] = "2v2",
        [3] = "3v3",
        [5] = "5v5",
    },

    -- Backpack (0) + 4 bags (1..4).
    NUM_BAGS = 5,

    -- UNIT_AURA does not always fire when the buff fades on TBC.
    BUFF_CHECK_TICK = 1.0,

    WORKFLOW_DEFAULT_SLOTS = 5,
    WORKFLOW_MAX_SLOTS = 20,

    WORKFLOW_GCD_TICK = 0.1,

    WORKFLOW_CAST_TIMEOUT = 10,

    -- Hidden SecureActionButtonTemplate that casts when the hotkey is pressed.
    WORKFLOW_BUTTON_NAME = "ACPWorkflowButton",

    -- Gates summon/createItem steps that consume a shard.
    SOUL_SHARD_ITEM_ID = 6265,

    WORKFLOW_TARGETS = { "player", "party1", "party2", "party3", "party4" },

    WORKFLOW_STATE = {
        IDLE = "IDLE",
        RUNNING = "RUNNING",
        PAUSED = "PAUSED",
        DONE = "DONE",
    },

    DELIVERY_STATE = {
        IDLE = "IDLE",
        ACTIVE = "ACTIVE",
        TRADING = "TRADING",
        DONE = "DONE",
    },

    -- Pause reason keys (localized via L.workflow["reason" .. reason]).
    WORKFLOW_REASON = {
        EngineDisabled = "engineDisabled",
        NotArena = "notArena",
        InCombat = "inCombat",
        Dead = "dead",
        NoTarget = "noTarget",
        Casting = "casting",
        Moving = "moving",
        NoShard = "noShard",
        GateSafety = "gateSafety",
        NoHotkey = "noHotkey",
        CastTimeout = "castTimeout",
        CastBlocked = "castBlocked",
        CastInterrupted = "castInterrupted",
        CastFailed = "castFailed",
    },

    WORKFLOW_STEP_CAST = "cast",
    WORKFLOW_STEP_SUMMON = "summon",
    WORKFLOW_STEP_CREATE_ITEM = "createItem",
    WORKFLOW_STEP_EQUIP_ITEM = "equipItem",
    -- A pet ability cast by the current pet; exempt from the player-casting
    -- gate so it can be applied DURING the previous step's cast.
    WORKFLOW_STEP_PET = "pet",
};

return ACP;
