# Guide: createItem advances on cast-end (item wait only before a repeated conjure)

## 0. Goal (behavior contract)

Today every `createItem` step completes only when its product appears in the bags
(`WorkflowCastController:onCastComplete` → `isItemCreated()` → else `waitForItem`).
The client grants the item ~1–1.5 s AFTER `UNIT_SPELLCAST_STOP`, so consecutive
conjure steps are slowed by 1–1.5 s each.

New rules:

1. **createItem completes on cast-end** (`UNIT_SPELLCAST_STOP`/`SUCCEEDED`), i.e. the
   engine advances immediately — **UNLESS the NEXT step is also a `createItem` step
   that casts the SAME resolved spell** (2× Create Healthstone of different stored
   ranks, 2× Conjure Water, …). In that case keep today's item wait: the next step's
   goal-met skip (`isItemAlreadyPresent`) must see the crafted item.
2. **equipItem waits for an in-flight item**: if the item is absent at step start, do
   NOT advance immediately (today = "already equipped" skip). Poll up to
   `WORKFLOW_EQUIP_GRACE` (3 s) for it to appear (the preceding conjure step advanced
   on cast-end and the item is in flight); arm the equip when it appears; if it never
   appears, advance (already equipped — today's behavior, just delayed by the grace).
3. Everything else is unchanged: `UNIT_SPELLCAST_INTERRUPTED` re-arm, `FAILED` pause,
   `waitForItem` (poll + `ACP_ITEMS_CHANGED` fast path + 10 s timeout) for the
   repeated-conjure case, count-target goal-met logic, autotrade pipeline.

## 1. Files to change

| File | Change |
|---|---|
| `Data/Constants.lua` | add `WORKFLOW_EQUIP_GRACE = 3` |
| `Classes/WorkflowItemSteps.lua` | add `nextRepeatsConjure(engine)`; restructure `equipItem` (grace poll) |
| `Classes/WorkflowCastController.lua` | `onCastComplete`: advance-on-cast-end branch |
| `Classes/WorkflowEngine.lua` | `cancelTimers()`: cancel `"WorkflowEquipGrace"` |
| `Tests/Classes/test_workflowexecution.lua` | update 2 tests, add 3 new tests |
| `.ai/ARCHITECTURE.md`, `.ai/CONTEXT.md` | contract-first doc updates (see §6) |

No changes to: `waitForItem`, `isItemCreated`, `countExpectedItems`,
`isItemAlreadyPresent`, the `ACP_ITEMS_CHANGED` fast path (`WIS._init`),
`PetAbilityCaster`, `WorkflowBindings`, Data files.

## 2. `Data/Constants.lua`

After `WORKFLOW_CAST_TIMEOUT = 10` add:

```lua
    -- equipItem grace: how long to wait for a conjured item still in flight
    -- (the previous createItem step advanced on cast-end without the item).
    WORKFLOW_EQUIP_GRACE = 3,
```

## 3. `Classes/WorkflowItemSteps.lua`

### 3.1 New helper `nextRepeatsConjure` (place after `isItemCreated`)

```lua
--- Whether the NEXT step repeats the same conjure: another createItem step
--- whose RESOLVED cast spell equals the current step's (e.g. two Create
--- Healthstone entries stored as different ranks). The current step then
--- keeps the item wait so the next step's goal-met check sees the item.
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
```

Notes:
- Compare the RESOLVED cast IDs (`resolveCastInfo`): a Warlock at 70 stores
  `27230` and `11730` (family `Create Healthstone`), both resolve to `27230` → "repeats".
- `resolveCastInfo` returns `(spellID, itemID)` — capturing only the first value is intentional.
- Only `createItem` + `createItem` adjacency triggers the wait; `createItem → cast/summon/pet/equipItem` advances immediately.

### 3.2 Restructure `equipItem`

Extract the arming section into a module-local function and add the grace poll. Replace
the whole `equipItem` method with:

```lua
--- Arms the secure button as type="item" and prompts the press; the
--- completion poll (item leaves bags) is armed here too.
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

--- equipItem: the same secure button re-pointed to type="item". No spell
--- events fire for item use — completion is poll-driven (item leaves bags).
--- An absent item is waited for (in flight from the preceding conjure step,
--- which advanced on cast-end); if it never appears the step advances as
--- already-equipped.
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
```

Details:
- `waitingForEquip` is only read inside this module + tests (verified: no other
  consumers) — moving its assignment into `armEquip` is safe.
- Tick-count cap (`ticks * 0.25 >= grace`), NOT `GetTime()` — deterministic under the
  `SyncTimers` test recorder (no `_G.__stub.time` pinning needed).
- The grace poll guard mirrors the existing poll guard (`state ~= RUNNING or
  equipItemID ~= itemID` → bail); `pause()`/`advance()`/`reset()` clear `equipItemID`
  via `clearTransientState`, so the timer self-neutralizes even if a stray tick fires.
- `armEquip` keeps the exact current behavior for the "item present" path (including
  the `Reason.NoHotkey` pause and the debugPrint/pressEquip prompts).

## 4. `Classes/WorkflowCastController.lua` — `onCastComplete`

Replace the `engine.expectedItemID` branch:

```lua
    if (engine.expectedItemID) then
        if (engine:isItemCreated()) then
            engine.expectedItemID = nil;
            engine.expectedItemIDs = nil;
            engine.expectedBaseline = nil;
            engine:advance();
            return;
        end

        if (ACP.WorkflowItemSteps:nextRepeatsConjure(engine)) then
            -- A repeated conjure follows — its goal-met check needs this
            -- cast's item; keep the wait (poll / ACP_ITEMS_CHANGED).
            engine:waitForItem(engine.expectedItemID);
            return;
        end

        -- Item not needed by the next step: advance on cast-end.
        engine.expectedItemID = nil;
        engine.expectedItemIDs = nil;
        engine.expectedBaseline = nil;
        engine:advance();
        return;
    end
```

Notes:
- The `expectedItemID` clearing before `advance()` is redundant with
  `advance()` → `clearTransientState` but keeps the branch symmetrical with the
  existing code — keep it.
- `advance()` also clears `expectedItemIDs`/`expectedBaseline`, so the late
  `ACP_ITEMS_CHANGED` fast path (WIS `_init` handler, guard
  `not engine.expectedItemID`) never falsely advances the NEXT step.
- STOP and SUCCEEDED both route here; the first to fire wins (unchanged).

## 5. `Classes/WorkflowEngine.lua` — `cancelTimers`

Add the new timer name:

```lua
function WorkflowEngine:cancelTimers()
    ACP.Utils.Timers:cancel("WorkflowCastTimeout");
    ACP.Utils.Timers:cancel("WorkflowGCD");
    ACP.Utils.Timers:cancel("WorkflowItemPoll");
    ACP.Utils.Timers:cancel("WorkflowPetVerify");
    ACP.Utils.Timers:cancel("WorkflowEquipGrace");
end
```

## 6. Tests

### 6.1 Update `Tests/Classes/test_workflowexecution.lua`

- **`testSpellcastStopCompletesCreateItemViaWait`** — a single createItem step has NO
  next step, so the new behavior is immediate advance. Rename to
  `testSpellcastStopCompletesCreateItemImmediately`, keep the setup
  (installTimers, `waitingForCast = true`, expected fields, `countItemStub({})`), and
  assert: `Engine.state == "DONE"` and `H.hasTimer("WorkflowItemPoll")` is FALSE.
- **`testEquipItemAlreadyEquippedAdvances`** — count==0 now goes through the grace poll.
  Keep the setup, then `H.advance("WorkflowEquipGrace")` 12 times (3 s / 0.25 s); assert
  `Engine.state == "DONE"`. Also assert it is NOT "DONE" before the grace elapses (e.g.
  after 5 advances still RUNNING).

### 6.2 New tests

- **`testSpellcastStopRepeatedConjureKeepsItemWait`** — `setupEngine` with TWO
  createItem steps (27230/22105 then 11730/19012, `knownSpells = { [27230] = true }`
  so 11730 resolves to 27230), `stepIndex = 1`, `waitingForCast = true`, expected
  fields, `countItemStub({})`. Fire `UNIT_SPELLCAST_STOP` →
  `H.hasTimer("WorkflowItemPoll")` TRUE (still waiting). Then
  `countItemStub({ [22105] = 1 })` + `H.advance("WorkflowItemPoll")` → step 2's
  goal-met check (count ≥ 1) skips it → assert `Engine.state == "DONE"`.
- **`testSpellcastStopDifferentConjureAdvancesImmediately`** — two createItem steps
  Water (27090/22018) then Food (33717/22019), `knownSpells = { [27090] = true,
  [33717] = true }`, `stepIndex = 1`, expected fields, `countItemStub({})`. Fire STOP →
  assert `Engine.stepIndex == 2`, `Engine.expectedItemID == nil`, no
  "WorkflowItemPoll" timer.
- **`testEquipItemGraceArmsWhenItemArrives`** — equipItem step (22646), `installTimers`,
  count stub {} at start, then swap to `{ [22646] = 1 }`; `H.advance("WorkflowEquipGrace")`
  once → assert `Engine.waitingForEquip == true` and `H.hasTimer("WorkflowItemPoll")` TRUE
  (armed, not advanced). Keep the existing `testEquipItemPollCompletesWhenItemGone` as-is.

No changes to `Tests/Classes/test_workflowitemsteps.lua` (goal-met logic untouched).

## 7. Docs (contract-first — do this BEFORE the code)

- `.ai/ARCHITECTURE.md`:
  - §2.10 bullet "createItem" (line 510): describe the two completion modes.
  - Edge-case table (line 598): update "createItem cast done, item not in bags yet".
  - Add ADR 22: "createItem completes on cast-end; the item wait stays only before a
    repeated conjure; equipItem waits up to WORKFLOW_EQUIP_GRACE (3 s) for an in-flight
    conjured item before advancing as already-equipped."
- `.ai/CONTEXT.md`: add gotcha #25 summarizing the same rule + the equip grace.
- Memory (LAST, after live verification): append to `.ai/memories/repo/arena-chill-prep.md`.

## 8. Verification

1. `.\Tests\run-tests.ps1` → exit `0` (all green, coverage ≥ 90%, CLEAN stats).
2. `.ai/tools/vararg-check.ps1` + `.ai/tools/syntax-check.ps1`.
3. `.ai/tools/deploy.ps1`.
4. Live (`/acp debug`, `/acp workflowtest 1`):
   - Mage: Water→Water→Food→Food pairs — waits only after Water#1 and Food#1;
     steps 2/4 advance right at cast end.
   - Warlock: HS pair still yields one Master stone (2nd step skips); Spellstone →
     equip Master Spellstone still equips (grace covers the in-flight stone).
   - Jump mid-cast still re-arms the same step; bags-full / FAILED still pause.

## 9. Non-goals (do NOT do)

- Do NOT change `isItemAlreadyPresent`/count-target logic, `waitForItem`, the
  `ACP_ITEMS_CHANGED` fast path, `INTERRUPTED`/`FAILED` handlers.
- Do NOT add an item-arrival watchdog or in-flight goal-met compensation — the
  user's chosen variant relies only on the repeated-conjure wait + the equip grace.
- Do NOT touch `TradeManager`/`TradePlanner`/`Inventory`/`DeliveryController`.
