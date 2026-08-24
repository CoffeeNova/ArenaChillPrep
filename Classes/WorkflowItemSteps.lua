-- ArenaChillPrep — Classes/WorkflowItemSteps
-- Item step execution, extracted from WorkflowEngine (refactor Phase 5):
-- createItem (conjure + item-appearance wait) and equipItem (secure-button
-- equip + poll completion) + the expected-item resolution helpers. Every
-- stateful function takes the ENGINE as its first argument — the engine OWNS
-- the state; the pure resolvers (resolveExpectedItems / expandExpectedItems)
-- take no engine.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local pcall = _G.pcall;
local tostring = _G.tostring;

--- State machine values (Data/Constants.WORKFLOW_STATE).
local WS = ACP.Data.Constants.WORKFLOW_STATE;

--- Pause reason keys (Data/Constants.WORKFLOW_REASON).
local Reason = ACP.Data.Constants.WORKFLOW_REASON;

---@class WorkflowItemSteps
local WorkflowItemSteps = {};

---@type WorkflowItemSteps
ACP.WorkflowItemSteps = WorkflowItemSteps;

--- createItem step (§3.6): self-cast via the secure hotkey (all conjure
--- spells are cast-time on 20506 — Create Healthstone is 3 s), then wait for
--- the item to appear.
---@param engine WorkflowEngine
---@param step table
function WorkflowItemSteps:createItem(engine, step)
    -- Resolve the castable rank: if the stored rank is castable it is used as-is;
    -- only an unlearned stored rank is upgraded to the player's known rank, and
    -- the expected item is derived from whichever rank actually casts.
    local castSpellID, castItemID = engine:resolveCastInfo(step);

    -- NOTE: createItem does NOT skip when a same-family stone is already in
    -- bags. TBC 2.5.5 lets a Warlock carry MULTIPLE healthstones/spellstones
    -- (they do not share a unique tag), and the prep workflow's purpose is to
    -- conjure several to trade to a partner (DeliveryController). Each create
    -- step therefore always casts; completion is detected by a NEW stone of the
    -- family appearing (isItemCreated delta), not by mere presence.

    local name = engine:spellName(castSpellID);
    engine.expectedItemID = castItemID;
    -- Exact-rank expectation when the stored rank is castable (the TBC ranks
    -- coexist — a rank-5 cast really creates a Major stone, and only a NEW
    -- Major satisfies it). The expectation covers the rank's full variant
    -- pair (e.g. Major = 19012/19013 — the client conjures either), so the
    -- step completes on the variant the client actually created. The
    -- family-widened set is only for the unlearned-rank fallback, where the
    -- cast upgrades to the player's known rank.
    engine.expectedItemIDs = (castSpellID ~= step.spellID)
        and self:resolveExpectedItems(castSpellID, castItemID)
        or self:expandExpectedItems(castSpellID, castItemID);
    engine.expectedBaseline = engine:countExpectedItems();
    engine.pendingCastSpellID = castSpellID;
    engine:requestKeyCast(name, step);
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

--- The full set of item IDs a cast of `castSpellID` can produce: both
--- historical variants of the spell's stone rank when known (healthstone
--- ranks 1-5 are ID pairs — the client conjures one variant per rank, e.g.
--- rank 5 → 19013 while the step stores 19012, live-verified 2026-08-22),
--- else the single expected item ID.
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

--- Current bag count across `expectedItemIDs` (0 when not set).
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

--- Whether the createItem cast has produced its item yet: a delta vs. the
--- pre-cast bag count across the accepted item IDs (so a leftover higher-rank
--- stone does not satisfy a lower-rank step).
---@param engine WorkflowEngine
---@return boolean
function WorkflowItemSteps:isItemCreated(engine)
    if (not engine.expectedItemIDs) then
        return false;
    end

    return engine:countExpectedItems() > (engine.expectedBaseline or 0);
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
---@param engine WorkflowEngine
---@param step table
function WorkflowItemSteps:equipItem(engine, step)
    local itemID = step.itemID;
    engine.waitingForEquip = true;
    engine.equipItemID = itemID;

    -- Goal already met: nothing in bags to equip (already equipped/consumed).
    if (ACP.Inventory:countItem(itemID) == 0) then
        engine:advance();
        return;
    end

    local itemName = engine:itemName(step);

    engine:setCastAttribute("type", "item");
    engine:setCastAttribute("item", itemName);
    engine:setCastAttribute("unit", nil);

    local key = engine:resolveCastKey(engine.currentSlot);

    if (key) then
        ACP:debugPrint(ACP.L.workflow.pressEquip, key, itemName);
        ACP:debugPrint("workflow equip: %s (step %d) waiting for key %s", itemName, engine.stepIndex, key);
    else
        engine.waitingForEquip = false;
        engine:pause(Reason.NoHotkey);
        return;
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

--- Wait for a created item to appear in bags: poll every 0.25 s (covers items
--- the Inventory cache does not track, e.g. Major Soulstone 22103) with a
--- WORKFLOW_CAST_TIMEOUT safety window.
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

--- Register the createItem fast-path event (owns the ACP_ITEMS_CHANGED
--- subscription).
---@param engine WorkflowEngine
function WorkflowItemSteps:_init(engine)
    -- createItem: a crafted (tracked) item appeared — fast path. Untracked
    -- items (Major Soulstone) are covered by the waitForItem poll. Detection
    -- is delta-based (isItemCreated) against the exact-rank expected set, so
    -- a leftover higher-rank stone never completes a lower-rank step.
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
