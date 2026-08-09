# ArenaChillPrep — v0.1 Development Plan (first version)

> **Archived — starting point for v0.1 only.** This is the initial development plan that was used to build the **first version** of the addon. It is intentionally **not referenced** by the current agent workflow (`AGENTS.md`, `.github/`) — treat it as historical context.

**Target version:** v0.1 — Warlock only (Healthstones of all ranks) and passing them to a partner during arena preparation.

**Game:** WoW TBC Anniversary, Interface `20506`.

> Rule: every phase ends with a working build that can be loaded in game (`/reload`) and verified. Don't move to the next phase until the Definition of Done is met.

---

## Phase 0 — Scaffold and data

**Goal:** the addon loads without errors; the file structure and static data exist.

### Tasks

- [x] `ArenaChillPrep.toc`:
  - `## Interface: 20506`
  - `## Title`, `## Notes`, `## Version: 0.1.0`, `## SavedVariables: ArenaChillPrepDB`
  - File order: `bootstrap.lua` → `Data/*` → `Utils/*` → `Classes/*` (load order matters — no libraries).
- [x] `bootstrap.lua`:
  - Global `ACP` table (`_G.ArenaChillPrep = ACP` or `_G.ACP`).
  - Invisible event frame `ACP.Frame`.
  - `ADDON_LOADED` → module init in the order from ARCHITECTURE.md (2.1).
  - Stub modules (each file exists, `_init()` empty).
- [x] `Data/Constants.lua`: `ACP.Data.Constants.ARENA_PREP_SPELL_ID = 32727`, `MAX_TRADE_RETRIES = 3`, timings.
- [x] `Data/Items.lua`: healthstone catalog `19004/19005/19006/19007/19008/19009` + `classItems[CLASS_WARLOCK]`.
- [x] `Data/DefaultSettings.lua`: settings structure (see `.github/CONTEXT.md`), including `gateSafetySeconds = 15`.
- [x] `Data/Localization.lua`: `L` table (enUS + ruRU minimum).
- [x] `Utils/Tables.lua`, `Utils/Items.lua`, `Utils/Timers.lua` (basic helpers + named timers via `C_Timer`).

### Definition of Done

- `/reload` — no Lua errors (check via `/console scriptErrors 1`).
- A service message `ACP v0.1.0 loaded` appears in chat on load (remove or keep in debug mode).
- `/acp status` prints "initialized: false, state: IDLE" (no crashes).

---

## Phase 1 — Arena preparation detection

**Goal:** the addon correctly detects the `Arena Preparation` buff.

### Tasks

- [x] `Classes/ArenaPrep.lua`:
  - `isActive()`, `checkNow()`.
  - Buff lookup — **verified on 2.5.5**: `C_UnitAuras.GetPlayerAuraBySpellID(32727)` (returns an object; sArena_Reloaded uses it). Do **not** use `UnitBuff("player", name)` (crashes — deprecated wrapper accepts only a numeric index) nor `UnitAura(unit, i, filter)` (returns shifted legacy positions, no spellID/expirationTime).
  - Listeners: `UNIT_AURA` (filter `"player"`), `PLAYER_ENTERING_WORLD`.
  - 1 s ticker while the buff is active (safety against a missed buff fade).
  - Events `ACP_BUFF_GAINED` / `ACP_BUFF_LOST`.
  - `getBracket()`: `GetNumPartyMembers() + 1` → `"2v2"/"3v3"/"5v5"` (`{ [2] = "2v2", [3] = "3v3", [5] = "5v5" }`, else `nil`); cross-check with `GetNumArenaOpponents()` when available (feature-detect; present since 2.5.1, 20506 ≥ 2.5.1). Shim `GetNumPartyMembers or GetNumSubgroupMembers`.
  - `getRemainingTime()`: seconds until the gates open — **verified on 2.5.5**: the prep buff aura reports `duration=0`/`expirationTime=0`, so the countdown comes from `CHAT_MSG_BG_SYSTEM_NEUTRAL` + localized message map (`ACP.Data.Constants.ARENA_COUNTDOWN_MESSAGES`, seeded with `ARENA_PREP_SECONDS` on buff gain). Returns `nil` if unknown (the gate check then does not block).
- [x] In `bootstrap.lua` after init — `ArenaPrep:checkNow()` (the `/reload`-in-arena case).
- [x] Temporary `/acp status`: show `buff active: true/false`, `instance: arena/other`, `bracket: 2v2/3v3/5v5/nil`, `remaining: <seconds before gates>`.

> **Research: gate-open countdown (verified on 2.5.5).** The prep buff aura reports `duration=0`/`expirationTime=0` — it cannot measure the countdown. The working approach (ArenaAnalytics + sArena on the same client) is `CHAT_MSG_BG_SYSTEM_NEUTRAL` + a localized countdown message map (60/30/15/0), tracking `countdownEndTime = GetTime() + N`. `GetBattlefieldTimeRemaining()` is a battleground match timer, not the pre-gate countdown.

### Definition of Done

- In an arena — at countdown start `status` shows `buff active: true`, after combat starts — `false`.
- In a 2v2/3v3/5v5 arena — `status` shows the correct bracket; outside an arena — `bracket: nil`.
- In an arena — `status` shows `remaining` counting down (~60 s at start) and reaching 0 when the gates open.
- No false positives outside an arena.

---

## Phase 2 — Bag scan and item counting

**Goal:** the addon sees healthstones in bags and counts them.

### Tasks

- [x] `Classes/Inventory.lua`:
  - `getCount(itemID)`, `findItem(itemID)`.
  - Full scan bag `0..4`; `stackCount`-aware.
  - Listeners `BAG_UPDATE` / `BAG_UPDATE_DELAYED` → recount → `Events:fire("ACP_ITEMS_CHANGED", itemID, count)`.
  - Counter cache by itemID.
  - Tracked itemIDs built from `ACP.Data.Items.classItems[englishClass]` (via `select(2, UnitClass("player"))`).
- [x] `Utils/Items.lua`: wrapper over `GetContainerItemInfo` with the TBC signature in mind (base it on `GL:getContainerItemInfo` from Gargul, `Utils/Inventory.lua`).
- [x] `Utils/Items.lua`: `findItemInBags(itemID, skipSoulbound)` — simplified port of Gargul's `GL:findBagIdAndSlotForItem` (`Utils/Items.lua`): bags `0..4` only, no bank/link variants for v0.1; soulbound skip via the `bound` flag (11th container value — reliable on TBC, no tooltip needed).
- [x] `/acp status`: show the count of each healthstone rank in bags.
- [x] (Optional, for verification) `Tests/inventory_sandbox.lua`: an in-game stub that replaces `GetContainerItemInfo` with fake data and verifies stack counting. (`ACP.Tests`, run via `/run LoadAddOn("ArenaChillPrep_Tests"); ACP.Tests:run()` — not in the release TOC.)

### Definition of Done

- Craft a healthstone in bags — `/acp status` shows `count: 1` without `/reload`.
- Destroy a healthstone (use/delete) — the count updates.
- Stacks (multiple stones in one slot) are counted correctly.

---

## Phase 3 — Orchestrator (core logic)

**Goal:** the chain "buff active → item appeared → time to trade".

### Tasks

- [x] `Classes/DeliveryController.lua`:
  - State machine: `IDLE / ACTIVE / TRADING / DONE` (diagram in ARCHITECTURE.md, 2.5).
  - Handlers `ACP_BUFF_GAINED`, `ACP_BUFF_LOST`, `ACP_ITEMS_CHANGED`.
  - **Bracket gate** on `ACP_BUFF_GAINED`: `ArenaPrep:getBracket()` + `Settings:get("brackets." .. bracket)`; disabled/unknown bracket → stay `IDLE` with a chat log line.
  - **Given-items memory (`givenTo`):** runtime-only set (per prep, **not** saved to `ArenaChillPrepDB`) of partners who already received items. Partner detection skips them; on `ACP_TRADE_COMPLETED` the partner is added; reset on `ACP_BUFF_LOST`. No eligible partner left → `DONE`, else → `ACTIVE` (wait for the next crafted item).
  - **Gate safety:** only start a trade while `ArenaPrep:getRemainingTime() >= Settings:get("gateSafetySeconds")` (default 15); when the remaining time drops below the threshold — cancel pending initiations/retries. An already-open trade window is left untouched.
  - Partner detection: `partnerMode = "auto"` (first non-self party member, skipping `givenTo`) / `"party1"`.
  - Context check: `IsInInstance()`, arena instance type, `not UnitAffectingCombat("player")`.
  - "Ready" decision: for each enabled item category `count >= setting.count`.
  - Timing: `tradeDelay` pause after the item appears before opening the trade.
- [x] `TradeManager` interaction via events `ACP_TRADE_START`, `ACP_TRADE_COMPLETED`, `ACP_TRADE_FAILED` (minimal TradeManager: `InitiateTrade` + completion via `ERR_TRADE_COMPLETE`, failure on `TRADE_CLOSED` without completion; full placement/auto-accept/retries in Phase 4).
- [x] Listeners `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` (combat cancels/defers attempts).
- [x] `Classes/Settings.lua` — implemented early (Phase 3 needs `get`/`set`): deep-merge defaults + `ArenaChillPrepDB`, dot-path get/set, `dump()`. Full UI panel stays in Phase 5.

### Definition of Done

- In an arena: craft a stone → after `tradeDelay` seconds a trade request opens with the partner (the partner sees the window).
- If the stone was already in bags at prep start — the trade starts immediately.
- In 3v3/5v5 (with default settings, only `2v2` enabled) — **no trade request is sent**; `/acp status` explains why (bracket disabled).
- Two healthstones crafted in a row (2v2): the second one does **not** re-open a trade with the same partner (`givenTo`).
- With `gateSafetySeconds = 15`: crafting a stone within the last 15 s before the gates open → **no trade request is sent**.
- If the partner declined — silent retry (up to 3), then wait.
- If combat started — attempts stop without error spam.
- After a successful trade — no second trade until the next buff.

---

## Phase 4 — Trade window automation

**Goal:** items are automatically placed into trade slots, with auto-accept.

### Tasks

- [x] `Classes/TradeManager.lua` (pattern: Gargul `Classes/TradeWindow.lua`, same client):
  - `startTrade(unit)` → `InitiateTrade(unit)`; success via `UI_INFO_MESSAGE` == `ERR_TRADE_COMPLETE`; `TRADE_CLOSED` alone means failure (verdict delayed 0.5 s → `ACP_TRADE_FAILED`). One-shot open timeout + retry backoff live in the DeliveryController (Phase 3); retries here are driven by the controller's `ACP_TRADE_FAILED` handler.
  - `TRADE_SHOW` → verify/record partner (`UnitName("NPC", true)`); then process a FIFO queue on a short repeating ticker (`TRADE_ITEM_TICK`, one item per tick): `findItemInBags` (skip soulbound) → `UseContainerItem(bag, slot)` — the game auto-places the item into the next free trade slot.
  - `ITEM_UNLOCKED` → re-queue items the game removed within 0.5 s of being added (keyed by `C_Item.GetItemGUID`).
  - Completion via `UI_INFO_MESSAGE` == `ERR_TRADE_COMPLETE`; `TRADE_CLOSED` alone means failure, not success.
  - `TRADE_ACCEPT_UPDATE`: if `autoAccept` — click `TradeFrameTradeButton` after a 1 s delay (give the partner time).
  - `TRADE_CLOSED` → `ClearCursor()`; events `ACP_TRADE_COMPLETED` / `ACP_TRADE_FAILED(reason)`.
- [x] Multi-item placement: the FIFO queue + ticker places one item per tick; `queueConfiguredItems()` fills the queue from Settings (enabled ranks, up to `count`). Split-stack (`SplitContainerItem`) deferred — v0.1 trades whole stones (stack size 1).
- [x] `/acp debug` — log every trade step to chat.

### Definition of DoneSorry, your request failed. Please try again.

Client Request Id: a18d516e-5dd3-43de-92b9-0622037180de

Reason: Request Failed: 400 {"error":{"type":"server_error","message":"Error from provider (Console): Upstream request failed: [404] No endpoints found that support image input"}}: Error: Request Failed: 400 {"error":{"type":"server_error","message":"Error from provider (Console): Upstream request failed: [404] No endpoints found that support image input"}} at GG._provideLanguageModelResponse (c:\Users\dnmno\AppData\Local\Programs\Microsoft VS Code\df53daabb1\resources\app\extensions\copilot\dist\extension.js:1690:14392) at process.processTicksAndRejections (node:internal/process/task_queues:104:5) at async GG.provideLanguageModelResponse (c:\Users\dnmno\AppData\Local\Programs\Microsoft VS Code\df53daabb1\resources\app\extensions\copilot\dist\extension.js:1690:15505)

- Full cycle in an arena: stone appeared → trade opened → item in slot → trade accepted → `status: DONE`.
- `autoAccept = true`: the trade completes without player clicks.
- Partner cancels: the retry counter grows; after exhaustion — silence until the next event.
- The cursor doesn't "stick" with an item after the window closes.

---

## Phase 5 — Settings and UI

**Goal:** the player controls behavior from the interface.

### Tasks

- [x] `Classes/Settings.lua`: deep-merge defaults and `ArenaChillPrepDB`, `get(path)`/`set(path, value)` (implemented in Phase 3, incl. `ensureDefaults` migration + `normalizeSegment` numeric-key handling + `normalizeRankKeys` cleanup).
- [x] `Classes/OptionsUI.lua`: Settings panel — top-level category **ArenaChillPrep** with a **subcategory "Autotrade"** (native `Settings.RegisterCanvasLayoutCategory` + `Settings.RegisterCanvasLayoutSubcategory`; legacy `InterfaceOptions_AddCategory` fallback; extensible `Subcategories` list for future General/Abilities/...):
  - master switch, `autoAccept` (with tooltip) — **General** box;
  - **bracket checkboxes (2v2 / 3v3 / 5v5)** — default `2v2 = true`, `3v3 = false`, `5v5 = false`; 3v3/5v5 shown disabled (`Disable()` + alpha) for v0.1, code kept for the future;
  - **Ranks to pass** box (WeakAuras-style boxed list, one checkbox per rank, toggles all itemIDs of that rank; built from the class's categories so other classes render their own; default Major + Master);
  - **Timing** box: `tradeDelay` + `gateSafetySeconds` sliders (labels above, word-wrap);
  - partner is always auto (first non-self party member) — no manual slot;
  - layout: two-column grid (left General+Brackets, right Ranks+Timing), all groups boxed, fixed panel 660×400.
- [x] `Data/DefaultSettings.lua`: `brackets = { ["2v2"] = true, ["3v3"] = false, ["5v5"] = false }` + `items.healthstone` (default ranks = Major + Master, count 1).
- [x] Slash commands: `/acp` (opens the panel, prefers the Autotrade subcategory), `enable/disable/status/debug`.
- [x] All strings localized via `L` (enUS/ruRU).

### Definition of Done

- All settings persist between sessions (game restart).
- Disabled addon — completely idle.
- UI strings translated to enUS and ruRU without hardcoding in code.

---

## Phase 6 — Polish, tests, v0.1 release

### Tasks

- [x] **Code hardening (edge-case review, ARCHITECTURE.md §4):** trade-open timeout (`TRADE_OPEN_TIMEOUT` was defined but unused — a silently failing `InitiateTrade` left the controller stuck in `TRADING` forever; now a one-shot `TradeOpen` timer → `TradeManager:cancel()` → `ACP_TRADE_FAILED("timeout")` → retry ×3); 3v3 continuation (`onTradeCompleted` returns to `ACTIVE` while an unserved partner exists — a crafted item after the first trade now goes to the next partner, per CONTEXT #13); stray-failure guard (`onTradeFailed` only acts in `TRADING` — no trade after the gates open); death check (`UnitIsDeadOrGhost` in `canStartTrade`). Docs updated first (ARCHITECTURE §2.5/§2.6/§4/§6, CONTEXT status).
- [x] **Automated decision-logic tests:** `Tests/controller_sandbox.lua` — synchronous sandbox (`/run ACP.Tests:runController()`, dev-only TOC comment) covering the bracket gate (2v2 default vs 3v3), `givenTo` (2v2 — one trade; 3v3 — second batch goes to the other partner, both pre-crafted and post-craft), gate safety (craft in the last 15 s → no trade) and the trade-open timeout.
- [ ] **Live edge-case walkthrough** (in-game, checklist below).
- [ ] **Test scenarios** (in-game, checklist below): 2v2 and 3v3, death before start, partner disconnect.
- [ ] **Bracket test** (in-game, checklist below): default (2v2 only) — 3v3/5v5 no trade; enable 3v3 — works.
- [ ] **`givenTo` test** (in-game, checklist below): 2v2 — two stones, only the first opens a trade; 3v3 — second goes to the other partner.
- [ ] **Gate-safety test** (in-game, checklist below): craft in the last 15 s — no trade.
- [x] `CHANGELOG.md`, final `README.md`.
- [x] License (MIT) + `LICENSE` file + `## License: MIT` in the TOC.
- [ ] **Cleanliness check** (in-game): no Lua errors during extended play with `/console scriptErrors 1`.

### Definition of Done

- v0.1 works stably for the author: at least 10 arenas with zero errors and no missed trade.
- README is up to date; how to add a new class/item is documented step by step (per `.github/ARCHITECTURE.md`, 6).

### Phase 6 — live test checklist (in-game)

Run with `/console scriptErrors 1`. `/acp debug` on during tests. Enable 3v3 for tests 3/4 via SavedVariables or:

```
/run ACP.Settings:set("brackets.3v3", true); ArenaChillPrepDB = ACP.Settings.Data
```

1. **Edge cases (ARCHITECTURE.md §4):** `/reload` inside an arena with the buff active (trade still works); item already in bags at prep start (trade starts immediately); partner declines (3 silent retries then wait); window doesn't open within 1 s (timeout → retries); combat during prep; `ITEM_UNLOCKED` re-add; fewer items than configured (waits); not an arena (idle); stacks; soulbound skipped; bracket not enabled (log line); unknown bracket (deferred gate); `getRemainingTime` nil (gate not enforced, debug note); second stone after a successful trade.
2. **Death before start:** die during prep (e.g. `/run ACP.ArenaPrep:checkNow()` with healthstones ready — should refuse while dead, resume after revive if the buff is still up).
3. **Partner disconnect:** partner leaves mid-prep before the trade → timeout → retries → give-up; rejoin → `GROUP_ROSTER_UPDATE` resumes; disconnect during an open window → `TRADE_CLOSED` → retry.
4. **Bracket:** default (2v2 only) in 3v3 and 5v5 — no trade initiated (`/acp status` explains: "bracket 3v3 disabled"); enable 3v3 — trading starts.
5. **`givenTo`:** 2v2 — craft two stones in a row, only the first opens a trade; 3v3 (enabled) — craft two batches, the second goes to the *other* partner (also when the second batch is crafted after the first trade completes).
6. **Gate safety:** `gateSafetySeconds = 15` — craft a stone within the last 15 s of prep → no trade initiated.
7. **Stability:** 10+ arenas (mix of 2v2; 3v3 with bracket enabled) — zero Lua errors, no missed trade.

---

## Main test scenario (v0.1 checklist)

1. Queue 2v2 with a partner (Warlock + anyone).
2. Wait for the arena to load — the prep buff is active, `/acp status` shows `bracket: 2v2`.
3. Craft a Master Healthstone.
4. Expectation: after `tradeDelay` a trade opens with the partner, the stone is in the slot, the trade completes.
5. `autoAccept` off — verify the addon doesn't accept the trade itself.
6. Verify that after the trade the state is `DONE`, no second trade.
9. Craft a second healthstone after the first trade — **no second trade request** (same partner already in `givenTo`).
10. Gate safety: set `gateSafetySeconds = 15` and craft only within the last 15 s of prep — no trade is sent.
7. Next arena — everything repeats from scratch.
8. Queue 3v3 — with default settings **no trade request is sent**; enable `3v3` in options → trade works again.

---

## Effort estimate (rough)

| Phase | Estimate |
|---|---|
| 0. Scaffold | 1–2 h |
| 1. Buff detection | 1–2 h |
| 2. Bag scan | 2–3 h |
| 3. Orchestrator | 3–4 h |
| 4. Trade window | 3–4 h |
| 5. Settings/UI | 3–4 h |
| 6. Polish/release | 2–3 h |
| **Total** | **~15–22 h** |

---

## Working with an AI assistant

1. Before starting a phase — read `.github/ARCHITECTURE.md` and `.github/CONTEXT.md` (Context for developers section).
2. Implement the phase files per the task list.
3. Verify the phase DoD in game.
4. After the phase — check the boxes and record issues in `CHANGELOG.md` or an issue.
