-- ArenaChillPrep — Classes/WorkflowEngine
-- Runs a user-defined sequence of warlock prep actions: cast buffs, summon a
-- pet, create items (healthstones). State machine IDLE→RUNNING→PAUSED→DONE,
-- resets to IDLE on ACP_BUFF_LOST. Pure logic (no UI); ALL steps cast through
-- a hidden secure button bound to ONE hotkey — 20506 blocks insecure casting
-- (CastSpellByID/CastSpellByName) for cast-time AND instant spells outside
-- safe zones, so only a real hardware key press can cast (verified 2026-08-19).
--
-- Step execution is event-driven, never sleep-based (see the workflow-engine
-- development plan §3.4–3.11):
--   cast-time spells:  wait for UNIT_SPELLCAST_STOP/SUCCEEDED as a SIGNAL
--                      (verify UnitCastingInfo("player") == nil), safety
--                      timeout WORKFLOW_CAST_TIMEOUT;
--   instant spells:    poll GetSpellCooldown until duration == 0 (the natural
--                      GCD — verified shape on 20506);
--   createItem:        cast, then wait for the item to appear in bags
--                      (ACP_ITEMS_CHANGED + a polling safety net for items the
--                      Inventory cache does not track, e.g. Major Soulstone).
-- All timers run through ACP.Utils.Timers (named) — the C_Timer Cancel()
-- unreliability gotcha is honored by every callback re-checking state.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local pcall = _G.pcall;
local select = _G.select;
local tostring = _G.tostring;
local InCombatLockdown = _G.InCombatLockdown;
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost;
local UnitCastingInfo = _G.UnitCastingInfo;
local IsPlayerMoving = _G.IsPlayerMoving;
local IsPlayerSpell = _G.IsPlayerSpell;
local GetSpellCooldown = _G.GetSpellCooldown;
local GetSpellInfo = _G.GetSpellInfo;
local GetTime = _G.GetTime;
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

--- Cancel every engine timer by name (named timers — see Utils/Timers).
function WorkflowEngine:cancelTimers()
    ACP.Utils.Timers:cancel("WorkflowCastTimeout");
    ACP.Utils.Timers:cancel("WorkflowGCD");
    ACP.Utils.Timers:cancel("WorkflowItemPoll");
    ACP.Utils.Timers:cancel("WorkflowPetVerify");
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
    local definition = ACP.Settings:get("workflows.definitions." .. slot);

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
    local C = ACP.Data.Constants;
    if (not ACP.Settings:get("enabled") or not ACP.Settings:get("workflows.enabled")) then
        return "engineDisabled";
    end

    if (not self.debugBypass and not ACP.ArenaPrep:isActive()) then
        return "notArena";
    end

    if (InCombatLockdown and InCombatLockdown()) then
        return "inCombat";
    end

    if (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        return "dead";
    end

    -- Target-availability gate: a step configured for a party member must not
    -- silently cast on the wrong unit (live 2026-08-22: party-targeted Fire
    -- Shield and Unending Breath landed on the PLAYER — the unit token never
    -- resolved on the cast side). When the party slot is missing (solo test,
    -- raid group, member left), pause with a clear reason instead of
    -- mis-buffing. Checked BEFORE the pet exemption so pet steps get it too.
    if (step.target and step.target ~= "player" and _G.UnitExists and not _G.UnitExists(step.target)) then
        return "noTarget";
    end

    -- Pet-ability steps are cast by the pet, not the player — they are exempt
    -- from the player-casting and movement gates so they can be applied DURING
    -- the previous step's cast.
    if (step.type ~= C.WORKFLOW_STEP_PET) then
        if (UnitCastingInfo and UnitCastingInfo("player")) then
            return "casting";
        end

        -- Pause-on-move is an unconditional safety rule. Instant self-buffs can be
        -- cast while moving on some clients, so workflows always wait for the
        -- player to stop; there is no user setting for this behavior.
        if (IsPlayerMoving and IsPlayerMoving()) then
            return "moving";
        end
    end

    -- Reagent gate: summon/createItem steps consume a Soul Shard (6265).
    -- A live scan (countItem) — the Inventory cache only tracks healthstones.
    local entry = self:getCatalogEntry(step.spellID);

    if (entry and entry.needsShard and ACP.Inventory:countItem(ACP.Data.Constants.SOUL_SHARD_ITEM_ID) < 1) then
        return "noShard";
    end

    -- Gate safety: stop CAST-TIME steps close to the gates opening. Instant
    -- spells and steps without a cast time (equipItem, unknown spells, pet
    -- abilities) complete in <1 GCD and cannot be caught mid-cast — a
    -- gateSafety pause on an instant step created a resume→pause infinite
    -- loop (live 2026-08-22). Instant steps just proceed.
    if (not entry or not entry.isCastTime) then
        return nil;
    end

    local gateSafety = ACP.Settings:get("gateSafetySeconds") or 15;
    local remaining = ACP.ArenaPrep:getRemainingTime();

    if (remaining ~= nil and remaining < gateSafety) then
        return "gateSafety";
    end

    return nil;
end

--- Whether the target already has the buff, matched by NAME (rank-agnostic —
--- a higher-rank cast has a different spellID than the catalog entry).
--- Uses C_UnitAuras.GetAuraDataByIndex (the verified 20506 aura API).
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

--- Whether a createItem step's product is ALREADY in the bags, so the step's
--- goal is met before any cast. On TBC 2.5.5 the stone ranks coexist — a
--- rank-5 step is "done" only when a Major stone is present, and a leftover
--- higher-rank stone (e.g. Master 22105) must NOT satisfy it. So when the
--- stored rank is castable the expected set is exactly the rank's full variant
--- set (healthstone ranks 1-5 are historical ID pairs — the client conjures
--- either variant, e.g. rank 5 → 19013 while the step stores 19012); the
--- family-widened set (resolveExpectedItems) is used only for the
--- unlearned-rank fallback, where the cast is upgraded to a higher known rank.
---@param step table
---@return boolean
function WorkflowEngine:isItemAlreadyPresent(step)
    local castSpellID, castItemID = self:resolveCastInfo(step);

    local ids = (castSpellID ~= step.spellID)
        and self:resolveExpectedItems(castSpellID, castItemID)
        or self:expandExpectedItems(castSpellID, castItemID);

    for _, id in ipairs(ids) do
        if (ACP.Inventory:countItem(id) > 0) then
            return true;
        end
    end

    return false;
end

--- Whether a step's goal is already met (so a skipIfBuffed step can be skipped
--- without casting). Buff steps → aura present; summon → pet already out;
--- createItem → product already in bags.
---@param step table
---@return boolean
function WorkflowEngine:isStepGoalMet(step)
    local C = ACP.Data.Constants;

    if (step.type == C.WORKFLOW_STEP_CAST) then
        return self:isAlreadyBuffed(step);
    elseif (step.type == C.WORKFLOW_STEP_SUMMON) then
        return self:isAlreadySummoned(step);
    elseif (step.type == C.WORKFLOW_STEP_CREATE_ITEM) then
        return self:isItemAlreadyPresent(step);
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

    local C = ACP.Data.Constants;

    if (step.type == C.WORKFLOW_STEP_CAST
        or step.type == C.WORKFLOW_STEP_SUMMON
        or step.type == C.WORKFLOW_STEP_CREATE_ITEM) then
        return ACP.Settings:get("workflows.skipIfBuffedDefault") == true;
    end

    return false;
end

---@param step table
---@return boolean
function WorkflowEngine:isAlreadyBuffed(step)
    local spellName = self:spellName(step.spellID);

    if (not GetAuraDataByIndex or spellName:sub(1, 1) == "#") then
        return false;
    end

    local target = step.target or "player";

    for i = 1, MAX_AURA_INDEX do
        local aura = GetAuraDataByIndex(target, i, "HELPFUL");

        if (not aura) then
            break;
        end

        if (aura.name == spellName) then
            return true;
        end
    end

    return false;
end

--- Every step (instant AND cast-time) casts through the secure hotkey
--- (§3.6): 20506 blocks insecure casting even for INSTANT spells outside safe
--- zones — verified 2026-08-19 (bare CastSpellByName("Fel Armor") in the open
--- world pops "blocked from an action"; no GCD, no buff). The engine points
--- the button at the spell and waits for the user's key press (waitingForKey).
--- Completion is waited for by cast type:
---   cast-time → events (SENT/START → waitingForCast, STOP/SUCCEEDED → advance);
---   instant   → waitForInstantEffect (the cast's effect: the buff landing, a
---               registered GCD, or SENT if the client fires it — verified
---               2026-08-19 that SENT may NOT fire for instant spells, so the
---               effect watch is the primary completion signal).
---
--- TARGETING: the step's unit travels in the button's `unit` attribute only
--- (requestKeyCast) — the old TargetUnit("party1")/TargetLastTarget() swap was
--- REMOVED (2026-08-22): calling TargetUnit from insecure code popped
--- "blocked action" on the first party-targeted cast, and the swap was fully
--- redundant with the unit attribute anyway.
---@param step table
function WorkflowEngine:castSpell(step)
    local castSpellID, _ = self:resolveCastInfo(step);
    local name = self:spellName(castSpellID);
    local entry = self:getCatalogEntry(castSpellID);

    -- Already has the buff and the step is set to skip: the goal state is met
    -- — no key press needed.
    if (entry and entry.buffSpellID and self:effectiveSkip(step) and self:isAlreadyBuffed(step)) then
        self:advance();
        return;
    end

    self.pendingCastSpellID = castSpellID;
    self:requestKeyCast(name, step);

    if (not (entry and entry.isCastTime)) then
        self.instantPressDetected = false;
        self:waitForInstantEffect(step);
    end
end

--- CAST step (§3.6): the client requires a real hardware event to cast —
--- insecure casting is blocked even out of combat (verified 2026-08-18). Point
--- every live secure button (the /acp bind hotkey button + the current slot's
--- button — both permanently click-bound, no takeover) at the spell and wait
--- for the user's key press (waitingForKey). UNIT_SPELLCAST_SENT/START then
--- transition to waitingForCast + timeout.
---@param name string  localized spell name
---@param step table
function WorkflowEngine:requestKeyCast(name, step)
    self.castAccepted = false;
    self.waitingForKey = true;
    self.waitingForCast = false;

    if (step.spellID) then
        -- SecureActionButtonTemplate accepts the exact spellID on this client
        -- (BetterFishing/Details pattern). Use the RESOLVED cast spellID: a
        -- stored lower rank can be unlearned at high level, so casting it by
        -- spellID silently does nothing — the engine resolves the player's
        -- actual known rank (resolveCastInfo) for both createItem and cast
        -- steps. "type" is restored here too — an equipItem step re-points the
        -- buttons to type="item" and they must be spell buttons again.
        local castSpellID = self.pendingCastSpellID or step.spellID;
        self:setCastAttribute("type", "spell");
        self:setCastAttribute("spell", castSpellID);
        -- Target the cast directly at the step's unit via the button's `unit`
        -- attribute (the M6 ActionBook pattern — spell + unit attribute group,
        -- verified on 20506). A nil target keeps the default current-target
        -- behavior (summons/conjures self-cast).
        self:setCastAttribute("unit", step.target or nil);
    end

    local key = self:resolveCastKey(self.currentSlot);

    if (key) then
        ACP:debugPrint(ACP.L.workflow.pressKey, key, name);
        ACP:debugPrint("workflow keycast: %s (step %d) waiting for key %s", name, self.stepIndex, key);
    else
        self.waitingForKey = false;
        self:pause("noHotkey");
    end
end

--- The user pressed the cast key and the client accepted the cast (SENT/START).
--- Cast-time → waitingForCast + completion timeout; the buttons are re-pointed
--- at the armed pet macro (or made inert so mid-cast presses do nothing).
--- Instant → flag the press for waitForInstantEffect (which may already have
--- detected the effect via the buff landing, since the client may not fire SENT
--- for instant spells).
--- Guard: both SENT and START fire for one cast (START follows SENT); the
--- first transition already armed the cast-time wait (and the optional pet
--- step), so a second onKeyPressed for the same cast is a no-op (a live "pet
--- ability armed during cast" was logged twice per cast, 2026-08-22).
function WorkflowEngine:onKeyPressed()
    if (self.waitingForCast) then
        return;
    end

    local C = ACP.Data.Constants;
    self.waitingForKey = false;

    local def = self:getDefinition(self.currentSlot);
    local step = def and def.steps[self.stepIndex];
    local entry = step and self:getCatalogEntry(step.spellID);

    if (entry and entry.isCastTime) then
        self.waitingForCast = true;
        self:armCastTimeout();
        -- If the NEXT step is a pet ability, arm it now so it can be pressed
        -- DURING this cast (the pet casts independently of the player). The
        -- buttons are re-pointed at the pet macro; a second key press casts
        -- the pet ability while the player's cast is still in progress.
        -- GATED on the pet EXISTING: pressing the armed key during a SUMMON
        -- (pet not out yet) executes the pet macro with no pet to route it to —
        -- the client then treats it as a player cast, which interrupts the
        -- summon and pops "blocked action" (live 2026-08-22). Without the pet
        -- the step is not armed and runs standalone after the summon completes.
        local nextStep = def and def.steps[self.stepIndex + 1];

        if (nextStep and nextStep.type == C.WORKFLOW_STEP_PET
            and _G.UnitExists and _G.UnitExists("pet")) then
            self.pendingPetStep = self.stepIndex + 1;
            self.petStepDone = false;
            self.waitingForPet = true;
            self.waitingForKey = true;

            local macro = self:petMacroText(nextStep);
            self:setCastAttribute("type", "macro");
            self:setCastAttribute("macrotext", macro);
            self:setCastAttribute("unit", nil);
            ACP:debugPrint("workflow pet macro: %s", macro);
            ACP:debugPrint("workflow pet ability armed during cast: %s (step %d) petGUID=%s", self:spellName(nextStep.spellID), self.pendingPetStep, tostring(_G.UnitGUID and _G.UnitGUID("pet")));
        else
            -- No pet step armed: make the buttons inert for the duration of the
            -- cast — the slot key stays click-bound now (no takeover/release),
            -- so a mid-cast press must do nothing instead of re-casting.
            if (nextStep and nextStep.type == C.WORKFLOW_STEP_PET) then
                ACP:debugPrint("workflow pet step NOT armed (pet not out): %s (step %d)", self:spellName(nextStep.spellID), self.stepIndex + 1);
            end
            self:clearKeyCast();
        end
    else
        self.waitingForCast = false;
        self.instantPressDetected = true;
    end
end

--- Arm the cast-time completion safety timeout. Fires WORKFLOW_CAST_TIMEOUT
--- seconds after a cast is ACCEPTED (the key was pressed); pauses if the cast
--- never completes.
function WorkflowEngine:armCastTimeout()
    ACP.Utils.Timers:after("WorkflowCastTimeout", ACP.Data.Constants.WORKFLOW_CAST_TIMEOUT, function()
        self:onCastTimeout();
    end);
end

--- The secure macro a pet step casts: "/cast [pet:<type>,@unit] <pet ability>".
--- The @unit conditional is the 20506-reliable target form (the old
--- [target=unit] form did NOT redirect pet abilities in live tests 2026-08-22 —
--- a Fire Shield step with target=party1 buffed the PLAYER; TBC Classic guides
--- use [@arena1]/[@mouseover] for pet abilities on this client). The
--- [pet:<type>] conditional gates the cast on the RIGHT pet being out: when it
--- isn't (e.g. the pet was dismissed mid-summon), the macro does NOTHING instead
--- of the client treating it as a player cast — no interruption, no
--- "blocked action" popup. This is how Sacrifice is pressed during the
--- Summon Felhunter cast (the Voidwalker is still out until the summon
--- completes) — the requirement that ALL pet abilities work armed-during-cast.
--- "player" and a missing target both default to @player (the warlock); a
--- party target keeps its explicit unit.
---@param step table
---@return string
function WorkflowEngine:petMacroText(step)
    local name = self:spellName(step.spellID);
    local target = (step.target and step.target ~= "player") and step.target or "player";
    local entry = self:getCatalogEntry(step.spellID);
    local petCond = (entry and entry.pet) and ("pet:" .. tostring(entry.pet) .. ",") or "";

    return ("/cast [%s@%s] %s"):format(petCond, target, name);
end

--- Whether a pet ability ACTUALLY applied (2026-08-22, live-verified): the
--- client applies a pet ability only when the key is pressed near the END of
--- the player's cast — an early press is silently swallowed (Sacrifice pressed
--- +2 s into a 6 s summon did nothing; +5 s fired). The engine must therefore
--- NOT mark a pet step done on the press itself; it marks it done only when
--- the effect is visible:
---   1. the ability's buff is on the target (matched by NAME like
---      isAlreadyBuffed — covers Fire Shield AND the Sacrifice shield);
---   2. the Voidwalker is GONE while the player's cast is still in progress
---      (Sacrifice consumes the pet).
---@param step table
---@return boolean
function WorkflowEngine:isPetAbilityApplied(step)
    local spellName = self:spellName(step.spellID);
    local target = step.target or "player";

    if (GetAuraDataByIndex and spellName:sub(1, 1) ~= "#") then
        for i = 1, MAX_AURA_INDEX do
            local aura = GetAuraDataByIndex(target, i, "HELPFUL");

            if (not aura) then
                break;
            end

            if (aura.name == spellName) then
                return true;
            end
        end
    end

    -- Sacrifice consumes the Voidwalker. Only during the player's cast — after
    -- the summon completes the NEW pet exists, so "pet gone" would no longer
    -- prove anything (and UnitExists is true anyway).
    local entry = self:getCatalogEntry(step.spellID);

    if (entry and entry.pet == "voidwalker" and self.waitingForCast
        and _G.UnitExists and not _G.UnitExists("pet")) then
        return true;
    end

    return false;
end

--- Poll a pressed-but-unconfirmed pet step: when the ability's effect lands
--- (isPetAbilityApplied), mark the armed step done / advance the standalone
--- step. The poll is user-paced — no timeout; the user keeps pressing until
--- the client applies the ability. Bails as soon as the state no longer
--- matches (advance/pause/reset/interrupt all clear pendingPetStep or cancel
--- the timer via cancelTimers).
function WorkflowEngine:armPetVerify()
    ACP.Utils.Timers:interval("WorkflowPetVerify", 0.1, function()
        if (self.state ~= "RUNNING") then
            return;
        end

        local def = self:getDefinition(self.currentSlot);
        local step;

        if (self.pendingPetStep) then
            step = def and def.steps[self.pendingPetStep];
        elseif (self.waitingForPet) then
            step = def and def.steps[self.stepIndex];
        end

        if (not step or step.type ~= ACP.Data.Constants.WORKFLOW_STEP_PET or not self:isPetAbilityApplied(step)) then
            return;
        end

        ACP.Utils.Timers:cancel("WorkflowPetVerify");

        if (self.pendingPetStep) then
            ACP:debugPrint("workflow pet ability verified: %s (step %d)", self:spellName(step.spellID), self.pendingPetStep);
            self.petStepDone = true;
            self.pendingPetStep = nil;
            self.waitingForPet = false;
            self.waitingForKey = false;
            self:clearKeyCast();
        else
            ACP:debugPrint("workflow pet ability verified: %s (step %d)", self:spellName(step.spellID), self.stepIndex);
            self.waitingForPet = false;
            self.waitingForKey = false;
            self:clearKeyCast();
            self:advance();
        end
    end);
end

--- Point every live secure button at a macro that casts a pet ability by name
--- (/cast resolves pet abilities — e.g. Fire Shield, Sacrifice). The pet casts
--- the ability independently of the player's cast/GCD, so the step is
--- user-paced: the press (PostClick → onSecurePress) is the completion signal
--- and the engine does not wait for any player cast to finish.
---@param step table  the pet step
function WorkflowEngine:petAbility(step)
    local name = self:spellName(step.spellID);
    local macro = self:petMacroText(step);

    self:setCastAttribute("type", "macro");
    self:setCastAttribute("macrotext", macro);
    self:setCastAttribute("unit", nil);

    ACP:debugPrint("workflow pet macro: %s", macro);

    self.waitingForPet = true;
    self.waitingForKey = true;

    local key = self:resolveCastKey(self.currentSlot);

    if (key) then
        ACP:debugPrint(ACP.L.workflow.pressKey, key, name);
        ACP:debugPrint("workflow pet ability: %s (step %d) waiting for key %s", name, self.stepIndex, key);
    else
        self.waitingForPet = false;
        self.waitingForKey = false;
        self:pause("noHotkey");
        return;
    end
end

--- The secure button was clicked by the user's hardware key press (PostClick).
--- Branches by what is pending: an armed pet step during a player cast, a
--- standalone pet step, or a player-cast press (handled by the SENT/START flow).
--- The slot parameter is the pressed button's slot (nil for the /acp bind
--- hotkey button); a press from a button that does not belong to the current
--- slot is ignored (defensive — the client routes one key to one button).
---@param slot number|nil
function WorkflowEngine:onSecurePress(slot)
    local C = ACP.Data.Constants;
    if (self.state ~= "RUNNING") then
        return;
    end

    if (slot and self.currentSlot and slot ~= self.currentSlot) then
        return;
    end

    local def = self:getDefinition(self.currentSlot);

    if (self.pendingPetStep) then
        -- The armed pet ability was pressed during the player's cast. The
        -- press is NOT enough: the client silently swallows pet abilities
        -- pressed early in the cast (live 2026-08-22 — Sacrifice at +2 s of a
        -- 6 s summon did nothing, +5 s fired). Mark the step done ONLY when
        -- the effect is verified (isPetAbilityApplied); otherwise keep it
        -- armed — the user keeps spamming the key until the ability lands
        -- (armPetVerify also catches the effect the moment it appears).
        local petStep = def and def.steps[self.pendingPetStep];

        if (petStep and petStep.type == C.WORKFLOW_STEP_PET) then
            local name = self:spellName(petStep.spellID);
            ACP:debugPrint("workflow pet ability pressed during cast: %s (step %d) petExists=%s petGUID=%s", name, self.pendingPetStep, tostring(_G.UnitExists and _G.UnitExists("pet")), tostring(_G.UnitGUID and _G.UnitGUID("pet")));

            if (self:isPetAbilityApplied(petStep)) then
                ACP:debugPrint("workflow pet ability verified: %s (step %d)", name, self.pendingPetStep);
                self.petStepDone = true;
                self.pendingPetStep = nil;
                self.waitingForPet = false;
                self.waitingForKey = false;
                ACP.Utils.Timers:cancel("WorkflowPetVerify");
                self:clearKeyCast();
            else
                ACP:debugPrint("workflow pet ability NOT applied yet: %s (step %d) — keep pressing", name, self.pendingPetStep);
                self:armPetVerify();
            end

            return;
        end
    end

    if (self.waitingForPet) then
        -- A standalone pet step's key was pressed — the same verification
        -- applies: advance only once the ability's effect is visible. The
        -- key stays click-bound (no takeover), so re-presses re-run the macro.
        local step = def and def.steps[self.stepIndex];

        if (step and step.type == C.WORKFLOW_STEP_PET and self:isPetAbilityApplied(step)) then
            ACP:debugPrint("workflow pet ability verified: %s (step %d)", self:spellName(step.spellID), self.stepIndex);
            self.waitingForPet = false;
            self.waitingForKey = false;
            ACP.Utils.Timers:cancel("WorkflowPetVerify");
            self:clearKeyCast();
            self:advance();
        else
            ACP:debugPrint("workflow pet ability NOT applied yet: %s (step %d) — keep pressing", step and self:spellName(step.spellID) or "?", self.stepIndex);
            self:armPetVerify();
        end
    end
    -- Player-cast presses are handled by the UNIT_SPELLCAST_SENT/START flow.
end

--- Cast-time timeout callback: no cast in progress after WORKFLOW_CAST_TIMEOUT
--- since the cast was accepted. Emit client state, then pause.
function WorkflowEngine:onCastTimeout()
    if (self.state ~= "RUNNING" or not self.waitingForCast) then
        return;
    end

    -- Defense in depth: a legitimately long cast is still going — wait for
    -- the real completion event instead of pausing.
    if (UnitCastingInfo and UnitCastingInfo("player")) then
        return;
    end

    -- No cast in progress and never completed — emit client state so the next
    -- run is self-diagnosing.
    ACP:debugPrint("workflow cast dropped: accepted=%s inCombat=%s affectingCombat=%s shards=%d",
        tostring(self.castAccepted),
        tostring(InCombatLockdown and InCombatLockdown()),
        tostring(UnitAffectingCombat and UnitAffectingCombat("player")),
        ACP.Inventory:countItem(ACP.Data.Constants.SOUL_SHARD_ITEM_ID));
    self.waitingForPet = false;
    self.pendingPetStep = nil;
    self.petStepDone = false;
    self:pause(self.castAccepted and "castTimeout" or "castBlocked");
end

--- Instant-step wait: watch for the cast's EFFECT (the press happening) and
--- advance when the step's goal is met. The client may NOT fire
--- UNIT_SPELLCAST_SENT for instant spells (verified stall 2026-08-19), so the
--- effect is the primary signal:
---   buff steps → the buff appearing in the aura list (isAlreadyBuffed). This
---               is the ONLY signal for buff steps — the GCD is NOT consulted
---               because the previous step's GCD can still be running when this
---               step begins (a false "press" would skip the step silently).
---   other steps → SENT (if the client fires it) or a NEW GCD started after
---               this step began (start >= stepStart).
--- Buff steps advance immediately once detected (the buff present proves the
--- cast landed); non-buff steps advance once the GCD clears after detection.
--- The watch is user-paced — no timeout while waitingForKey (the user controls
--- when to press).
---@param step table
function WorkflowEngine:waitForInstantEffect(step)
    local entry = self:getCatalogEntry(step.spellID);
    local spellID = step.spellID;
    local stepStart = GetTime and GetTime() or 0;
    local detected = false;
    local ticks = 0;

    ACP.Utils.Timers:interval("WorkflowGCD", ACP.Data.Constants.WORKFLOW_GCD_TICK, function()
        if (self.state ~= "RUNNING" or self.waitingForCast or self.expectedItemID) then
            return;
        end

        ticks = ticks + 1;

        if (not detected) then
            if (entry and entry.buffSpellID) then
                if (self:isAlreadyBuffed(step)) then
                    detected = true; -- the buff landed (SENT may not fire for instant)
                end
            elseif (self.instantPressDetected) then
                detected = true; -- SENT/START fired for this step
            else
                local start, duration = GetSpellCooldown and GetSpellCooldown(spellID);

                if (start and duration and duration > 0 and start >= stepStart) then
                    detected = true; -- a NEW GCD began (the press landed)
                end
            end

            if (not detected) then
                return; -- the user hasn't pressed yet
            end

            self.castAccepted = true;
            self.waitingForKey = false;
        end

        if (entry and entry.buffSpellID) then
            -- Buff present → the cast landed → the step is done.
            ACP.Utils.Timers:cancel("WorkflowGCD");
            self:advance();
            return;
        end

        -- Non-buff step: advance once the GCD is clear after detection.
        local _, duration = GetSpellCooldown and GetSpellCooldown(spellID);

        if (not (duration and duration > 0) and ticks >= 3) then
            ACP.Utils.Timers:cancel("WorkflowGCD");
            self:advance();
        end
    end);
end

--- createItem step (§3.6): self-cast via the secure hotkey (all conjure
--- spells are cast-time on 20506 — Create Healthstone is 3 s), then wait for
--- the item to appear.
function WorkflowEngine:createItem(step)
    -- Resolve the castable rank: if the stored rank is castable it is used as-is;
    -- only an unlearned stored rank is upgraded to the player's known rank, and
    -- the expected item is derived from whichever rank actually casts.
    local castSpellID, castItemID = self:resolveCastInfo(step);

    -- NOTE: createItem does NOT skip when a same-family stone is already in
    -- bags. TBC 2.5.5 lets a Warlock carry MULTIPLE healthstones/spellstones
    -- (they do not share a unique tag), and the prep workflow's purpose is to
    -- conjure several to trade to a partner (DeliveryController). Each create
    -- step therefore always casts; completion is detected by a NEW stone of the
    -- family appearing (isItemCreated delta), not by mere presence.

    local name = self:spellName(castSpellID);
    self.expectedItemID = castItemID;
    -- Exact-rank expectation when the stored rank is castable (the TBC ranks
    -- coexist — a rank-5 cast really creates a Major stone, and only a NEW
    -- Major satisfies it). The expectation covers the rank's full variant
    -- pair (e.g. Major = 19012/19013 — the client conjures either), so the
    -- step completes on the variant the client actually created. The
    -- family-widened set is only for the unlearned-rank fallback, where the
    -- cast upgrades to the player's known rank.
    self.expectedItemIDs = (castSpellID ~= step.spellID)
        and self:resolveExpectedItems(castSpellID, castItemID)
        or self:expandExpectedItems(castSpellID, castItemID);
    self.expectedBaseline = self:countExpectedItems();
    self.pendingCastSpellID = castSpellID;
    self:requestKeyCast(name, step);
end

--- Item IDs a createItem step accepts as successfully created, for the
--- UNLEARNED-RANK FALLBACK only. On TBC 2.5.5 the stone ranks coexist and the
--- client does NOT auto-upgrade a cast to the max rank — a castable stored
--- rank is cast as-is and expects exactly its own rank's stone (see
--- isItemAlreadyPresent/createItem). Only when the stored rank is unlearned
--- does the engine upgrade the cast to the player's known rank, and then the
--- step must accept the upgraded rank's stone too: for stone spells return
--- every same-family item of rank >= the step's rank (each expanded to its
--- full variant pair); otherwise the single exact itemID.
---@param spellID number  the (resolved) cast spellID to check the stone family for
---@param itemID number  fallback item ID for non-stone spells
---@return table
function WorkflowEngine:resolveExpectedItems(spellID, itemID)
    local rankEntry = ACP.Data.Workflows.stoneRanks[spellID];

    if (not rankEntry) then
        return { itemID };
    end

    local ids = {};

    for _, r in pairs(ACP.Data.Workflows.stoneRanks) do
        if (r.spellName == rankEntry.spellName and r.rank >= rankEntry.rank) then
            local variants = r.itemIDs or { r.itemID };

            for _, id in ipairs(variants) do
                ids[#ids + 1] = id;
            end
        end
    end

    return ids;
end

--- The full set of item IDs a cast of `castSpellID` can produce: both
--- historical variants of the spell's stone rank when known (healthstone
--- ranks 1-5 are ID pairs — the client conjures one variant per rank, e.g.
--- rank 5 → 19013 while the step stores 19012, live-verified 2026-08-22),
--- else the single expected item ID.
---@param castSpellID number
---@param castItemID number
---@return table
function WorkflowEngine:expandExpectedItems(castSpellID, castItemID)
    local rank = ACP.Data.Workflows and ACP.Data.Workflows.stoneRanks
        and ACP.Data.Workflows.stoneRanks[castSpellID];

    if (rank and rank.itemIDs) then
        return rank.itemIDs;
    end

    return { castItemID };
end

--- Current bag count across `expectedItemIDs` (0 when not set).
---@return number
function WorkflowEngine:countExpectedItems()
    if (not self.expectedItemIDs) then
        return 0;
    end

    local total = 0;

    for _, id in ipairs(self.expectedItemIDs) do
        total = total + ACP.Inventory:countItem(id);
    end

    return total;
end

--- Whether the createItem cast has produced its item yet: a delta vs. the
--- pre-cast bag count across the accepted item IDs (so a leftover higher-rank
--- stone does not satisfy a lower-rank step).
---@return boolean
function WorkflowEngine:isItemCreated()
    if (not self.expectedItemIDs) then
        return false;
    end

    return self:countExpectedItems() > (self.expectedBaseline or 0);
end

--- equipItem step (§3.6): equip a conjured item (e.g. the Master Spellstone
--- from the /equip line of the m6 macros). The client treats equipping like
--- casting on 20506 — insecure calls are blocked outside safe zones, so the
--- equip goes through the SAME secure button, temporarily re-pointed from
--- type="spell" to type="item" (SecureActionButtonTemplate item attribute;
--- the M6-equivalent of /equip <name>).
---
--- Completion is goal-met and poll-driven: the item is no longer in bags
--- (equipped into the ranged/wand slot). No UNIT_SPELLCAST_* events fire for
--- item use, so the watch is user-paced — no timeout while waiting for the
--- press. Fast path: item already not in bags → step is already done.
---@param step table
function WorkflowEngine:equipItem(step)
    local itemID = step.itemID;
    self.waitingForEquip = true;
    self.equipItemID = itemID;

    -- Goal already met: nothing in bags to equip (already equipped/consumed).
    if (ACP.Inventory:countItem(itemID) == 0) then
        self:advance();
        return;
    end

    local itemName = self:itemName(step);

    self:setCastAttribute("type", "item");
    self:setCastAttribute("item", itemName);
    self:setCastAttribute("unit", nil);

    local key = self:resolveCastKey(self.currentSlot);

    if (key) then
        ACP:debugPrint(ACP.L.workflow.pressEquip, key, itemName);
        ACP:debugPrint("workflow equip: %s (step %d) waiting for key %s", itemName, self.stepIndex, key);
    else
        self.waitingForEquip = false;
        self:pause("noHotkey");
        return;
    end

    ACP.Utils.Timers:interval("WorkflowItemPoll", 0.25, function()
        if (self.state ~= "RUNNING" or not self.waitingForEquip or self.equipItemID ~= itemID) then
            return;
        end

        if (ACP.Inventory:countItem(itemID) == 0) then
            ACP.Utils.Timers:cancel("WorkflowItemPoll");
            self:advance();
        end
    end);
end

--- A cast finished (UNIT_SPELLCAST_STOP/SUCCEEDED, verified not casting).
--- For createItem the item may still be landing — check bags, else wait.
--- Does NOT clear pendingPetStep/petStepDone — an armed pet step pressed during
--- this cast keeps its "done" flag so the engine skips it when it advances to
--- that index; an un-pressed pet step is reached normally afterwards.
function WorkflowEngine:onCastComplete()
    self.waitingForCast = false;
    self.waitingForKey = false;
    self:clearKeyCast();
    ACP.Utils.Timers:cancel("WorkflowCastTimeout");

    if (self.expectedItemID) then
        if (self:isItemCreated()) then
            self.expectedItemID = nil;
            self.expectedItemIDs = nil;
            self.expectedBaseline = nil;
            self:advance();
            return;
        end

        -- Item not in bags yet: ACP_ITEMS_CHANGED (tracked items) or the
        -- polling safety net (untracked items) will advance us.
        self:waitForItem(self.expectedItemID);
        return;
    end

    self:advance();
end

--- Reset every live cast button to an inert value so a stray key press
--- OUTSIDE a workflow does nothing (a secure button retains its last
--- attribute; without this, the key would keep re-casting the last step's
--- spell after the workflow is DONE/paused/reset).
function WorkflowEngine:clearKeyCast()
    -- Restore the spell type too: an equipItem step switches the buttons to
    -- type="item" — a stale "item" type would make a stray key press USE the
    -- last item instead of casting after the workflow ends.
    self:setCastAttribute("type", "spell");
    self:setCastAttribute("spell", "");
    -- Clear the target unit as well — a stale unit attribute (e.g. a party1
    -- step) would retarget a later untargeted cast at the old unit.
    self:setCastAttribute("unit", nil);
end

--- Wait for a created item to appear in bags: poll every 0.25 s (covers items
--- the Inventory cache does not track, e.g. Major Soulstone 22103) with a
--- WORKFLOW_CAST_TIMEOUT safety window.
---@param itemID number
function WorkflowEngine:waitForItem(itemID)
    ACP.Utils.Timers:interval("WorkflowItemPoll", 0.25, function()
        if (self.state ~= "RUNNING" or self.expectedItemID ~= itemID) then
            return;
        end

        if (self:isItemCreated()) then
            ACP.Utils.Timers:cancel("WorkflowItemPoll");
            self.expectedItemID = nil;
            self.expectedItemIDs = nil;
            self.expectedBaseline = nil;
            self:advance();
        end
    end);

    ACP.Utils.Timers:after("WorkflowCastTimeout", ACP.Data.Constants.WORKFLOW_CAST_TIMEOUT, function()
        if (self.state ~= "RUNNING" or self.expectedItemID ~= itemID) then
            return;
        end

        self:pause("castTimeout");
    end);
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
    self.waitingForCast = false;
    self.waitingForKey = false;
    self.waitingForEquip = false;
    self.waitingForPet = false;
    self.instantPressDetected = false;
    self.expectedItemID = nil;
    self.expectedItemIDs = nil;
    self.expectedBaseline = nil;
    self.pendingCastSpellID = nil;
    self.equipItemID = nil;
    self.pendingPetStep = nil;
    self.stepIndex = self.stepIndex + 1;
    self:executeCurrentStep();
end

--- Run the current step: gates, unknown-spell/buff skips, dispatch by type.
--- Also the DONE transition (stepIndex past the last step, incl. empty
--- workflows).
function WorkflowEngine:executeCurrentStep()
    if (self.state ~= "RUNNING") then
        return;
    end

    local definition = self:getDefinition(self.currentSlot);
    local steps = (definition and type(definition.steps) == "table") and definition.steps or {};
    local step = steps[self.stepIndex];

    -- Out of steps → DONE.
    if (not step) then
        self:cancelTimers();
        self:clearKeyCast();
        self.state = "DONE";
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

    -- Dispatch by type.
    local C = ACP.Data.Constants;
    local stepType = step.type;

    -- equipItem has no spellID — it must run BEFORE the spell-only checks.
    if (stepType == C.WORKFLOW_STEP_EQUIP_ITEM) then
        self:equipItem(step);
        return;
    end

    -- Pet abilities are cast by the pet, not the player — they must run before
    -- the player-spell checks (IsPlayerSpell is false for pet abilities). A pet
    -- step already pressed during the previous player cast is skipped here.
    if (stepType == C.WORKFLOW_STEP_PET) then
        if (self.petStepDone) then
            self.petStepDone = false;
            self:advance();
            return;
        end

        self:petAbility(step);
        return;
    end

    -- Unknown spell → skip the step, continue with the next.
    if (not self:knowsSpell(step)) then
        ACP:debugPrint(ACP.L.workflow.stepSkippedUnknown, self.stepIndex);
        self:advance();
        return;
    end

    if (stepType == C.WORKFLOW_STEP_CAST or stepType == C.WORKFLOW_STEP_SUMMON) then
        self:castSpell(step);
    elseif (stepType == C.WORKFLOW_STEP_CREATE_ITEM) then
        self:createItem(step);
    end
end

--- Pause the running workflow (state → PAUSED), keeping the current step so
--- the next key press resumes from it. Idempotent.
---@param reason string  reason key (L.workflow.reason*)
function WorkflowEngine:pause(reason)
    if (self.state ~= "RUNNING") then
        return;
    end

    self.state = "PAUSED";
    self.waitingForCast = false;
    self.waitingForKey = false;
    self.waitingForEquip = false;
    self.waitingForPet = false;
    self.instantPressDetected = false;
    self.expectedItemID = nil;
    self.equipItemID = nil;
    self.pendingPetStep = nil;
    self.petStepDone = false;
    self.expectedItemID = nil;
    self.expectedItemIDs = nil;
    self.expectedBaseline = nil;
    self.pendingCastSpellID = nil;
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
    self.state = "IDLE";
    self.currentSlot = nil;
    self.stepIndex = 1;
    self.waitingForCast = false;
    self.waitingForKey = false;
    self.waitingForEquip = false;
    self.waitingForPet = false;
    self.instantPressDetected = false;
    self.expectedItemID = nil;
    self.expectedItemIDs = nil;
    self.expectedBaseline = nil;
    self.pendingCastSpellID = nil;
    self.equipItemID = nil;
    self.pendingPetStep = nil;
    self.petStepDone = false;
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

    if (self.state == "RUNNING" and self.currentSlot == slot) then
        return; -- already running
    end

    -- One run per prep/test command (2026-08-22): after DONE the key press is
    -- a no-op in BOTH modes — the user complained the workflow "went a second
    -- round". A fresh run starts on ACP_BUFF_LOST (new arena) or by re-issuing
    -- /acp workflowtest N, which resets the engine before start().
    if (self.state == "DONE") then
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
        and (self.state == "RUNNING" or self.state == "PAUSED")) then
        self:reset();
    end

    -- Resume the same paused slot.
    if (self.state == "PAUSED" and self.currentSlot == slot) then
        self.state = "RUNNING";
        ACP:debugPrint(ACP.L.workflow.resumed, slot, definition.name or "", self.stepIndex);
        ACP.Events:fire("ACP_WORKFLOW_RESUMED");
        self:executeCurrentStep();
        return;
    end

    -- Fresh start.
    self.currentSlot = slot;
    self.stepIndex = 1;
    self.waitingForCast = false;
    self.expectedItemID = nil;
    self.expectedItemIDs = nil;
    self.expectedBaseline = nil;
    self.pendingCastSpellID = nil;
    self.state = "RUNNING";
    ACP:debugPrint(ACP.L.workflow.started, slot, definition.name or "");
    ACP.Events:fire("ACP_WORKFLOW_STARTED", slot);
    self:executeCurrentStep();
end

--- The configured workflow hotkey (Settings "workflows.hotkey"), or nil.
---@return string|nil
function WorkflowEngine:boundKey()
    return ACP.Settings:get("workflows.hotkey");
end

--- The loaded binding set (1 = account, 2 = character), or nil when bindings
--- aren't loaded yet. On 20506 GetCurrentBindingSet() returns 0 before the
--- bindings load, and SaveBindings(0) throws "Usage: SaveBindings(1||2)" (it
--- crashed the whole _init at ADDON_LOADED — verified 2026-08-19). 0 is truthy
--- in Lua, so a plain truthiness guard is NOT enough — the value must be 1|2.
---@return number|nil
function WorkflowEngine:bindingSet()
    local bs = GetCurrentBindingSet and GetCurrentBindingSet();
    return (bs == 1 or bs == 2) and bs or nil;
end

--- Bind the hotkey to the secure cast button (SetBindingClick). Safe to call
--- repeatedly: rebinds the current key and unbinds a previous one. No-op when
--- no hotkey is set or the button/binding APIs are unavailable; retries while
--- the binding set has not loaded yet or during combat (bindings can't change
--- in combat).
function WorkflowEngine:applyBinding()
    if (not SetBindingClick or not self.castButton) then
        return;
    end

    local key = self:boundKey();

    if (self._boundKey and self._boundKey ~= key and SetBinding) then
        SetBinding(self._boundKey, "");
    end

    self._boundKey = nil;

    if (not key or key == "none" or key == "off") then
        return;
    end

    if (not self:bindingSet()) then
        -- Bindings load late — retry shortly.
        ACP.Utils.Timers:after("WorkflowKeyBindRetry", 1, function()
            self:applyBinding();
        end);
        return;
    end

    if (InCombatLockdown and InCombatLockdown()) then
        ACP.Utils.Timers:after("WorkflowKeyBindRetry", 2, function()
            self:applyBinding();
        end);
        return;
    end

    SetBindingClick(key, ACP.Data.Constants.WORKFLOW_BUTTON_NAME);

    local bs = self:bindingSet();

    if (SaveBindings and bs) then
        SaveBindings(bs);
    end

    self._boundKey = key;
end

--- The active cast key for a run: the Key Bindings UI key of the workflow
--- slot (remembered by applySlotBindings — the slot key is permanently
--- click-bound to the slot's secure button for the session), else the
--- configured /acp bind hotkey. The workflow key wins so ONE key both
--- starts/resumes and casts.
---@param slot number|nil
---@return string|nil
function WorkflowEngine:resolveCastKey(slot)
    slot = slot or self.currentSlot;

    local key = slot and self.slotKeys[slot];

    if (key and key ~= "") then
        return key;
    end

    return self:boundKey();
end

--- The secure button the current slot's key clicks (per-slot buttons created
--- in _init), or nil while no slot is running.
---@return frame|nil
function WorkflowEngine:currentButton()
    return self.currentSlot and self.castButtons[self.currentSlot] or nil;
end

--- Apply `attr = value` to EVERY live cast button — the /acp bind hotkey
--- button and the current slot's button — so BOTH keys cast the armed step.
---@param attr string
---@param value any
function WorkflowEngine:setCastAttribute(attr, value)
    if (self.castButton and self.castButton.SetAttribute) then
        self.castButton:SetAttribute(attr, value);
    end

    local btn = self:currentButton();

    if (btn and btn.SetAttribute) then
        btn:SetAttribute(attr, value);
    end
end

--- Insecure PreClick hook (ItemRack pattern, verified on 20506): runs BEFORE
--- the button's secure action, so ONE press can start/resume the workflow AND
--- cast the freshly armed step. No-op while the button is already armed
--- (waitingForKey/waitingForPet) and after DONE (one run per prep — the button
--- is inert, see executeCurrentStep's DONE branch).
---@param slot number
function WorkflowEngine:onPreClick(slot)
    if (self.state == "IDLE" or self.state == "PAUSED"
        or (self.state == "RUNNING" and self.currentSlot ~= slot)) then
        self:start(slot);
    end
    -- RUNNING + same slot: the button is already armed (cast/pet/equip) or
    -- inert (mid-cast) — leave it alone. DONE: no-op.
end

--- Point each workflow slot's Key Bindings UI key at that slot's secure cast
--- button via SetOverrideBindingClick(owner, true, ...) — a PRIORITY OVERRIDE
--- (BetterFishing pattern, verified on 20506: BetterFishing.lua:276/290).
---
--- Unlike SetBindingClick, an override does NOT displace the player's command
--- binding: GetBindingKey/GetBindingAction keep returning the real binding, so
--- the Key Bindings UI and the Workflows-tab key capture keep working — the
--- user can rebind ";"/any key at any time (the displaced-command approach
--- broke key assignment entirely, live 2026-08-22). Overrides die with the
--- session (nothing to restore or persist on logout). With the key on the
--- button, one press starts AND casts (PreClick → start → arm; click → cast).
---
--- This is a FULL RESYNC: previous overrides are cleared, then re-applied from
--- the authoritative binding table — safe because the table itself is never
--- modified. Deferred (with retry) until the binding set is loaded.
function WorkflowEngine:applySlotBindings()
    if (not SetOverrideBindingClick or not GetBindingKey or not self.castButton) then
        return;
    end

    if (not self:bindingSet()) then
        -- Bindings load late — retry shortly.
        ACP.Utils.Timers:after("WorkflowSlotBindRetry", 1, function()
            self:applySlotBindings();
        end);
        return;
    end

    self:clearSlotOverrides();

    for slot = 1, ACP.Data.Constants.WORKFLOW_MAX_SLOTS do
        local action = "ACP_WORKFLOW" .. tostring(slot);
        local key = GetBindingKey(action);

        if (key and key ~= "") then
            self.slotKeys[slot] = key;
            SetOverrideBindingClick(self.castButton, true, key, ACP.Data.Constants.WORKFLOW_BUTTON_NAME .. tostring(slot));
        else
            self.slotKeys[slot] = nil;
        end
    end
end

--- Remove every slot-key override. Called by applySlotBindings (resync), when
--- the Blizzard Key Bindings UI opens (so its key-capture dialog receives the
--- presses) and on PLAYER_LOGOUT (hygiene — overrides die with the session).
function WorkflowEngine:clearSlotOverrides()
    if (ClearOverrideBindings and self.castButton) then
        ClearOverrideBindings(self.castButton);
    end
end

--- The player saved bindings (UPDATE_BINDINGS): the binding table changed —
--- full resync of the overrides. Keys the player unbound/rebound simply stop
--- being overridden (GetBindingKey reflects the fresh state).
function WorkflowEngine:onBindingsUpdated()
    self:applySlotBindings();
end

--- Remove the current hotkey binding (used by `/acp bind off`).
function WorkflowEngine:clearBinding()
    if (self._boundKey and SetBinding) then
        SetBinding(self._boundKey, "");

        local bs = self:bindingSet();

        if (SaveBindings and bs) then
            SaveBindings(bs);
        end

        self._boundKey = nil;
    end
end

--- Status summary for /acp status.
---@return string
function WorkflowEngine:getStatus()
    local definition = self.currentSlot and self:getDefinition(self.currentSlot);
    local steps = definition and type(definition.steps) == "table" and #definition.steps or 0;

    return string.format("%s | slot=%s | step=%d/%d | key=%s",
        self.state, tostring(self.currentSlot), self.stepIndex, steps, tostring(self:resolveCastKey(self.currentSlot)));
end

function WorkflowEngine:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    -- Secure cast button (M6 pattern): pressing the hotkey clicks this button
    -- (a real hardware event), and the client casts the spell set via its
    -- "spell" attribute. A programmatic :Click() is silently dropped on 20506,
    -- so the engine NEVER clicks it — it waits for the user's key press
    -- (waitingForKey) on cast-time steps. This is the /acp bind hotkey button.
    if (CreateFrame and not self.castButton) then
        local btn = CreateFrame("Button", ACP.Data.Constants.WORKFLOW_BUTTON_NAME, nil, "SecureActionButtonTemplate");

        if (btn and btn.SetAttribute) then
            btn:SetAttribute("type", "spell");
            btn:SetAttribute("spell", "");
            if (btn.RegisterForClicks) then
                btn:RegisterForClicks("AnyDown");
            end
            if (btn.Hide) then
                btn:Hide();
            end
            -- The hardware key press clicks this button (SetBindingClick), so
            -- PostClick is the reliable "the user pressed the key" signal for
            -- pet abilities (no UNIT_SPELLCAST_* fires for the pet's cast).
            btn:SetScript("PostClick", function()
                self:onSecurePress(nil);
            end);
            self.castButton = btn;
        end
    end

    -- Per-slot secure cast buttons: the Key Bindings UI slot keys are
    -- click-bound to these (applySlotBindings). PreClick starts/resumes the
    -- slot and the SAME press's click casts the armed step — ONE press both
    -- starts and casts (2026-08-22).
    if (CreateFrame and not next(self.castButtons)) then
        for slot = 1, ACP.Data.Constants.WORKFLOW_MAX_SLOTS do
            local sbtn = CreateFrame("Button",
                ACP.Data.Constants.WORKFLOW_BUTTON_NAME .. tostring(slot), nil, "SecureActionButtonTemplate");

            if (sbtn and sbtn.SetAttribute) then
                sbtn:SetAttribute("type", "spell");
                sbtn:SetAttribute("spell", "");
                if (sbtn.RegisterForClicks) then
                    sbtn:RegisterForClicks("AnyDown");
                end
                if (sbtn.Hide) then
                    sbtn:Hide();
                end
                sbtn:SetScript("PreClick", function()
                    self:onPreClick(slot);
                end);
                sbtn:SetScript("PostClick", function()
                    self:onSecurePress(slot);
                end);
                self.castButtons[slot] = sbtn;
            end
        end
    end

    self:applyBinding();
    self:applySlotBindings();

    ACP.Events:register("WE.BUFF_LOST", "ACP_BUFF_LOST", function()
        self:reset();
    end);

    -- Combat makes casting impossible (protected API) → pause; the user
    -- resumes with the key after combat ends.
    ACP.Events:register("WE.COMBAT_START", "PLAYER_REGEN_DISABLED", function()
        self:pause("inCombat");
    end);

    -- Slot-key overrides are re-applied when bindings load/change and after
    -- combat (a full resync — the override table is rebuilt from the real
    -- bindings, which are never modified).
    ACP.Events:register("WE.PLAYER_LOGIN", "PLAYER_LOGIN", function()
        self:applySlotBindings();
    end);
    ACP.Events:register("WE.UPDATE_BINDINGS", "UPDATE_BINDINGS", function()
        self:onBindingsUpdated();
    end);
    ACP.Events:register("WE.REGEN_ENABLED", "PLAYER_REGEN_ENABLED", function()
        self:applySlotBindings();
    end);

    -- While the Blizzard Key Bindings UI is open, drop the priority overrides
    -- so its key-capture dialog receives the presses (a priority override
    -- would steal them). Re-apply when the frame closes. NOT ADDON_UNLOADING —
    -- the client throws "Attempt to register unknown event ADDON_UNLOADING"
    -- on 20506 (verified 2026-08-19; it crashed the whole _init).
    if (_G.KeyBindingFrame and _G.KeyBindingFrame.HookScript) then
        _G.KeyBindingFrame:HookScript("OnShow", function()
            self:clearSlotOverrides();
        end);
        _G.KeyBindingFrame:HookScript("OnHide", function()
            self:applySlotBindings();
        end);
    end

    -- Logout hygiene: clear the overrides (they are session-scoped and would
    -- die with the session anyway; the binding table itself is untouched, so
    -- nothing needs restoring or persisting).
    ACP.Events:register("WE.LOGOUT", "PLAYER_LOGOUT", function()
        self:clearSlotOverrides();
    end);

    -- Cast acceptance signal: UNIT_SPELLCAST_SENT fires when the client
    -- ACCEPTS a cast command (instant and cast-time spells alike) — i.e. the
    -- user pressed the hotkey. Branch by cast type: cast-time → waitingForCast
    -- + completion timeout; instant → GCD-driven completion (waitForGCD).
    ACP.Events:register("WE.SPELLCAST_SENT", "UNIT_SPELLCAST_SENT", function(unit)
        if (unit ~= "player" or self.state ~= "RUNNING" or not (self.waitingForKey or self.waitingForCast)) then
            return;
        end

        self.castAccepted = true;

        if (self.waitingForKey) then
            self:onKeyPressed();
        end

        ACP:debugPrint("workflow cast accepted (step %d)", self.stepIndex);
    end);

    -- The cast bar appeared. For a cast-time step this is the same
    -- "key pressed, cast accepted" transition as SENT (SENT may be skipped by
    -- the client for some casts); completion is still driven by
    -- STOP/SUCCEEDED (see the research: START is a signal, not completion).
    ACP.Events:register("WE.SPELLCAST_START", "UNIT_SPELLCAST_START", function(unit)
        if (unit ~= "player" or self.state ~= "RUNNING" or not (self.waitingForKey or self.waitingForCast)) then
            return;
        end

        if (self.waitingForKey) then
            self.castAccepted = true;
            self:onKeyPressed();
        end

        ACP:debugPrint("workflow cast started (step %d)", self.stepIndex);
    end);

    -- Cast completion signals. Signal-only: verify the player is no longer
    -- casting before treating the event as completion (§3.6).
    ACP.Events:register("WE.SPELLCAST_STOP", "UNIT_SPELLCAST_STOP", function(unit)
        if (unit ~= "player" or self.state ~= "RUNNING" or not self.waitingForCast) then
            return;
        end

        if (UnitCastingInfo and UnitCastingInfo("player")) then
            return;
        end

        self:onCastComplete();
    end);

    ACP.Events:register("WE.SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SUCCEEDED", function(unit)
        if (unit ~= "player" or self.state ~= "RUNNING" or not self.waitingForCast) then
            return;
        end

        if (UnitCastingInfo and UnitCastingInfo("player")) then
            return;
        end

        self:onCastComplete();
    end);

    ACP.Events:register("WE.SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_INTERRUPTED", function(unit)
        if (unit ~= "player" or self.state ~= "RUNNING" or not self.waitingForCast) then
            return;
        end

        -- The user stopped the cast (movement, ESC, /stopcasting): re-arm the
        -- SAME step in waitingForKey so the next F9 press re-casts it — the
        -- hotkey IS the resume mechanism (no /acp workflow 1 needed). Combat
        -- still hard-pauses via PLAYER_REGEN_DISABLED.
        self.waitingForCast = false;
        self.waitingForPet = false;
        self.pendingPetStep = nil;
        self.petStepDone = false;
        ACP.Utils.Timers:cancel("WorkflowCastTimeout");
        ACP.Utils.Timers:cancel("WorkflowPetVerify");

        local def = self:getDefinition(self.currentSlot);
        local step = def and def.steps[self.stepIndex];
        local name = step and self:spellName(step.spellID);

        if (step and name) then
            self:requestKeyCast(name, step);
        else
            self:pause("castInterrupted");
        end
    end);

    ACP.Events:register("WE.SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED", function(unit)
        if (unit ~= "player" or self.state ~= "RUNNING" or not self.waitingForCast) then
            return;
        end

        self:pause("castFailed");
    end);

    -- createItem: a crafted (tracked) item appeared — fast path. Untracked
    -- items (Major Soulstone) are covered by the waitForItem poll. Detection
    -- is delta-based (isItemCreated) against the exact-rank expected set, so
    -- a leftover higher-rank stone never completes a lower-rank step.
    ACP.Events:register("WE.ITEMS_CHANGED", "ACP_ITEMS_CHANGED", function()
        if (self.state ~= "RUNNING" or not self.expectedItemID) then
            return;
        end

        if (self:isItemCreated()) then
            ACP.Utils.Timers:cancel("WorkflowItemPoll");
            self.expectedItemID = nil;
            self.expectedItemIDs = nil;
            self.expectedBaseline = nil;
            self:advance();
        end
    end);
end

return ACP;
