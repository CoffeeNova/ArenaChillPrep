# ArenaChillPrep — Architecture Review & Refactoring Plan

> Standalone review for the development lead. The addon's authoritative contract docs
> are `.ai/CONTEXT.md` and `.ai/ARCHITECTURE.md` — this document is a review of
> current state and a proposed refactoring sequence. It does **not** change behavior.

---

## Executive Summary

The addon is a **well-disciplined v0.1** with strong docs, a contract-first workflow, and
genuine 96%+ test coverage on its core modules. Its foundational layer (Events / Inventory /
ArenaPrep / Utils) is clean and cohesive. However, the codebase has accumulated **two
god-object modules** (`WorkflowEngine.lua` ~1955 lines, `WorkflowUI.lua` ~1203 lines),
**a layering violation** (`TradeManager` broke its "low-level dependency-free" contract),
**two parallel orchestrators** (DeliveryController + WorkflowEngine) that duplicate ~50 lines
of precondition logic, and pervasive **stringly-typed state / step-type dispatch** with no
shared enums. These are the primary refactoring targets. The refactor is **behavior-
preserving** and must follow the project's contract-first rule (update `.ai/` before code,
record in `/.ai/memories/repo/` after).

---

## 1. Strengths (do not break these)

1. **Single global `ACP` table + vararg module chain** — clean, no Ace dependency, trivially testable.
2. **Event bus** (`ACP.Events`) with `ACP_` prefix convention — clean leaf module, acyclic event flow.
3. **Clean dependency layering at the bottom**: `Events → Utils → Data → ArenaPrep/Inventory → DeliveryController/TradeManager`. No cycles via events.
4. **Gargul-pattern port** for trade mechanics (callback+timeout, FIFO ticker, ITEM_UNLOCKED re-add, ERR_TRADE_COMPLETE detection) — proven prior art, correctly adapted.
5. **Verified client gotchas** documented in CONTEXT.md and encoded in code (C_Timer cancel-bug workaround in `Utils/Timers.lua`, aura-scan API choice, `[@unit]` pet macro conditionals, spell-ID guard on SENT/START).
6. **Comprehensive unit tests** for non-UI modules with sync timer recorder.
7. **Contract-first `.ai/` documentation** as source of truth — rare and valuable.

---

## 2. Architectural Weaknesses (by severity)

### CRITICAL — God Objects

**W1. `WorkflowEngine.lua` is a god object (1955 lines, 53 methods, 12 concerns).**
Responsibilities conflated: state machine, spell casting, pet-ability subsystem, item
equipping, buff/aura scanning, createItem completion detection, 5+ gate checks, secure-button
+ key-binding management, WoW event wiring, catalog lookup. The binding-management concern
alone (~300 lines, `WorkflowEngine.lua:1509-1822`) has **zero conceptual overlap** with
workflow execution. Only 4 of 53 methods are called externally (`getStatus`, `applyBinding`,
`clearBinding`, `effectiveSkip`) — the other 49 should be module-local functions.

**W2. `WorkflowUI.lua` is a fat view (1203 lines, 21 methods + 14 file-local helpers).**
Mixes view (layout/render), controller (step-type inference, target/skip defaults at
`addStep:547-567`), repository (dot-path surgery `workflows.definitions.<slot>` ×12 sites),
and raw WoW I/O (`SetBinding`/`SaveBindings` in `setSelectedKey:644-689`). `buildStepRow` is
156 lines; `deleteWorkflow` is 74.

### HIGH — Layering & Coupling Violations

**W3. `TradeManager` violates its "low-level, dependency-free" contract.**
`TradeManager:queueConfiguredItems` (`:246-296`) reads `ACP.Settings:get` (`:255`),
`ACP.Data.Items` catalog (`:247,259`), and `ACP.Inventory:getCount` (`:278`) — it is
decision logic that the architecture doc (`ARCHITECTURE.md` §2.6) explicitly says
TradeManager must NOT contain. The file header comment ("dependency-free") is now false.

**W4. `DeliveryController` reaches into `TradeManager.partnerUnit` private field**
(`DeliveryController.lua:378`) instead of via a public accessor.

**W5. Two parallel orchestrators duplicate precondition logic.**
`DeliveryController:canStartTrade` (`:184-219`) and `WorkflowEngine:checkGates`
(`:322-391`) both check enabled/arena-active/not-dead/gateSafety/combat — 4 of 5 conditions
identical, with **divergent combat APIs** (`UnitAffectingCombat("player")` vs
`InCombatLockdown()`).

**W6. Reverse layering: data → UI.**
`Settings:reset` calls `ACP.OptionsUI:refresh()` (`Settings.lua:398-400`);
`WorkflowSpellbook:_refreshUI` calls `ACP.WorkflowUI:refresh()` (`:542-546`). Both guarded,
both still coupling smells — a reset/scan event would decouple them.

**W7. Path-string vocabulary re-typed across consumers.**
`"workflows.definitions.<slot>.steps.<i>"` appears in 12+ places in `WorkflowUI`, again in
`WorkflowEngine:275`, with no shared `WorkflowRepository`/paths module.

### MEDIUM — Design Smells

**W8. Stringly-typed state enums with no validation.**
`DeliveryController` (`:29`: `"IDLE"|"ACTIVE"|"TRADING"|"DONE"`) and `WorkflowEngine`
(`:45`: `"IDLE"|"RUNNING"|"PAUSED"|"DONE"`) use raw string literals compared at 14+ sites
each. A typo silently corrupts state. No centralized enum table. The implicit **sub-state**
in WorkflowEngine is a cluster of ~12 booleans (`waitingForKey/Cast/Pet/Equip`,
`castAccepted`, `pendingPetStep`, `petStepDone`, `expectedItemID*`, `pendingCastSpellID`,
`equipItemID`) encoding "which RUNNING sub-state" — no enum, fragile, root cause of the 5
duplicated reset blocks.

**W9. Stringly-typed `step.type` dispatch duplicated 5× in WorkflowEngine**
(`executeCurrentStep:1339-1369`, `isStepGoalMet:489-495`, `effectiveSkip:521-523`,
`checkGates:353,379`, `onSecurePress:882,909`) and again in `WorkflowUI.buildStepRow` — a
per-step-type handler table would collapse these into one lookup.

**W10. Long, deeply-nested methods.**
`WorkflowEngine._init` (238 lines), `executeCurrentStep` (86), `start` (76), `checkGates`
(69); `DeliveryController.checkReady` (88, 4-level nesting, 2 inline timer closures);
`TradeManager._init` (81 lines of inline closures); `Widgets.UI.Keybind` (180 lines, 5
mutually-referencing closures); `OptionsUI.handleCommand` (123-line if/elseif chain).

**W11. `castAccepted` state-transition gap.** Cleared only in `requestKeyCast` (`:604`),
never in `pause()`/`reset()`/`advance()` — survives across states, a latent stale-flag
surface (CONTEXT.md gotcha #19 documents the SENT/START guard that depends on it).

**W12. WorkflowEngine catalog-traversal duplication.** `getCatalogEntry`'s fallback
(`:216-228`) and `getPetEntry` (`:402-414`) both walk `ACP.Data.Workflows.spells` directly,
bypassing `WorkflowSpellbook:getEntry` — logic that belongs in the spellbook module.

**W13. Two subtly different `setSetting` wrappers** (`OptionsUI:64-67` double-persists;
`WorkflowUI:109-111` relies on internal persist) plus a third `persistSettings`
(`WorkflowUI:113-117`) with a dead `persist`-nil guard.

### LOW — Inconsistencies

**W14. Inconsistent nil-checking of `TradeFrame`** (DeliveryController:301 nil-checks;
TradeManager:114 does not) and unguarded `useContainerItem(...)` call (TradeManager:148).

**W15. Possibly-dead-on-target defensive code:** ArenaPrep index-based aura fallback
(`:65-80`), `buffExpirationTime` path in `getRemainingTime` (`:157-161`), TradeManager
`C_Item.GetItemGUID` path (`:97-109`) — all depend on APIs the 20506 client likely lacks;
need runtime verification before deleting.

**W16. Two independent binding mechanisms** (`ACP_WORKFLOW<i>` per-slot via WorkflowUI's
Keybind widget vs `workflows.hotkey` global cast key via `/acp bind`) surface in the same
UI without distinction.

**W17. No scroll-position preservation** across `renderSteps` — rows re-parented to
RecycleFrame every refresh, resetting scroll (likely UX bug).

---

## 3. Dead Code Inventory

| Item | Location | Evidence |
|---|---|---|
| Dead event `ACP_TRADE_START` | `TradeManager.lua:67` | No `Events:register("ACP_TRADE_START")` anywhere |
| Duplicate `self.expectedItemID = nil` | `WorkflowEngine.lua:1390` | Already nil'd at :1386 |
| Duplicate `spellTypeIsSpell` definition | `WorkflowSpellbook.lua:47-49` | Redefined at :129-131; first is shadowed |
| `OptionsUI.rankToName` table | `OptionsUI.lua:30` | Written at :213, never read (name also on `entry.label`) |
| 6 dead localization keys | `Localization.lua:102-105,114,116` | `keybindHeader/keybindHint/slotBinding/notBound/keyStatusLabel/activationKeyLabel` — 0 references; leftover from redesigned status block |
| 3v3/5v5 bracket checkboxes | `OptionsUI.lua:308-315` | Created but permanently disabled by `setAutotradeEnabled`; "code kept for the future" |
| `WorkflowUI.setEnabled` `flag` param | `WorkflowUI.lua:1197-1201` | Ignored; only calls `refreshStatus` |
| `OptionsUI:setSetting` redundant persist | `OptionsUI.lua:64-67` | `Settings:set` already persists internally |
| `WorkflowUI:persistSettings` nil-guard | `WorkflowUI.lua:113-117` | `Settings:persist` always defined |
| Commented `food`/`water`/`CLASS_MAGE` stubs | `Data/Items.lua:40-45` | No live references |
| `spellLabel`/`itemLabel`/`selectedKey` API-nil guards | `WorkflowUI.lua:168,204,148` | `GetSpellInfo`/`GetItemInfo`/`GetBindingKey` always present on 20506 |
| `scroll.SetVerticalScroll` nil-guard | `WorkflowUI.lua:694` | `UIPanelScrollFrameTemplate` always provides it |

---

## 4. Duplicate Code Inventory

| Duplication | Sites | Fix |
|---|---|---|
| **State-clearing block (~10 fields)** ×5 | `WorkflowEngine:1264-1279, 1380-1394, 1405-1422, 1496-1503, 944-947` | `clearTransientState()` helper |
| **Aura-scan-by-name loop** ×2 | `WorkflowEngine:541-551, 751-761` | `hasBuff(target, name)` helper |
| **SENT/START spell-ID guard** ×2 | `WorkflowEngine:1835-1841, 1859-1865` | `isWaitingForKeyOrCast()` predicate |
| **Cast-completion guard** ×4 | `WorkflowEngine:1878,1890,1902,1929` | `isRunningCastStep()` predicate |
| **Catalog traversal of `Data.Workflows.spells`** ×2 | `WorkflowEngine:216-228, 402-414` | Move to `WorkflowSpellbook:getEntry/getPetEntry` |
| **Expected-item-set resolution ternary** ×2 | `WorkflowEngine:468-470, 1044-1046` | Helper |
| **Pet-arming attribute block** ×2 | `WorkflowEngine:671-685, 827-835` | Helper |
| **`attachTooltip`** verbatim | `Widgets.lua:69-83` vs `WorkflowUI.lua:289-307` | Delete WorkflowUI copy; re-export from Widgets |
| **`isSafeBindingKey`** byte-identical | `Widgets.lua:463-470` vs `WorkflowUI.lua:158-165` | Single source in Widgets |
| **`setSetting` wrapper** ×2 (different contracts) | `WorkflowUI:109-111`, `OptionsUI:64-67` | One shared helper |
| **`workflows.definitions.<slot>` path** ×12 | `WorkflowUI.lua:396,424,446,500,501,504,1011,1013,1018,1020,1130,1175` + `WorkflowEngine:275` | `WorkflowRepository` paths module |
| **Category/rank grouping logic** | `DeliveryController:105-137` vs `TradeManager:246-296` | Single `TradePlanner` / call one from the other |
| **Readiness gate (enabled/arena/dead/gateSafety/combat)** | `DeliveryController:184-219` vs `WorkflowEngine:322-391` | Shared `Preconditions` module |
| **`gateSafetySeconds or 15`** | `DeliveryController:208`, `WorkflowEngine:383` | Constant in `Data.Constants` |
| **Healthstone rank→itemID mapping** ×3 | `Data/Items.lua:22-37`, `Data/Workflows.lua:127-132`, `WorkflowSpellbook.lua:33` (`HEALTHSTONE_RESULTS`) | Derive from single source |
| **`CLASS_WARLOCK` guard** ×2 | `Data/Items.lua:14`, `WorkflowSpellbook.lua:31` | Single constant |
| **`deepCopy`** | `Utils/Tables.lua:47` vs `Tests/helpers.lua:53` | Reuse in tests |
| **`setState` change-suppression log** | `DeliveryController:47-52`, `WorkflowEngine` (same shape) | `StateMachine` mixin |
| **`_initialized` guard boilerplate** | 5+ `_init` methods | Mixin |

---

## 5. Coupling & Cohesion Summary

**Low cohesion (god objects):** `WorkflowEngine` (12 concerns), `WorkflowUI`
(view+controller+repository+I/O), `WorkflowSpellbook` (scanner+catalog+class-gating+labels
+UI-refresh), `Settings` (dot-path store + entire migration pipeline).

**High coupling (reaching into internals):**
- `WorkflowEngine` → `Data.Workflows.spells` internals (catalog traversal bypassing spellbook)
- `DeliveryController` → `TradeManager.partnerUnit` (private field)
- `OptionsUI` → `WorkflowEngine.debugBypass` (private field, `:168`)
- `OptionsUI` → `ACP.DebugLog` (direct array access), `ACP.debug`, `ACP._initialized`
- `Settings` → `OptionsUI` (reverse), `WorkflowSpellbook` → `WorkflowUI` (reverse)

**Clean modules (model targets):** `Events`, `ArenaPrep`, `Inventory`, `Utils/Tables`,
`Utils/Timers`, `Widgets` (presentation-only), `Data/Constants`.

---

## 6. Refactoring Plan (Phased, Behavior-Preserving, Contract-First)

Each phase: (1) update `.ai/ARCHITECTURE.md` + relevant `.ai/CONTEXT.md` gotcha,
(2) implement, (3) update/add tests, (4) run `.\Tests\run-tests.ps1`,
(5) syntax-check `.ai/tools/syntax-check.ps1`, (6) deploy + live-verify,
(7) record outcome in `/.ai/memories/repo/`.

### Phase 0 — Test infrastructure gaps (prerequisite)

**0a. Add `WorkflowEngine` to luacov coverage include list** (`Tests/run_tests.lua:18-21`
currently omits `Classes/WorkflowEngine$`). The largest module has a test suite but **zero
coverage tracking** — unacceptable before refactoring it.
**0b. Ensure every existing test passes and baseline coverage is recorded** before touching code.

### Phase 1 — Dead code & trivial duplication removal (LOW RISK)

Safe, mechanical, no behavior change:
1. Delete dead event fire `ACP_TRADE_START` (`TradeManager.lua:67`).
2. Delete duplicate `expectedItemID = nil` (`WorkflowEngine.lua:1390`).
3. Delete dead `spellTypeIsSpell` (`WorkflowSpellbook.lua:47-49`).
4. Delete `OptionsUI.rankToName` table + its write (`:30, :213`).
5. Remove 6 dead localization keys (`Localization.lua:102-105,114,116`).
6. Delete `WorkflowUI:persistSettings` nil-guard; collapse `OptionsUI:setSetting` to not double-persist.
7. Remove API-nil guards that are always-true on 20506 (`spellLabel:168`, `itemLabel:204`, `selectedKey:148`, `scroll.SetVerticalScroll:694`).
8. Deduplicate `attachTooltip` (WorkflowUI → re-export from Widgets), `isSafeBindingKey` (WorkflowUI → Widgets), `deepCopy` (Tests → reuse `Utils/Tables`).
9. Derive `HEALTHSTONE_RESULTS`/`SOULSTONE_RESULTS` from `Data/Items.lua`; consolidate `CLASS_WARLOCK` guard.
10. Move `gateSafetySeconds` default `15` into `Data.Constants`.

### Phase 2 — Centralize enums & helpers (LOW-MEDIUM RISK)

Behavior-preserving consolidation that prepares for Phase 3-5:
1. Add `ACP.Data.Constants.WORKFLOW_STATE_*` and `DELIVERY_STATE_*` enum tables; replace raw string comparisons in both orchestrators.
2. Add `Reason` table for WorkflowEngine pause reasons (13 magic strings → `Reason.InCombat` etc.).
3. Add `ACP.Data.Constants.WORKFLOW_STEP_*` already exists — ensure **all** `step.type == "..."` sites use it (verify none use raw strings).
4. Extract `WorkflowEngine:clearTransientState(includePetDone)` → call from `advance/pause/reset/start/onCastTimeout` (eliminates 5 duplicated blocks + the dead :1390).
5. Extract `WorkflowEngine:hasBuff(target, name)` → replaces aura loops in `isAlreadyBuffed:541-551` and `isPetAbilityApplied:751-761`.
6. Extract `isWaitingForKeyOrCast()` / `isRunningCastStep()` predicates → collapse SENT/START/STOP/SUCCEEDED guards.
7. Extract `WorkflowRepository` (paths module): `definitionPath(slot)`, `stepsPath(slot)`, `stepPath(slot,i)` → replace 12+ re-typed paths in WorkflowUI + WorkflowEngine.
8. Replace `Settings:reset → OptionsUI:refresh` and `WorkflowSpellbook:_refreshUI → WorkflowUI:refresh` with events (`ACP_SETTINGS_RESET`, `ACP_SPELLBOOK_CHANGED`) → removes reverse layering (W6).

### Phase 3 — Fix TradeManager layering violation (MEDIUM RISK)

The highest-value architectural fix:
1. Move `queueConfiguredItems` decision logic (`TradeManager:246-296`) **out** of TradeManager into a new `ACP.TradePlanner` (or into DeliveryController). TradeManager reverts to true low-level: `startTrade`/`queueItem(itemID)`/`cancel`/`isTrading`.
2. Single source for category/rank grouping: `TradePlanner:buildQueue()` calls the same grouping as `DeliveryController:categoryReady` (extract `categoryReady` into `TradePlanner` too, have DeliveryController call it).
3. Add `TradeManager:getPartner()` public accessor; replace `DeliveryController:378` direct field access.
4. Fix `TradeFrame` nil-check inconsistency (W14) and guard `useContainerItem` (W14).
5. Update `ARCHITECTURE.md` §2.6 to reflect TradeManager's restored low-level contract.

### Phase 4 — Extract shared Preconditions + StateMachine mixin (MEDIUM RISK)

Eliminates the two-parallel-orchestrators duplication (W5):
1. New `ACP.Preconditions` module: `enabled()`, `inArenaWithBuff()`, `notInCombat()` (pick ONE API — `UnitAffectingCombat` is the TBC-correct one; `InCombatLockdown` is for secure-frame protection, a different concern), `notDead()`, `gateSafetyOk()`.
2. `DeliveryController:canStartTrade` and `WorkflowEngine:checkGates` both delegate to `Preconditions` for the shared 5 checks; each keeps only its action-specific gates.
3. New `ACP.StateMachine` mixin: `setState(state)` with change-suppression log + enum validation, `_initialized` guard, `reset()` scaffolding. Both orchestrators embed it.
4. Centralize `castAccepted` clearing into `clearTransientState` (fixes W11).

### Phase 5 — Split WorkflowEngine god object (HIGH RISK, highest leverage)

Do this **after** Phases 2-4 reduce its size and coupling. Split into:
- **`ACP.WorkflowEngine`** (core state machine + step dispatch via handler table) — ~400 lines.
- **`ACP.WorkflowBindings`** (already exists as a thin file — absorb `:1509-1822` secure-button + override-binding management) — ~300 lines.
- **`ACP.PetAbilityCaster`** (pet subsystem: `petMacroText`, `armPetVerify`, `isPetAbilityApplied`, `pendingPetStep`/`petStepDone` lifecycle) — ~150 lines.
- **`ACP.WorkflowCastController`** (`castSpell`, `requestKeyCast`, `onKeyPressed`, `waitForInstantEffect`, `onCastComplete`, `onCastTimeout`, spellcast event handlers) — ~300 lines.
- **`ACP.WorkflowItemSteps`** (`createItem`, `equipItem`, `countExpectedItems`, `isItemAlreadyPresent`, `waitForItem`) — ~150 lines.

Apply the per-step-type handler table (W9): `{ [CAST]={run=castController.cast, goalMet=buffs.isAlreadyBuffed, ...}, [PET]={...}, ... }` — collapses 5 dispatch sites into one lookup. Each extracted module owns its event subscriptions.

### Phase 6 — Split WorkflowUI fat view (HIGH RISK)

Split into:
- **`ACP.WorkflowUI`** (pure layout/render) — calls into repository + engine via public API only.
- **`ACP.WorkflowRepository`** (CRUD + binding migration + persistence) — owns `definitions.<slot>` paths.
- **`ACP.WorkflowKeybindController`** (`SetBinding`/`SaveBindings`/conflict-steal) — replaces `setSelectedKey:644-689`.
- Move `stepType`/target/skip default inference (`addStep:547-567`) into `WorkflowEngine` or a `StepFactory` — UI should not re-derive business rules.
- Add `bindControl(path, tooltip)` helper → collapses ~40 lines of repeated getter/setter closures.
- Preserve scroll position across `renderSteps` (fixes W17).
- Replace hardcoded `Widgets.lua:478,486,555` keybind fallback strings with caller-passed `L.*` values.

### Phase 7 — Split WorkflowSpellbook & Settings (MEDIUM RISK)

- **`WorkflowSpellbook`** → `SpellbookScanner` (API probing) + `CatalogBuilder` (assembly) + `WarlockCatalogExtender` (class-gated static fallback + pet/stone extras) + `SpellbookLabels` (`stoneName`/`stoneStepLabel`).
- **`Settings`** → keep dot-path `get/set/persist/reset`; extract `SettingsMigrator` (`migrateWorkflowNames`/`migrateStepSpellIDs`/`normalizeRankKeys`/`ensureDefaults`/placeholder replace) — ~150 lines currently interleaved in `_init`.
- Unify `Data/Workflows.lua` `spells.createItem` and `stoneRanks` into one structure (W: §9).

### Phase 8 — Documentation & memory

- Update `ARCHITECTURE.md` module diagram + §2.x descriptions to reflect new module boundaries.
- Update `CONTEXT.md` gotchas if any verified behavior shifted (shouldn't — behavior-preserving).
- Add `ARCHITECTURE.md` ADR entries for: shared `Preconditions`, `StateMachine` mixin, `WorkflowRepository` paths, step-type handler table.
- Record each phase outcome in `/.ai/memories/repo/` per project rules.
- Update `Tests/run_tests.lua` suites list + coverage include list for any new modules (gotcha — unlisted suites silently never run).

---

## 7. Risk Assessment

| Phase | Risk | Mitigation |
|---|---|---|
| 0 | Low — test infra only | — |
| 1 | Low — mechanical deletion | Full test run after each batch |
| 2 | Low-Med — pure refactor, behavior-preserving | Predicate/helper extraction, tests unchanged |
| 3 | Medium — moves decision logic across module boundary | Live-verify a full trade cycle in 2v2 after |
| 4 | Medium — shared mixin changes both orchestrators | Live-verify both autotrade + workflow paths |
| 5 | **High** — splits the most complex module | Do last; the handler-table refactor is the riskiest single change — keep old dispatch as fallback behind a flag until live-verified |
| 6 | High — UI restructuring | Screenshot-review cycle per user workflow (UI-redesign loop) |
| 7 | Medium — data-layer split | Migration logic is the riskiest; keep `_init` order identical |

**Recommended sequencing:** Phases 0→1→2→3→4 first (yield ~40% line reduction in the two god
objects without splitting them). Then reassess whether Phase 5/6 splits are still warranted or
whether the now-smaller modules are acceptable. **Phase 5's step-type handler-table refactor
is the single highest-leverage but highest-risk change** — it should be its own commit with a
feature flag and live verification of all 5 step types (cast/summon/createItem/equipItem/pet).

---

## 8. Open Questions for the Development Lead

1. **Risk tolerance for Phase 5/6 splits** — accept the overhead of ~5 new modules for a v0.1
   single-class addon, or stop after Phases 1-4 reduce WorkflowEngine to a more manageable size?
2. **`castAccepted` semantics (W11)** — is the current "cleared only in `requestKeyCast`"
   intentional or a latent bug? If intentional, document it; if not, Phase 4 fixes it.
3. **Possibly-dead-on-target code (W15)** — worth a runtime `/dump` verification pass before
   the refactor to confidently delete or keep the ArenaPrep/TradeManager defensive branches?
4. **Combat-API divergence (W5)** — `UnitAffectingCombat` vs `InCombatLockdown`: which is
   canonical for "can't trade/cast right now"? They test different things (combat state vs
   secure-frame lockdown); `Preconditions` may need both.

---

*Prepared by architecture review. Line references are against the codebase at review time
(bootstrap `_init` order: Events → Settings → WorkflowSpellbook → ArenaPrep → Inventory →
TradeManager → WorkflowEngine → DeliveryController → WorkflowBindings → OptionsUI).*
