# Guide: make the workflow engine independent of the spellbook "Show all spell ranks" toggle

## 0. Goal (behavior contract)

The standard Warlock workflows 1 and 2 stall silently at the step
**"Create Healthstone (rank 5)"** (`spellID = 11730`, creates **Major Healthstone**
item `19012`/`19013`). Live-verified cause (user): the spellbook's
**"Show all spell ranks"** checkbox (CVar `showAllSpellRanks`). When it is OFF,
the rank-5 stone is not created; when ON, everything works.

Contract after the fix:

1. The workflow creates **both** stones regardless of the toggle: step 2
   (`27230`) → **Master Healthstone** (`22105`), step 3 (`11730`) → **Major
   Healthstone** (`19012`/`19013`). The game allows carrying several
   healthstones of different ranks — this is the intended behavior.
2. **No rank resolution changes.** `resolveCastInfo` keeps returning the stored
   rank verbatim when known: `11730` stays `11730` (it MUST NOT be upgraded to
   `27230` — the user rejected that).
3. The user's toggle value is restored after every workflow run — the addon
   must never permanently change the player's spellbook preference.
4. Workflows that do not need it (max-rank-only steps, Mage defaults) never
   touch the CVar.

## 1. Background: the bug (evidence)

Debug log (user, `/acp workflowtest 2`, debug on):

```
[13:16:08] ACP: Workflow 2 (2s no sacrifice) started
[13:16:08] ACP: Press F5 to cast Summon Imp
[13:16:08] ACP: workflow cast accepted (step 1)
[13:16:14] ACP: Press F5 to cast Create Healthstone
[13:16:15] ACP: workflow spellbook catalog rebuilt: found=22
[13:16:15] ACP: workflow cast accepted (step 2)
[13:16:18] ACP: Press F5 to cast Create Healthstone
[13:16:18] You create: [Master Healthstone].
[13:16:19] ACP: item 22105 count changed -> 1
```

Interpretation (already confirmed against the code):

- Step 2 (`27230`) casts fine, the Master stone lands at 13:16:19.
- At 13:16:18 the engine advanced to step 3 (`11730`) and armed it — that is
  the second `Press F5` line (`WorkflowItemSteps:createItem` →
  `requestKeyCast`). `nextRepeatsConjure` correctly returned FALSE (the two
  stored ranks resolve to different spells — different stones are intended).
- The user presses F5 for step 3: **the secure button cast silently fizzles.**
  No `UNIT_SPELLCAST_SENT` (no "cast accepted (step 3)"), no
  `UNIT_SPELLCAST_FAILED`, no error message — so the engine stays in
  `waitingForKey` forever. Nothing else is logged, exactly like the log shows.
- Only workflows 1 and 2 contain a below-max-rank healthstone step — that is
  why only they stall.

The user then live-verified: with the spellbook checkbox "Show all spell
ranks" **ON**, the rank-5 cast works and the workflow proceeds. With it OFF the
rank-5 stone is never created.

## 2. Root cause

On the TBC Anniversary client (Interface 20506) the CVar
`showAllSpellRanks` ("0"/"1") does not only filter the spellbook display — it
also controls which trained ranks the **casting system** accepts. With the CVar
"0", a `SecureActionButtonTemplate` click with `SetAttribute("spell", 11730)`
is dropped silently: no cast, no `UNIT_SPELLCAST_*` event, no error.

Note: `IsPlayerSpell` still reports the hidden rank (that is why
`resolveCastInfo` resolves `11730` verbatim and the engine correctly arms the
step — nothing in the engine's resolve/goal-met logic is wrong).

## 3. The proven fix (evidence from working addons on the SAME client)

Two working addons implement exactly this workaround — temporarily set the CVar
to "1", do the work, restore the user's value:

- `M6/Libs/ActionBook/Categories.lua:82-101`:
  `local asv = not MODERN and GetCVar("showAllSpellRanks")` →
  `if asv and asv ~= "1" then SetCVar("showAllSpellRanks", "1") end` →
  (spellbook scan) → `if asv and asv ~= "1" and not MODERN then SetCVar("showAllSpellRanks", asv) end`.
- `WeakAuras/Libs/LibDispel/LibDispel.lua:158/220` — the same pattern, with the
  comment: *"this will fix a problem where spells dont show as existing because
  they are 'hidden'"*: `local undoRanks = (vanilla and GetCVar('ShowAllSpellRanks') ~= '1') and SetCVar('ShowAllSpellRanks', '1')`
  → work → `SetCVar('ShowAllSpellRanks', '0')`.

CVar names are case-insensitive; use M6's lowercase form `showAllSpellRanks`.

## 4. Design decisions (already approved by the user)

1. **Run-scoped override.** While a workflow RUNS (from `start()`/`startTest()`
   until DONE / `reset()` / `stopTest()` / `PLAYER_LOGOUT`), set
   `showAllSpellRanks = "1"` — but ONLY when the workflow definition contains a
   `createItem` step whose stored rank is below the max rank of its family
   (per the static rank table). Pausing does NOT restore (a resume may need to
   cast the same step again).
2. **Restore exactly.** On every exit path restore the exact value that
   `GetCVar` returned; if it returned `nil`, restore to `"0"` (the client
   default = ranks hidden).
3. **Why the whole run and not per-step:** a per-step toggle around the cast
   would have to survive the `UNIT_SPELLCAST_INTERRUPTED` re-arm path (which
   calls `requestKeyCast` directly, not `createItem`) — a whole-run override is
   simpler and has no such holes.
4. The CVar persists in `config-cache.wtf` — the `PLAYER_LOGOUT` restore is
   REQUIRED so a logout mid-run cannot leave the user's setting flipped.

## 5. Files to change

No new modules. No changes to TOC or `Tests/loader.lua`.

### 5.1 `Data/Constants.lua`

After `SOUL_SHARD_ITEM_ID = 6265,` (around line 83) add:

```lua
    -- Spellbook CVar gating hidden-rank castability (see CONTEXT gotcha #26).
    SPELL_RANKS_CVAR = "showAllSpellRanks",
```

### 5.2 `Classes/WorkflowItemSteps.lua`

Add two file-scope aliases next to the existing ones at the top (after
`local Reason = ...`):

```lua
local GetCVar = _G.GetCVar;
local SetCVar = _G.SetCVar;
```

Add three functions and one local helper BEFORE `WorkflowItemSteps:_init`
(after `waitForItem`, around line 280). Use the exact code below:

```lua
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
```

### 5.3 `Classes/WorkflowEngine.lua`

1. **State fields** — in the table literal after `instantPressDetected = false,`
   (around line 87) add:

```lua
    ---@type boolean
    spellRanksOverridden = false,

    ---@type string|nil
    savedSpellRanksCVar = nil,
```

2. **`start(slot)` — PAUSED-resume branch** (around line 691). Insert the
   enable right before `self:executeCurrentStep()` (note: `currentSlot` is
   already set here, which `needsSpellRanks` needs):

```lua
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
```

3. **`start(slot)` — fresh-start path** (around line 699). Same insertion after
   `ACP.Events:fire("ACP_WORKFLOW_STARTED", slot);` and before
   `self:executeCurrentStep();`:

```lua
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
```

   (Both call sites are needed because `start()` has two separate exit paths;
   `enableSpellRanks` is idempotent, so a double call is harmless.)

4. **`reset()`** (around line 623) — restore right after `self:cancelTimers();`:

```lua
function WorkflowEngine:reset()
    self:cancelTimers();
    self:restoreSpellRanks();
    self:setState(WS.IDLE);
    ...
```

5. **DONE branch of `executeCurrentStep()`** (around line 540) — restore next
   to `cancelTimers()`:

```lua
    if (not step) then
        local wasTesting = self.isTesting;

        self:cancelTimers();
        self:restoreSpellRanks();
        self:clearKeyCast();
        self:setState(WS.DONE);
```

6. **`_init()`** (around line 756) — register a logout restore (CVars persist
   across sessions; `PLAYER_LOGOUT` also fires on `/reload`):

```lua
    ACP.Events:register("WE.LOGOUT_SPELL_RANKS", "PLAYER_LOGOUT", function()
        self:restoreSpellRanks();
    end);
```

7. **Delegates** — next to the existing WorkflowItemSteps delegates (around
   line 830-860, after `waitForItem`):

```lua
function WorkflowEngine:needsSpellRanks()
    return ACP.WorkflowItemSteps:needsSpellRanks(self);
end

function WorkflowEngine:enableSpellRanks()
    return ACP.WorkflowItemSteps:enableSpellRanks(self);
end

function WorkflowEngine:restoreSpellRanks()
    return ACP.WorkflowItemSteps:restoreSpellRanks(self);
end
```

### 5.4 `Tests/stubs/wow_stubs.lua`

1. In `_G.__stub` (around line 24) add a mutable table:

```lua
    cvars = {},            -- { [name] = value } for GetCVar/SetCVar
```

2. At the end of the file add:

```lua
-- ---- CVars (captured by WorkflowItemSteps) ----
_G.GetCVar = function(name) return _G.__stub.cvars[name] end;
_G.SetCVar = function(name, value) _G.__stub.cvars[name] = tostring(value); end;
```

### 5.5 `Tests/Classes/test_workflowexecution.lua`

1. Extend `teardownEngine` (around line 59-77) so CVar state is always reset
   (luaunit runs tests alphabetically across suites — nothing may leak):

```lua
    _G.__stub.cvars = {};
    Engine.spellRanksOverridden = false;
    Engine.savedSpellRanksCVar = nil;
```

2. Add these tests (place them near the other WorkflowItemSteps tests; reuse
   `setupEngine`/`teardownEngine`/`countItemStub` — the suite's default
   `UnitClass` is Warlock, so `activeRankTable()` returns `stoneRanks`):

```lua
function testNeedsSpellRanksFalseWithoutRankedCreateStep()
    local savedDef = setupEngine({
        { type = "cast", spellName = "Fel Armor", spellID = 28189, target = "player" },
    });

    lu.assertIsFalse(Engine:needsSpellRanks());
    teardownEngine(savedDef);
end

function testNeedsSpellRanksTrueForBelowMaxRankCreateItem()
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Create Healthstone", spellID = 11730, itemID = 19012 },
    });

    lu.assertIsTrue(Engine:needsSpellRanks(), "rank 5 < rank 6 family max");
    teardownEngine(savedDef);
end

function testNeedsSpellRanksFalseForMaxRankCreateItem()
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Create Healthstone", spellID = 27230, itemID = 22105 },
    });

    lu.assertIsFalse(Engine:needsSpellRanks(), "rank 6 is the family max");
    teardownEngine(savedDef);
end

function testEnableSpellRanksOverridesAndRemembers()
    local savedDef = setupEngine({});
    _G.__stub.cvars["showAllSpellRanks"] = "0";

    Engine:enableSpellRanks();

    lu.assertIsTrue(Engine.spellRanksOverridden);
    lu.assertEquals(Engine.savedSpellRanksCVar, "0");
    lu.assertEquals(_G.__stub.cvars["showAllSpellRanks"], "1");
    teardownEngine(savedDef);
end

function testEnableSpellRanksIdempotent()
    local savedDef = setupEngine({});
    _G.__stub.cvars["showAllSpellRanks"] = "0";

    Engine:enableSpellRanks();
    Engine:enableSpellRanks();

    lu.assertEquals(Engine.savedSpellRanksCVar, "0", "first saved value kept");
    teardownEngine(savedDef);
end

function testRestoreSpellRanksRestoresPreviousValue()
    local savedDef = setupEngine({});
    _G.__stub.cvars["showAllSpellRanks"] = "0";
    Engine:enableSpellRanks();

    Engine:restoreSpellRanks();

    lu.assertIsFalse(Engine.spellRanksOverridden);
    lu.assertIsNil(Engine.savedSpellRanksCVar);
    lu.assertEquals(_G.__stub.cvars["showAllSpellRanks"], "0");
    teardownEngine(savedDef);
end

function testRestoreSpellRanksNilPreviousRestoresZero()
    local savedDef = setupEngine({});
    Engine:enableSpellRanks();

    Engine:restoreSpellRanks();

    lu.assertEquals(_G.__stub.cvars["showAllSpellRanks"], "0");
    teardownEngine(savedDef);
end

function testRestoreSpellRanksNoopWhenNotOverridden()
    local savedDef = setupEngine({});
    _G.__stub.cvars["showAllSpellRanks"] = "0";

    Engine:restoreSpellRanks();

    lu.assertEquals(_G.__stub.cvars["showAllSpellRanks"], "0", "user value untouched");
    teardownEngine(savedDef);
end

function testStartWithBelowMaxRankStepOverridesCVar()
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Create Healthstone", spellID = 11730, itemID = 19012 },
    });
    local restoreCount = countItemStub({ [6265] = 1 });
    _G.__stub.cvars["showAllSpellRanks"] = "0";
    Engine.state = "IDLE";
    Engine.stepIndex = 1;
    Engine.debugBypass = true;

    Engine:start(1);

    lu.assertEquals(_G.__stub.cvars["showAllSpellRanks"], "1", "override applied on start");
    lu.assertEquals(Engine.savedSpellRanksCVar, "0");

    Engine:reset();

    lu.assertEquals(_G.__stub.cvars["showAllSpellRanks"], "0", "restored on reset");
    restoreCount();
    teardownEngine(savedDef);
end

function testStartWithMaxRankStepsLeavesCVar()
    local savedDef = setupEngine({
        { type = "createItem", spellName = "Create Healthstone", spellID = 27230, itemID = 22105 },
    });
    local restoreCount = countItemStub({ [6265] = 1 });
    _G.__stub.cvars["showAllSpellRanks"] = "0";
    Engine.state = "IDLE";
    Engine.stepIndex = 1;
    Engine.debugBypass = true;

    Engine:start(1);

    lu.assertEquals(_G.__stub.cvars["showAllSpellRanks"], "0", "user value untouched");
    restoreCount();
    teardownEngine(savedDef);
end

function testPlayerLogoutRestoresSpellRanks()
    local savedDef = setupEngine({});
    _G.__stub.cvars["showAllSpellRanks"] = "0";
    Engine:enableSpellRanks();

    ACP.Events:fire("PLAYER_LOGOUT");

    lu.assertEquals(_G.__stub.cvars["showAllSpellRanks"], "0");
    teardownEngine(savedDef);
end
```

Notes for the test writer:

- `setupEngine` sets `Engine.debugBypass = true` and stubs the slot-1 key, so
  `start(1)` passes the gates; the `countItemStub({ [6265] = 1 })` satisfies the
  Soul Shard gate of the createItem step.
- `testPlayerLogoutRestoresSpellRanks` needs the engine's event handlers
  registered — `setupEngine` forces `Engine._initialized = false` and calls
  `Engine:_init()`, which registers them.
- Do NOT assert chat/print output — only state and CVar values.
- Every test MUST restore what it mutated; `teardownEngine` handles the CVar
  and the new engine fields (step 1 of this section).

## 6. Docs (contract-first — do this in the same change)

1. `.ai/CONTEXT.md` — add gotcha **#26** right after #25, with the text below:

```
26. **Spellbook "Show all spell ranks" toggle gates hidden-rank CASTING (fixed 2026-08-31).**
   With `showAllSpellRanks = "0"` a trained-but-hidden lower rank (e.g. Create
   Healthstone 11730) silently FIZZLES on the secure cast path: no SENT, no
   FAILED, no error — the engine sat in `waitingForKey` forever on the rank-5
   step (live-reported: workflows 1-2 stalled at "Create Healthstone (rank 5)";
   the log ends at the item-arrival line). `IsPlayerSpell` still reports hidden
   ranks, so `resolveCastInfo`/goal-met worked — only the CAST was refused.
   Fix: a run-scoped override of the `showAllSpellRanks` CVar ("1" during the
   run, restore the exact previous value on DONE/reset/stopTest/PLAYER_LOGOUT)
   — enabled only when the definition contains a createItem step below its
   family's max rank (`WorkflowItemSteps:needsSpellRanks` +
   `enableSpellRanks`/`restoreSpellRanks`, called from `WorkflowEngine:start`/
   `reset`/DONE/`_init` logout handler). Pattern proven by working addons on
   the same client: M6 `Libs/ActionBook/Categories.lua:82-101` and WeakAuras
   `Libs/LibDispel/LibDispel.lua:158/220` ("fix a problem where spells dont
   show as existing because they are 'hidden'"). CVar name:
   `showAllSpellRanks` (case-insensitive; M6's lowercase form). The stored rank
   is still honored — a rank-5 step still creates the Major stone (the user
   explicitly rejected resolving it up to Master).
```

2. `.ai/ARCHITECTURE.md` — add **ADR 23** in §5 after the ADR 22 block
   (separator line + paragraph, same style):

```
23. **Run-scoped `showAllSpellRanks` override (2026-08-31).** Hidden spell
   ranks fizzle on the secure cast path (CONTEXT gotcha #26). The engine keeps
   the CVar at "1" for the whole workflow run — from `start()`/`startTest()`
   (only when `WorkflowItemSteps:needsSpellRanks` finds a createItem step below
   its family's max rank) until DONE/`reset()`/`stopTest()`/`PLAYER_LOGOUT`
   (`restoreSpellRanks`, exact previous value, nil → "0" — the CVar persists in
   config-cache.wtf, so the logout restore is required). Pause/resume do NOT
   restore — a resumed run may cast the same hidden-rank step again. The
   pattern is proven by M6 ActionBook and WeakAuras LibDispel on the same
   client. `resolveCastInfo`/goal-met/`nextRepeatsConjure` are untouched: a
   stored rank-5 step still creates the Major stone.
```

3. `.ai/skills/wow-api-20506/SKILL.md` — add a row to the verified-gotchas
   table:

```
| `showAllSpellRanks` CVar = "0" | Trained-but-HIDDEN ranks silently fizzle on a `SecureActionButtonTemplate` cast (no SENT/FAILED/error); `IsPlayerSpell` still reports them. Live-verified 2026-08-31 | Temporarily `SetCVar("showAllSpellRanks", "1")` for the operation and restore the previous value (M6 `Libs/ActionBook/Categories.lua:82-101`, WeakAuras `Libs/LibDispel/LibDispel.lua:158/220` — same client) |
```

4. Repo memory — do NOT write yet (memory-last rule). The live-verification
   report goes to memory after the user confirms in game.

## 7. Verification (agent-side, in order)

1. `.\Tests\run-tests.ps1` → **exit code 0** (all tests pass AND coverage ≥ 90%
   on a clean luacov stats file). If new lines are uncovered, add a test — the
   `enableSpellRanks`/`restoreSpellRanks`/`needsSpellRanks` paths and the
   PLAYER_LOGOUT handler must all be covered.
2. `.\.ai\tools\vararg-check.ps1` → every `.lua` ends with `return ACP;`.
3. `.\.ai\tools\syntax-check.ps1` → all files parse.
4. `.\.ai\tools\deploy.ps1` → deploy to the client so the user can test.

## 8. Non-goals (do NOT do any of these)

- Do NOT change `resolveCastInfo` (no always-upgrade — the user explicitly
  rejected resolving `11730` → `27230`).
- Do NOT change `isItemAlreadyPresent` / `nextRepeatsConjure` / `waitForItem` /
  `isItemCreated` / `createItem`'s expected-item logic.
- Do NOT switch casting to macrotext or spellbook slots — the CVar override is
  the chosen mechanism.
- Do NOT set the CVar permanently, and do NOT restore on `pause()` (resume must
  keep the override).
- Do NOT touch Mage logic, the delivery pipeline, or any UI code.
- Do NOT add comments beyond the repo conventions (one short WHY line where the
  code is genuinely non-obvious; the full story lives in `.ai/` docs).

## 9. Live verification checklist (for the user, after deploy)

1. Turn the spellbook checkbox "Show all spell ranks" **OFF**.
2. `/acp debug` on, then `/acp workflowtest 2`:
   - step 2 creates **Master Healthstone**, step 3 creates **Major
     Healthstone** ("You create: [Major Healthstone]" + `item 19012/19013
     count changed`), and the workflow proceeds to the Fire Shield step
     (no stall at "Create Healthstone (rank 5)");
   - the debug log shows `workflow spell ranks override: on` at start and
     `workflow spell ranks override: off` when the run finishes.
3. After the run: the spellbook checkbox is still OFF (restored), and stays OFF
   after `/reload` and after relogging.
4. Regression: run `/acp workflowtest 2` with the toggle ON — identical
   behavior.
5. Run workflow 1 (`/acp workflowtest 1`) — both healthstone pairs (steps 2-3
   and 8-9) create Master + Major stones.
6. `.\Tests\run-tests.ps1` already ran green before deploy.
