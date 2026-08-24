-- ArenaChillPrep — Classes/WorkflowEngine
-- Core state machine + step orchestration. Runs a user-defined sequence of
-- warlock prep actions: cast buffs, summon a pet, create items (healthstones).
-- State machine IDLE→RUNNING→PAUSED→DONE, resets to IDLE on ACP_BUFF_LOST.
-- Pure logic (no UI); ALL steps cast through a hidden secure button bound to
-- ONE hotkey — 20506 blocks insecure casting (CastSpellByID/CastSpellByName)
-- for cast-time AND instant spells outside safe zones, so only a real
-- hardware key press can cast (verified 2026-08-19).
--
-- REFACTOR (Phase 5, 2026-08-24): the step EXECUTORS were extracted into
--   WorkflowCastController  — player-cast steps + UNIT_SPELLCAST_* events
--   PetAbilityCaster        — pet steps + the PostClick press handling
--   WorkflowItemSteps       — createItem/equipItem + item waits
--   WorkflowBindings        — secure buttons + key binding management
-- The engine keeps the state, the gates, the catalog/aura helpers, the
-- lifecycle (start/pause/reset/advance) and a per-step-type dispatch table
-- (W9). The extracted modules operate ON the engine (first argument); the
-- delegating methods below keep the engine's public surface stable.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local pcall = _G.pcall;
local select = _G.select;
local tostring = _G.tostring;
local InCombatLockdown = _G.InCombatLockdown;
local UnitCastingInfo = _G.UnitCastingInfo;
local IsPlayerMoving = _G.IsPlayerMoving;
local IsPlayerSpell = _G.IsPlayerSpell;
local GetSpellInfo = _G.GetSpellInfo;
local UnitGUID = _G.UnitGUID;
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex;

---@class WorkflowEngine
local WorkflowEngine = {
    _initialized = false,

    --- "IDLE" | "RUNNING" | "PAUSED" | "DONE"
    state = "IDLE",

    ---@type number|nil
    currentSlot = nil,

    ---@type number
    stepIndex = 1,

    --- True while waiting for a cast-time spell to finish (guards the
    --- UNIT_SPELLCAST_* handlers so instant steps and other addons' casts
    --- never advance the engine).
    ---@type boolean
    waitingForCast = false,

    --- Whether the client ACCEPTED the current cast (UNIT_SPELLCAST_SENT).
    --- False + no cast in progress at the timeout => the cast call was
    --- dropped by the client (typically a protected action in a restricted
    --- state), reported as "castBlocked" instead of a bare "castTimeout".
    ---@type boolean
    castAccepted = false,

    --- CAST-TIME steps: waiting for the USER to press the workflow hotkey —
    --- the hardware event the 20506 client requires (insecure casting of
    --- cast-time spells is blocked even out of combat). True until
    --- UNIT_SPELLCAST_SENT/START transitions to waitingForCast.
    ---@type boolean
    waitingForKey = false,

    --- Set when a createItem step is waiting for its item to appear.
    ---@type number|nil
    expectedItemID = nil,

    --- Item IDs a createItem step accepts as "created". On TBC 2.5.5 the stone
    --- ranks COEXIST (the client does NOT auto-upgrade a rank-5 cast to the max
    --- rank), so when the stored rank is castable the expected set is exactly
    --- { that rank's stone }. The family-widened set (every same-family stone of
    --- rank >= the step's rank) is used ONLY for the unlearned-rank fallback,
    --- where the cast is upgraded to the player's known rank (e.g. a stored
    --- unlearned rank-5 11730 casts rank 6 and yields Master 22105, not 19012).
    --- Nil for non-stone steps — then only `expectedItemID` is accepted.
    ---@type table|nil
    expectedItemIDs = nil,

    --- Bag count of `expectedItemIDs` captured just BEFORE the createItem cast,
    --- so completion is a delta (a NEW stone appeared), not mere presence — a
    --- leftover higher-rank stone must not satisfy a lower-rank step.
    ---@type number|nil
    expectedBaseline = nil,

    --- The spellID actually cast for the current step after rank resolution
    --- (an unlearned lower rank is upgraded to the player's known rank). Set by
    --- castSpell/createItem just before requestKeyCast; read by requestKeyCast.
    ---@type number|nil
    pendingCastSpellID = nil,

    --- True while an equipItem step waits for the user to press the hotkey
    --- (the secure button is re-pointed at the item; no spell events fire for
    --- item use, so completion is poll-driven: the item leaving the bags).
    ---@type boolean
    waitingForEquip = false,

    --- The itemID an equipItem step is trying to equip (poll guard).
    ---@type number|nil
    equipItemID = nil,

    --- Index of a pet step armed during the current player cast so its key can
    --- be pressed BEFORE the cast finishes (the pet casts independently). Nil
    --- when no pet step is armed.
    ---@type number|nil
    pendingPetStep = nil,

    --- Whether the armed pet step's key was pressed (the pet cast the ability).
    ---@type boolean
    petStepDone = false,

    --- True while a standalone pet step waits for its key press (no player cast
    --- in progress; the pet casts the ability on its own).
    ---@type boolean
    waitingForPet = false,

    --- Per-slot secure cast buttons (slot → frame). Each is permanently
    --- click-bound (session-transient SetBindingClick) to that slot's Key
    --- Bindings UI key: PreClick starts/resumes the slot and the SAME press's
    --- click casts the freshly armed step (one press = start + cast,
    --- 2026-08-22 redesign — the old takeover/release dance is gone).
    --- Managed by WorkflowBindings.
    ---@type table<number, frame>
    castButtons = {},

    --- The Key Bindings UI key each slot's button is click-bound to
    --- (slot → key string). Filled by applySlotBindings; nil when the slot has
    --- no bound key. The session-transient click takeover NEVER touches the
    --- bindings-cache (no SaveBindings) and is reverted on PLAYER_LOGOUT.
    ---@type table<number, string>
    slotKeys = {},

    --- DEBUG: bypass the arena-prep requirement (start() and the notArena
    --- gate). Set via /acp workflowtest to test casts outside an arena.
    ---@type boolean
    debugBypass = false,
};

---@type WorkflowEngine
ACP.WorkflowEngine = WorkflowEngine;

--- Max aura index scanned by the skip-if-buffed check.
local MAX_AURA_INDEX = 40;

--- State machine values (Data/Constants.WORKFLOW_STATE).
local WS = ACP.Data.Constants.WORKFLOW_STATE;

--- Pause reason keys (Data/Constants.WORKFLOW_REASON).
local Reason = ACP.Data.Constants.WORKFLOW_REASON;

local C = ACP.Data.Constants;

--- Per-step-type dispatch (W9): one lookup replaces the old multi-site
--- if/elseif chains (executeCurrentStep / isStepGoalMet / effectiveSkip /
--- checkGates). `run` executes the step; `goalMet` reports whether its goal
--- is already met (skip-if-buffed); `skippable` opts into the global skip
--- default; `needsKnownSpell` gates the player-spell check; `petDoneAware`
--- consumes the petStepDone flag; `petExempt` exempts the step from the
--- player-casting/movement gates. Handlers live in the extracted step
--- modules — the old if/elseif chain is preserved in git history
--- (HEAD 9f0cb9e).
local STEP_DISPATCH = {
    [C.WORKFLOW_STEP_EQUIP_ITEM] = {
        run = function(engine, step)
            return ACP.WorkflowItemSteps:equipItem(engine, step);
        end,
        needsKnownSpell = false,
    },
    [C.WORKFLOW_STEP_PET] = {
        run = function(engine, step)
            return ACP.PetAbilityCaster:petAbility(engine, step);
        end,
        needsKnownSpell = false,
        petDoneAware = true,
        petExempt = true,
    },
    [C.WORKFLOW_STEP_CAST] = {
        run = function(engine, step)
            return ACP.WorkflowCastController:castSpell(engine, step);
        end,
        goalMet = function(engine, step)
            return engine:isAlreadyBuffed(step);
        end,
        skippable = true,
        needsKnownSpell = true,
    },
    [C.WORKFLOW_STEP_SUMMON] = {
        run = function(engine, step)
            return ACP.WorkflowCastController:castSpell(engine, step);
        end,
        goalMet = function(engine, step)
            return engine:isAlreadySummoned(step);
        end,
        skippable = true,
        needsKnownSpell = true,
    },
    [C.WORKFLOW_STEP_CREATE_ITEM] = {
        run = function(engine, step)
            return ACP.WorkflowItemSteps:createItem(engine, step);
        end,
        goalMet = function(engine, step)
            return ACP.WorkflowItemSteps:isItemAlreadyPresent(engine, step);
        end,
        skippable = true,
        needsKnownSpell = true,
    },
};

--- Cancel every engine timer by name (named timers — see Utils/Timers).
function WorkflowEngine:cancelTimers()
    ACP.Utils.Timers:cancel("WorkflowCastTimeout");
    ACP.Utils.Timers:cancel("WorkflowGCD");
    ACP.Utils.Timers:cancel("WorkflowItemPoll");
    ACP.Utils.Timers:cancel("WorkflowPetVerify");
end

--- State write with change-suppression log + enum validation (StateMachine
--- mixin — the WS table is the WORKFLOW_STATE enum).
---@param newState string
function WorkflowEngine:setState(newState)
    ACP.StateMachine:setState(self, newState, WS);
end

--- Localized name of a spell, falling back to the catalog's English label
--- (and finally "#<id>") when GetSpellInfo cannot resolve it.
---@param spellID number
---@return string
function WorkflowEngine:spellName(spellID)
    if (GetSpellInfo) then
        local name = select(1, GetSpellInfo(spellID));

        if (name) then
            return name;
        end
    end

    local entry = self:getCatalogEntry(spellID);

    return (entry and entry.name) or ("#" .. tostring(spellID));
end

--- Localized name of an item for an equipItem step: GetItemInfo first
--- (the created stone is in bags by then, so the info is cached), then the
--- step's stored itemName (catalog/English fallback), then "item:<id>".
---@param step table
---@return string
function WorkflowEngine:itemName(step)
    local itemID = step.itemID;

    if (GetItemInfo) then
        local ok, name = pcall(GetItemInfo, itemID);

        if (ok and name) then
            return name;
        end
    end

    if (type(step.itemName) == "string" and step.itemName ~= "") then
        return step.itemName;
    end

    return "item:" .. tostring(itemID);
end

--- Catalog entry for a spell, or nil. The catalog lives in
--- ACP.Data.Workflows.spells (grouped by category — buffs/summons/createItem/
--- utility).
---@param spellID number
---@return table|nil
function WorkflowEngine:getCatalogEntry(spellID)
    if (ACP.WorkflowSpellbook and ACP.WorkflowSpellbook.getEntry) then
        local runtimeEntry = ACP.WorkflowSpellbook:getEntry(spellID);

        if (runtimeEntry) then
            return runtimeEntry;
        end
    end

    local spells = ACP.Data.Workflows and ACP.Data.Workflows.spells;

    if (not spells) then
        return nil;
    end

    for _, category in pairs(spells) do
        for _, entry in ipairs(category) do
            if (entry.spellID == spellID) then
                return entry;
            end
        end
    end

    return nil;
end

--- Resolve the spell a step should ACTUALLY cast and the item it will create.
--- If the stored rank is castable (IsPlayerSpell), it is used verbatim — the
--- player explicitly chose that rank and it is the spell they can cast (e.g.
--- rank 5 "Create Healthstone (rank 5)" / 11730, which is learned and castable).
--- Only when the stored rank is UNLEARNED (the client replaced it with a higher
--- rank at level-up) do we fall back to the highest KNOWN rank of the same
--- family. The family lookup uses the family name (e.g. "Create Healthstone"),
--- not the rank-suffixed localized spell name, so the spellbook group matches.
--- Both the cast and the completion check use this resolved rank so an unlearned
--- lower rank no longer silently stalls, while a deliberately-stored castable
--- rank is never overridden.
---@param step table
---@return number castSpellID
---@return number castItemID
function WorkflowEngine:resolveCastInfo(step)
    local spellID = step.spellID;

    local ok, known = pcall(IsPlayerSpell, spellID);
    if (ok and known) then
        return spellID, step.itemID or (self:getCatalogEntry(spellID) and self:getCatalogEntry(spellID).itemID) or spellID;
    end

    local stone = ACP.Data.Workflows and ACP.Data.Workflows.stoneRanks
        and ACP.Data.Workflows.stoneRanks[spellID];
    local familyName = (stone and stone.spellName) or self:spellName(spellID);

    local highest = (familyName and familyName:sub(1, 1) ~= "#" and ACP.WorkflowSpellbook)
        and ACP.WorkflowSpellbook:getHighestKnownRank(familyName) or nil;

    if (highest) then
        return highest.spellID, highest.itemID or step.itemID;
    end

    return spellID, step.itemID;
end

--- Settings definition of a workflow slot, or nil when it is missing or
--- disabled. When the debug bypass is active (workflowtest), the per-slot
--- enabled flag is ignored so ANY slot can be tested regardless of state.
---@param slot number
---@return table|nil
function WorkflowEngine:getDefinition(slot)
    local definition = ACP.Settings:get(ACP.WorkflowRepository:definitionPath(slot));

    if (type(definition) == "table" and (self.debugBypass or definition.enabled)) then
        return definition;
    end

    return nil;
end

--- Name of the running/paused workflow (for log messages).
---@return string
function WorkflowEngine:definitionName()
    local definition = self.currentSlot and self:getDefinition(self.currentSlot);

    return definition and definition.name or "";
end

--- Whether the player knows the spell. IsPlayerSpell accepts a spell NAME
--- (matches any known rank — a trained rank replaces the base ID in the
--- spellbook, so the rank-1 catalog ID alone would be false at max level) or
--- an ID (the TrackingEye-proven form). Both checks are pcall-guarded.
---@param step table
---@return boolean
function WorkflowEngine:knowsSpell(step)
    local name = self:spellName(step.spellID);

    if (IsPlayerSpell and name and name:sub(1, 1) ~= "#") then
        local ok, known = pcall(IsPlayerSpell, name);
        if (ok and known) then
            return true;
        end
    end

    if (IsPlayerSpell) then
        local ok, known = pcall(IsPlayerSpell, step.spellID);
        if (ok and known) then
            return true;
        end
    end

    return false;
end

--- Per-step gates (§3.7). Returns nil when every gate passes, or the reason
--- key of the failing gate (localized via L.workflow.reason*).
---@param step table
---@return string|nil
function WorkflowEngine:checkGates(step)
    if (not ACP.Preconditions:enabled() or not ACP.Settings:get("workflows.enabled")) then
        return Reason.EngineDisabled;
    end

    if (not self.debugBypass and not ACP.Preconditions:buffActive()) then
        return Reason.NotArena;
    end

    if (not ACP.Preconditions:notInLockdown()) then
        return Reason.InCombat;
    end

    if (not ACP.Preconditions:notDead()) then
        return Reason.Dead;
    end

    -- Target-availability gate: a step configured for a party member must not
    -- silently cast on the wrong unit (live 2026-08-22: party-targeted Fire
    -- Shield and Unending Breath landed on the PLAYER — the unit token never
    -- resolved on the cast side). When the party slot is missing (solo test,
    -- raid group, member left), pause with a clear reason instead of
    -- mis-buffing. Checked BEFORE the pet exemption so pet steps get it too.
    if (step.target and step.target ~= "player" and _G.UnitExists and not _G.UnitExists(step.target)) then
        return Reason.NoTarget;
    end

    local handler = STEP_DISPATCH[step.type];

    -- Pet-ability steps are cast by the pet, not the player — they are exempt
    -- from the player-casting and movement gates so they can be applied DURING
    -- the previous step's cast.
    if (not (handler and handler.petExempt)) then
        if (UnitCastingInfo and UnitCastingInfo("player")) then
            return Reason.Casting;
        end

        -- Pause-on-move is an unconditional safety rule. Instant self-buffs can be
        -- cast while moving on some clients, so workflows always wait for the
        -- player to stop; there is no user setting for this behavior.
        if (IsPlayerMoving and IsPlayerMoving()) then
            return Reason.Moving;
        end
    end

    -- Reagent gate: summon/createItem steps consume a Soul Shard (6265).
    -- A live scan (countItem) — the Inventory cache only tracks healthstones.
    local entry = self:getCatalogEntry(step.spellID);

    if (entry and entry.needsShard and ACP.Inventory:countItem(ACP.Data.Constants.SOUL_SHARD_ITEM_ID) < 1) then
        return Reason.NoShard;
    end

    -- Gate safety: stop CAST-TIME steps close to the gates opening. Instant
    -- spells and steps without a cast time (equipItem, unknown spells, pet
    -- abilities) complete in <1 GCD and cannot be caught mid-cast — a
    -- gateSafety pause on an instant step created a resume→pause infinite
    -- loop (live 2026-08-22). Instant steps just proceed.
    if (not entry or not entry.isCastTime) then
        return nil;
    end

    if (not ACP.Preconditions:gateSafetyOk()) then
        return Reason.GateSafety;
    end

    return nil;
end

--- The creature entry ID a summon spell produces, resolved from the static
--- `Data.Workflows.spells` catalog (the runtime spellbook scan does not carry
--- `petEntry`). Locale-independent — used to match the active pet's GUID.
---@param spellID number
---@return number|nil
function WorkflowEngine:getPetEntry(spellID)
    local spells = ACP.Data.Workflows and ACP.Data.Workflows.spells;

    if (not spells) then
        return nil;
    end

    for _, category in pairs(spells) do
        for _, entry in ipairs(category) do
            if (entry.spellID == spellID and entry.petEntry) then
                return entry.petEntry;
            end
        end
    end

    return nil;
end

--- Whether the summoned pet for this step is ALREADY the active pet. Matches
--- the creature entry ID from the pet's GUID (locale-independent) against the
--- summon catalog entry's `petEntry`, so a summon step is skipped when the same
--- pet is already out (e.g. arena reload mid-prep, or a duplicate step).
---@param step table
---@return boolean
function WorkflowEngine:isAlreadySummoned(step)
    if (not UnitExists or not UnitExists("pet") or not UnitGUID) then
        return false;
    end

    local petEntry = self:getPetEntry(step.spellID);

    if (not petEntry) then
        return false;
    end

    local guid = UnitGUID("pet");

    if (not guid) then
        return false;
    end

    -- TBC Classic 2.5.x GUID format for a creature/pet:
    --   <type>-<server>-<instance>-<zone>-<entry>-<spawnHex>
    -- where <type> is the unit-type word ("Pet"/"Creature"/"Vehicle", verified
    -- live as "Pet-0-6423-1-18-416-1100B8E8E4") — %w+ covers both the word and
    -- any numeric-type builds. The creature entry ID is the 5th segment.
    local id = guid:match("^%w+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$");

    ACP:debugPrint("workflow pet GUID %s -> entry %s (want %s)", tostring(guid), tostring(id), tostring(petEntry));

    return id ~= nil and tonumber(id) == petEntry;
end

--- Whether a step's goal is already met (so a skipIfBuffed step can be skipped
--- without casting). Buff steps → aura present; summon → pet already out;
--- createItem → product already in bags. Per-type via the dispatch table (W9).
---@param step table
---@return boolean
function WorkflowEngine:isStepGoalMet(step)
    local handler = STEP_DISPATCH[step.type];

    if (handler and handler.goalMet) then
        return handler.goalMet(self, step);
    end

    return false;
end

--- Whether a step should skip when its goal is already met. The global
--- "skip completed steps" setting (`workflows.skipIfBuffedDefault`) is the
--- master switch for `cast` (buff) / `summon` / `createItem` steps, so it
--- governs existing workflows whose steps were saved without an explicit flag
--- (the user's complaint: a summoned pet / conjured item should not be
--- re-done just because the per-step flag was never set). An explicit per-step
--- `skipIfBuffed` overrides the setting: `false` never skips, `true` always
--- skips.
---@param step table
---@return boolean
function WorkflowEngine:effectiveSkip(step)
    if (step.skipIfBuffed == false) then
        return false;
    end

    if (step.skipIfBuffed == true) then
        return true;
    end

    local handler = STEP_DISPATCH[step.type];

    if (handler and handler.skippable) then
        return ACP.Settings:get("workflows.skipIfBuffedDefault") == true;
    end

    return false;
end

--- Whether `name` is among the HELPFUL auras on `unit`, matched by NAME
--- (rank-agnostic — a higher-rank cast has a different spellID than the
--- catalog entry). Uses C_UnitAuras.GetAuraDataByIndex (the verified 20506
--- aura API).
---@param unit string
---@param name string
---@return boolean
function WorkflowEngine:hasBuff(unit, name)
    if (not GetAuraDataByIndex or name:sub(1, 1) == "#") then
        return false;
    end

    for i = 1, MAX_AURA_INDEX do
        local aura = GetAuraDataByIndex(unit, i, "HELPFUL");

        if (not aura) then
            break;
        end

        if (aura.name == name) then
            return true;
        end
    end

    return false;
end

---@param step table
---@return boolean
function WorkflowEngine:isAlreadyBuffed(step)
    return self:hasBuff(step.target or "player", self:spellName(step.spellID));
end

--- Clear the transient per-step wait state (the RUNNING sub-state flags).
--- `includePetDone` also clears petStepDone — a pet ability pressed DURING the
--- just-finished player cast must survive advance() (so executeCurrentStep
--- skips that pet step instead of re-arming it), but pause/reset start fresh.
--- castAccepted is always cleared: it is only read by onCastTimeout, which is
--- only armed after a fresh SENT/START (W11 — no stale flag across states).
---@param includePetDone boolean
function WorkflowEngine:clearTransientState(includePetDone)
    self.waitingForCast = false;
    self.waitingForKey = false;
    self.waitingForEquip = false;
    self.waitingForPet = false;
    self.instantPressDetected = false;
    self.castAccepted = false;
    self.expectedItemID = nil;
    self.expectedItemIDs = nil;
    self.expectedBaseline = nil;
    self.pendingCastSpellID = nil;
    self.equipItemID = nil;
    self.pendingPetStep = nil;

    if (includePetDone) then
        self.petStepDone = false;
    end
end

--- Advance to the next step after cleaning up the current wait. Recurses
--- through skip paths; the natural GCD/event waits yield between cast steps.
--- NOTE: `pendingPetStep` is cleared (the arming is per-cast), but
--- `petStepDone` is deliberately NOT — a pet ability pressed DURING the
--- just-completed cast must survive this transition so executeCurrentStep
--- skips that pet step instead of re-arming it (pause/reset/interrupt clear
--- it; the pet-step branch consumes it).
function WorkflowEngine:advance()
    self:cancelTimers();
    self:clearTransientState(false);
    self.stepIndex = self.stepIndex + 1;
    self:executeCurrentStep();
end

--- Run the current step: gates, unknown-spell/buff skips, dispatch by type
--- (W9 handler table). Also the DONE transition (stepIndex past the last
--- step, incl. empty workflows).
function WorkflowEngine:executeCurrentStep()
    if (self.state ~= WS.RUNNING) then
        return;
    end

    local definition = self:getDefinition(self.currentSlot);
    local steps = (definition and type(definition.steps) == "table") and definition.steps or {};
    local step = steps[self.stepIndex];

    -- Out of steps → DONE.
    if (not step) then
        self:cancelTimers();
        self:clearKeyCast();
        self:setState(WS.DONE);
        ACP:debugPrint(ACP.L.workflow.done, self.currentSlot, self:definitionName());
        ACP.Events:fire("ACP_WORKFLOW_DONE");
        return;
    end

    -- Validate the step schema (§3.5) — an invalid step is skipped, not fatal.
    local ok, err = ACP.Data.Workflows:validateStep(step);

    if (not ok) then
        ACP:debugPrint(ACP.L.workflow.stepSkippedInvalid, self.stepIndex, tostring(err));
        self:advance();
        return;
    end

    ACP.Events:fire("ACP_WORKFLOW_STEP", self.currentSlot, self.stepIndex, step);

    -- skipIfBuffed → skip WITHOUT casting when the step's goal is already met
    -- (buff present, pet already summoned, or item already in bags). Checked
    -- before the gates so a met goal is honored even when a reagent/combat gate
    -- would otherwise pause the step (no point conjuring a stone you already
    -- have, or summoning a pet that is already out).
    if (self:effectiveSkip(step) and self:isStepGoalMet(step)) then
        ACP:debugPrint(ACP.L.workflow.stepSkippedDone, self.stepIndex);
        self:advance();
        return;
    end

    -- Gates (§3.7): a failing gate pauses — the user fixes the condition and
    -- presses the key to resume from the same step.
    local reason = self:checkGates(step);

    if (reason) then
        self:pause(reason);
        return;
    end

    -- Dispatch by type (W9 handler table — the old if/elseif chain is in git
    -- history, HEAD 9f0cb9e).
    local handler = STEP_DISPATCH[step.type];

    -- Pet abilities are cast by the pet, not the player — a pet step already
    -- pressed during the previous player cast is skipped here.
    if (handler and handler.petDoneAware and self.petStepDone) then
        self.petStepDone = false;
        self:advance();
        return;
    end

    -- Unknown spell → skip the step, continue with the next. Spell steps only:
    -- equipItem has no spellID and pet abilities are never player spells.
    if (handler and handler.needsKnownSpell and not self:knowsSpell(step)) then
        ACP:debugPrint(ACP.L.workflow.stepSkippedUnknown, self.stepIndex);
        self:advance();
        return;
    end

    if (handler) then
        handler.run(self, step);
    end
end

--- Pause the running workflow (state → PAUSED), keeping the current step so
--- the next key press resumes from it. Idempotent.
---@param reason string  reason key (L.workflow.reason*)
function WorkflowEngine:pause(reason)
    if (self.state ~= WS.RUNNING) then
        return;
    end

    self:setState(WS.PAUSED);
    self:clearTransientState(true);
    self:clearKeyCast();
    self:cancelTimers();

    local localized = ACP.L.workflow["reason" .. reason] or tostring(reason);
    ACP:debugPrint(ACP.L.workflow.paused, self.currentSlot, self:definitionName(), localized);
    ACP.Events:fire("ACP_WORKFLOW_PAUSED", reason);
end

--- Reset the engine to IDLE (§3.11). Called on ACP_BUFF_LOST and when a
--- different workflow slot is started mid-run. stepIndex is in-memory only —
--- each new arena starts from step 1.
function WorkflowEngine:reset()
    self:cancelTimers();
    self:setState(WS.IDLE);
    self.currentSlot = nil;
    self.stepIndex = 1;
    self:clearTransientState(true);
    self:clearKeyCast();
    ACP:debugPrint("workflow reset");
    ACP.Events:fire("ACP_WORKFLOW_RESET");
end

--- Start a workflow slot, or resume a paused one (§3.4). No-op outside arena
--- prep, in combat, while a workflow is already running, or once DONE (a new
--- arena resets the engine via ACP_BUFF_LOST).
---@param slot number
function WorkflowEngine:start(slot)
    slot = slot or 1;

    if (type(slot) ~= "number" or slot < 1 or slot > ACP.Data.Constants.WORKFLOW_MAX_SLOTS) then
        ACP:debugPrint(ACP.L.workflow.slotUnknown, tostring(slot));
        return;
    end

    if (self.state == WS.RUNNING and self.currentSlot == slot) then
        return; -- already running
    end

    -- One run per prep/test command (2026-08-22): after DONE the key press is
    -- a no-op in BOTH modes — the user complained the workflow "went a second
    -- round". A fresh run starts on ACP_BUFF_LOST (new arena) or by re-issuing
    -- /acp workflowtest N, which resets the engine before start().
    if (self.state == WS.DONE) then
        return;
    end

    if (not ACP.Settings:get("enabled") or not ACP.Settings:get("workflows.enabled")) then
        ACP:debugPrint(ACP.L.workflow.reasonEngineDisabled);
        return;
    end

    if (not self.debugBypass and not ACP.ArenaPrep:isActive()) then
        ACP:debugPrint(ACP.L.workflow.notInArena);
        return;
    end

    if (InCombatLockdown and InCombatLockdown()) then
        ACP:debugPrint(ACP.L.workflow.reasonInCombat);
        return;
    end

    local definition = self:getDefinition(slot);

    if (not definition) then
        ACP:debugPrint(ACP.L.workflow.slotInvalid, slot);
        return;
    end

    -- An empty workflow has nothing to do — say so instead of flashing
    -- "started … complete".
    if (type(definition.steps) ~= "table" or #definition.steps == 0) then
        ACP:debugPrint(ACP.L.workflow.emptyWorkflow, slot, definition.name or "");
        return;
    end

    -- A different slot is running/paused → reset first, then start fresh.
    if (self.currentSlot and self.currentSlot ~= slot
        and (self.state == WS.RUNNING or self.state == WS.PAUSED)) then
        self:reset();
    end

    -- Resume the same paused slot.
    if (self.state == WS.PAUSED and self.currentSlot == slot) then
        self:setState(WS.RUNNING);
        ACP:debugPrint(ACP.L.workflow.resumed, slot, definition.name or "", self.stepIndex);
        ACP.Events:fire("ACP_WORKFLOW_RESUMED");
        self:executeCurrentStep();
        return;
    end

    -- Fresh start.
    self.currentSlot = slot;
    self.stepIndex = 1;
    self:clearTransientState(true);
    self:setState(WS.RUNNING);
    ACP:debugPrint(ACP.L.workflow.started, slot, definition.name or "");
    ACP.Events:fire("ACP_WORKFLOW_STARTED", slot);
    self:executeCurrentStep();
end

--- Status summary for /acp status.
---@return string
function WorkflowEngine:getStatus()
    local definition = self.currentSlot and self:getDefinition(self.currentSlot);
    local steps = definition and type(definition.steps) == "table" and #definition.steps or 0;

    return string.format("%s | slot=%s | step=%d/%d | key=%s",
        self.state, tostring(self.currentSlot), self.stepIndex, steps, tostring(self:resolveCastKey(self.currentSlot)));
end

--- Initialize the engine: lifecycle events + the extracted subsystems (the
--- secure buttons and binding events live in WorkflowBindings; the cast and
--- item event handlers in their step modules).
function WorkflowEngine:_init()
    if (not ACP.StateMachine:initOnce(self)) then
        return;
    end

    ACP.WorkflowBindings:_init(self);
    ACP.WorkflowCastController:_init(self);
    ACP.WorkflowItemSteps:_init(self);

    ACP.Events:register("WE.BUFF_LOST", "ACP_BUFF_LOST", function()
        self:reset();
    end);

    -- Combat makes casting impossible (protected API) → pause; the user
    -- resumes with the key after combat ends.
    ACP.Events:register("WE.COMBAT_START", "PLAYER_REGEN_DISABLED", function()
        self:pause(Reason.InCombat);
    end);
end

-- ---------------------------------------------------------------------------
-- Delegates to the extracted step/binding modules. These keep the engine's
-- public surface stable (WorkflowUI, OptionsUI, WorkflowBindings globals and
-- the test suite call through the engine), while the implementations live in
-- their own modules operating on `self` (the engine).
-- ---------------------------------------------------------------------------

-- Cast subsystem (Classes/WorkflowCastController.lua)
function WorkflowEngine:castSpell(step)
    return ACP.WorkflowCastController:castSpell(self, step);
end

function WorkflowEngine:requestKeyCast(name, step)
    return ACP.WorkflowCastController:requestKeyCast(self, name, step);
end

function WorkflowEngine:isWaitingForKeyOrCast(unit, spellID)
    return ACP.WorkflowCastController:isWaitingForKeyOrCast(self, unit, spellID);
end

function WorkflowEngine:isRunningCastStep(unit)
    return ACP.WorkflowCastController:isRunningCastStep(self, unit);
end

function WorkflowEngine:onKeyPressed()
    return ACP.WorkflowCastController:onKeyPressed(self);
end

function WorkflowEngine:armCastTimeout()
    return ACP.WorkflowCastController:armCastTimeout(self);
end

function WorkflowEngine:onCastTimeout()
    return ACP.WorkflowCastController:onCastTimeout(self);
end

function WorkflowEngine:waitForInstantEffect(step)
    return ACP.WorkflowCastController:waitForInstantEffect(self, step);
end

function WorkflowEngine:onCastComplete()
    return ACP.WorkflowCastController:onCastComplete(self);
end

function WorkflowEngine:clearKeyCast()
    return ACP.WorkflowCastController:clearKeyCast(self);
end

-- Pet subsystem (Classes/PetAbilityCaster.lua)
function WorkflowEngine:petMacroText(step)
    return ACP.PetAbilityCaster:petMacroText(self, step);
end

function WorkflowEngine:isPetAbilityApplied(step)
    return ACP.PetAbilityCaster:isPetAbilityApplied(self, step);
end

function WorkflowEngine:armPetVerify()
    return ACP.PetAbilityCaster:armPetVerify(self);
end

function WorkflowEngine:petAbility(step)
    return ACP.PetAbilityCaster:petAbility(self, step);
end

function WorkflowEngine:onSecurePress(slot)
    return ACP.PetAbilityCaster:onSecurePress(self, slot);
end

-- Item subsystem (Classes/WorkflowItemSteps.lua)
function WorkflowEngine:createItem(step)
    return ACP.WorkflowItemSteps:createItem(self, step);
end

function WorkflowEngine:resolveExpectedItems(spellID, itemID)
    return ACP.WorkflowItemSteps:resolveExpectedItems(spellID, itemID);
end

function WorkflowEngine:expandExpectedItems(castSpellID, castItemID)
    return ACP.WorkflowItemSteps:expandExpectedItems(castSpellID, castItemID);
end

function WorkflowEngine:countExpectedItems()
    return ACP.WorkflowItemSteps:countExpectedItems(self);
end

function WorkflowEngine:isItemCreated()
    return ACP.WorkflowItemSteps:isItemCreated(self);
end

function WorkflowEngine:isItemAlreadyPresent(step)
    return ACP.WorkflowItemSteps:isItemAlreadyPresent(self, step);
end

function WorkflowEngine:equipItem(step)
    return ACP.WorkflowItemSteps:equipItem(self, step);
end

function WorkflowEngine:waitForItem(itemID)
    return ACP.WorkflowItemSteps:waitForItem(self, itemID);
end

-- Binding subsystem (Classes/WorkflowBindings.lua)
function WorkflowEngine:boundKey()
    return ACP.WorkflowBindings:boundKey(self);
end

function WorkflowEngine:bindingSet()
    return ACP.WorkflowBindings:bindingSet(self);
end

function WorkflowEngine:applyBinding()
    return ACP.WorkflowBindings:applyBinding(self);
end

function WorkflowEngine:clearBinding()
    return ACP.WorkflowBindings:clearBinding(self);
end

function WorkflowEngine:resolveCastKey(slot)
    return ACP.WorkflowBindings:resolveCastKey(self, slot);
end

function WorkflowEngine:currentButton()
    return ACP.WorkflowBindings:currentButton(self);
end

function WorkflowEngine:setCastAttribute(attr, value)
    return ACP.WorkflowBindings:setCastAttribute(self, attr, value);
end

function WorkflowEngine:onPreClick(slot)
    return ACP.WorkflowBindings:onPreClick(self, slot);
end

function WorkflowEngine:applySlotBindings()
    return ACP.WorkflowBindings:applySlotBindings(self);
end

function WorkflowEngine:clearSlotOverrides()
    return ACP.WorkflowBindings:clearSlotOverrides(self);
end

function WorkflowEngine:onBindingsUpdated()
    return ACP.WorkflowBindings:onBindingsUpdated(self);
end

return ACP;
