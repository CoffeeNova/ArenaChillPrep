-- ArenaChillPrep — Classes/WorkflowItemSteps
-- createItem (conjure + item-appearance wait) and equipItem (secure-button
-- equip + poll completion). Operates on the engine (first argument).

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local pcall = _G.pcall;
local tostring = _G.tostring;

local WS = ACP.Data.Constants.WORKFLOW_STATE;

local Reason = ACP.Data.Constants.WORKFLOW_REASON;

local GetCVar = _G.GetCVar;
local SetCVar = _G.SetCVar;

---@class WorkflowItemSteps
local WorkflowItemSteps = {};

---@type WorkflowItemSteps
ACP.WorkflowItemSteps = WorkflowItemSteps;

---@return table|nil
local function activeRankTable()
    return ACP.Data.Workflows and ACP.Data.Workflows:activeRankTable();
end

--- createItem never skips on an already-present stone: the prep workflow
--- conjures several to trade, so completion is a delta (a NEW stone of the
--- expected rank appears).
---@param engine WorkflowEngine
---@param step table
function WorkflowItemSteps:createItem(engine, step)
    local castSpellID, castItemID = engine:resolveCastInfo(step);

    local name = engine:spellName(castSpellID);
    engine.expectedItemID = castItemID;
    -- The stored castable rank expects exactly its own rank's variants; the
    -- family-widened set only applies when the cast was upgraded.
    engine.expectedItemIDs = (castSpellID ~= step.spellID)
        and self:resolveExpectedItems(castSpellID, castItemID)
        or self:expandExpectedItems(castSpellID, castItemID);
    engine.expectedBaseline = engine:countExpectedItems();
    engine.pendingCastSpellID = castSpellID;
    engine:requestKeyCast(name, step);
end

--- Item IDs accepted for the UNLEARNED-rank fallback: every same-family item
--- of rank >= the step's rank (variants expanded), else the single itemID.
---@param spellID number
---@param itemID number
---@return table
function WorkflowItemSteps:resolveExpectedItems(spellID, itemID)
    local rankTable = activeRankTable();
    local rankEntry = rankTable and rankTable[spellID];

    if (not rankEntry) then
        return { itemID };
    end

    local ids = {};

    for _, r in pairs(rankTable) do
        if (r.spellName == rankEntry.spellName and r.rank >= rankEntry.rank) then
            local variants = r.itemIDs or { r.itemID };

            for _, id in ipairs(variants) do
                ids[#ids + 1] = id;
            end
        end
    end

    return ids;
end

--- The full set of item IDs a cast of `castSpellID` can produce (both
--- historical variants when known), else the single item ID.
---@param castSpellID number
---@param castItemID number
---@return table
function WorkflowItemSteps:expandExpectedItems(castSpellID, castItemID)
    local rankTable = activeRankTable();
    local rank = rankTable and rankTable[castSpellID];

    if (rank and rank.itemIDs) then
        return rank.itemIDs;
    end

    return { castItemID };
end

---@param engine WorkflowEngine
---@return number
function WorkflowItemSteps:countExpectedItems(engine)
    if (not engine.expectedItemIDs) then
        return 0;
    end

    local total = 0;

    for _, id in ipairs(engine.expectedItemIDs) do
        total = total + ACP.Inventory:countItem(id);
    end

    return total;
end

---@param engine WorkflowEngine
---@return boolean
function WorkflowItemSteps:isItemCreated(engine)
    if (not engine.expectedItemIDs) then
        return false;
    end

    return engine:countExpectedItems() > (engine.expectedBaseline or 0);
end

--- A following createItem step whose RESOLVED cast equals this step's keeps the item wait.
---@param engine WorkflowEngine
---@return boolean
function WorkflowItemSteps:nextRepeatsConjure(engine)
    local def = engine:getDefinition(engine.currentSlot);
    local steps = def and def.steps;
    local current = steps and steps[engine.stepIndex];
    local nextStep = steps and steps[engine.stepIndex + 1];

    if (not (current and nextStep)) or nextStep.type ~= ACP.Data.Constants.WORKFLOW_STEP_CREATE_ITEM then
        return false;
    end

    local currentID = engine:resolveCastInfo(current);
    local nextID = engine:resolveCastInfo(nextStep);

    return currentID ~= nil and currentID == nextID;
end

--- Whether a createItem step's product is already in bags. A castable stored
--- rank expects exactly its own rank's variants (a leftover higher-rank stone
--- must not satisfy it); the family-widened set is only for the upgraded cast.
--- When the resolved spell is a tracked autotrade item (its rank entry maps to
--- an enabled `items.<key>` setting with a count), the goal is the COUNT
--- TARGET — repeated Conjure steps conjure until `count` is met. Otherwise any
--- variant present satisfies the step.
---@param engine WorkflowEngine
---@param step table
---@return boolean
function WorkflowItemSteps:isItemAlreadyPresent(engine, step)
    local castSpellID, castItemID = engine:resolveCastInfo(step);

    local ids = (castSpellID ~= step.spellID)
        and self:resolveExpectedItems(castSpellID, castItemID)
        or self:expandExpectedItems(castSpellID, castItemID);

    local rankTable = activeRankTable();
    local rankEntry = rankTable and rankTable[castSpellID];

    if (rankEntry and rankEntry.category and ACP.Data.Items.settingsKeyFor) then
        local settingsKey = ACP.Data.Items:settingsKeyFor(rankEntry.category);
        local setting = ACP.Settings:get("items." .. settingsKey);

        if (setting and setting.enabled and type(setting.count) == "number") then
            local total = 0;

            for _, id in ipairs(ids) do
                total = total + ACP.Inventory:countItem(id);
            end

            return total >= setting.count;
        end
    end

    for _, id in ipairs(ids) do
        if (ACP.Inventory:countItem(id) > 0) then
            return true;
        end
    end

    return false;
end

--- Points the secure button at the item and arms the completion poll.
local function armEquip(engine, step, itemID, itemName)
    engine.waitingForEquip = true;

    engine:setCastAttribute("type", "item");
    engine:setCastAttribute("item", itemName);
    engine:setCastAttribute("unit", nil);

    local key = engine:resolveCastKey(engine.currentSlot);

    if (not key) then
        if (engine.debugBypass) then
            ACP:print(ACP.L.workflow.testNoKey, engine.currentSlot);
        end
        engine.waitingForEquip = false;
        engine:pause(Reason.NoHotkey);
        return;
    end

    if (engine.debugBypass) then
        ACP:print(ACP.L.workflow.pressEquip, key, itemName);
    else
        ACP:debugPrint(ACP.L.workflow.pressEquip, key, itemName);
    end

    ACP.Utils.Timers:interval("WorkflowItemPoll", 0.25, function()
        if (engine.state ~= WS.RUNNING or not engine.waitingForEquip or engine.equipItemID ~= itemID) then
            return;
        end

        if (ACP.Inventory:countItem(itemID) == 0) then
            ACP.Utils.Timers:cancel("WorkflowItemPoll");
            engine:advance();
        end
    end);
end

--- An absent item is in flight from the conjure step that advanced on cast-end;
--- poll up to WORKFLOW_EQUIP_GRACE, then advance as already-equipped.
---@param engine WorkflowEngine
---@param step table
function WorkflowItemSteps:equipItem(engine, step)
    local itemID = step.itemID;
    engine.equipItemID = itemID;
    local itemName = engine:itemName(step);

    if (ACP.Inventory:countItem(itemID) > 0) then
        armEquip(engine, step, itemID, itemName);
        return;
    end

    local grace = ACP.Data.Constants.WORKFLOW_EQUIP_GRACE;
    local ticks = 0;

    ACP.Utils.Timers:interval("WorkflowEquipGrace", 0.25, function()
        if (engine.state ~= WS.RUNNING or engine.equipItemID ~= itemID) then
            return;
        end

        ticks = ticks + 1;

        if (ACP.Inventory:countItem(itemID) > 0) then
            ACP.Utils.Timers:cancel("WorkflowEquipGrace");
            armEquip(engine, step, itemID, itemName);
            return;
        end

        if (ticks * 0.25 >= grace) then
            ACP.Utils.Timers:cancel("WorkflowEquipGrace");
            engine:advance();
        end
    end);
end

--- Poll for a created item (covers items the Inventory cache does not track).
---@param engine WorkflowEngine
---@param itemID number
function WorkflowItemSteps:waitForItem(engine, itemID)
    ACP.Utils.Timers:interval("WorkflowItemPoll", 0.25, function()
        if (engine.state ~= WS.RUNNING or engine.expectedItemID ~= itemID) then
            return;
        end

        if (engine:isItemCreated()) then
            ACP.Utils.Timers:cancel("WorkflowItemPoll");
            engine.expectedItemID = nil;
            engine.expectedItemIDs = nil;
            engine.expectedBaseline = nil;
            engine:advance();
        end
    end);

    ACP.Utils.Timers:after("WorkflowCastTimeout", ACP.Data.Constants.WORKFLOW_CAST_TIMEOUT, function()
        if (engine.state ~= WS.RUNNING or engine.expectedItemID ~= itemID) then
            return;
        end

        engine:pause(Reason.CastTimeout);
    end);
end

--- Highest rank of the family `familyName` in the rank table.
---@param rankTable table
---@param familyName string
---@return number|nil
local function familyMaxRank(rankTable, familyName)
    local max = nil;

    for _, candidate in pairs(rankTable) do
        if (candidate.spellName == familyName and (not max or candidate.rank > max)) then
            max = candidate.rank;
        end
    end

    return max;
end

--- Whether the run's definition contains a createItem step whose stored rank
--- is BELOW the family's max rank — such a rank can be hidden by the
--- spellbook's "Show all spell ranks" toggle and its secure cast fizzles.
---@param engine WorkflowEngine
---@return boolean
function WorkflowItemSteps:needsSpellRanks(engine)
    local def = engine:getDefinition(engine.currentSlot);

    if (not def) then
        return false;
    end

    local rankTable = activeRankTable();

    if (not rankTable) then
        return false;
    end

    for _, step in ipairs(def.steps or {}) do
        if (step.type == ACP.Data.Constants.WORKFLOW_STEP_CREATE_ITEM) then
            local rankEntry = rankTable[step.spellID];

            if (rankEntry) then
                local max = familyMaxRank(rankTable, rankEntry.spellName);

                if (max and rankEntry.rank < max) then
                    return true;
                end
            end
        end
    end

    return false;
end

--- Sets showAllSpellRanks = "1" for the duration of the run (restored by
--- restoreSpellRanks). Idempotent — a second call while active is a no-op.
---@param engine WorkflowEngine
function WorkflowItemSteps:enableSpellRanks(engine)
    if (engine.spellRanksOverridden) then
        return;
    end

    local name = ACP.Data.Constants.SPELL_RANKS_CVAR;

    if (GetCVar) then
        engine.savedSpellRanksCVar = GetCVar(name);

        if (engine.savedSpellRanksCVar ~= "1" and SetCVar) then
            SetCVar(name, "1");
        end
    end

    engine.spellRanksOverridden = true;
    ACP:debugPrint("workflow spell ranks override: on");
end

--- Restores the user's showAllSpellRanks value (nil → "0", the default).
---@param engine WorkflowEngine
function WorkflowItemSteps:restoreSpellRanks(engine)
    if (not engine.spellRanksOverridden) then
        return;
    end

    local name = ACP.Data.Constants.SPELL_RANKS_CVAR;

    if (SetCVar) then
        SetCVar(name, engine.savedSpellRanksCVar or "0");
    end

    engine.savedSpellRanksCVar = nil;
    engine.spellRanksOverridden = false;
    ACP:debugPrint("workflow spell ranks override: off");
end

---@param engine WorkflowEngine
function WorkflowItemSteps:_init(engine)
    -- createItem fast path: a crafted (tracked) item appeared.
    ACP.Events:register("WIS.ITEMS_CHANGED", "ACP_ITEMS_CHANGED", function()
        if (engine.state ~= WS.RUNNING or not engine.expectedItemID) then
            return;
        end

        if (engine:isItemCreated()) then
            ACP.Utils.Timers:cancel("WorkflowItemPoll");
            engine.expectedItemID = nil;
            engine.expectedItemIDs = nil;
            engine.expectedBaseline = nil;
            engine:advance();
        end
    end);
end

return ACP;
