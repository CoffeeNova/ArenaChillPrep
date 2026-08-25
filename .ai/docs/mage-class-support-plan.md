# ArenaChillPrep — Mage Class Support: Development Plan

> **Status: IMPLEMENTED (2026-08-25).** All phases 0-7 are done — Mage support ships in v0.2 (Warlock + Mage). In-game verification on a Mage is PENDING user testing.
> **Target:** v0.2 — Warlock + Mage. Mage gets its own spell catalog, its own default workflows and food/water autotrade.
> **Client:** WoW TBC Anniversary, Interface `20506`.
> **Scope note:** class-specific code lives in separate files behind a dispatcher — editing one class never touches the other.

---

## 1a. Resolved data (Phase 0, verified against Questie TBC itemDB + Warcraft Wiki + wowclassicdb)

| Spell | Spell ID | Creates | Item ID | Per cast |
|---|---|---|---|---|
| Conjure Food (rank 8) | `33717` | **Conjured Croissant** | **`22019`** | 10 |
| Conjure Water (rank 9) | `27090` | **Conjured Glacier Water** | **`22018`** | 10 |
| Ritual of Refreshment | `43987` | summons a table object (no bag item) | — | — |

- **Conjured Manna Biscuit (34062) is NOT created by Conjure Food** — it comes from the Ritual of Refreshment table (verified 2026-08-25). The plan's earlier assumption (spell 33717 → Manna Biscuit) was wrong.
- Both conjured items stack to 20; both are tradable and disappear after 15 min offline.
- `conjuredRanks` entries carry a `category` field (`food` / `water`) that maps to the autotrade settings key via `Items:settingsKeyFor()` — the same field was added to Warlock `stoneRanks` (`healthstones`) so the count-target goal-met check is generic.
- Warlock `stoneRanks` entries also carry `category = "healthstones"` (behavior-neutral: `items.healthstone.count = 1` makes the count-target path identical to the old "any variant present").

## 1b. Design deviations from the draft (user-facing notes)

- `itemsReady()` now requires **ALL enabled categories** to be ready (food AND water) — the draft §6.4 wording; the old ANY-category code was single-category behavior. Warlock (one category) is unaffected.
- The Autotrade right column is laid out with a **vertical cursor** across categories (rank rows of food and water stack under each other, count sliders below them); the ranks box height is computed from the actual rank rows + sliders (not the fixed 6-row box).
- `TradePlanner` no longer captures `UnitClass` at file scope — it reads it at call time (needed for the per-class category mapping and test overrides).

## 1c. User-test fixes (2026-08-25, second round)

| Report | Fix |
|---|---|
| "Food/Water to await" labels | Renamed to **"Food count to pass:" / "Water count to pass:"** (`foodCountLabel`/`waterCountLabel`, enUS + ruRU) |
| Invisibility (32612) not working | → **66** (classic/TBC Invisibility, user-verified) |
| Molten Armor (34913) not working | → **30482** (TBC rank 1, user-verified) |
| Frost Armor (Rank 3) → Ice Armor | 7301 replaced by **Ice Armor (Rank 5) 27124** |
| Amplify/Dampen Magic rank 1 "missing" | Root cause: the Add Step menu collapsed same-name groups into ONE entry (always the max rank). Buff entries now carry a `rank` field (1008/33946 = ranks 1/6, 604/33944 = ranks 1/6); `SpellbookCatalogBuilder:addEntry` propagates `metadata.rank` (matched by exact spellID — the old name-match returned the first same-name entry's metadata for ALL of them); the Add Step menu lists any group whose entries ALL carry a rank **per rank** (`SpellbookLabels:rankStepLabel` → "Amplify Magic (rank 1)"). Warlock groups have no rank fields → their menu rendering is untouched (Fel Armor still collapses to max rank). |
| Warlock "Create Healthstone (Rank 1-5)" broken, only rank 6 works | Hardened `WorkflowEngine:resolveCastInfo`: ranked families (stone/conjure) now resolve the highest KNOWN rank from the **STATIC rank table** (IsPlayerSpell per rank entry) — never from the runtime catalog. A catalog-rebuild issue can no longer skip low-rank steps as "unknown" (the runtime catalog is empty until PLAYER_LOGIN and is the historical failure point for low ranks). Regression test `testResolveCastInfoUpgradesWithoutRuntimeCatalog` (empty catalog → 11730 step still resolves to 27230/22105). If the symptom persists in-game, capture `/acp debug` + `/acp dumplog` from a `/acp workflowtest` run. — **user confirmed fixed (round 3).** |
| Add "Conjure Mana Emerald" | Added to `MageData.spells.createItem`: spell **27101** → **Mana Emerald 22044** (single-rank conjure; plain Add Step entry — not in `conjuredRanks`, so no count-target/rank decoration side effects). |

## 1d. Coverage-gate discovery (2026-08-25)

- **The 90% coverage gate had been failing with CLEAN luacov stats** (HEAD measured 83.68%): every historical 91-96% number was inflated by `Tests/luacov.stats.out` accumulation — a crashed/pipe-killed run leaves the stats file and luacov MERGES it into the next run. `run_tests.lua` now deletes the stats file before init (deterministic clean measurement).
- The two class-data files were compacted to **single-line step tables** — the LuaJIT line hook never fires for the LAST field of a multi-line table constructor, so the multi-line step style left ~150 data lines permanently "uncovered".
- New suite `Tests/Classes/test_workflowexecution.lua` covers the previously untested execution paths (createItem/equipItem flows, UNIT_SPELLCAST_* handlers, timeouts, gates, skip/DONE paths).
- **Real pre-existing production bug fixed along the way:** `GetSpellCooldown and GetSpellCooldown(spellID)` in `WorkflowCastController:waitForInstantEffect` truncated the call to one value (`and` drops extra returns) — the GCD-detection branch of the instant-cast wait NEVER fired. Both call sites rewritten with explicit capture.

---

## 1. Overview

The addon currently supports Warlock only (healthstones autotrade + Warlock workflow catalog). This plan adds Mage:

1. **Workflow catalog** — Mage spells grouped by type (`buffs` / `createItem` / `utility`), no summons, no pets, no equippable items.
2. **Autotrade** — two categories: **Conjured Food** (spell 33717) and **Conjured Water** (spell 27090). Per-category "how many items to await before trading" settings — default **20 food / 20 water**, slider 10–60 step 10 (each conjure creates 10 items).
3. **Default workflows** — Mage's own 5 slots, unrelated to Warlock's. Filled per-class at login (character SavedVariables).
4. **Welcome popup** — Mages get the first-run popup too (class-conditional feature lines).
5. **UI gating** — `OptionsUI:isSupportedClass()` accepts MAGE; every other class still sees the Compatibility page.

The autotrade pipeline (`Inventory` → `DeliveryController` → `TradeManager` → `TradePlanner`) and the workflow engine (`WorkflowEngine` + step modules) are already class-agnostic — they dispatch on `classItems[englishClass]` and `step.type`. Only data + catalog assembly + UI gating are Warlock-specific.

---

## 2. Design decisions (confirmed with user)

| Decision | Choice | Rationale |
|---|---|---|
| Class isolation | Separate data files + catalog extenders per class, behind a `ClassCatalogDispatch` registry | Editing Mage never breaks Warlock; common code loads the active class's data |
| Mage default workflows | Own 5 slots, unrelated to Warlock's | Per-character SavedVariables (`ArenaChillPrepCharDB`); filled from the active class's `defaultDefinitions` at login |
| Autotrade categories | `food` + `water` | The Mage's 2 tradeable conjured items |
| Count settings | 2 separate settings `items.food.count` / `items.water.count`; default **20**, slider **10–60 step 10** | Each conjure creates 10 items (20 = 2 casts); separate settings per item type |
| Trade volume | One trade per partner; 6 slots hold 6 full stacks (20-item stacks) — enough | The count is the **trigger threshold** (await N before opening the trade); the existing `givenTo` one-trade-per-partner contract holds |
| Conjure step completion | Count-target goal-met for conjured items (see §7) | 2 identical Conjure steps + count-target skip = conjure until 20 with one key press each; Warlock stones keep the delta behavior |
| Welcome popup | Mages get it (class-conditional `welcomeLine1/2`) | `Welcome.lua` already gates on `isSupportedClass()` |
| Amplify / Dampen Magic | **Both ranks as separate Add-Step entries** (1008 + 33946, 604 + 33944) | Same pattern as Warlock's two Fel Armor entries (28176/28189) |
| Mage item IDs | Cast spellIDs from the user's prompt (33717/27090); the resulting bag **itemIDs** are resolved in Phase 0 | Bags are scanned by itemID; the spell→item result pair must be verified (`/dump` or researcher) |
| Mage summons/pets/equipItems | None | Mage has no pets, no summons, no equippable conjured items; the equip-items Add-Step category stays Warlock-only |

---

## 3. Current architecture: class-specific vs. class-agnostic

### 3.1 Already class-agnostic (NO changes)

| Module | Why generic |
|---|---|
| `bootstrap.lua`, `Classes/Events.lua`, `Classes/ArenaPrep.lua` | No class references |
| `Classes/Inventory.lua` | `_buildTrackedItems()` uses `classItems[englishClass] or {}` (`Inventory.lua:26-38`) |
| `Classes/TradePlanner.lua` | `getCategories()` uses `classItems[englishClass] or {}` (`TradePlanner.lua:22-27`); `categoryReady`/`buildQueue` iterate all categories generically |
| `Classes/DeliveryController.lua`, `TradeManager.lua`, `Preconditions.lua`, `StateMachine.lua` | No class references (except the pluralization helper — see §5.4) |
| `Classes/WorkflowEngine.lua` + `WorkflowCastController` / `WorkflowItemSteps` / `PetAbilityCaster` / `WorkflowBindings` | Dispatch on `step.type` / `step.spellID`; `PetAbilityCaster` simply never fires for Mage (no pet steps) |
| `Classes/WorkflowRepository.lua`, `WorkflowKeybindController.lua` | Pure CRUD/keybind logic |
| `Classes/UI/Widgets.lua`, `Classes/UI/WorkflowUI.lua` | Render whatever the active catalog exposes |

### 3.2 Warlock-specific extension points (need Mage parallels)

| # | Location | What is Warlock-specific | Mage action |
|---|---|---|---|
| 1 | `Data/Constants.lua:12` | `CLASS_WARLOCK = "WARLOCK"` | Add `CLASS_MAGE = "MAGE"` |
| 2 | `Data/Items.lua:44-46` | `classItems[CLASS_WARLOCK] = { "healthstones" }` | Add `food`/`water` catalogs + `classItems[CLASS_MAGE]` |
| 3 | `Data/Workflows.lua` | `spells` (all Warlock), `stoneRanks`, `equipItems` | Move Warlock data out; add `Data/MageWorkflows.lua` |
| 4 | `Data/DefaultSettings.lua` | `items.healthstone` + 5 Warlock `definitions[1..5]` | Add `items.food`/`items.water`; class-gate `definitions` |
| 5 | `Classes/WarlockCatalogExtender.lua` | `isWarlock()` gates `mergeStaticWarlock` + `addStaticFallback` | Add `MageCatalogExtender.lua` (twin) + dispatcher |
| 6 | `Classes/WorkflowSpellbook.lua:25-26` | Calls Warlock extender directly in `scan()` | Dispatch to the active class's extender |
| 7 | `Classes/SpellbookCatalogBuilder.lua` | `staticMetadata` scans `Data.Workflows.spells`; `rankResultItem` matches Healthstone/Soulstone names; `addEntry` family-grouping reads `Data.Workflows.stoneRanks` | Scan the ACTIVE class's `spells`; family grouping reads the active class's rank table |
| 8 | `Classes/SpellbookLabels.lua:19-20` | `stoneStepLabel` reads `Data.Workflows.stoneRanks` | Read the active class's rank table |
| 9 | `Classes/OptionsUI.lua:47-50` | `isSupportedClass()` returns `"WARLOCK"` only | Accept `"MAGE"` |
| 10 | `Classes/UI/WorkflowUI.lua:290` | equip-items Add-Step category gated to `CLASS_WARLOCK` | Stays Warlock-only (Mage has none) — no change |
| 11 | `Classes/UI/Welcome.lua:318` | gates on `isSupportedClass()` | Works once #9 lands; add class-conditional feature lines |
| 12 | `Data/Localization.lua` | Warlock-flavored strings (`welcomeLine1/2`, `rankTooltip`, `compatMessage`) | Add Mage variants / generalize |
| 13 | `OptionsUI.lua:418`, `DeliveryController.lua:103`, `TradePlanner.lua:91` | `category:sub(1, -2)` plural→singular mapping | Breaks for `"food"` → `"foo"` — replace with an explicit map (see §5.4) |

---

## 4. Required refactoring (class isolation)

### 4.1 Split class data (Refactor A)

- **`Data/Workflows.lua`** → keeps ONLY the generic schema: `targets`, `validateStep`, `isValidTarget`, `getEquipItem`. Removes `spells`, `stoneRanks`, `equipItems`.
- **`Data/WarlockWorkflows.lua`** (new) → `WarlockData.spells`, `WarlockData.stoneRanks`, `WarlockData.equipItems`, `WarlockData.defaultDefinitions` (the current 5 slots moved verbatim from `DefaultSettings.lua:41-511`).
- **`Data/MageWorkflows.lua`** (new) → `MageData.spells`, `MageData.conjuredRanks`, `MageData.defaultDefinitions`.
- **`ACP.Data.classWorkflows(englishClass)`** (new accessor, lives in `Data/Workflows.lua`) → `{ WARLOCK = WarlockData, MAGE = MageData }[englishClass]`.
- `SpellbookCatalogBuilder`: `staticMetadata` scans `classWorkflows(englishClass).spells`; `addEntry` family grouping reads the active class's rank table (rename the Warlock lookup point to a shared accessor `rankedCreates(data)` — `data.conjuredRanks or data.stoneRanks`).
- New files added to `ArenaChillPrep.toc` AND `Tests/loader.lua` AND the luacov include list (gotcha #22).

### 4.2 Catalog extender dispatch (Refactor B)

- **`Classes/MageCatalogExtender.lua`** (new) — twin of `WarlockCatalogExtender`: `isMage()` gate + `mergeStaticMage(spellbook)` (conjured ranks into `createItem` category) + `addStaticFallback(spellbook)` (full Mage catalog).
- **`Classes/ClassCatalogDispatch.lua`** (new, thin) — registry:
  ```lua
  ClassCatalogDispatch.extenders = { WARLOCK = ACP.WarlockCatalogExtender, MAGE = ACP.MageCatalogExtender };
  ClassCatalogDispatch:merge(spellbook)      -- calls the active extender's merge* (no-op for unknown)
  ClassCatalogDispatch:addStaticFallback(spellbook)
  ```
- **`Classes/WorkflowSpellbook.lua:scan()`** — replace the two `WarlockCatalogExtender` calls with `ACP.ClassCatalogDispatch` calls. Keep the existing facade delegates (`mergeStaticWarlock`/`addStaticFallback`) so tests and callers keep compiling; they now route through the dispatcher.
- `WarlockCatalogExtender` keeps its name and behavior; Mage edits never touch it.

### 4.3 Class-gated default definitions (Refactor C)

- **`Data/DefaultSettings.lua`** → `workflows.definitions = {}` (empty). `enabled`/`slotCount`/`skipIfBuffedDefault` stay (class-agnostic).
- **`SettingsMigrator:applyClassDefaults(workflows, englishClass)`** (new): when `definitions` is empty/missing, fill slots `1..5` (deep-copied) from `classWorkflows(englishClass).defaultDefinitions`.
- Run it in `Settings:_init()` (class may be unknown at ADDON_LOADED → skip when `englishClass` is nil) and re-run on **PLAYER_LOGIN** (class known — same pattern as `Inventory:_buildTrackedItems`).
- `migratePlaceholderDefinitions` (Warlock OLD_PLACEHOLDER snapshot) stays Warlock-scoped and unchanged; fresh Mage characters have no definitions to migrate — `applyClassDefaults` fills them.
- Per-character SavedVariables guarantee a Mage never receives Warlock definitions (and vice versa).

### 4.4 Category → settings-key mapping (Refactor D — required bug prevention)

`category:sub(1, -2)` assumes every catalog key is a plural noun ending in "s". `"food"` → `"foo"`, `"water"` → `"wate"` — the autotrade settings would silently never match. Three production sites: `OptionsUI.lua:418`, `DeliveryController.lua:103`, `TradePlanner.lua:91`.

- Add to `Data/Items.lua`:
  ```lua
  settingsKeyByCategory = { healthstones = "healthstone", food = "food", water = "water" },
  ```
  and `Items:settingsKeyFor(category)` → `settingsKeyByCategory[category] or category:sub(1, -2)` (fallback keeps the old behavior for unknown categories).
- Replace the 3 sites with `ACP.Data.Items:settingsKeyFor(category)`.
- Update the `settings-savedvars` skill (`SKILL.md:40-42`) — the documented pattern changes.

---

## 5. Mage spell catalog (`Data/MageWorkflows.lua`)

Categories mirror the Warlock `categoryOrder` (`buffs`, `createItem`, `utility`; Mage has no `summons`/`pets` and no `equipItems`).

### `spells.buffs` (instant; self or party-targeted)

| spellID | name | canTargetParty | buffSpellID | notes |
|---|---|---|---|---|
| 27127 | Arcane Brilliance | false | 27127 | group-wide intellect buff (rank 2) |
| 27126 | Arcane Intellect | true | 27126 | single-target party buff (rank 6) |
| 33946 | Amplify Magic | true | 33946 | rank 6 (max) — separate entry per rank (user decision) |
| 1008 | Amplify Magic | true | 1008 | rank 1 |
| 33944 | Dampen Magic | true | 33944 | rank 6 (max) |
| 604 | Dampen Magic | true | 604 | rank 1 |
| 27125 | Mage Armor | false | 27125 | self-only armor (rank 4) |
| 34913 | Molten Armor | false | 34913 | self-only armor (rank 1) |
| 7301 | Frost Armor | false | 7301 | self-only armor (rank 3) |
| 27128 | Fire Ward | false | 27128 | self-only absorb (rank 6) |
| 32796 | Frost Ward | false | 32796 | self-only absorb (rank 6) |
| 33405 | Ice Barrier | false | 33405 | self-only shield (rank 6) |
| 32612 | Invisibility | false | 32612 | instant self spell |

> Both Amplify/Dampen ranks ship as separate entries with the SAME name — exactly the Fel Armor 28176/28189 pattern (`resolveCastInfo` resolves the family by name; the player picks a specific entry in Add Step).

### `spells.createItem` (cast-time, conjured — the autotrade items)

| spellID | name | itemID | notes |
|---|---|---|---|
| 33717 | Conjure Food | `<foodItemID>` (Phase 0) | rank 8; +10 items per cast |
| 27090 | Conjure Water | `<waterItemID>` (Phase 0) | rank 9; +10 items per cast |

### `spells.utility` (cast-time, no bag item)

| spellID | name | notes |
|---|---|---|
| 43987 | Ritual of Refreshment | conjures a table on the ground (like Ritual of Souls) — not a bag item |

### `conjuredRanks` (Mage twin of Warlock `stoneRanks`)

```lua
conjuredRanks = {
    [33717] = { spellID = 33717, spellName = "Conjure Food",  itemID = <foodID>,  itemIDs = { <foodID> },  itemName = "Conjured Food",  rank = 8 },
    [27090] = { spellID = 27090, spellName = "Conjure Water", itemID = <waterID>, itemIDs = { <waterID> }, itemName = "Conjured Water", rank = 9 },
},
```

Unlike healthstones (historical ID pairs), Mage food/water have a single itemID per rank — `itemIDs = { itemID }`.

---

## 6. Mage autotrade

### 6.1 `Data/Items.lua`

```lua
food  = { [<foodID>]  = { id = <foodID>,  rank = 8, name = "Conjured Food" } },
water = { [<waterID>] = { id = <waterID>, rank = 9, name = "Conjured Water" } },
classItems = {
    [CLASS_WARLOCK] = { "healthstones" },
    [CLASS_MAGE]    = { "food", "water" },
},
settingsKeyByCategory = { healthstones = "healthstone", food = "food", water = "water" },
countRanges = {
    food  = { min = 10, max = 60, step = 10 },
    water = { min = 10, max = 60, step = 10 },
},
```

### 6.2 `Data/DefaultSettings.lua`

```lua
items = {
    healthstone = { enabled = true, count = 1, ranks = { ... } },   -- Warlock, unchanged
    food  = { enabled = true, count = 20, ranks = { [<foodID>] = true } },
    water = { enabled = true, count = 20, ranks = { [<waterID>] = true } },
},
```

### 6.3 Autotrade UI (`OptionsUI:buildAutotrade`)

- Right column (under the rank rows): per-category **count sliders** — rendered only for categories with a `countRanges` entry (Mage food/water; Warlock healthstone keeps its fixed `count = 1`, no slider). `UI.Slider` with `min`/`max`/`step` from `countRanges`, getter/setter → `items.<settingsKey>.count`. Localized label per item type (`Food to await:` / `Water to await:`).
- Rank rows: `buildRankRows` is generic and already works (`L.ranks` has no rank-8/9 entry → falls back to `record.name` = "Conjured Food"). The ranks box height is computed for 6 rows — fine for 1 row per category.

### 6.4 Pipeline behavior (no logic change needed)

- `Inventory:countItem` sums `stackCount` — 20 conjured food in one stack = count 20. Correct.
- `TradePlanner:categoryReady` requires EVERY enabled category's rank count ≥ `count` → the trade opens only when BOTH 20 food AND 20 water are present.
- Capacity: `MAX_TRADABLE_ITEMS = 6`; each stack goes into one slot → 2 slots used (food + water). `count` is a **trigger threshold**, not a per-trade placement number. One trade per partner (`givenTo`) — unchanged contract.

### 6.5 Conjure-step completion (count-target goal-met)

`createItem` steps are `skippable` with `goalMet = WorkflowItemSteps:isItemAlreadyPresent` (`WorkflowEngine.lua:145-147`). For Warlock stones "any stone of the rank present" is the goal. For Mage conjured items the goal must be **"count ≥ target"**, so two identical Conjure Water steps conjure 20 (10 + 10) while skip-completed ON skips the second one when 20 are already in bags:

- `WorkflowItemSteps:isItemAlreadyPresent(engine, step)`: when the resolved spell is in the active class's rank table AND `Items:settingsKeyFor(category)` maps to an enabled `items.<key>` setting with `count` — return `countExpectedItems() >= setting.count`. Otherwise keep the current behavior (any variant present). Warlock stones: `createItem` category maps to `items.healthstone.count = 1` — **verify this does not change Warlock behavior** (healthstone count = 1, so "≥ 1 present" ≈ current "any present"; spellstones have NO items setting → unchanged delta path).
- Completion (`isItemCreated`) stays delta-based — a cast that adds a stack advances the step.
- Default Mage workflows ship **2× Conjure Water + 2× Conjure Food steps** so one workflow run conjures 20/20 (each key press = one cast = +10; the second step is skipped when the target is already met).

---

## 7. Mage default workflows (FINAL — user-tuned in-game, 2026-08-26)

`MageData.defaultDefinitions` — 5 slots, all `enabled = true`, unrelated to Warlock slots. The user tuned these on his live Mage (2.5.5) and the set was copied into the defaults verbatim from his SavedVariables:

1. **"2s standard"** — Conjure Water ×2 → Conjure Food ×2 → Conjure Mana Emerald → Arcane Intellect (player) → Dampen Magic (player) → Arcane Intellect (party1) → Dampen Magic (party1) → Ice Armor → Ice Barrier → Frost Ward
2. **"2s with healer"** — Conjure Water ×2 → Conjure Food ×2 → Conjure Water ×2 → Conjure Food ×2 → Conjure Mana Emerald → Arcane Intellect (player/party1) → Amplify Magic (player/party1) → Ice Armor → Ice Barrier → Frost Ward
3. **"3s standard"** — Ritual of Refreshment → Conjure Mana Emerald → Arcane Brilliance → Amplify Magic (player/party1/party2) → Ice Armor → Frost Ward
4. **"3s pom pyro"** — Ritual of Refreshment → Conjure Mana Emerald → Arcane Brilliance → Amplify Magic (player/party1/party2) → Molten Armor → Frost Ward
5. **"5s standard"** — Ritual of Refreshment → Conjure Mana Emerald → Arcane Brilliance → Amplify Magic (player/party1/party2/party3/party4) → Ice Armor → Ice Barrier → Frost Ward

Step format identical to Warlock (`{ type = "createItem", spellName = "Conjure Water", itemID = 22018, spellID = 27090 }`, `{ type = "cast", target = "player", spellName = "...", spellID = ... }`); Ritual of Refreshment (utility) is a `cast` step targeting the player. 2v2 slots use Amplify/Dampen rank selection: slot 1 Dampen rank 1 (604), slot 2 Amplify rank 6 (33946); 3s/5s slots use Amplify rank 1 (1008).

---

## 8. Localization (`Data/Localization.lua`)

- `welcomeLine1/2` — add Mage variants (e.g. `welcomeLine1Mage = "Auto-trades food and water to your partner."`); `Welcome.lua` picks by class.
- `rankTooltip` hardcodes "healthstones" — generalize via a `%s` category name (rank rows already pass the localized rank name).
- Add: `foodCountLabel` / `waterCountLabel` + tooltips for the count sliders; `compatMessage` unchanged (still the Warlock reroll joke for other classes).
- ruRU: add the same keys for the Russian locale.

---

## 9. Implementation phases

### Phase 0 — Item-ID research (DONE 2026-08-25)
- Resolved: Conjure Food 33717 → **Conjured Croissant 22019**; Conjure Water 27090 → **Conjured Glacier Water 22018** (Questie tbcItemDB + Warcraft Wiki + wowclassicdb; the Manna Biscuit 34062 comes from the Ritual of Refreshment table, NOT from Conjure Food). Ritual of Refreshment 43987 = Summon Object — no bag item. See §1a.

### Phase 1 — Constants + class data split (Refactor A) — DONE
### Phase 2 — Catalog extender dispatch (Refactor B) — DONE
### Phase 3 — Items, defaults, autotrade mapping (Refactors C + D) — DONE
### Phase 4 — Class gating + UI — DONE
### Phase 5 — Mage default workflows content — DONE (5 slots per §7 draft; user tunes in the UI)
### Phase 6 — Tests — DONE (349 tests, 91.93% coverage)
### Phase 7 — Verify — syntax/vararg/coverage green; in-game Mage DoD PENDING user testing

---

## 10. Out of scope (explicitly)

- Multi-trade-per-partner (the `givenTo` one-trade-per-partner contract holds).
- Auto-crafting items by the addon (workflows cast; autotrade waits — unchanged division of labor).
- More classes beyond Mage.
- Changing Warlock default workflows or its catalog entries in this phase.

---

## 11. Definition of Done

1. Mage: full settings panel, Mage catalog (Add Step + per-rank Amplify/Dampen entries), Mage default workflows (own 5 slots, unrelated to Warlock).
2. Autotrade: `food`/`water` with separate count settings (default 20/20, slider 10–60 step 10); trade opens when both targets are met; 6-slot stack placement.
3. Warlock: behavior-preserving — same catalog, same defaults, same autotrade.
4. All tests pass, coverage ≥ 90%; no Lua errors; deploy verified in-game for both classes.
5. `.ai/` docs updated (ARCHITECTURE §2, CONTEXT status/settings/gotchas) after implementation; memory entry recorded.
