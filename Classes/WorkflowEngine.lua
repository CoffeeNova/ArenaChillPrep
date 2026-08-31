-- ArenaChillPrep — Classes/WorkflowEngine
-- Workflow state machine (IDLE→RUNNING→PAUSED→DONE) + step orchestration.
-- Step executors live in WorkflowCastController / PetAbilityCaster /
-- WorkflowItemSteps; secure buttons + bindings in WorkflowBindings. All
-- casting goes through a hidden secure button — 20506 blocks insecure casts.

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

    ---@type boolean
    waitingForCast = false,

    ---@type boolean
    castAccepted = false,

    ---@type boolean
    waitingForKey = false,

    ---@type number|nil
    expectedItemID = nil,

    ---@type table|nil
    expectedItemIDs = nil,

    ---@type number|nil
    expectedBaseline = nil,

    ---@type number|nil
    pendingCastSpellID = nil,

    ---@type boolean
    waitingForEquip = false,

    ---@type number|nil
    equipItemID = nil,

    ---@type number|nil
    pendingPetStep = nil,

    ---@type boolean
    petStepDone = false,

    ---@type boolean
    waitingForPet = false,

    ---@type table<number, frame>
    castButtons = {},

    ---@type table<number, string>
    slotKeys = {},

    ---@type boolean
    debugBypass = false,

    ---@type boolean
    isTesting = false,

    ---@type number|nil
    testSlot = nil,

    instantPressDetected = false,

    ---@type boolean
    spellRanksOverridden = false,

    ---@type string|nil
    savedSpellRanksCVar = nil,
};

---@type WorkflowEngine
ACP.WorkflowEngine = WorkflowEngine;

local MAX_AURA_INDEX = 40;

local WS = ACP.Data.Constants.WORKFLOW_STATE;

local Reason = ACP.Data.Constants.WORKFLOW_REASON;

local C = ACP.Data.Constants;

--- Per-step-type dispatch: `run` executes, `goalMet` reports an already-met
--- goal (skip-completed), `skippable` opts into the global setting,
--- `needsKnownSpell` gates the player-spell check, `petDoneAware` consumes
--- petStepDone, `petExempt` exempts pet steps from player-casting gates.
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

function WorkflowEngine:cancelTimers()
    ACP.Utils.Timers:cancel("WorkflowCastTimeout");
    ACP.Utils.Timers:cancel("WorkflowGCD");
    ACP.Utils.Timers:cancel("WorkflowItemPoll");
    ACP.Utils.Timers:cancel("WorkflowPetVerify");
    ACP.Utils.Timers:cancel("WorkflowEquipGrace");
end

---@param newState string
function WorkflowEngine:setState(newState)
    ACP.StateMachine:setState(self, newState, WS);
end

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

---@param spellID number
---@return table|nil
function WorkflowEngine:getCatalogEntry(spellID)
    if (ACP.WorkflowSpellbook and ACP.WorkflowSpellbook.getEntry) then
        local runtimeEntry = ACP.WorkflowSpellbook:getEntry(spellID);

        if (runtimeEntry) then
            return runtimeEntry;
        end
    end

    local data = ACP.Data.activeClassWorkflows();
    local spells = data and data.spells;

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

--- Spell a step actually casts (and the item it will create): the stored rank
--- verbatim when castable, else the highest KNOWN rank of its family. On
--- 20506 a trained higher rank replaces the lower one in the spellbook.
--- Ranked families (stone/conjure) resolve from the STATIC rank table — never
--- from the runtime catalog — so a low-rank step can never break on a
--- catalog-rebuild issue.
---@param step table
---@return number castSpellID
---@return number castItemID
function WorkflowEngine:resolveCastInfo(step)
    local spellID = step.spellID;

    local ok, known = pcall(IsPlayerSpell, spellID);
    if (ok and known) then
        return spellID, step.itemID or (self:getCatalogEntry(spellID) and self:getCatalogEntry(spellID).itemID) or spellID;
    end

    local rankTable = ACP.Data.Workflows and ACP.Data.Workflows:activeRankTable();
    local rankEntry = rankTable and rankTable[spellID];
    local familyName = (rankEntry and rankEntry.spellName) or self:spellName(spellID);

    local highest = nil;

    if (rankTable and rankEntry and familyName:sub(1, 1) ~= "#") then
        for _, candidate in pairs(rankTable) do
            if (candidate.spellName == familyName) then
                local knownRank, isKnown = pcall(IsPlayerSpell, candidate.spellID);

                if (knownRank and isKnown and (not highest or candidate.rank > highest.rank)) then
                    highest = candidate;
                end
            end
        end
    elseif (familyName:sub(1, 1) ~= "#" and ACP.WorkflowSpellbook) then
        highest = ACP.WorkflowSpellbook:getHighestKnownRank(familyName);
    end

    if (highest) then
        return highest.spellID, highest.itemID or step.itemID;
    end

    return spellID, step.itemID;
end

---@param slot number
---@return table|nil
function WorkflowEngine:getDefinition(slot)
    local definition = ACP.Settings:get(ACP.WorkflowRepository:definitionPath(slot));

    if (type(definition) == "table" and (self.debugBypass or definition.enabled)) then
        return definition;
    end

    return nil;
end

---@return string
function WorkflowEngine:definitionName()
    local definition = self.currentSlot and self:getDefinition(self.currentSlot);

    return definition and definition.name or "";
end

--- Checks the RESOLVED cast spell (resolveCastInfo), not the stored ID — a
--- stored lower rank is not in the spellbook once a higher one is trained.
---@param step table
---@return boolean
function WorkflowEngine:knowsSpell(step)
    local resolvedID = self:resolveCastInfo(step);
    local name = self:spellName(resolvedID);

    if (IsPlayerSpell and name and name:sub(1, 1) ~= "#") then
        local ok, known = pcall(IsPlayerSpell, name);
        if (ok and known) then
            return true;
        end
    end

    if (IsPlayerSpell) then
        local ok, known = pcall(IsPlayerSpell, resolvedID);
        if (ok and known) then
            return true;
        end
    end

    return false;
end

---@param step table
---@return string|nil reason
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

    -- Pause instead of mis-buffing when a party target does not exist.
    if (step.target and step.target ~= "player" and _G.UnitExists and not _G.UnitExists(step.target)) then
        return Reason.NoTarget;
    end

    local handler = STEP_DISPATCH[step.type];

    -- Pet steps are cast by the pet: exempt from player-casting/movement gates.
    if (not (handler and handler.petExempt)) then
        if (UnitCastingInfo and UnitCastingInfo("player")) then
            return Reason.Casting;
        end

        if (IsPlayerMoving and IsPlayerMoving()) then
            return Reason.Moving;
        end
    end

    local entry = self:getCatalogEntry(step.spellID);

    if (entry and entry.needsShard and ACP.Inventory:countItem(ACP.Data.Constants.SOUL_SHARD_ITEM_ID) < 1) then
        return Reason.NoShard;
    end

    -- Gate safety applies to cast-time steps only (instant steps cannot be
    -- caught mid-cast).
    if (not entry or not entry.isCastTime) then
        return nil;
    end

    if (not ACP.Preconditions:gateSafetyOk()) then
        return Reason.GateSafety;
    end

    return nil;
end

---@param spellID number
---@return number|nil
function WorkflowEngine:getPetEntry(spellID)
    local data = ACP.Data.activeClassWorkflows();
    local spells = data and data.spells;

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

    -- TBC pet GUID: <type>-<server>-<instance>-<zone>-<entry>-<spawnHex>;
    -- the creature entry ID is the 5th segment.
    local id = guid:match("^%w+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$");

    ACP:debugPrint("workflow pet GUID %s -> entry %s (want %s)", tostring(guid), tostring(id), tostring(petEntry));

    return id ~= nil and tonumber(id) == petEntry;
end

---@param step table
---@return boolean
function WorkflowEngine:isStepGoalMet(step)
    local handler = STEP_DISPATCH[step.type];

    if (handler and handler.goalMet) then
        return handler.goalMet(self, step);
    end

    return false;
end

--- The global "skip completed steps" setting governs cast/summon/createItem
--- steps; there is no per-step flag.
---@param step table
---@return boolean
function WorkflowEngine:effectiveSkip(step)
    local handler = STEP_DISPATCH[step.type];

    if (handler and handler.skippable) then
        return ACP.Settings:get("workflows.skipIfBuffedDefault") == true;
    end

    return false;
end

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

--- ExpirationTime of the named helpful aura, or nil when absent. Lets
--- waitForInstantEffect distinguish "the buff landed" from "already there"
--- when the target is buffed at step start (skip-completed OFF → re-cast).
---@param unit string
---@param name string
---@return number|nil
function WorkflowEngine:getBuffExpiration(unit, name)
    if (not GetAuraDataByIndex or name:sub(1, 1) == "#") then
        return nil;
    end

    for i = 1, MAX_AURA_INDEX do
        local aura = GetAuraDataByIndex(unit, i, "HELPFUL");

        if (not aura) then
            break;
        end

        if (aura.name == name) then
            return aura.expirationTime;
        end
    end

    return nil;
end

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

function WorkflowEngine:advance()
    self:cancelTimers();
    self:clearTransientState(false);
    self.stepIndex = self.stepIndex + 1;
    self:executeCurrentStep();
end

function WorkflowEngine:executeCurrentStep()
    if (self.state ~= WS.RUNNING) then
        return;
    end

    local definition = self:getDefinition(self.currentSlot);
    local steps = (definition and type(definition.steps) == "table") and definition.steps or {};
    local step = steps[self.stepIndex];

    if (not step) then
        local wasTesting = self.isTesting;

        self:cancelTimers();
        self:restoreSpellRanks();
        self:clearKeyCast();
        self:setState(WS.DONE);

        if (wasTesting) then
            self.isTesting = false;
            self.testSlot = nil;
            self.debugBypass = false;
        end

        ACP:debugPrint(ACP.L.workflow.done, self.currentSlot, self:definitionName());

        if (wasTesting) then
            ACP:print(ACP.L.workflow.done, self.currentSlot, self:definitionName());
        end

        ACP.Events:fire("ACP_WORKFLOW_DONE");
        return;
    end

    local ok, err = ACP.Data.Workflows:validateStep(step);

    if (not ok) then
        ACP:debugPrint(ACP.L.workflow.stepSkippedInvalid, self.stepIndex, tostring(err));
        self:advance();
        return;
    end

    ACP.Events:fire("ACP_WORKFLOW_STEP", self.currentSlot, self.stepIndex, step);

    -- Skip-completed: checked before the gates so a met goal is honored even
    -- without reagents.
    if (self:effectiveSkip(step) and self:isStepGoalMet(step)) then
        ACP:debugPrint(ACP.L.workflow.stepSkippedDone, self.stepIndex);
        self:advance();
        return;
    end

    local reason = self:checkGates(step);

    if (reason) then
        self:pause(reason);
        return;
    end

    local handler = STEP_DISPATCH[step.type];

    if (handler and handler.petDoneAware and self.petStepDone) then
        self.petStepDone = false;
        self:advance();
        return;
    end

    if (handler and handler.needsKnownSpell and not self:knowsSpell(step)) then
        ACP:debugPrint(ACP.L.workflow.stepSkippedUnknown, self.stepIndex);
        self:advance();
        return;
    end

    if (handler) then
        handler.run(self, step);
    end
end

---@param reason string
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

function WorkflowEngine:reset()
    self:cancelTimers();
    self:restoreSpellRanks();
    self:setState(WS.IDLE);
    self.currentSlot = nil;
    self.stepIndex = 1;
    self.isTesting = false;
    self:clearTransientState(true);
    self:clearKeyCast();
    ACP:debugPrint("workflow reset");
    ACP.Events:fire("ACP_WORKFLOW_RESET");
end

---@param slot number
function WorkflowEngine:start(slot)
    slot = slot or 1;

    if (type(slot) ~= "number" or slot < 1 or slot > ACP.Data.Constants.WORKFLOW_MAX_SLOTS) then
        ACP:debugPrint(ACP.L.workflow.slotUnknown, tostring(slot));
        return;
    end

    if (self.state == WS.RUNNING and self.currentSlot == slot) then
        return;
    end

    -- While a test run is active, only the tested slot's key may start/resume.
    if (self.debugBypass and self.testSlot and slot ~= self.testSlot) then
        ACP:debugPrint("workflow test: ignoring start for slot %d (testing slot %d)", slot, self.testSlot);
        return;
    end

    -- One run per prep/test: after DONE the key is a no-op.
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

    if (type(definition.steps) ~= "table" or #definition.steps == 0) then
        ACP:debugPrint(ACP.L.workflow.emptyWorkflow, slot, definition.name or "");
        return;
    end

    if (self.currentSlot and self.currentSlot ~= slot
        and (self.state == WS.RUNNING or self.state == WS.PAUSED)) then
        self:reset();
    end

    if (self.state == WS.PAUSED and self.currentSlot == slot) then
        self:setState(WS.RUNNING);
        ACP:debugPrint(ACP.L.workflow.resumed, slot, definition.name or "", self.stepIndex);
        ACP.Events:fire("ACP_WORKFLOW_RESUMED");
        if (self:needsSpellRanks()) then
            self:enableSpellRanks();
        end
        self:executeCurrentStep();
        return;
    end

    self.currentSlot = slot;
    self.stepIndex = 1;
    self:clearTransientState(true);
    self:setState(WS.RUNNING);
    ACP:debugPrint(ACP.L.workflow.started, slot, definition.name or "");
    ACP.Events:fire("ACP_WORKFLOW_STARTED", slot);
    if (self:needsSpellRanks()) then
        self:enableSpellRanks();
    end
    self:executeCurrentStep();
end

--- Test run outside an arena: bypasses the prep requirement and resets first.
---@param slot number
function WorkflowEngine:startTest(slot)
    slot = slot or 1;
    self.debugBypass = true;
    self.testSlot = nil;
    self:reset();
    self:start(slot);

    if (self.state == WS.RUNNING and self.currentSlot == slot) then
        self.isTesting = true;
        self.testSlot = slot;
        local definition = self:getDefinition(slot);
        local name = type(definition) == "table" and definition.name or "";
        ACP:print(ACP.L.workflow.started, slot, name);
    else
        -- Do not leak the bypass when the test did not start.
        self.debugBypass = false;
    end
end

function WorkflowEngine:stopTest()
    local slot = self.testSlot or self.currentSlot;
    self.isTesting = false;
    self.testSlot = nil;
    self.debugBypass = false;
    self:reset();
    ACP:print(ACP.L.workflow.testStopped, slot or 0);
end

---@return string
function WorkflowEngine:getStatus()
    local definition = self.currentSlot and self:getDefinition(self.currentSlot);
    local steps = definition and type(definition.steps) == "table" and #definition.steps or 0;

    return string.format("%s | slot=%s | step=%d/%d | key=%s",
        self.state, tostring(self.currentSlot), self.stepIndex, steps, tostring(self:resolveCastKey(self.currentSlot)));
end

function WorkflowEngine:_init()
    if (not ACP.StateMachine:initOnce(self)) then
        return;
    end

    ACP.WorkflowBindings:_init(self);
    ACP.WorkflowCastController:_init(self);
    ACP.WorkflowItemSteps:_init(self);

    ACP.Events:register("WE.BUFF_LOST", "ACP_BUFF_LOST", function()
        -- A test run ignores the arena buff — do not tear it down.
        if (not self.isTesting) then
            self:reset();
        end
    end);

    ACP.Events:register("WE.COMBAT_START", "PLAYER_REGEN_DISABLED", function()
        self:pause(Reason.InCombat);
    end);

    ACP.Events:register("WE.LOGOUT_SPELL_RANKS", "PLAYER_LOGOUT", function()
        self:restoreSpellRanks();
    end);
end

-- Delegates to the extracted step/binding modules (they operate on `self`).

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

function WorkflowEngine:needsSpellRanks()
    return ACP.WorkflowItemSteps:needsSpellRanks(self);
end

function WorkflowEngine:enableSpellRanks()
    return ACP.WorkflowItemSteps:enableSpellRanks(self);
end

function WorkflowEngine:restoreSpellRanks()
    return ACP.WorkflowItemSteps:restoreSpellRanks(self);
end

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
