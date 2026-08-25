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

---@class WorkflowItemSteps
local WorkflowItemSteps = {};

---@type WorkflowItemSteps
ACP.WorkflowItemSteps = WorkflowItemSteps;

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

--- Item IDs accepted for the UNLEARNED-rank fallback: every same-family stone
--- of rank >= the step's rank (variants expanded), else the single itemID.
---@param spellID number
---@param itemID number
---@return table
function WorkflowItemSteps:resolveExpectedItems(spellID, itemID)
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

--- The full set of item IDs a cast of `castSpellID` can produce (both
--- historical variants when known), else the single item ID.
---@param castSpellID number
---@param castItemID number
---@return table
function WorkflowItemSteps:expandExpectedItems(castSpellID, castItemID)
    local rank = ACP.Data.Workflows and ACP.Data.Workflows.stoneRanks
        and ACP.Data.Workflows.stoneRanks[castSpellID];

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

--- Whether a createItem step's product is already in bags. A castable stored
--- rank expects exactly its own rank's variants (a leftover higher-rank stone
--- must not satisfy it); the family-widened set is only for the upgraded cast.
---@param engine WorkflowEngine
---@param step table
---@return boolean
function WorkflowItemSteps:isItemAlreadyPresent(engine, step)
    local castSpellID, castItemID = engine:resolveCastInfo(step);

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

--- equipItem: the same secure button re-pointed to type="item". No spell
--- events fire for item use — completion is poll-driven (item leaves bags).
---@param engine WorkflowEngine
---@param step table
function WorkflowItemSteps:equipItem(engine, step)
    local itemID = step.itemID;
    engine.waitingForEquip = true;
    engine.equipItemID = itemID;

    if (ACP.Inventory:countItem(itemID) == 0) then
        engine:advance();
        return;
    end

    local itemName = engine:itemName(step);

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
