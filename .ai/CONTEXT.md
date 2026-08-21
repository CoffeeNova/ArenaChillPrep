# ArenaChillPrep — Context (for AI agents)

> Source of truth: this directory (`.ai/`). Entry point: `AGENTS.md` at the repo root.
> This file is the main source of context when working on the addon. **Read `ARCHITECTURE.md` before changing any code.**

**Current status:** v0.1 in development — Warlock only (Soulstones of all ranks).

---

## What the addon does

While the arena preparation buff is active, the addon will:

1. **Determine the player's class** and the list of items that class can pass (currently — Warlock → soulstones only).
2. **Check the arena bracket** (2v2 / 3v3 / 5v5) against the per-bracket setting — by default the addon only works in **2v2**.
3. **Scan the bags** for the required items and count them (stack-aware).
4. **As soon as the required amount of items appears in the bags** (or was already there when preparation started) — **automatically open the trade window** with the partner.
5. **Place the items into the trade slots** (up to `MAX_TRADABLE_ITEMS` per trade).
6. **The player confirms the trade manually.** There is no auto-accept: `AcceptTrade()` is restricted on 2.5.x (requires a hardware event), so a programmatic call or `button:Click()` is silently blocked by the client. The addon places the items; the player clicks "Trade".
7. **Remembers which partners already received items** this prep — never trades with the same player twice.
8. **Stops trading N seconds before the gates open** (`gateSafetySeconds`, default 15).

### Important to understand

- The addon works **only while the arena preparation buff is active**. Outside an arena it is completely idle.
- The addon **does not craft items itself** (no spell casts). It waits for the player (or another addon) to craft the item, catches the moment the item appears in the bags (`BAG_UPDATE`) and immediately starts the trade.
- The addon never cancels a trade and never sends gold — items only.

---

## Technical data (TBC Anniversary)

| Entity | Value |
|---|---|
| Game version | TBC Anniversary (2.5.x), Interface `20506` |
| Preparation buff | Spell **32727** — "Arena Preparation" |
| Location requirement | Instance of type `arena` (`IsInInstance()`, `GetInstanceInfo()`) |
| Bracket detection | Party size `GetNumPartyMembers() + 1` (2/3/5), cross-checked with `GetNumArenaOpponents()` (available since 2.5.1) |
| Trade slots | `MAX_TRADABLE_ITEMS` (6 in TBC), slots `TRADE_PLAYER_ITEM_1..6` |

### Soulstones (Warlock)

| Rank | Item | Item ID | Create spell | Learned at |
|---|---|---|---|---|
| 1 | Minor Soulstone | `16892` | 693 | 14 |
| 2 | Lesser Soulstone | `16893` | 14298 | 28 |
| 3 | Soulstone | `16894` | 14299 | 42 |
| 4 | Greater Soulstone | `16895` | 14300 | 56 |
| 5 | Major Soulstone | `22103` | 14301 | 70 |

---

## Project structure

```
ArenaChillPrep/
├── AGENTS.md                 # Agent entry point → read .ai/ (this directory)
├── ArenaChillPrep.toc        # TOC (Interface: 20506, SavedVariables: ArenaChillPrepDB)
├── bootstrap.lua             # Entry point: global ACP table, event frame, initialization
├── README.md                 # Human-facing description (users) — not technical docs
├── .ai/                  # Agent documentation & instructions (source of truth)
│   ├── CONTEXT.md            # This file: context, conventions, gotchas, settings
│   └── ARCHITECTURE.md       # Architecture: modules, data flow, state machine
├── Data/                     # Static data
│   ├── Constants.lua         # Buff ID, constants, timings, bracket size map
│   ├── Items.lua             # Item catalog + class → items mapping
│   ├── DefaultSettings.lua   # SavedVariables defaults
│   └── Localization.lua      # Strings (enUS / ruRU)
├── Classes/                  # Service modules
│   ├── Events.lua            # Event frame wrapper
│   ├── ArenaPrep.lua         # Prep buff detection, bracket detection, remaining time
│   ├── Inventory.lua         # Bag scan, counters, BAG_UPDATE subscription
│   ├── DeliveryController.lua# Orchestrator: prep → wait for items → trade
│   ├── TradeManager.lua      # Trade window automation
│   ├── Settings.lua          # SavedVariables wrapper
│   ├── WorkflowSpellbook.lua # Per-character spellbook scan + rank groups
│   ├── UI/
│   │   ├── Widgets.lua       # Reusable options widgets (ACP.UI.*: Box/Header/Divider/
│   │   │                     #   Checkbox/Slider/Button/StatusLine/Dropdown/TextInput/
│   │   │                     #   ScrollFrame + geometry constants)
│   │   └── WorkflowUI.lua    # "Workflows" subcategory content (ACP.WorkflowUI)
│   └── OptionsUI.lua         # Interface Options panel + /acp slash command
└── Utils/                    # Utilities
    ├── Items.lua             # Item helpers (find by ID, counters, bag search)
    ├── Tables.lua            # Table helpers
    └── Timers.lua            # Named timers via C_Timer (after/interval/cancel)
Tests/                        # Unit tests (run OUTSIDE the game under LuaJIT)
    ├── run_tests.lua         # Runner: luacov + luaunit + WoW stubs + loader
    ├── run-tests.ps1         # PowerShell wrapper (exit 0 = pass + coverage ≥ 90%)
    ├── loader.lua            # Loads all modules in TOC order via the vararg chain
    ├── helpers.lua           # SyncTimers recorder, deepCopy, resetAll (singleton)
    ├── stubs/wow_stubs.lua   # WoW API stubs (mutable state in _G.__stub)
    ├── lib/                  # Vendored: luaunit 3.5 + luacov 0.17
    ├── test_bootstrap.lua    # bootstrap suite (mirrors the addon root)
    ├── Data/                 # Suites mirror the addon structure
    │   └── test_*.lua        #   constants, items, defaultsettings, localization
    ├── Utils/
    │   └── test_*.lua        #   tables, items, timers
    └── Classes/
        └── test_*.lua        #   events, settings, arenaprep, inventory,
                              #   deliverycontroller, trademanager
```

---

## Development environment (where the WoW client lives)

This repo is developed **outside** the game client. The WoW TBC Anniversary client
with its addons is a separate folder on the machine — it is NOT part of this repo
and its path must never be hardcoded here.

- The client's AddOns folder is configured in **`.env`** at the repo root
  (copy `.env.example` → `.env`), variable **`addons_path_anniversary`**,
  e.g. `addons_path_anniversary=G:\games\World of Warcraft\_anniversary_\Interface\AddOns`.
- `.env` is git-ignored (machine-specific). `.env.example` documents the variable.
- Scripts that need the path read it from the environment:
  - `tools/research.ps1` — searches the working addons (default root = `$env:addons_path_anniversary`, override with `-Root`).
  - `tools/load-env.ps1` — loads `.env` into the session (dot-source it: `. .\.ai\tools\load-env.ps1`).
  - `tools/deploy.ps1` — deploys the addon to the client (see below).
- To test in game: run `tools/deploy.ps1` — it copies **only the game artifacts**
  (the `.toc` + every file it references + `LICENSE`) into `%addons_path_anniversary%\ArenaChillPrep`,
  keeping the repo clean of client files. The old full-repo copy in the client folder
  (left over from before the migration) can be deleted — `deploy.ps1` recreates a clean folder.

## Release bundle (CurseForge / CI)

`tools/deploy.ps1 -Bundle` builds a release zip in `dist/` (git-ignored) named
`<addon>-<version>.zip` (version read from the `.toc`). The zip contains exactly
the game artifacts — the same file set as a client deploy — so it can be uploaded
to CurseForge or used by a CI pipeline. `dist/` is never committed.

---

## Code conventions

- **Lua 5.1**, no external libraries (no Ace — the addon is self-contained).
- Every file is a module table. The addon's global table is `ACP` (ArenaChillPrep).
- Modules receive the `ACP` reference via vararg: `local _, ACP = ...;`.
- Style follows the **Gargul** addon (same workspace): `---@class` annotations, `_G.` prefix for global APIs, local aliases for globals at the top of the file.
- UI strings go through `Data/Localization.lua` (table `L`, metatable fallback to the key, like `Gargul_L`).
- Cross-session state only via `ArenaChillPrepDB` (SavedVariables), accessed through `ACP.Settings`.

---

## Unit tests (run outside the game)

The addon has an automated unit-test suite in `Tests/` that runs under **LuaJIT** (Lua 5.1 — the same version WoW uses), so no game client is needed. It covers **all non-UI modules** (bootstrap, Data, Utils, and the Classes logic) with **96%+ line coverage**; `OptionsUI.lua` is excluded (UI code — checkboxes/forms/labels).

**Run:** `.\Tests\run-tests.ps1` (or `luajit Tests\run_tests.lua` from the addon root). Requires LuaJIT on PATH (`winget install DEVCOM.LuaJIT`). Exit codes: `0` = pass + coverage ≥ 90%, `1` = test failures, `2` = coverage < 90%. Report: `Tests/luacov.report.out`.

**How it works:**

- `Tests/stubs/wow_stubs.lua` stubs the WoW API. Mutable state lives in `_G.__stub` (time, instance, aura, party size, combat, bags, chat). File-scope captures (e.g. `GetTime`, `C_UnitAuras`, `TradeFrame`) read `_G.__stub`; call-time reads can be overridden directly.
- `Tests/loader.lua` loads every module in TOC order through the vararg chain.
- `Tests/helpers.lua` is a **singleton** (`_G.__TEST_HELPERS`) providing `SyncTimers` (a synchronous timer recorder — callbacks are stored, advanced explicitly via `H.advance(name)`), `deepCopy`, `reloadModule`, and `resetAll()` (re-inits ALL modules + wipes the event bus).
- Each `Tests/<Data|Utils|Classes>/test_<module>.lua` (mirroring the addon structure; `test_bootstrap.lua` at the root) defines global `test*` functions; luaunit discovers them **alphabetically across all suites**.

**Gotchas when writing tests (see repo memory `arena-chill-prep-tests.md` for the full list):**

- luaunit runs tests alphabetically across suites — every test must restore what it mutates (Settings DB, module state, globals, event bus).
- `Settings:_init` deep-copies the defaults (the live `Data` is fully detached from `ACP.Data.DefaultSettings` — a historical shallow copy shared nested tables and could corrupt the defaults via `Settings:set`). Settings tests restore pristine defaults before each test.
- Event-driven tests must call `H.resetAll()` first (events cascade across modules, e.g. `BAG_UPDATE` → `ACP_ITEMS_CHANGED` → DeliveryController).
- `C_Container.GetContainerItemInfo` returns a TABLE; the legacy global returns the 11-value tuple — stubs must provide both.
- `Utils/Items` prefers the GLOBAL `GetContainerNumSlots` but `C_Container` for `GetContainerItemInfo` — override all four container functions in bag stubs.
- **New suites must be added to the `suites` list in `Tests/run_tests.lua`** — luaunit only runs suites it lists; an unlisted (but committed) suite silently never executes, so a broken module can pass the suite.
- **`if (pcall(fn, ...)) then` is a bug** — `pcall` returns `(ok, result)`; an `if` only sees the first value (`ok`), so the branch fires whenever `fn` is callable regardless of its result. Capture the result: `local ok, res = pcall(fn, ...); if (ok and res) then`.
- **A `function X:y()` written inside another method body is valid Lua** (it assigns `X.y` at runtime, not at load) and passes syntax-check; the method stays `nil` until that outer method executes. Keep all methods top-level.

---

## Key mechanics and gotchas

1. **Prep buff detection.** TBC has no `PLAYER_AURA` event — use `UNIT_AURA` with the `"player"` unit filter plus a check on `PLAYER_ENTERING_WORLD`. **Verified on 2.5.5:** use `C_UnitAuras.GetPlayerAuraBySpellID(32727)` — returns an object, works reliably (sArena_Reloaded uses exactly this). Do **not** use `UnitBuff("player", name)` (crashes — the deprecated wrapper proxies to `C_UnitAuras.GetBuffDataByIndex` which only accepts a numeric index) or `UnitAura(unit, i, filter)` (returns shifted legacy positions; spellID/expirationTime are never captured on this client).
2. **Trading in TBC.** `InitiateTrade(unit)` only works out of combat and within range. Window events: `TRADE_SHOW` / `TRADE_CLOSED` / `TRADE_ACCEPT_UPDATE`. Don't forget the `TRADE_CLOSED` branch: if the partner cancelled — retry with backoff.
3. **Combat.** Trading is impossible in combat. Listen to `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` and defer attempts. There is no combat during preparation, but the item may be crafted after combat started — the trade attempt must silently fail and retry later.
4. **Item counting.** Soulstones stack (up to 10). The counter = sum of `stackCount` across all bags/slots for the given itemID.
5. **One trade per prep.** One player = one trade per preparation. After a successful trade the state is `DONE` until the end of the current buff. A new buff (new arena) resets it.
6. **Diagnostics.** All actions are logged to chat via a utility (`ACP:` prefix) so the player can see why the addon is waiting or skipped a trade. No file logging in v0.1 — chat only.
7. **Item placement.** Use `UseContainerItem(bag, slot)` while the trade window is open — the game auto-places the item into the next available trade slot. No `PickupContainerItem` + `ClickTradeButton` needed.
8. **Place items one at a time.** The game can silently remove items added to the trade window too rapidly. Use a FIFO queue processed by a short repeating ticker, plus an `ITEM_UNLOCKED` re-add for the rare cases where the game still removes an item (added < 0.5 s ago).
9. **Completion detection.** A trade completes when `UI_INFO_MESSAGE` fires with `ERR_TRADE_COMPLETE`. `TRADE_CLOSED` fires before the completion message, so on its own it means failure, not success.
10. **Timers without Ace.** `C_Timer.After` / `C_Timer.NewTicker` are available on TBC Anniversary (20506) — use them (via a small named-timer helper) instead of Ace timers. **Verified 2026-08-10: a C_Timer handle's `Cancel()` is UNRELIABLE on this client — a "cancelled" timer can still fire.** A cancelled `TradeOpen` timer fired after `TRADE_SHOW` (false "window did not open" timeout that cancelled a live trade and lost the partner attribution → repeat trades) and a cancelled poll ticker kept re-trading with no backoff. Fix pattern (AceTimer's — see `Utils/Timers.lua`): each named timer stores `{active = true, handle}`; `cancel()` flags it inactive and removes it; the C_Timer callback bails unless `active` and the entry is still the one registered under the name. `handle:Cancel()` is best-effort only. Always guard timeouts by checking the real state (e.g. `TradeFrame:IsShown()`) before acting.
11. **Bracket detection.** An addon **can** determine the bracket. Primary signal: your party size in the arena — in TBC you must queue with a group of exactly the bracket size, so `GetNumPartyMembers() + 1` is `2`, `3` or `5` (and the group is locked once inside, so it's stable during prep). Cross-check when available (client ≥ 2.5.1): `GetNumArenaOpponents() + 1` — number of opponents (1/2/4); it may return `0` briefly at arena load, hence the fallback. Note: the API is `GetNumPartyMembers` in TBC — `GetNumSubgroupMembers` only exists from 5.0.4+.
12. **Gate-open countdown — use `CHAT_MSG_BG_SYSTEM_NEUTRAL`, not the aura.** Verified on 2.5.5: the prep buff's aura reports `duration=0` / `expirationTime=0` (treated as infinite), so `expirationTime - GetTime()` is useless. The working approach — proven by ArenaAnalytics and sArena_Reloaded on the same client — is listening to `CHAT_MSG_BG_SYSTEM_NEUTRAL` and matching the localized countdown messages ("One minute until the Arena battle begins!" = 60, "Thirty seconds..." = 30, "Fifteen seconds..." = 15, "The Arena battle has begun!" = 0; the map lives in `ACP.Data.Constants.ARENA_COUNTDOWN_MESSAGES`). Track `countdownEndTime = GetTime() + N`, seeded with `+60 s` on buff gain as a fallback. `GetBattlefieldTimeRemaining()` is a battleground match timer, not the pre-gate countdown.
13. **One trade per partner, not per prep.** The addon keeps a runtime `givenTo` set (reset on `ACP_BUFF_LOST`) of partners who already received items and never re-trades with them. In 2v2 this means one trade per prep; in 3v3/5v5 a newly crafted item goes to the next eligible partner. `givenTo` is runtime-only — never persist it to `ArenaChillPrepDB`.
14. **Workflow step targeting (verified 2026-08-22).** Party-targeted workflow steps cast DIRECTLY at the unit — never through the player's current target or `TargetUnit` token swaps (that path buffed the PLAYER live, and calling `TargetUnit` from insecure code popped "blocked action" on the first party cast — it was removed). Player spells: the secure cast button gets `SetAttribute("unit", step.target)` (M6 ActionBook pattern); pet abilities: `[@unit]` macro conditionals (`/cast [@party1] Fire Shield` — the legacy `[target=party1]` form does not redirect pet casts on 20506); `checkGates` pauses with `reasonNoTarget` when the unit doesn't exist (solo test, raid group, member left) instead of mis-buffing. Always reset the `unit` attribute in `clearKeyCast`/`equipItem`/`petAbility` — a stale party unit retargets later steps.
15. **One run per prep/test.** After DONE the workflow key is a no-op — the engine never auto-restarts. A fresh run starts on `ACP_BUFF_LOST` (new arena) or by re-issuing `/acp workflowtest N` (the command calls `reset()` before `start()`).
16. **One press = start + cast (verified design 2026-08-22).** Each workflow slot's Key Bindings UI key is pointed at a per-slot hidden secure button `ACPWorkflowButton<N>` via `SetOverrideBindingClick(owner, true, key, button)` — a priority override (BetterFishing pattern on 20506) that does **NOT displace the player's command binding**: `GetBindingKey` keeps returning the real binding, so the Blizzard Key Bindings UI and the Workflows-tab key capture keep working (the earlier transient `SetBindingClick` takeover broke key assignment entirely and was removed). The button's **PreClick** starts/resumes the workflow and arms the step, and the SAME press's click casts it. `applySlotBindings` (full resync: clear overrides → re-apply from the real binding table) runs on PLAYER_LOGIN / UPDATE_BINDINGS / PLAYER_REGEN_ENABLED / late-binding retry; overrides are dropped while the Blizzard Key Bindings UI is shown. Pet macros bake `/cast [pet:<type>,@unit] <ability>` — the `[pet:<type>]` conditional makes a press a no-op when that pet is not out (no interruption/"blocked action"), which is how Sacrifice is pressed during the Summon Felhunter cast.
17. **Workflow chat messages are debug-only.** started/resumed/paused/done, press prompts, pause reasons and the cast-dropped diagnostic all go through `ACP:debugPrint` (`/acp debug` to see them); `/acp status` and slash-command responses stay visible.
18. **Pet-ability verification (2026-08-22).** The client silently swallows a pet ability pressed EARLY in the player's cast (Sacrifice at +2s of a 6s summon did nothing; +5s fired, live-verified). The engine does NOT mark the pet step done on the press itself — `isPetAbilityApplied(step)` checks the ability's effect (buff present on the target by NAME, e.g. Fire Shield / Sacrifice shield, or the Voidwalker gone while the cast is in progress); an unverified press keeps the step armed (`armPetVerify` poll every 0.1s) — the user spams the key until the ability finally applies near the end of the cast.

---

## Proven patterns (researched from Gargul)

Gargul (same workspace) already implements exactly this flow — opening a trade with another player and auto-placing items into it. ArenaChillPrep's `TradeManager` is a dependency-free port of these patterns (verified against `Gargul/Classes/TradeWindow.lua`):

- **Open with callback + timeout.** `TradeWindow:open(playerName, callback, alwaysExecuteCallback)` registers a one-shot listener for the trade-window-shown event with a 1-second timeout: if the window doesn't open in time, the callback fires with `success = false`. This drives ArenaChillPrep's retry logic.
- **Partner verification.** On `TRADE_SHOW`, the partner is read from `UnitName("NPC", true)` and the `TradeFrameRecipientNameText` text field (sanitized); the callback receives whether it matches the requested name (handles `Name-Realm`).
- **Skip soulbound.** When searching bags for an item to add, items with no trade time remaining (soulbound) are skipped (`findBagIdAndSlotForItem(linkOrID, skipSoulbound = true)`).
- **`ITEM_UNLOCKED` re-add.** The game can auto-remove an item from the trade window if items were added too rapidly. If an item unlocks within 0.5 s of being added, Gargul re-queues it.
- **State per trade.** `updateState()` snapshots partner, per-slot items (`GetTradePlayerItemInfo/Link`, `GetTradeTargetItemInfo/Link`) and gold; custom events (`GL.TRADE_SHOW`, `GL.TRADE_COMPLETED`, ...) fire afterwards so listeners get the data.
- **Container access shim.** `GL:getContainerItemInfo(bag, slot)` handles both `C_Container.GetContainerItemInfo` and the legacy `GetContainerItemInfo` — the same shim is needed for TBC Anniversary.

---

## Slash commands

| Command | Action |
|---|---|
| `/acp` | Open settings (Interface Options panel) |
| `/acp enable` / `/acp disable` | Enable/disable the addon |
| `/acp status` | Show current state (buff active, **bracket**, items found, partner) |
| `/acp debug` | Toggle verbose logging |

---

## Settings (v0.1)

The Interface Options panel is a top-level category **ArenaChillPrep** with three tabbed
subcategories (built with `Settings.RegisterCanvasLayoutSubcategory` — the legacy
`InterfaceOptions_AddCategory` is nil on 2.5.5):

- **General** — master switch (`enabled`), the **"Enable workflow engine"** switch
  (`workflows.enabled`) and the **"Reset to defaults"** button (`ACP.Settings:reset()`).
- **Workflows** — stored in `ArenaChillPrepCharDB`, so each character has an independent
  workflow profile. Built around the "pick a slot → assemble/check the sequence → fire by key"
  scenario: a status line on top (engine state + slot state + step count; the bound key is
  shown ONLY in the editable Key field below — no duplicate status strings; when the global
  engine is OFF it explains why and offers an "Enable workflow engine" CTA button — the tab
  does NOT gray out), a **Workflow defaults** block (`skipIfBuffedDefault` + short
  description; movement pause is always enforced and is not configurable), a **Workflow
  editor** block (labeled `Workflow:` selector + `+ Add workflow`, `Name:` input + `Enabled`
  checkbox, `Key:` keybind capture + `Clear` button with unbound/capturing/bound visual
  states), and a **Steps** table that fills the remaining panel height (table header +
  scrollable rows: two-line spell cell with name + `SpellID: <id>` (pet-ability steps show a `pet ability` hint), fixed Target and
  "Skip if buffed" columns that render an explicit `Not available` state when a parameter
  does not apply, right-aligned `↑`/`↓`/`Delete` actions). `equipItem` rows show the item
  name + `ItemID: <id>` instead (no rank/target/skip). "+ Add step" lists each learned
  spell as a plain name (no rank/SpellID decoration) grouped by category, built from a
  scan of the ACTIVE character's spellbook (never a hardcoded class list — the Warlock
  static fallback is class-gated and the scan re-runs on PLAYER_LOGIN + SPELLS_CHANGED);
  the **Pet abilities** category (Fire Shield [Imp, party-castable], Sacrifice [Voidwalker]) and the **Equip items** category
  (spellstones → `equipItem` steps) appear only for Warlocks, and stone-creating spells are
  listed per rank with the stone's name (`Create Master Healthstone`, `Create Major
  Healthstone`, …); every step uses the highest learned rank (no rank selection — the old
  per-step rank dropdown was removed). Five slots exist by default; `+ Add workflow` adds slots up
  to the bindable maximum. Slots 1-2 ship pre-defined with the user's m6 arena-prep
  macros as steps (slot 1 "2s full prep": Imp → HS → Spellstone → Felhunter → Soul Link →
  HS → Fel Armor → UB/DI x2 → equip Master Spellstone; slot 2 "Full prep (Voidwalker)":
  same without Soul Link, Voidwalker instead of Felhunter; duplicate Create Healthstone
  macro entries are stored as 27230/22105 (the max rank), and they complete instantly once
  the Master stone is in bags. On TBC 2.5.5 the stone ranks COEXIST (a Warlock can create
  each rank; the client does NOT auto-upgrade a rank-5 cast), so a step stores its exact
  rank and is "done" only when THAT rank's stone is present). Healthstone ranks 1-5 exist
  as historical ID PAIRS (e.g. Major = 19012/19013 — see `Data/Items.lua`); the client
  conjures one variant per rank (rank 5 = 19013, live-verified 2026-08-22), so the
  engine's createItem completion/goal-met checks accept BOTH variants of the step's rank
  (`stoneRanks[spellID].itemIDs`) — but never a different rank's stone.
  Layout uses a vertical cursor (each section returns its own height) so it adapts to the
  actual panel size — no hardcoded offsets. Built by `Classes/UI/WorkflowUI.lua` and
  `Classes/WorkflowSpellbook.lua`
  (`ACP.WorkflowUI`); all edits write to Settings immediately.
- **Autotrade** — two columns: left = bracket checkboxes (2v2 active; 3v3/5v5 permanently disabled) + timing sliders with a header divider between them; right = rank checkboxes.
- Every control has a tooltip; all strings go through `Data/Localization.lua`. Turning the
  master switch off grays out all Autotrade controls; turning the workflow engine off shows
  a status warning + an "Enable workflow engine" CTA on the Workflows tab (controls stay
  editable — edits persist regardless of the gate).
- Control creation lives in `Classes/UI/Widgets.lua` (`ACP.UI.*`, vanilla API only) — see
  `ARCHITECTURE.md` §2.8.

```lua
ArenaChillPrepDB = {
    enabled        = true,   -- master switch
    partnerMode    = "auto", -- "auto" | "party1" (explicit party slot)
    manualPartner  = "party1",
    tradeDelay     = 1.5,    -- seconds between item appearing and opening the trade
    gateSafetySeconds = 15,  -- stop all trading N seconds before the gates open
    brackets = {             -- which arena brackets auto-trade is active in
        ["2v2"] = true,      -- default: 2v2 only
        ["3v3"] = false,
        ["5v5"] = false,
    },
    items = {
        soulstone = {
            enabled = true,  -- pass soulstones
            count   = 1,     -- how many per trade
            ranks   = { [22103] = true }, -- which ranks to consider (by itemID)
        },
    },
}
```

`Settings:reset()` restores a deep copy of `ACP.Data.DefaultSettings` and re-syncs the panel.
Account-wide settings remain in `ArenaChillPrepDB`; workflow settings are routed through
`ACP.Settings` to `ArenaChillPrepCharDB.workflows` and migrate from the old account-wide
`ArenaChillPrepDB.workflows` table on first load. `workflows.slotCount` starts at 5; new
slots are created empty. `WORKFLOW_MAX_SLOTS` is the fixed binding capacity, while the UI
only renders slots up to the current character's `slotCount`.
The workflows branch merges **per-slot replace** (a saved `definitions[N]` wins wholesale —
deepMerge would index-merge the steps arrays into hybrids), `ensureDefaults` is array-aware,
and saved definitions that still match the OLD placeholder defaults exactly are replaced by
the new m6-macro defaults on load (user edits are never touched).
`Utils/Tables` provides `deepCopy`/`deepMerge`/`shallowCopy`.
