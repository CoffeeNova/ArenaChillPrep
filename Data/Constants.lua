-- ArenaChillPrep — Data/Constants
-- Static constants: buff ID, timings, bracket map. No game calls at file scope.

---@type ACP
local _, ACP = ...;

ACP.Data = ACP.Data or {};

---@class Constants
ACP.Data.Constants = {
    -- CLASS_WARLOCK is NOT defined as a global on TBC Anniversary FrameXML
    -- (retail-only constant). Guarded single source for the class-gated
    -- catalogs (Data/Items, WorkflowSpellbook, WorkflowUI).
    CLASS_WARLOCK = _G.CLASS_WARLOCK or "WARLOCK",

    -- Default gate-safety threshold (seconds) used when the setting is
    -- missing from SavedVariables.
    GATE_SAFETY_DEFAULT = 15,

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

    -- Seconds to wait for the trade window to open before calling back as failed.
    TRADE_OPEN_TIMEOUT = 1.0,

    -- Seconds between placing items into the open trade window (FIFO queue tick).
    -- Placing items too fast makes the game silently remove them.
    TRADE_ITEM_TICK = 0.15,

    -- Retry backoff schedule, in seconds, indexed by the current retry number
    -- (1-based). How many retries are allowed is the `tradeRetries` setting
    -- (default 1); indices beyond this table fall back to 8 s.
    RETRY_BACKOFF = { 2, 4, 8, 12, 16 },

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

    -- Workflow engine (Phase 8+). Five slots are shown by default; the
    -- binding/XML capacity supports additional character-local slots.
    WORKFLOW_DEFAULT_SLOTS = 5,
    WORKFLOW_MAX_SLOTS = 20,

    -- Poll interval (seconds) for the GCD wait between instant-cast steps.
    WORKFLOW_GCD_TICK = 0.1,

    -- Safety timeout (seconds) for a cast-time step waiting for completion.
    WORKFLOW_CAST_TIMEOUT = 10,

    -- Name of the hidden SecureActionButtonTemplate that casts cast-time
    -- steps when the user presses the bound hotkey (SetBindingClick target).
    WORKFLOW_BUTTON_NAME = "ACPWorkflowButton",

    -- Soul Shard item ID (verified: Questie tbcItemDB.lua, SoulShardManager,
    -- SoulSort). Gates summon/createItem steps that consume a shard.
    SOUL_SHARD_ITEM_ID = 6265,

    -- Target unit tokens a `cast` step may use (2v2/3v3/5v5).
    WORKFLOW_TARGETS = { "player", "party1", "party2", "party3", "party4" },

    -- WorkflowEngine state machine values (WorkflowEngine.state).
    WORKFLOW_STATE = {
        IDLE = "IDLE",
        RUNNING = "RUNNING",
        PAUSED = "PAUSED",
        DONE = "DONE",
    },

    -- DeliveryController state machine values (DeliveryController.state).
    DELIVERY_STATE = {
        IDLE = "IDLE",
        ACTIVE = "ACTIVE",
        TRADING = "TRADING",
        DONE = "DONE",
    },

    -- WorkflowEngine pause reason keys (localized via
    -- L.workflow["reason" .. reason]). Shared by the engine and its extracted
    -- step modules (WorkflowCastController / PetAbilityCaster /
    -- WorkflowItemSteps) — hence in Constants, not module-local.
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

    -- Step type strings (see Data/Workflows.validateStep).
    WORKFLOW_STEP_CAST = "cast",
    WORKFLOW_STEP_SUMMON = "summon",
    WORKFLOW_STEP_CREATE_ITEM = "createItem",
    WORKFLOW_STEP_EQUIP_ITEM = "equipItem",
    -- A pet ability cast by the player's current pet (e.g. Imp Fire Shield,
    -- Voidwalker Sacrifice). The pet casts it independently — the engine
    -- exempts it from the "player is casting" gate so it can be applied
    -- DURING the previous step's cast.
    WORKFLOW_STEP_PET = "pet",
};

return ACP;
