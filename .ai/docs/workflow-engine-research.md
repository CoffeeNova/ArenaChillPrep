# Warlock Spell-Cast Workflow — Feasibility Research (TBC Anniversary 2.5.6)

**Status:** Research / feasibility. No code written yet. Contract-first: this document is the
spec basis for a future `WorkflowEngine` phase — nothing here is implemented.

**Goal being evaluated:** a user-defined, one-button "arena preparation workflow": the addon
runs a programmable sequence of warlock actions (buff self, buff/affect party members, summon a
pet, create and hand over healthstones, plus user-defined extra casts), each step waitable
(cast-time vs instant), interruptible on movement (resume with the same button), restartable
from the beginning every arena, and bindable to its own key.

**Client:** WoW TBC Anniversary, build 2.5.6, Interface `20506`. Methods are marked with the
addon that proves them **on this exact client** (`.toc` Interface 20506). Retail-only evidence
is explicitly flagged as **not** proof for 2.5.6.

---

## 1. Executive summary

| Question | Verdict on 2.5.6 |
|---|---|
| Can the addon cast spells programmatically? | **INSTANT spells: yes, out of combat** (`CastSpellByName`/`CastSpellByID` — proven live). **CAST-TIME spells: NO — blocked even out of combat** (`ForceTaint_Strong`, verified 2026-08-18; see §2.1 note). |
| Can it run a whole cast *sequence* on one press? | **No.** Cast-time spells need a hardware event per cast; the engine routes them through ONE hotkey (`SecureActionButtonTemplate` + `SetBindingClick`, M6 pattern) — press per cast-time step. |
| Can it cast during combat (the fight itself)? | **No, not autonomously.** Casting APIs are protected during `InCombatLockdown()`; only one secure action per hardware event is allowed. Arena prep is out of combat, so this does not block the idea. |
| Can it target party members (`party1`, `party2`)? | **Yes.** Out of combat: `TargetUnit` + cast + restore. Combat-safe: secure attribute buttons with a `unit` attribute (proven: M6 ActionBook, 20506). |
| Can workflows be bound to keys? | **Yes.** Full keybinding API works (proven: BetterFishing, GatherMate2, ItemRack — all 20506). |
| Can it interrupt on movement and resume? | **Yes.** `IsPlayerMoving()` (20506), `UNIT_SPELLCAST_INTERRUPTED/STOP`, plus a persistent step index. |
| Can it create healthstones / summon pets? | **Only via a real key press (secure hotkey).** Both are cast-time on 20506 (Create Healthstone = 3 s, summons = 6 s), and insecure cast-time casting is blocked OOC (2026-08-18). Worse, insecure INSTANT casting is also blocked OUTSIDE SAFE ZONES (bare `CastSpellByName("Fel Armor")` in the open world pops "blocked from an action", no GCD, no buff — 2026-08-19). The engine routes EVERY step through a hidden `SecureActionButtonTemplate` bound via `SetBindingClick` and waits for the user's press (M6 pattern). |
| Can it hand over stones automatically? | **Already implemented** (existing `DeliveryController` → `TradeManager`). Player still confirms the trade manually (known 2.5.x restriction). |

**Bottom line:** the idea is feasible on 2.5.6 as long as the workflow runs during arena
preparation (out of combat) — with the **critical caveat** that cast-time spells (summons,
conjures) require a real hardware event (a key press) per cast; the engine cannot cast them
autonomously. The engine therefore drives a one-hotkey secure-button flow for cast-time
steps and casts instant steps autonomously.

---

## 2. Verified building blocks (all Interface 20506)

> Method of verification: read the `.toc` of each addon in the client AddOns folder, confirmed
> `## Interface: 20506`, then read the exact call site. Addons that target other interfaces
> (retail `120007`, Era `11502/11305`, etc.) are listed separately and are NOT treated as proof.

### 2.1 Casting spells

```lua
pcall(CastSpellByID, spellId)   -- TrackingEye/Features/Core.lua:187
```
- `CastSpellByID(spellID)` — a global on 20506; TrackingEye casts its **instant** tracking
  spells with it (out of combat), and it also passes `GetSpellCooldown` gating before casting
  (Core.lua:172).
- **CRITICAL (live-verified 2026-08-18): insecure casting of CAST-TIME spells is blocked on
  20506 even out of combat.** `CastSpellByName("Fel Armor")` (instant) worked (GCD
  registered), but Summon Succubus (6 s, by name AND id), Inferno, Create Healthstone (3 s)
  and Shadow Bolt were all dropped with `ForceTaint_Strong` ("blocked from an action only
  available to the Blizzard UI") — in a safe zone, OOC, 22 shards held. `SecureActionButton
  Template:Click()` → silently dropped (hardware-event restriction, same as `AcceptTrade()`);
  `RunBinding()` on a bound spell and on a bound macro → both blocked. Conclusion: a cast-time
  spell requires a **real hardware event (user key press)** on this client. The engine's
  cast-time path therefore waits for a key press on a bound secure button instead of casting.
- `GetSpellInfo(spellID)` → name, and `select(7, GetSpellInfo(...))` resolves a name back to an
  ID (M6 Categories.lua:44,126; Handlers.lua:290) — useful for locale-independent lookups.
- `IsPlayerSpell(spellID)` (TrackingEye Core.lua:155,244), `IsUsableSpell(spell)` (M6
  Handlers.lua:317), `IsSpellInRange(spell, unit)` (M6 Handlers.lua:317), `IsCurrentSpell`
  (M6 Handlers.lua:344) — all used on 20506. These are the per-step "can we cast it now" gates.

> `CastSpellByName(name, target)` exists as a global but the **target parameter is a pre-4.0
> legacy**; do not rely on it. Use `TargetUnit` + cast + restore (2.4), or the secure `unit`
> attribute (2.2).

### 2.2 Targeting party members (buffing teammates)

- **Out of combat (prep):** `TargetUnit("party1")` → `CastSpellByID(id)` → `TargetLastTarget()`
  (or `ClearTarget()`). `TargetUnit` is not protected and is core API; no 20506 addon in this
  workspace needed it, so verify live with a one-liner before relying on it.
- **Combat-safe (also usable in prep):** the secure-button pattern, proven by M6's ActionBook:
  ```lua
  -- M6/Libs/ActionBook/ActionBook.lua:258-263
  sabtHost:SetAttribute("spell-" .. id, spellID)
  sabtHost:SetAttribute("unit-" .. id, unitToken)   -- "party1", "player", ...
  -- then click the SecureActionButtonTemplate button
  ```
  A `SecureActionButtonTemplate` button with `type="spell"`, `spell=<id>`, `unit=<token>` casts
  that spell at that unit. **This is the only casting path that works in combat**, and it needs a
  hardware event per click (see §3).
- **Targeting cursor:** `SpellIsTargeting()` is used on 20506 by ItemRack (ItemRack.lua:1679,
  1690, 1736, 2495, 2515) to detect an active "target a unit" cursor. Its companions
  `SpellCanTargetUnit(unit, spell)` / `SpellTargetUnit(unit)` (finish a cursor-target spell on a
  unit) are classic-era APIs expected to exist — verify live.

### 2.3 Cast lifecycle events (the sequencing hooks)

Registered on 20506 (all in TBC-compatible addons):

| Event | Proven on 20506 | Call site |
|---|---|---|
| `UNIT_SPELLCAST_SENT` | GatherMate2 | Collector.lua:74, handler `(event, unit, target, guid, spellcast)` at :206 |
| `UNIT_SPELLCAST_START` | ItemRack | ItemRack.lua:294, 817 |
| `UNIT_SPELLCAST_STOP` | ItemRack, GatherMate2 | ItemRack.lua:295,818; Collector.lua:75 |
| `UNIT_SPELLCAST_SUCCEEDED` | ItemRack, TrackingEye | ItemRack.lua:296,819; TrackingEye Features/Core.lua:613 |
| `UNIT_SPELLCAST_INTERRUPTED` | ItemRack, GatherMate2 | ItemRack.lua:297,820; Collector.lua:77 |
| `UNIT_SPELLCAST_FAILED` | ItemRack, GatherMate2, M6 | ItemRack.lua:298,821; Collector.lua:76; M6 Rewire.lua:707 |

- **`UNIT_SPELLCAST_SENT` signature on 20506 is modern**: `(unit, target, castGUID, spellID)` —
  GatherMate2 reads the 4th event arg as the spellID and feeds it to `GetSpellInfo`
  (Collector.lua:206-211).
- **`UNIT_SPELLCAST_SUCCEEDED` args are ambiguous on 20506 — verify before building on them.**
  TrackingEye reads `select(2, ...)` as the spellID (Features/Core.lua:613-618) and explicitly
  states its cast bookkeeping is "reliable on every client". The retail signature
  `(unit, castGUID, spellID)` (Wowhead_Looter — retail 11401, NOT proof) differs. **Engineering
  answer: do not consume the event args at all** — use the event only as "the player's cast
  finished", then verify the real state (`UnitCastingInfo("player") == nil`, GCD below). If the
  spellID is needed, dump the args in-game once (see §6 checklist) and pick the position.

### 2.4 "Is a cast happening right now" — `UnitCastingInfo`

```lua
local name, _, texture, _, startTime, endTime, _, notInterruptible, spellId = UnitCastingInfo(unit)
-- position 9 = spellID (BetterBlizzFrames castbar.lua:971 — retail; verify on 20506)
-- position 8 = notInterruptible (used by multiple addons)
```
- TrackingEye uses `UnitCastingInfo("player")` as part of its `CanCast()` gate (Utilities.lua:141).
- BetterFishing uses `UnitChannelInfo("player")` with `select(8, ...)` = spellID (20506,
  BetterFishing.lua:180-182). Classic 9/8-tuple positions work on this client.
- The robust "can I start the next cast now" check (pattern from TrackingEye `CanCast()`):
  not dead/ghost, not stealthed, `not UnitCastingInfo("player")`, `not UnitAffectingCombat("player")`.

### 2.5 Cooldown / global cooldown

```lua
local start, duration, enabled, modRate, active = GetSpellCooldown(spellID)
-- TrackingEye Features/Core.lua:172,302 (start/duration); M6 Handlers.lua:195 (5 values)
```
- **GCD wait pattern:** after an instant cast, `GetSpellCooldown(nextSpellID)` returns a
  `duration` equal to the remaining GCD (~1.5 s) for any spell. Wait until
  `start + duration <= GetTime()` (or `duration == 0`) before casting the next step. TrackingEye
  treats "on GCD" as "on cooldown" (Core.lua:160-167).
- `C_Spell.GetSpellCooldownDuration` / `GetSpellChargeDuration` / `GetSpellDisplayCount` /
  `GetSpellName` exist on 20506 (M6 Handlers.lua:96-100) — modern alternatives, feature-detect.

### 2.6 Items (healthstones, shards)

- `GetItemCount(itemID)` — Gargul BagInspector.lua:76 (20506).
- `UseContainerItem(bag, slot)` with the `UseContainerItem or C_Container.UseContainerItem` shim
  — Gargul Shims.lua:13 (20506). Already used by this addon's `TradeManager`.
- `PickupContainerItem` / `C_Container.PickupContainerItem` — ItemRack ItemRack.lua:92-111 (20506).
- Soul Shard itemID = `6265` (Questie classicItemDB.lua:3824). Create Healthstone = spell `6201`.
- Warlock spellIDs (stable): summon Imp `688`, Voidwalker `697`, Succubus `712`, Felhunter `691`,
  Felguard `30146`; soulstone create spells `693/14298/14299/14300/14301` (already in
  `.ai/CONTEXT.md`). Resolve all names at runtime via `GetSpellInfo`.

### 2.7 Movement (interrupt/resume)

- `IsPlayerMoving()` — used on 20506 by BetterFishing (BetterFishing.lua:182) and M6
  (Conditionals.lua:262).
- `PLAYER_STOPPED_MOVING` event — NovaWorldBuffs.lua:9641/9781 (classic client family; verify).
- A cast-time cast broken by movement fires `UNIT_SPELLCAST_INTERRUPTED` (registered on 20506,
  §2.3) — that is the "something interrupted us" signal.
- Instant self-buffs (Demon Armor/Fel Armor class) do NOT break on movement; the
  "pause when moving" behavior is therefore a design choice enforced by checking
  `IsPlayerMoving()` before each step, not a client hard rule.

### 2.8 Keybindings

Full API works on 20506:

| API | Proven on 20506 | Call site |
|---|---|---|
| `BINDING_HEADER_*` / `BINDING_NAME_*` globals | BetterFishing | BetterFishing.lua:29 |
| `GetBindingKey(binding)` | BetterFishing | BetterFishing.lua:142,297 |
| `SetBinding(key, cmd)` / `GetBindingAction(key)` / `SaveBindings(set)` / `GetCurrentBindingSet()` | GatherMate2 | Config.lua:198-246 |
| `SetBindingClick(key, buttonName)` + hidden `SecureActionButtonTemplate` | ItemRack | ItemRack.lua:2331-2382 |

Two working binding strategies:
1. **In-game Key Bindings UI**: define `BINDING_HEADER_ACP = "ArenaChillPrep"` and
   `BINDING_NAME_ACP_WORKFLOW<N> = "Workflow N"` globals. The player binds keys in the UI.
   Programmatically: `SetBinding(key, "ACP_WORKFLOW1"); SaveBindings(GetCurrentBindingSet())`.
2. **ItemRack-style click bind (robust, in-combat safe)**: create a hidden
   `SecureActionButtonTemplate` button per workflow, `SetBindingClick(key, buttonName)`, and let
   the button's `PreClick` start/resume the workflow. ItemRack's pattern includes
   `RegisterForClicks("AnyDown")` (a keybind delivers both down and up clicks) and
   `SaveBindings(bindingSet)` with a retry while `GetCurrentBindingSet()` is nil (bindings load
   late). This also works as a **click** surface for macros / other addons.

### 2.9 Slash commands as a binding surface

Already the addon's pattern (`/acp`). A workflow can be assigned to a macro:
`/run ACP.Workflows:start(1)` or `/click ACPWorkflowButton1`. Fine out of combat.

---

## 3. Hard limitations on 2.5.6 (what CANNOT be done)

1. **Autonomous multi-step casting during combat is impossible.** All casting entry points
   (`CastSpellByID`, `CastSpellByName`, `UseAction`, insecure `button:Click()`) are **protected**
   during `InCombatLockdown()` — the client blocks them with
   "Interface action failed because of an AddOn". The only combat-safe cast is a
   `SecureActionButtonTemplate` click, and the secure system executes **exactly one action per
   hardware event** (a real key press/click). There is no API to "queue N casts" or to fire a
   secure action from a timer. A `/castsequence`-style macro also needs one press per cast.
   → The described prep workflow runs out of combat, so this limitation does **not** block the
   idea. It DOES mean: never start a workflow step while combat has begun, and if the gates
   open mid-workflow, stop and wait for the next arena.
2. **Auto-accepting a trade remains impossible** (already documented): `AcceptTrade()` is
   restricted on 2.5.x, `C_SecureTransfer` does not exist. Healthstone hand-off keeps the
   current "addon places items, player clicks Trade" flow.
3. **Nothing outside the instance / while dead / while mounted** — workflow should gate on
   arena prep context (existing `ArenaPrep`) + `CanCast()` (§2.4).
4. **Protected targeting edge:** `TargetUnit` itself is usable, but after combat starts the
   workflow must not run at all (see #1), so the restore-target dance only matters during prep.

---

## 4. How it would be built (design sketch, contract-first)

New modules (mirroring the existing architecture; every decision testable in `Tests/`):

### 4.1 `Classes/WorkflowEngine.lua` — step machine

- State: `IDLE → RUNNING → PAUSED → DONE`, reset to `IDLE` on every arena
  (`ACP_BUFF_GAINED` starts it / `ACP_BUFF_LOST` or combat resets it). Progress = a plain
  `stepIndex` **in memory only** (never `ArenaChillPrepDB`) so each arena starts from step 1.
- A workflow = ordered array of **steps** (from `Data/Workflows.lua` + user settings):
  - `{ type = "cast", spell = 687, target = "player"|"party1"|..., optional = true }`
  - `{ type = "summon", pet = "succubus" }` (special-cased cast)
  - `{ type = "createItem", spell = 6201, item = 19008 }` (cast → wait `BAG_UPDATE`)
  - `{ type = "item", action = "use"|"trade", item = 19008 }` (trade delegates to existing `TradeManager`)
  - `{ type = "wait", seconds = N }` / `{ type = "wait", until = "gcd" }`
  - `{ type = "condition", if = "hasShard"|"petAlive"|"notMoving", skipTo = N }`
- Per-step gates before casting (each is a 20506-proven call):
  `IsPlayerSpell`, `IsUsableSpell`, `IsSpellInRange(spell, target)`,
  `GetSpellCooldown(spell)` GCD check, `UnitCastingInfo("player") == nil`, `IsPlayerMoving()`.
  Any gate fails → mark `PAUSED` at this step index (do not skip silently; `optional` steps may skip).
- **Advance protocol** (event-driven, no fixed sleeps):
  1. Set target (self / `TargetUnit` + cast + restore).
  2. `CastSpellByID(spellID)` (or the M6 secure-attribute path if we later support combat steps).
  3. Wait for `UNIT_SPELLCAST_SUCCEEDED` on `"player"` **as a signal only** (ignore args, §2.3)
     OR `UNIT_SPELLCAST_STOP` for instant spells that never fire SUCCEEDED (verify which fires).
  4. If `UNIT_SPELLCAST_INTERRUPTED` / `FAILED` → `PAUSED` at this step.
  5. Before the next step: wait out the GCD via `GetSpellCooldown(nextStep.spell)`.
- **Resume** on button press: re-run gates for the current step, continue.
- Internal events via the existing bus: `ACP_WORKFLOW_STARTED/STEP/PAUSED/DONE`.

### 4.2 `Data/Workflows.lua` — warlock presets + schema

- Warlock preset (build-time, spell names resolved via `GetSpellInfo`): Demon Armor → self,
  Summon <pet>, Create Healthstone ×N, then the existing autotrade takes over, or an explicit
  `item.trade` step. Soul Shard count (`GetItemCount(6265)`) gates summon/stone steps.
- User workflows stored under settings (dot-path, mirroring `items.*`); multi-workflow support =
  `workflows = { [1] = {...}, [2] = {...} }`.

### 4.3 Binding + trigger

- One global per workflow: `BINDING_HEADER_ACP`, `BINDING_NAME_ACP_WORKFLOW1..N`; the handler
  toggles start/resume. Optional ItemRack-style `SetBindingClick` hidden buttons for
  macro/click-driven start (the pattern in §2.8.2).

### 4.4 Reuse

- `ArenaPrep` (buff/bracket/countdown/combat context), `Events`, `Utils/Timers` (named timers —
  remember the unreliable-`Cancel()` gotcha), `Inventory` (shard/stone counts), `TradeManager`
  (hand-off). The engine itself is pure logic → unit-testable under LuaJIT like
  `DeliveryController` (steps as data, fake `CastSpellByID`/`GetSpellCooldown` in `wow_stubs`).

---

## 5. What the working addons prove (evidence index)

| Fact | Addon (Interface 20506 unless noted) | File:line |
|---|---|---|
| `CastSpellByID` casts out of combat | TrackingEye | Features/Core.lua:187 |
| `GetSpellCooldown` 2/5-value shape | TrackingEye / M6 | Features/Core.lua:172 · Handlers.lua:195 |
| `UNIT_SPELLCAST_SENT` modern signature | GatherMate2 | Collector.lua:74,206 |
| `UNIT_SPELLCAST_*` registered | ItemRack, GatherMate2, M6 | ItemRack.lua:294-298,817-821 · Collector.lua:74-77 · Rewire.lua:707 |
| `UNIT_SPELLCAST_SUCCEEDED` arg2=spellID | TrackingEye (args ambiguous, §2.3) | Features/Core.lua:613 |
| `SpellIsTargeting()` | ItemRack | ItemRack.lua:1679,2495 |
| Secure `spell`+`unit` attribute cast | M6 | Libs/ActionBook/ActionBook.lua:258-263 |
| `IsPlayerMoving()` | BetterFishing, M6 | BetterFishing.lua:182 · Conditionals.lua:262 |
| `UnitChannelInfo` spellID at pos 8 | BetterFishing | BetterFishing.lua:180 |
| `GetBindingKey` / `BINDING_NAME_*` | BetterFishing | BetterFishing.lua:29,142 |
| `SetBinding` / `GetBindingAction` / `SaveBindings` | GatherMate2 | Config.lua:198-246 |
| `SetBindingClick` + secure button | ItemRack | ItemRack.lua:2331-2382 |
| `GetItemCount` / `UseContainerItem` | Gargul | BagInspector.lua:76 · Shims.lua:13 |
| Soul Shard item 6265 | Questie (item DB) | classicItemDB.lua:3824 |

Not treated as proof (different interface): BetterBlizzFrames (`120007`, retail), Details
(`120007`), Wowhead_Looter (`11401`), WeakAuras (`40402`), OmniCD (`40402`), SoulShardManager /
SoulSort (Era `11305`/`11502`) — the last two are still useful as *functionality* prior art for
warlock shard automation, but their API calls must be re-verified on 20506.

---

## 6. Verification checklist (in-game, before building the engine)

Run with `/console scriptErrors 1` and a temporary debug dump (see the `debug-cycle` skill).

1. **`UNIT_SPELLCAST_SUCCEEDED` args** — log `...` for a self-cast → resolve the spellID
   position (arg 2 vs arg 3). Decide the advance signal accordingly.
2. **`UNIT_SPELLCAST_STOP` vs `SUCCEEDED` for instant spells** — cast an instant buff and record
   which events fire and in what order.
3. **`TargetUnit` + cast + `TargetLastTarget`** during prep (out of combat) — confirm target
   restoration and that a party-buff casts on the right member.
4. **`CastSpellByID(spellID, "party1")`** — does the optional target arg do anything on this
   client? (Likely ignored; do not build on it.)
5. **`SpellCanTargetUnit` / `SpellTargetUnit`** — exist and finish a cursor-target cast on a unit.
6. **`GetSpellCooldown` return arity** and GCD shape after an instant cast (~1.5 s).
7. **Keybinding dispatch** — `SetBinding("M","ACP_WORKFLOW1"); SaveBindings(1)` then press M:
   confirm the binding runs the global handler.
8. **`CastSpellByID(6201)`** with and without a Soul Shard → confirm the expected
   failure/behavior so the engine can log it instead of stalling.
9. **Pet summon out of combat** — `CastSpellByID(688)` while prep is active.
10. **Combat cut-off** — confirm that once `InCombatLockdown()` is true, no step fires (expected).

---

## 7. Open decisions (for a later phase)

- Advance signal: `UNIT_SPELLCAST_STOP` for everything vs `SUCCEEDED`+timeout — depends on #1/#2 above.
- Targeted casts: `TargetUnit` dance vs M6-style secure `unit` attribute (secure path also
  enables optional in-combat single casts later).
- Overlap with autotrade: does a workflow's stone step hand over via the existing
  `DeliveryController`, or does the workflow own its trade steps? (Recommend: workflow casts +
  counts, delivery stays in `DeliveryController`.)
- `optional` step semantics and per-workflow "skip if already buffed" rules (checked via
  `C_UnitAuras.GetPlayerAuraBySpellID`, the proven 20506 aura API).