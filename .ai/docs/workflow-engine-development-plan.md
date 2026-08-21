# ArenaChillPrep — Workflow Engine: Architecture & Development Plan

> **Status:** Planning document — the spec basis for implementing the workflow engine feature (v0.2). Contract-first: update `.ai/` docs before code.
> **Target:** v0.2 — Warlock-only workflow platform for one-button arena preparation (buff, summon, create stones; existing Autotrade handles handoff).
> **Client:** WoW TBC Anniversary, Interface `20506`.
> **Research basis:** `.ai/docs/workflow-engine-research.md` (feasibility confirmed 2026-08-18).

---

## 1. Overview

The user presses a single bound key on arena entry. The addon runs a user-defined sequence of warlock actions: buff self/teammates, summon a pet, create healthstones. The existing Autotrade feature (`DeliveryController` → `TradeManager`) detects stones in bags and auto-trades them to the partner — **no duplication of trade logic**. The workflow pauses on movement/combat/interruption and resumes from the same step when the key is pressed again. Each new arena resets the workflow to step 1.

**Scope (v0.2):** Warlock only. Platform is class-agnostic by design (spell catalog drives everything); future classes just add catalog entries.

---

## 2. Design decisions (confirmed with user)

| Decision | Choice | Rationale |
|---|---|---|
| Trade handoff | **Coexistence** — workflow casts; existing Autotrade trades | Reuses proven `DeliveryController`/`TradeManager`; no trade logic duplication. The trade happens automatically in parallel — the workflow never waits on it. |
| Workflow editor UI | **List-based editor** — add steps from spell dropdown, set target per step, reorder | Meets the "user chooses abilities and sequence" goal; feasible on vanilla API. |
| Skip-if-buffed | **On by default, configurable** — global default setting + per-step override | Saves time/mana on re-runs; user can disable per-step or change the global default. |
| Max workflow slots | **5** — `BINDING_NAME_ACP_WORKFLOW1..5` | Enough for "Full prep", "Buffs only", "Stones only", "Pet only", "Custom". |
| Auto-start | **No** — user presses the bound key | Per user: "ты заходишь на арену, нажимаешь кнопку". |
| General-spirit settings | **"Enable workflow engine" checkbox → General tab** | Master toggle for the feature; belongs with the existing master switch. |

---

## 3. Architecture

### 3.1 New modules

| File | Responsibility |
|---|---|
| `Data/Workflows.lua` | Warlock spell catalog (grouped by category), target unit tokens, step schema/validator. Static data only — like `Data/Items.lua`. |
| `Classes/WorkflowEngine.lua` | Step state machine (`IDLE→RUNNING→PAUSED→DONE`), per-step gates, cast/summon/createItem execution, pause/resume, reset, target management. Pure logic — unit-testable under LuaJIT. |
| `Classes/WorkflowBindings.lua` | `BINDING_HEADER_ACP` + `BINDING_NAME_ACP_WORKFLOW1..5` globals, global handler functions, binding persistence sync. |
| `Classes/UI/WorkflowUI.lua` | "Workflows" subcategory content: workflow selector, list-based step editor, per-step controls, keybind display. |

### 3.2 Modified modules

| File | Change |
|---|---|
| `bootstrap.lua` | Add init calls: `WorkflowEngine:_init()` (after `TradeManager`, before `DeliveryController`), `WorkflowBindings:_init()` (after `DeliveryController`). |
| `ArenaChillPrep.toc` | Add new files in load order (Data → Classes → UI). |
| `Data/DefaultSettings.lua` | Add `workflows` settings subtree (master switch, `skipIfBuffedDefault`, `slotCount`, `definitions[1..5]`). |
| `Data/Constants.lua` | Add `WORKFLOW_MAX_SLOTS = 5`, `WORKFLOW_GCD_TICK = 0.1`, `WORKFLOW_CAST_TIMEOUT = 10`, target token list, step type constants. |
| `Data/Localization.lua` | Add workflow strings (enUS + ruRU): section headers, step types, target names, button labels, tooltips, status messages. |
| `Classes/OptionsUI.lua` | Register "Workflows" subcategory (after General, before Autotrade); add "Enable workflow engine" checkbox to General; extend `/acp status` with workflow state; add `/acp workflow <N>` command. |
| `Classes/UI/Widgets.lua` | Add `UI.Dropdown` (UIDropDownMenuTemplate), `UI.TextInput` (EditBox), `UI.ScrollFrame` — reusable widgets for the editor. |

### 3.3 Module dependency graph (additions in bold)

```
bootstrap
  → Events → Settings → ArenaPrep → Inventory → TradeManager
  → WorkflowEngine ──► Events, ArenaPrep, Inventory, Settings, Data.Workflows
  → DeliveryController (unchanged)
  → WorkflowBindings ──► WorkflowEngine, Settings
  → OptionsUI ──► UI/Widgets, UI/WorkflowUI, Settings
```

**Init order in `bootstrap:_init()`:**
Events → Settings → ArenaPrep → Inventory → TradeManager → **WorkflowEngine** → DeliveryController → **WorkflowBindings** → OptionsUI → `ArenaPrep:checkNow()`

### 3.4 WorkflowEngine state machine

```
                    ┌──────── key press (start) ────────┐
                    ▼                                    │
    ┌──────────┐  RUNNING  ──── all steps done ───►  ┌───┴───┐
    │   IDLE   │    │  ▲                               │  DONE  │
    └────▲─────┘    │  │ resume (key press)            └───┬───┘
         │          │  │                                    │
         │     ┌────┴──┴────┐  pause:                       │
         │     │   PAUSED   │  • IsPlayerMoving()           │
         └─────┤            │  • InCombatLockdown()    ACP_BUFF_LOST
      ACP_BUFF_│            │  • cast interrupted/failed    │
         LOST  └────────────┘  • gate failure               │
         │          ▲                                    │
         │          └──── ACP_BUFF_LOST ──────────────────┘
         └────────────── (any state) ──────────────────────┘
```

**Key invariants:**
- `stepIndex` is **in-memory only** — never persisted to `ArenaChillPrepDB`. Each arena starts from step 1.
- `currentSlot` — which workflow slot (1..5) is running. Only one workflow runs at a time.
- `ACP_BUFF_LOST` → `reset()` from any state → `IDLE`, `stepIndex = 1`, `currentSlot = nil`, restore target, cancel all engine timers.

### 3.5 Step schema

Each step in `workflows.definitions[N].steps` is a table:

```lua
-- Cast a spell on a target (buffs, party buffs).
{ type = "cast", spellID = 706, target = "player", skipIfBuffed = true }

-- Summon a pet (special-cased cast, target irrelevant).
{ type = "summon", spellID = 712 }

-- Cast a spell that creates an item; wait for the item in bags.
{ type = "createItem", spellID = 6201, itemID = 22105 }

-- Equip a conjured item (e.g. the /equip line of an m6 macro).
{ type = "equipItem", itemID = 22646, itemName = "Master Spellstone" }
```

> **Sequencing is fully automatic.** There is NO user-configured wait/timing step. The engine
> casts a step, then advances as soon as the cast actually finished (cast-time: the
> `UNIT_SPELLCAST_STOP`/`SUCCEEDED` event; instant: the GCD clears via `GetSpellCooldown`) —
> and immediately casts the next step. Spells go back-to-back with only the natural GCD between
> them. The player never thinks about timing.

**Fields:**
| Field | Type | Description |
|---|---|---|
| `type` | string | `"cast"` / `"summon"` / `"createItem"` / `"equipItem"` |
| `spellID` | number | Spell ID (catalog reference; resolved to name via `GetSpellInfo` at runtime). Not present for `equipItem` steps. |
| `target` | string | `"player"` / `"party1"` / `"party2"` / `"party3"` / `"party4"`. Only for `cast`; `summon`, `createItem` and `equipItem` always target self. |
| `skipIfBuffed` | boolean | "Skip if already done". If true and the step's goal is already met, skip it: `cast` → target already has the buff aura; `summon` → the pet is already out; `createItem` → the product is already in bags. |
| `itemID` | number | Expected item ID: what `createItem` waits for in bags / what `equipItem` equips. Required for `createItem` and `equipItem`. For stone spells the engine expands it to the rank's FULL variant set (`stoneRanks[spellID].itemIDs` — healthstone ranks 1-5 are historical ID pairs, e.g. Major = 19012/19013; the client conjures one variant per rank, verified rank 5 → 19013, so completion accepts EITHER variant of the step's rank but never another rank). |
| `itemName` | string | Optional localized-item-name fallback for `equipItem` (display; the runtime resolves via `GetItemInfo(itemID)`). |

> **Goal-met fast paths (2026-08-20):** `createItem` advances immediately when the item is
> ALREADY in bags (no key press needed), and `equipItem` advances immediately when the item is
> NOT in bags (already equipped). This makes the m6 macros' spam-duplicates (multiple identical
> Create Healthstone entries) need only one press and never stall on "already have one" rejections.
> `equipItem` completion is poll-driven (item leaves the bags), user-paced — no UNIT_SPELLCAST_*
> event fires for item use. The secure button is re-pointed at the item (`type="item"`,
> `item=<name>`); `requestKeyCast`/`clearKeyCast` always restore `type="spell"`.

### 3.6 Step execution protocol

> **PRESS MODEL REVISED 2026-08-22 (one press = start + cast):** each workflow
> slot key is pointed at a per-slot hidden `SecureActionButtonTemplate`
> (`ACPWorkflowButton<N>`) via **`SetOverrideBindingClick(owner, true, key, button)`**
> — a priority override (BetterFishing pattern, verified on 20506) that does NOT
> displace the player's command binding, so `GetBindingKey`/the Key Bindings UI /
> the Workflows key capture keep working (the transient `SetBindingClick`
> takeover broke key assignment entirely — live regression, replaced the same
> day). The button's **PreClick** runs `onPreClick(slot)` — starts/resumes the
> workflow and arms the current step (ItemRack pattern, verified on 20506) — and
> the SAME press's click then executes the armed action. So ONE press both
> starts the workflow AND casts the first step; every later press casts the
> next armed step. `applySlotBindings` = full resync (ClearOverrideBindings +
> re-apply from the real binding table) on PLAYER_LOGIN / UPDATE_BINDINGS /
> PLAYER_REGEN_ENABLED / late-binding retry; overrides are dropped while the
> Blizzard Key Bindings UI is shown (OnShow/OnHide hooks) and die with the
> session. The /acp bind hotkey keeps its own button (cast-only, no PreClick).
>
> **CHAT IS DEBUG-ONLY (2026-08-22):** every workflow message (started/resumed/
> paused/done/press prompts/reasons/cast-dropped) goes through `ACP:debugPrint`.
> `/acp status`/slash-command responses stay `ACP:print`.

```
executeCurrentStep():
  1. If stepIndex > #steps → DONE, restore target, fire ACP_WORKFLOW_DONE.
  2. Fire ACP_WORKFLOW_STEP(slot, stepIndex, step).
   3. If skipIfBuffed and isStepGoalMet(step) → advance (skip). Checked BEFORE the
      gates (§3.7) so a met goal is honored even when a reagent/combat gate would
      otherwise pause the step (no point conjuring a stone you already have, or
      summoning a pet that is already out).
   4. Run gates (§3.7). If any gate fails → PAUSED.
  5. Dispatch by type (equipItem BEFORE the spell-only knowsSpell/skipIfBuffed checks):
     • cast/summon → castSpell(step)
     • createItem  → createItem(step)
     • equipItem   → equipItem(step)

castSpell(step):
  1. setTarget(step.target) — save current target, TargetUnit if not "player".
  2. Resolve the localized spell name via GetSpellInfo(step.spellID).
  3. ALL steps (instant AND cast-time) route through the secure hotkey: point
     ACPWorkflowButton's "spell" attribute at the spell name and wait for a USER
     key press (waitingForKey state). 20506 blocks insecure casting
     (CastSpellByName/CastSpellByID) for cast-time spells even OOC
     (ForceTaint_Strong popup, verified 2026-08-18) AND for INSTANT spells
     outside safe zones (bare CastSpellByName("Fel Armor") in the open world
     pops "blocked from an action" — verified 2026-08-19). The key press is the
     hardware event the client requires (M6 pattern: SecureActionButtonTemplate
     + SetBindingClick). No hotkey bound → PAUSED (reason "noHotkey").
     UNIT_SPELLCAST_SENT/START transitions waitingForKey → accepted and branch:
       • CAST-TIME → waitingForCast + arm WORKFLOW_CAST_TIMEOUT.
       • INSTANT → waitForGCD(step): poll GetSpellCooldown(step.spellID) every
         WORKFLOW_GCD_TICK; advance when duration == 0 (STOP/SUCCEEDED may not
         fire for instant spells, so completion is GCD-driven, not event-driven).
       Buff steps additionally require the buff to be present before advancing
       (isAlreadyBuffed) — a silent block can't be told apart by the GCD alone.
  4. Completion (cast-time): UNIT_SPELLCAST_STOP/SUCCEEDED (signal-only — verify
     UnitCastingInfo("player") == nil) → advance; UNIT_SPELLCAST_INTERRUPTED/FAILED
     → PAUSED; WORKFLOW_CAST_TIMEOUT with no cast in progress → PAUSED.

createItem(step):
  0. Goal-met fast path: any variant of the step's expected item already in bags
     (expandExpectedItems over stoneRanks[castSpellID].itemIDs) → advance
     (no cast, no press).
  1. Shard gate (if step.needsShard): Inventory:countItem(6265) >= 1.
  2. Always cast-time on 20506 (Create Healthstone = 3 s, Create Soulstone = 3 s) →
     the secure hotkey path (same as castSpell's cast-time branch).
  3. After cast completes: a NEW stone of the expected variant set appeared in bags
     (delta vs the pre-cast baseline) → advance. If not yet → wait for
     ACP_ITEMS_CHANGED (or the 0.25 s poll) → advance; WORKFLOW_CAST_TIMEOUT →
     PAUSED. The delta/variant check is why a rank-5 step completes on the
     19013 variant the client actually conjures (not the stored 19012) and is
     NOT satisfied by a leftover different-rank stone (e.g. Master 22105).

equipItem(step):
  0. Goal-met fast path: countItem(step.itemID) == 0 → advance (already equipped).
  1. Re-point ACPWorkflowButton at the item: type="item", item=<localized name>
     (GetItemInfo(itemID) — the conjured item is in bags, so the info is cached;
     fallbacks: step.itemName, "item:<id>").
  2. Same unified-key press flow as castSpell (pressEquip message; noHotkey pause).
  3. Completion is POLL-DRIVEN: 0.25 s poll until countItem(itemID) == 0 (the stone
     left the bags = equipped). User-paced — no timeout while waiting for the press;
     no UNIT_SPELLCAST_* fires for item use. No spellID → the spell-only gates
     (knowsSpell/skipIfBuffed) are skipped.

advance():
  1. restoreTarget() (if we changed it).
  2. stepIndex = stepIndex + 1.
  3. executeCurrentStep() (recurse to next step).

> **`petStepDone` survives `advance()` (2026-08-22 fix):** a pet step armed and
> PRESSED during the previous player cast sets `petStepDone = true`; the flag must
> live through the cast-completion `advance()` so `executeCurrentStep` skips that
> pet step (the press already happened). `advance()` clears `pendingPetStep`
> (the arming is per-cast) but NOT `petStepDone`; the pet-step branch consumes it.
> `pause()`/`reset()`/`UNIT_SPELLCAST_INTERRUPTED` still clear both.
>
> **Verification — the press is not the cast (2026-08-22):** the client silently
> swallows a pet ability pressed early in the player's cast (Sacrifice at +2 s
> of a 6 s summon did nothing; +5 s fired — live-verified). `isPetAbilityApplied`
> checks the effect (buff on target by NAME, or the Voidwalker consumed while
> `waitingForCast` is true); an unverified press leaves the step armed and starts
> `armPetVerify` (0.1 s poll) — the user spams until the ability actually lands.
>
> **Arm gate — pet must exist (2026-08-22):** `onKeyPressed` arms the next pet
> step only when `UnitExists("pet")` is true. Arming during a SUMMON (pet not out
> yet) let a mid-cast key press execute the pet macro with no pet to route it to —
> the client treated it as a player cast, interrupted the summon and popped
> "blocked action" (live). Without the pet the step is not armed and the buttons
> are made INERT (clearKeyCast) for the duration of the cast; it runs standalone
> after the summon completes.
>
> **Pet macro conditionals (2026-08-22):** pet macros bake BOTH conditionals:
> `/cast [pet:<type>,@unit] <ability>` — `[@unit]` is the 20506-reliable target
> form and `[pet:<type>]` gates the cast on the right pet being out, so a press
> after the pet was dismissed mid-summon does NOTHING (no interruption, no
> "blocked action"). This is how Sacrifice is pressed during the Summon Felhunter
> cast (the Voidwalker is still out until the summon completes) — the requirement
> that ALL pet abilities work armed-during-cast.
```

**Advance is event-driven, not sleep-based.** The engine never blocks; it registers listeners/timers and yields. This matches the existing addon's event-driven architecture.

### 3.7 Per-step gates (all 20506-verified)

Checked before every cast, in order:

| Gate | API | Fail behavior |
|---|---|---|
| Addon enabled | `Settings:get("enabled")` and `Settings:get("workflows.enabled")` | PAUSED |
| Prep active | `ACP.ArenaPrep:isActive()` | PAUSED (or IDLE if buff lost) |
| Not in combat | `not InCombatLockdown()` | PAUSED (combat → protected API block) |
| Not dead/ghost | `not UnitIsDeadOrGhost("player")` | PAUSED |
| Not already casting | `not UnitCastingInfo("player")` | PAUSED |
| Not moving | `not IsPlayerMoving()` | PAUSED |
| Knows the spell | `IsPlayerSpell(name)` or `IsPlayerSpell(spellID)` | Skip step (can't cast — log) |
| Has reagents (if needsShard) | `Inventory:countItem(6265) >= 1` | PAUSED |
| Gate safety | `ArenaPrep:getRemainingTime() >= gateSafetySeconds` | PAUSED |

**`optional` vs. blocking:** a gate failure on a `skipIfBuffed` step skips; on other steps, it pauses (the user fixes the condition and presses the key to resume).

> **Knows-the-spell refinement (Phase 8, 2026-08-18):** the gate uses `IsPlayerSpell(name)` (matches any known rank — a trained rank replaces the base ID in the spellbook, so the rank-1 catalog ID alone is false at max level) with `IsPlayerSpell(spellID)` as fallback, both pcall-guarded. `IsUsableSpell(name)` was NOT used — it conflates "known" with "usable" (a known spell with a missing reagent returns false), which would wrongly skip a shard-gated step before the shard gate runs.

### 3.8 Skip-if-buffed

```lua
-- For "player": iterate auras by index, match by spell NAME
-- (handles multi-rank buffs — the cast rank's spellID differs from the catalog ID).
function WorkflowEngine:isAlreadyBuffed(step)
    local spellName = select(1, GetSpellInfo(step.spellID));
    local target = step.target or "player";
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(target, i, "HELPFUL");
        if (not aura) then break; end
        if (aura.name == spellName) then return true; end
    end
    return false;
end
```

**Why by name, not spellID:** multi-rank buffs (Demon Armor rank 1 = 706, rank 5 = 11735; Fel Armor rank 1 = 28176) have different spell IDs but the same aura name. The player casts the highest known rank; the aura's spellID is that rank's ID, not the catalog's. Name matching is rank-agnostic. `C_UnitAuras.GetAuraDataByIndex` is proven on 20506 (returns objects with `.name`/`.spellId`).

### 3.9 Target management

> **REVISED 2026-08-22 (live bug):** party-targeted casts landed on the PLAYER —
> both for player spells (Unending Breath, target=party1 buffed the warlock) and
> pet abilities (Fire Shield [target=party1] buffed the warlock). The unit token
> never resolved on the cast side. Final design (all 20506-verified):
>
> 1. **Secure `unit` attribute (the ONLY path for player spells):** `requestKeyCast` sets
>    `castButton:SetAttribute("unit", step.target or nil)` next to `type="spell"`/
>    `spell=<id>` — the M6 ActionBook pattern (`spell-<id>` + `unit-<id>` attribute
>    group on a SecureActionButtonTemplate). The client casts DIRECTLY on the unit,
>    regardless of the current target; a nil unit keeps default current-target
>    behavior (summons/conjures). `clearKeyCast`/`equipItem`/`petAbility` reset
>    `unit` to nil so a stale party unit never retargets a later step.
> 2. **`[@unit]` pet macro (pet abilities):** pet steps bake `/cast [@party1] Fire
>    Shield` — the modern conditional form (TBC Classic guides use [@arena1]/
>    [@mouseover] for pet abilities; the legacy `[target=party1]` form fell through
>    to the player in live tests). Helper: `petMacroText(step)`.
> 3. **Target-availability gate:** `checkGates` pauses with `reasonNoTarget` when a
>    non-player target's `UnitExists` is false (solo test, raid group, member left)
>    — the engine must never silently buff the wrong unit.
>
> **REMOVED — the `TargetUnit("party1")`/`TargetLastTarget()` swap:** the first
> party-targeted cast popped "blocked action" (TargetUnit called from insecure code
> on 20506), and the swap was fully redundant with the unit attribute. `setTarget`/
> `restoreTarget` and the `targetChanged` field are gone; the engine NEVER changes
> the player's current target.

- Only `cast` steps carry a `target`; it travels exclusively in the button's `unit` attribute.
- `summon` and `createItem` don't need targeting (self-cast).
- The engine never touches the player's current target (no swap, nothing to restore).

### 3.10 Movement and combat handling

- **Movement:** `IsPlayerMoving()` is always checked as a pre-step gate. Additionally, movement during a cast-time spell triggers `UNIT_SPELLCAST_INTERRUPTED` → PAUSED. No separate movement event listener needed; there is no movement toggle.
- **Combat:** `PLAYER_REGEN_DISABLED` → PAUSED (can't cast in combat). `PLAYER_REGEN_ENABLED` → do **not** auto-resume (user presses key to resume, per design).
- **Resume:** `start(slot)` while PAUSED with `currentSlot == slot` → RUNNING → re-run gates for the current step → execute.

### 3.11 Reset behavior

```lua
function WorkflowEngine:reset()
    ACP.Utils.Timers:cancel("WorkflowCastTimeout");
    ACP.Utils.Timers:cancel("WorkflowGCD");
    self:restoreTarget();
    self.state = "IDLE";
    self.currentSlot = nil;
    self.stepIndex = 1;
    self.expectedItemID = nil;
    ACP.Events:fire("ACP_WORKFLOW_RESET");
end
```

Called on `ACP_BUFF_LOST` (new arena → fresh start). Also called if the user starts a different workflow slot while one is running/paused.

### 3.12 Keybindings

```lua
-- File scope (loaded by the client at login):
BINDING_HEADER_ACP = "ArenaChillPrep";
BINDING_NAME_ACP_WORKFLOW1 = "Workflow 1";
BINDING_NAME_ACP_WORKFLOW2 = "Workflow 2";
BINDING_NAME_ACP_WORKFLOW3 = "Workflow 3";
BINDING_NAME_ACP_WORKFLOW4 = "Workflow 4";
BINDING_NAME_ACP_WORKFLOW5 = "Workflow 5";

-- Global handler functions (called by the client on key press — this IS a hardware event):
function _G.ACP_WORKFLOW1() ACP.WorkflowEngine:start(1); end
function _G.ACP_WORKFLOW2() ACP.WorkflowEngine:start(2); end
-- ... through 5
```

- The player binds keys via **ESC → Options → Key Bindings → ArenaChillPrep** (a `Bindings.xml` in the addon folder declares the fixed `ACP_WORKFLOW1..20` actions — the `BINDING_NAME_*` globals alone are only display strings on 20506). The Workflows toolbar also captures the selected slot's key directly. **Do NOT list `Bindings.xml` in the TOC**: on 20506 the client auto-loads the file by filename convention, and a TOC reference double-parses it with the UI XML parser → `Unrecognized XML: Binding` errors per entry (verified 2026-08-19). deploy.ps1 ships it explicitly.
- WoW persists bindings per character (`SaveBindings` is handled by the client when the player binds in the UI).
- The `WorkflowUI` tab displays and edits the current binding for the selected slot (via `GetBindingKey("ACP_WORKFLOW<N>")` + `SetBinding`/`SaveBindings`).
- **Unified key (verified-in-progress, 2026-08-19):** one key both starts/resumes AND casts. While the engine waits for a key press (`requestKeyCast`), `takeoverCastKey` re-points the slot's workflow key at the secure cast button via `SetBindingClick` (the action was `ACP_WORKFLOW<N>`), so pressing it casts the current step; the original binding is restored by `releaseCastKey` on press/pause/reset/DONE. `resolveCastKey` prefers the workflow key over the `/acp bind` hotkey (fallback). The handler context alone cannot cast on 20506 — casting requires a real hardware press on the secure button (Phase 8), so the takeover is required for a single-key experience.

### 3.13 Settings structure (additions to `DefaultSettings.lua`)

```lua
workflows = {
    enabled = true,               -- master workflow switch (shown on General tab)
    skipIfBuffedDefault = true,   -- default for new cast/summon/createItem steps' skipIfBuffed
    slotCount = 5,                -- UI starts with five; + adds up to binding capacity
    definitions = {
        [1] = {
            enabled = true,
            name = "Full prep 2s",
            steps = {
                { type = "cast",       spellID = 28176, target = "player", skipIfBuffed = true },  -- Fel Armor (rank 1, verified in-game)
                { type = "summon",     spellID = 712 },                                         -- Succubus
                { type = "createItem", spellID = 6201, itemID = 22105 },                      -- Create Healthstone (Master)
            },
        },
        [2] = { enabled = false, name = "Prep with a Priest", steps = {} },
        [3] = { enabled = false, name = "Stones only", steps = {} },
        [4] = { enabled = false, name = "Pet only",    steps = {} },
        [5] = { enabled = false, name = "Custom",      steps = {} },
    },
},
```

> **Note (verified Phase 7, 2026-08-18):** spell IDs in the defaults were verified in-game and against TBC spell lists of working addons (GladiatorlosSA2 `spelllist_TBC.lua`, OmniBar_TBC, Details `spells.lua`, LibClassicDurations). Fel Armor = `28176` (rank 1; the former placeholder `28276` is Lightwell Renew on this client), Create Healthstone = `6201`, Summon Succubus = `712`. Catalog IDs are rank-1; `CastSpellByName` at runtime casts the highest-known rank. Remaining unverified: the exact TBC max-rank IDs of Fel Armor and Create Soulstone (rank pairing with item 22103) — see `Data/Workflows.lua` TODO comments.

Accessed via `Settings:get("workflows.definitions.1.steps.1.type")` — the existing dot-path system handles numeric segments (via `normalizeSegment`). For the UI editor, the whole `workflows` table is fetched/manipulated/persisted as a unit.

### 3.14 UI design — "Workflows" subcategory

**Tab order:** General → **Workflows** → Autotrade.

**General tab additions:**
- "Enable workflow engine" checkbox → `workflows.enabled` (with tooltip).

**Workflows tab layout (660×400):**

```
┌─────────────────────────────────────────────────────────────┐
│ Workflows                                                    │
│                                                              │
│ ┌─ Settings ─────────────────────────────────────────────┐  │
│ │ ☑ Pause workflow when moving                           │  │
│ │ ☑ Skip completed steps by default                     │  │
│ └────────────────────────────────────────────────────────┘  │
│                                                              │
│ ┌─ Workflow ─────────────────────────────────────────────┐  │
│ │ Workflow: [Dropdown: 1-Full prep]  ☑ Enabled           │  │
│ │ Name: [EditBox: Full prep]                              │  │
│ └────────────────────────────────────────────────────────┘  │
│                                                              │
│ ┌─ Steps ────────────────────────────────────────────────┐  │
│ │  1. Fel Armor          Target: [Self]    ☑ Skip        │  │
│ │     [▲] [▼] [✕]                                         │  │
│ │  2. Summon Succubus    (no target)                      │  │
│ │     [▲] [▼] [✕]                                         │  │
│ │  3. Create Healthstone (no target)                      │  │
│ │     [▲] [▼] [✕]                                         │  │
│ │  ──────────────────────────────────────────────────     │  │
│ │  Add step: [Dropdown: spell list]                       │  │
│ └────────────────────────────────────────────────────────┘  │
│                                                              │
│ Key bindings: ESC → Key Bindings → ArenaChillPrep            │
│ Slot 1: [Key here or "Not bound"]   Slot 2: [...]            │
└─────────────────────────────────────────────────────────────┘
```

**New widgets in `Classes/UI/Widgets.lua`:**

| Widget | Template | Purpose |
|---|---|---|
| `UI.Dropdown(parent, name, text, x, y, width, items, getter, setter, tooltipText)` | `UIDropDownMenuTemplate` | Spell selection, target selection, workflow selector. `items` = array of `{value, label}`. |
| `UI.TextInput(parent, name, x, y, w, h, getter, setter, tooltipText)` | `EditBox` + backdrop | Workflow name editing. |
| `UI.ScrollFrame(parent, x, y, w, h)` | `ScrollFrameTemplate` | Scrollable step list (if > 4 steps). |

**`WorkflowUI:build(content, w, h)`** assembles the layout. Step rows are created dynamically from the selected workflow's `steps` array. Adding/removing/reordering steps mutates the settings table and re-renders the list.

**Keybind display:** `GetBindingKey("ACP_WORKFLOW1")` → show the bound key or "Not bound". Read-only (the user binds via the Key Bindings UI, not in our panel).

### 3.15 Warlock spell catalog (`Data/Workflows.lua`)

```lua
ACP.Data.Workflows = {
    -- Grouped by category. Each entry: { spellID, name, category, isCastTime,
    --   canTargetParty, needsShard, buffSpellID (for skip check), itemID (for createItem) }
    spells = {
        buffs = {
            -- Self-only armors (canTargetParty = false)
            { spellID = 28176, name = "Fel Armor",     isCastTime = false, canTargetParty = false, buffSpellID = 28176 },
            { spellID = 706,   name = "Demon Armor",   isCastTime = false, canTargetParty = false, buffSpellID = 706 },
            -- Party-buffable
            { spellID = 5697,  name = "Unending Breath", isCastTime = false, canTargetParty = true,  buffSpellID = 5697 },
            { spellID = 6307,  name = "Soul Link",       isCastTime = false, canTargetParty = false, buffSpellID = 6307 },
        },
        summons = {
            { spellID = 688,   name = "Summon Imp",        isCastTime = true, needsShard = false },
            { spellID = 697,   name = "Summon Voidwalker", isCastTime = true, needsShard = true },
            { spellID = 712,   name = "Summon Succubus",   isCastTime = true, needsShard = true },
            { spellID = 691,   name = "Summon Felhunter",  isCastTime = true, needsShard = true },
            { spellID = 30146, name = "Summon Felguard",   isCastTime = true, needsShard = true },
        },
        createItem = {
            { spellID = 6201, name = "Create Healthstone", isCastTime = true, needsShard = true, itemID = 22105 },
            { spellID = 693,    name = "Create Soulstone",    isCastTime = true, needsShard = true, itemID = 22103 },
        },
        utility = {
            { spellID = 29893, name = "Ritual of Souls",      isCastTime = true, needsShard = true },
            { spellID = 698,   name = "Ritual of Summoning",  isCastTime = true, needsShard = true },
        },
    },
    targets = { "player", "party1", "party2", "party3", "party4" },
};
```

> **Spell IDs verified in Phase 7 (2026-08-18)** — in-game `GetSpellInfo` + TBC spell lists of working addons. Corrections vs. the original placeholders: Fel Armor `28276`→`28176` (28276 = Lightwell Renew on this client), Create Healthstone `116761`→`6201` (TBC ranks are `6201…27230`), Ritual of Souls `58887`→`29893` (58887 is WotLK rank 2). Remaining unverified: the TBC max-rank ID of Fel Armor and the Create Soulstone rank pairing with item 22103 (marked `-- TODO` in `Data/Workflows.lua`). The catalog is extensible: adding a class = adding a `spells` subtable + a `classSpells` mapping (mirrors `Data.Items.classItems`).

### 3.16 Integration with existing modules

| Module | Interaction |
|---|---|
| `ArenaPrep` | Engine listens to `ACP_BUFF_LOST` → `reset()`. Uses `isActive()`, `getRemainingTime()` (gate safety) in pre-step gates. |
| `Inventory` | Engine uses `getCount(SOUL_SHARD)` for shard gating; `getCount(itemID)` for createItem completion. Listens to `ACP_ITEMS_CHANGED` for createItem step advancement. |
| `DeliveryController` | **No changes.** Coexistence: the workflow creates stones → `DeliveryController` detects them via `ACP_ITEMS_CHANGED` → auto-trades (existing behavior). The two systems run in parallel during prep. |
| `TradeManager` | **No changes.** Driven by `DeliveryController` as before. |
| `Events` | Engine fires `ACP_WORKFLOW_*` internal events; listens to `UNIT_SPELLCAST_*`, `ACP_BUFF_LOST`, `ACP_ITEMS_CHANGED`, `PLAYER_REGEN_DISABLED/ENABLED`. |
| `Settings` | Engine reads `workflows.*` via dot-path. UI manipulates the `workflows.definitions` table directly. |
| `Utils/Timers` | Engine uses named timers (`WorkflowCastTimeout`, `WorkflowGCD`). Honors the unreliable-`Cancel()` gotcha — callbacks check `state == "RUNNING"` before acting. |

### 3.17 Unit tests (after user permission)

| Suite | Coverage |
|---|---|
| `Tests/Data/test_workflows.lua` | Catalog completeness, step schema validation, default workflow structure. |
| `Tests/Classes/test_workflowengine.lua` | State machine transitions, per-step gates, skip-if-buffed, pause/resume, reset on buff lost, createItem completion, target save/restore. |

**Stubs to add to `Tests/stubs/wow_stubs.lua`:** `CastSpellByID`, `CastSpellByName`, `GetSpellInfo`, `GetSpellCooldown`, `IsPlayerSpell`, `IsUsableSpell`, `UnitCastingInfo`, `IsPlayerMoving`, `InCombatLockdown`, `TargetUnit`, `TargetLastTarget`, `ClearTarget`, `UnitIsDeadOrGhost`. All mutable via `_G.__stub`.

Test pattern: same as `DeliveryController` tests — drive the real engine through `_G.__stub` + module state; swap `ACP.Utils.Timers` for `SyncTimers`. Steps are data (tables) — easy to construct test workflows.

---

## 4. Development phases

> Rule: every phase ends with a working build that loads in game (`/reload`) and can be verified. Follow the `phase-workflow` skill: contract-first, todo list, implement, verify, document.

### Phase 7 — Data layer (catalog, schema, settings)

**Goal:** the spell catalog, step schema, settings structure, constants, and localization strings exist; the addon loads without errors.

**Tasks:**
1. `Data/Workflows.lua`: warlock spell catalog (§3.15), target tokens, step schema validator (`WorkflowEngine` calls `validateStep(step)` → returns bool + error string).
2. `Data/DefaultSettings.lua`: add `workflows` subtree (§3.13) to the defaults.
3. `Data/Constants.lua`: add `WORKFLOW_MAX_SLOTS = 5`, `WORKFLOW_GCD_TICK = 0.1`, `WORKFLOW_CAST_TIMEOUT = 10`, `SOUL_SHARD_ITEM_ID = 6265`, `WORKFLOW_TARGETS = {"player","party1","party2","party3","party4"}`, step type constants.
4. `Data/Localization.lua`: add all workflow strings (enUS + ruRU) — section titles, step type labels, target names, button labels, tooltips, status/log messages.
5. `ArenaChillPrep.toc`: add `Data/Workflows.lua` after `Data/Localization.lua`.
6. Verify spell IDs via `GetSpellInfo` in-game (or via the `addon-research` skill if a working addon lists them). **Mark unverified IDs with a TODO comment.**

**Definition of Done:**
- `/reload` — no Lua errors.
- `ACP.Data.Workflows.spells` is populated and accessible.
- `Settings:get("workflows.definitions.1.steps.1.type")` returns `"cast"`.
- `tools/vararg-check.ps1` passes.

---

### Phase 8 — Engine core (state machine + casting)

**Goal:** the workflow engine runs a sequence of casts from the command line (`/acp workflow 1`), with pause/resume/reset.

**Tasks:**
1. `Classes/WorkflowEngine.lua`:
   - State machine: `IDLE → RUNNING → PAUSED → DONE`, `reset()` (§3.11).
   - `start(slot)` — start or resume (§3.4).
   - `executeCurrentStep()` — dispatch by type (§3.6).
   - `castSpell(step)` — target management (§3.9), `CastSpellByName`/`CastSpellByID`, wait for completion.
   - `waitForCastCompletion(step)` — `UNIT_SPELLCAST_STOP`/`SUCCEEDED` (signal only, verify `UnitCastingInfo == nil`), `INTERRUPTED`/`FAILED` → PAUSED, safety timeout.
   - `waitForGCD(step)` — poll `GetSpellCooldown` until `duration == 0`.
   - `createItem(step)` — cast + wait for `ACP_ITEMS_CHANGED` with `itemID`.
   - Per-step gates (§3.7).
   - `isAlreadyBuffed(step)` — iterate auras by name (§3.8).
   - Event listeners: `ACP_BUFF_LOST` → reset, `UNIT_SPELLCAST_*` (filtered "player"), `PLAYER_REGEN_DISABLED` → pause, `ACP_ITEMS_CHANGED` → createItem completion.
   - Internal events: `ACP_WORKFLOW_STARTED/STEP/PAUSED/RESUMED/DONE/RESET`.
   - All timers via `ACP.Utils.Timers` (named, Cancel-unreliable gotcha honored — callbacks check `state == "RUNNING"`).
2. `bootstrap.lua`: add `self.WorkflowEngine:_init()` after `self.TradeManager:_init()`, before `self.DeliveryController:_init()`.
3. `ArenaChillPrep.toc`: add `Classes/WorkflowEngine.lua` after `Classes/TradeManager.lua`.
4. `Classes/OptionsUI.lua`:
   - Extend `handleCommand`: add `/acp workflow <N>` — calls `ACP.WorkflowEngine:start(N)` (for testing without keybinds).
   - Extend `/acp status`: show `workflow: state=X | slot=N | step=N/total`.

**Definition of Done:**
- `/reload` — no Lua errors.
- `/acp workflow 1` in an arena (prep active) → engine starts, casts Fel Armor, summons pet, creates healthstone — each step casts automatically back-to-back as the previous one completes.
- Move during a cast-time spell → `UNIT_SPELLCAST_INTERRUPTED` re-arms the SAME step (re-prompts "Press F9 to cast …") — pressing F9 again re-casts it. The hotkey is the resume mechanism; no `/acp workflow 1` needed. A hard pause (`/acp workflow 1` to resume) happens on combat, buff-loss, reagent exhaustion, or a `UNIT_SPELLCAST_FAILED`.
- `ACP_BUFF_LOST` (gates open) → engine resets to IDLE.
- `/acp status` shows the workflow state.
- `tools/vararg-check.ps1` + `tools/syntax-check.ps1` pass.

> **Phase 8 status (2026-08-19):** engine implemented per the tasks above, including the
> **stateful one-hotkey design for ALL steps** (see RESOLVED below): hidden secure button
> `ACPWorkflowButton` + `/acp bind <key>` (`SetBindingClick`) + `waitingForKey` state;
> every step prints "Press F9 to cast X" and waits for one key press. Out-of-game
> verification complete: 10-scenario engine smoke test green (state machine, buffed-skip,
> shard gate, key-wait for every step via simulated presses, instant GCD wait, item wait,
> pause/resume, slot switch, buff-lost reset, no-press-waits-indefinitely); full unit
> suite green (170 tests, 96.89% coverage); `vararg-check` 18 files, `syntax-check`
> 46 files; deployed to the client (20 files). **In-game verified (2026-08-19, open world,**
> **`/acp workflowtest 1`):** `/acp bind F9` bound; F9 summoned the Succubus and then
> created a Master Healthstone; workflow reached DONE; `/acp status` shows
> `workflow: DONE | slot=1 | step=4/3 | key=F9` (step=4/3 is the documented post-DONE
> increment — see the In-combat table row "Workflow reaches the last step"). Also verified:
> a blocked insecure instant cast now PAUSES with a clear diagnostic instead of silently
> advancing. **Remaining DoD: full in-arena prep run** (`/acp workflow 1` with the real
> buff; pause/resume on move; `ACP_BUFF_LOST` → IDLE).
>
> **RESOLVED — cast-time autonomous casting is IMPOSSIBLE on 20506 (2026-08-18).** The
> block is a client-wide hardware-event restriction, NOT arena-specific and NOT caused by
> `CastSpellByName`. Live-verified in a safe zone, out of combat (`inCombat=false
> affectingCombat=false`, 22 Soul Shards held): `CastSpellByName("Fel Armor")` (instant)
> cast fine (GCD registered), but ANY cast-time spell — Summon Succubus (6 s, via name AND
> id), Inferno, Create Healthstone (3 s), Shadow Bolt — is dropped with the `ForceTaint_Strong`
> "blocked from an action" popup. `SecureActionButtonTemplate:Click()` → silently dropped
> (same restriction as `AcceptTrade()`); `RunBinding()` on a bound spell AND on a bound macro
> → both blocked. No working 20506 addon casts a cast-time spell via insecure code (absence
> of evidence = the client does not allow it). **Conclusion: autonomous cast-time casting is
> impossible on this client; only a real hardware event (a key press) can cast them.**
> **Design pivot (user-approved, option B):** cast-time steps route through a hidden
> `SecureActionButtonTemplate` ("ACPWorkflowButton", type=spell) bound to ONE hotkey via
> `SetBindingClick` (`/acp bind <key>`, setting `workflows.hotkey`). The user's key press is
> the hardware event (M6 pattern). Instant steps stay fully autonomous. The engine keeps all
> Phase 8 logic: skips already-buffed steps, skips no-shard steps, waits out the GCD, pauses
> on movement, stops near the gates, and prints what the next press will cast. The 255-char
> macro limit is moot (no macro text is generated). The user's own M6 `/castsequence` macro
> was the inspiration — this design is strictly better because it is stateful at runtime.
> Support tooling added for safe-zone diagnosis: `/acp workflowtest` (debug arena bypass),
> `/acp dumplog` + an in-memory ring buffer for chat output (the block popup makes chat
> un-copyable), and richer "workflow cast dropped" diagnostics.

---

### Phase 9 — Keybindings

**Goal:** each workflow slot is bindable to a key via the Key Bindings UI; pressing the key starts/resumes the workflow.

**Tasks:**
1. `Classes/WorkflowBindings.lua`:
   - Define `BINDING_HEADER_ACP` and `BINDING_NAME_ACP_WORKFLOW1..5` globals (file scope).
   - Define global handler functions `_G.ACP_WORKFLOW1..5` → `ACP.WorkflowEngine:start(N)`.
   - `_init()`: no complex setup needed — the globals are loaded at file scope; the client picks them up. Log a debug message on init.
2. `bootstrap.lua`: add `self.WorkflowBindings:_init()` after `self.DeliveryController:_init()`.
3. `ArenaChillPrep.toc`: add `Classes/WorkflowBindings.lua` after `Classes/WorkflowEngine.lua`.

**Definition of Done:**
- ESC → Key Bindings → ArenaChillPrep section shows "Workflow 1".."Workflow 5".
- Bind a key to Workflow 1 → press it in an arena → workflow starts.
- Press again while paused → resumes.
- Binding persists across `/reload` and game restart.

> **Phase 9 status (2026-08-19):** implemented. `Classes/WorkflowBindings.lua`
> registers `BINDING_HEADER_ACP`, `BINDING_NAME_ACP_WORKFLOW1..5` (localized via
> `L.workflow.bindingWorkflow`), and global handlers `_G.ACP_WORKFLOW1..5` →
> `ACP.WorkflowEngine:start(N)`. Wired into `bootstrap.lua` (`WorkflowBindings:_init()`
> after `DeliveryController:_init()`, before `OptionsUI:_init()`) and the TOC (after
> `WorkflowEngine.lua`); Tests loader + bootstrap init-order assertion updated
> accordingly. In-game: the bindings now appear under their own **ArenaChillPrep**
> category (Bindings.xml with `category="BINDING_HEADER_ACP"`
> — `category="ADDONS"` buried them). **Bindings.xml is auto-loaded by the client
> by filename convention and MUST NOT be listed in the TOC** (a TOC reference made
> the client double-parse it → 15 `Unrecognized XML: Binding` error popups on
> /reload; verified 2026-08-19 — no working addon references it in its TOC).
> Unified-key cast flow added to
> `WorkflowEngine` (`resolveCastKey`/`takeoverCastKey`/`releaseCastKey`, §3.12):
> pressing the workflow key casts each step (temporary SetBindingClick takeover,
> released on press/pause/reset/DONE), so `/acp workflowtest` follows the same
> key bindings as the future UI. The takeover is NOT SaveBindings'd (persisting
> it clobbered the workflow key on /reload — verified F5 loss 2026-08-19) and is
> restored on `PLAYER_LOGOUT`; `/acp workflowtest <N>` now tests ANY slot
> (ignores per-slot `enabled` under the debug bypass), and empty workflows print
> `emptyWorkflow` instead of "started … complete". **Fatal load crash fixed
> (2026-08-19):** `GetCurrentBindingSet()` returns `0` before bindings load and
> `SaveBindings(0)` threw `Usage: SaveBindings(1||2)` in `applyBinding`, aborting
> `_init` (addon dead, `/acp` unregistered). All `SaveBindings` call sites now
> guard via a `bindingSet()` helper (explicit 1|2, 0 is truthy so a truthiness
> guard was insufficient). **`ADDON_UNLOADING` is NOT registerable on 20506**
> (`RegisterEvent` throws "Attempt to register unknown event" — crashed `_init`);
> the logout restore now uses `PLAYER_LOGOUT` and `/reload`-safety relies on the
> takeover being in-memory only (reload re-reads bindings from disk). **Bindings.xml
> TOC-reference root-caused and fixed (2026-08-19):** the client auto-loads a file
> named `Bindings.xml` by filename convention, so listing it in the TOC made the
> client double-parse it with the UI XML parser → 15 `Unrecognized XML: Binding`
> error popups on /reload. Removed from the TOC (deploy.ps1 ships it explicitly).
> All three gotchas recorded in the wow-api-20506 skill. Checks green:
> 170 tests @ 97.04%, vararg 19 files, syntax 47 files. **In-game VERIFIED
> (2026-08-19):** with the TOC fix deployed, `/reload` produces NO Bindings.xml
> errors and the workflow key still starts/casts the workflow; phase DoD met
> (binding persists across /reload, key starts + casts each step). Phase 9
> COMPLETE.

---

### Phase 10 — Workflow UI

> **STATUS: COMPLETE (2026-08-20).** All tasks below implemented and verified
> out-of-game: new widgets (Dropdown/TextInput/ScrollFrame), `WorkflowUI.lua`
> (layout, step editor, keybind display), OptionsUI wiring (Workflows tab after
> General, engine checkbox on General, `refresh()` + `setWorkflowsEnabled`),
> TOC + Localization strings. Tests 170/170 @ 96.99%, `vararg-check` 20 files OK,
> syntax-check OK, deployed 23 files to the client.
>
> **P0 UI refactor (2026-08-20, per review):** tab rebuilt around the
> "pick slot → assemble sequence → fire by key" scenario — vertical-cursor
> layout (no magic offsets; sections return their own heights): status line on
> top (engine + slot/key/steps; when engine OFF shows explanation + "Enable
> workflow engine" CTA, no gray-out), compact toolbar (selector + per-slot
> enable + activation key of the SELECTED slot + name + Key Bindings hint),
> steps list as the dominant area (~60% of height, ~6 rows visible vs 3 before,
> subtle gray-gold border instead of the loud tooltip frame), bottom options
> row. Step rows: normal-gray spell names (gold reserved for the header/state),
> 30px `Up`/`Dn`/`X` buttons, Up/Down disabled at list ends, Remove turns red on hover,
> dim "Self"/"—" instead of "(no target)". Tests 170/170 @ 96.93%, deployed.
> Pending in-game DoD (reload → three tabs, visual layout, persist, status bar,
> CTA button).

> **Workflow model follow-up (2026-08-20):** workflow settings are now routed to
> `ArenaChillPrepCharDB.workflows`; five slots are created by default and the
> UI can add slots through the fixed 20-slot binding capacity. `WorkflowBindings`
> and `Bindings.xml` cover all 20 slots. Movement pause is unconditional and
> the old `pauseOnMove` setting/control is removed. `WorkflowSpellbook` scans
> learned active player spells on 20506, groups ranks by spell name, and the
> editor always uses the highest learned rank per step (rank is NOT
> user-selectable — the old per-step rank dropdown was removed 2026-08-20
> because it didn't work; steps store the max-rank exact spellID). The selected
> exact spellID is passed to the secure action button. Direct keybind
> capture is available in the Workflows toolbar. The Add Step list is built
> from the ACTIVE character's spellbook — the Warlock static fallback is
> class-gated and the scan re-runs on PLAYER_LOGIN + SPELLS_CHANGED, so a
> non-Warlock (e.g. a Mage) never sees Warlock spells. Pet abilities (Fire
> Shield for the Imp, Sacrifice for the Voidwalker) are added as `pet` steps
> (cast by the pet via a secure macro button) and are exempt from the player
> casting/movement gates; a pet step following a cast-time step is armed DURING
> that cast so the pet ability can be pressed before the cast finishes
> (the press sets `petStepDone`, which survives `advance()` so the step is
> skipped, not re-armed — fixed 2026-08-22).
> Stone-creating spells are listed per rank with the stone name so any rank can
> be picked. Out-of-game tests/syntax/vararg verified; pending in-game
> verification on multiple characters.

**Goal:** the user can create and edit workflows from the settings panel; the "Enable workflow engine" checkbox appears on General.

**Tasks:**
1. `Classes/UI/Widgets.lua`: add `UI.Dropdown`, `UI.TextInput`, `UI.ScrollFrame` (§3.14).
2. `Classes/UI/WorkflowUI.lua`:
   - `build(content, w, h)`: global settings box (pauseOnMove, skipIfBuffedDefault), workflow selector (dropdown 1-5 + enable checkbox + name input), step editor (scrollable list with per-step controls), keybind display.
   - `refresh()`: re-sync all controls from Settings.
   - Step row: spell name label, target dropdown (for `cast`/`pet` steps with `canTargetParty`), skip-if-done checkbox (for `cast` buff / `summon` / `createItem` steps), remove button, move up/down buttons.
   - Add step: dropdown of available spells from `ACP.Data.Workflows.spells` (grouped by category). Selecting a spell adds a step with defaults (target = "player" for castable steps; `skipIfBuffed = workflows.skipIfBuffedDefault` for `cast` (buff) / `summon` / `createItem` steps).
   - All changes write to `Settings` immediately and persist (`ArenaChillPrepDB = ACP.Settings.Data`).
3. `Classes/OptionsUI.lua`:
   - Add "Workflows" subcategory to `self.Subcategories` (after General, before Autotrade).
   - Add "Enable workflow engine" checkbox to `buildGeneral` → `workflows.enabled`.
   - Extend `refresh()` to sync workflow controls.
   - Extend `setAutotradeEnabled` (or add `setWorkflowsEnabled`) to gray out workflow controls when `workflows.enabled = false`.
4. `ArenaChillPrep.toc`: add `Classes/UI/WorkflowUI.lua` after `Classes/UI/Widgets.lua`.

**Definition of Done:**
- `/reload` → `/acp` → three tabs: General, Workflows, Autotrade.
- General: "Enable workflow engine" checkbox (toggles `workflows.enabled`).
- Workflows: select a workflow slot, add/remove/reorder steps, set targets, toggle skip-if-buffed.
- Changes persist across `/reload`.
- Keybind display shows the bound key or "Not bound" per slot.
- Master switch off → workflow controls grayed.
- `tools/vararg-check.ps1` passes.

---

### Phase 11 — Integration, edge cases, in-game verification

**Goal:** the workflow engine and autotrade coexist correctly; edge cases are handled; the feature is verified in arenas.

**Tasks:**
1. **Integration review:** confirm the workflow creates stones → `DeliveryController` auto-trades them (no conflict, no double-trade). The trade runs in parallel — the workflow continues to the next step immediately after the stone is created.
2. **Edge case handling (§5):** verify each edge case is handled in code.
3. **Documentation update (contract-first):**
   - `.ai/CONTEXT.md`: add workflow feature description, settings reference, new gotchas.
   - `.ai/ARCHITECTURE.md`: add WorkflowEngine module (§2.10), update module graph, add workflow state machine, update data flow, add edge cases.
   - `.ai/memories/repo/arena-chill-prep.md`: append `Phase 7-11 DONE` + new verified facts.
   - `.ai/skills/wow-api-20506/SKILL.md`: add any new gotchas discovered during implementation.
4. **In-game verification:** run the §6 checklist.

**Definition of Done:**
- Full cycle in a 2v2 arena: bind key → press → Fel Armor cast → Succubus summoned → Healthstone created → autotrade opens → partner receives stone → workflow DONE.
- Move during summon → PAUSED → stop → press key → resumes from summon step.
- New arena → workflow starts from step 1.
- `/console scriptErrors 1` — no Lua errors across 5+ arenas.
- `.ai/` docs updated.

---

### Phase 12 — Unit tests (after user permission)

**Tasks:**
1. Extend `Tests/stubs/wow_stubs.lua` with casting stubs (§3.17).
2. `Tests/Data/test_workflows.lua`: catalog, schema, defaults.
3. `Tests/Classes/test_workflowengine.lua`: state machine, gates, skip-if-buffed, pause/resume, reset, createItem, target management.
4. Run `.\Tests\run-tests.ps1` — exit 0, coverage ≥ 90%.

---

## 5. Edge cases

| Situation | Behavior |
|---|---|
| Player presses key outside an arena | `isActive()` = false → engine stays IDLE, log "not in arena prep". |
| Player presses key in combat | `InCombatLockdown()` = true → engine stays IDLE/PAUSED, log "in combat". |
| Player moves during a cast-time spell | `UNIT_SPELLCAST_INTERRUPTED` → PAUSED. Resume on key press. |
| Player moves before an instant cast | `IsPlayerMoving()` gate → PAUSED. Resume on key press (after stopping). |
| Player has no Soul Shard for summon/createItem | Shard gate → PAUSED, log "no soul shard". Resume after acquiring one (loot/bag update). |
| Player doesn't know the spell | `IsPlayerSpell`/`IsUsableSpell` fails → skip step (log "spell not known"), continue to next. |
| Step goal already met and skipIfBuffed = true | `isStepGoalMet` passes (buff aura present / pet already out / item already in bags) → skip step, advance, before the reagent gate. |
| Cast fails (out of range, LOS, etc.) | `UNIT_SPELLCAST_FAILED` → PAUSED. Resume on key press. |
| Workflow reaches the last step | DONE. `stepIndex` stays at last+1. Key press does nothing (must wait for new arena). |
| `ACP_BUFF_LOST` mid-workflow (gates open) | `reset()` → IDLE. No further casts. New arena → starts from step 1. |
| `/reload` in an arena mid-workflow | Engine re-inits to IDLE (stepIndex is in-memory only). User presses key to restart from step 1. |
| User starts workflow 2 while workflow 1 is PAUSED | `start(2)` with `currentSlot != 2` → `reset()` then start workflow 2 from step 1. |
| Autotrade opens a trade window mid-workflow | No conflict — the workflow keeps casting; `TradeManager` and `WorkflowEngine` are independent. |
| Create Healthstone spell completes but item not yet in bags | Wait for `ACP_ITEMS_CHANGED` with the expected `itemID` (timeout: `WORKFLOW_CAST_TIMEOUT`). |
| Gate safety: < 15s before gates open | Gate fails → PAUSED, log "gate safety". Effectively stops the workflow. |
| Player is dead | `UnitIsDeadOrGhost` gate → PAUSED. Resume after revive if prep still active. |
| Empty workflow (no steps) | `executeCurrentStep` finds no step → immediately DONE. |

---

## 6. In-game verification checklist

Run with `/console scriptErrors 1` and `/acp debug` on.

1. **Spell ID verification:** `/dump GetSpellInfo(28176)` — confirm "Fel Armor" (verified 2026-08-18; the plan's former placeholder 28276 is Lightwell Renew on this client). Repeat for each catalog entry. Fix wrong IDs in `Data/Workflows.lua`.
2. **`UNIT_SPELLCAST_SUCCEEDED` args:** cast a self-buff, log `...` → resolve the spellID position (arg 2 vs arg 3). Confirm the engine's signal-only approach works.
3. **`UNIT_SPELLCAST_STOP` vs `SUCCEEDED` for instant spells:** cast Fel Armor (instant), record which events fire and order. Confirm `waitForGCD` handles it.
4. **`TargetUnit` + cast + `TargetLastTarget`:** during prep, target party1, cast Unending Breath, restore target — confirm the buff lands on the right member and the target is restored.
5. **`CastSpellByName` highest-rank:** confirm `CastSpellByName("Create Healthstone")` casts the highest known rank (not rank 1).
6. **`GetSpellCooldown` GCD shape:** after an instant cast, confirm `duration ~= 0` and counts down to 0.
7. **Keybinding dispatch:** bind M to Workflow 1, press M in an arena → workflow starts. Press again while PAUSED → resumes.
8. **`CastSpellByID(6201)` with/without a Soul Shard** → confirm the failure behavior so the engine logs it instead of stalling.
9. **Pet summon during prep:** `CastSpellByID(712)` while prep is active — confirm it works.
10. **Combat cut-off:** confirm that once `InCombatLockdown()` is true, no step fires (expected).
11. **Full cycle:** 2v2 arena → bind key → press → Fel Armor → Succubus → Healthstone → autotrade opens → partner gets stone → workflow DONE.
12. **Pause/resume:** move during Succubus summon → PAUSED → stop → press key → resumes from summon.
13. **New arena reset:** next arena → press key → starts from step 1 (not where it left off).
14. **UI editor:** add/remove/reorder steps, set targets, toggle skip-if-buffed → changes persist across `/reload`.
15. **Coexistence:** workflow creates a stone → autotrade opens trade (existing behavior) — no conflict, no double-trade.
16. **Stability:** 5+ arenas with `/console scriptErrors 1` — zero Lua errors.

---

## 7. Conventions and constraints

- **Lua 5.1**, no libraries, single global `ACP`, modules via `local _, ACP = ...`, end with `return ACP;`.
- **`---@class` annotations**, `_G.` prefix for globals, local aliases at the top of each file.
- **UI strings** through `Data/Localization.lua` (`ACP.L`). All new strings in enUS + ruRU.
- **Timers** via `ACP.Utils.Timers` (named, C_Timer wrapper). Honor the unreliable-`Cancel()` gotcha.
- **Contract-first:** update `.ai/` docs before code when the design changes.
- **Tests:** do not touch `Tests/` while implementing phases 7–11 (per `phase-workflow` skill). Add tests in Phase 12 only after user permission.
