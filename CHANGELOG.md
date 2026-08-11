# ArenaChillPrep Changelog

## [Unreleased] (2026-08-11)

### Added

- **Automated unit-test suite** (`Tests/`) — runs **outside the game** under LuaJIT (Lua 5.1, the same version WoW uses):
  - `luaunit` 3.5 + `luacov` 0.17 vendored in `Tests/lib/`.
  - `Tests/run_tests.lua` runner + `Tests/run-tests.ps1` wrapper (exit `0` = pass + coverage ≥ 90%).
  - WoW API stubs (`Tests/stubs/wow_stubs.lua`), module loader (`Tests/loader.lua`), shared helpers (`Tests/helpers.lua`).
  - **169 tests covering all non-UI modules** (bootstrap, Data, Utils, Classes logic) at **96.45% line coverage** — `OptionsUI.lua` excluded (UI code).
  - Coverage report: `Tests/luacov.report.out`.

## [v0.1.0] (2026-08-09)

Initial release — Warlock only (Healthstones of all ranks), auto-trade during arena preparation on TBC Anniversary (Interface 20506).

### Added

- **Prep detection:** `Arena Preparation` buff (spell 32727) via `C_UnitAuras.GetPlayerAuraBySpellID` (the `UnitBuff`/`UnitAura` legacy wrappers are broken on 2.5.5); 1 s safety ticker while the buff is active.
- **Gate countdown:** `CHAT_MSG_BG_SYSTEM_NEUTRAL` + localized message map (enUS/ruRU) — the prep buff aura reports `duration=0` on 2.5.5, so the chat messages are the countdown source (60/30/15/0 s).
- **Bracket detection:** party size inside the arena (`2v2`/`3v3`/`5v5`), cross-checked with `GetNumArenaOpponents`; per-bracket settings (default: **2v2 only**, 3v3/5v5 disabled in the UI for v0.1).
- **Bag scan:** stack-aware counting of all healthstone ranks (paired IDs 19004/05 … 19012/13 + Master 22105 count as one rank), `BAG_UPDATE`-driven.
- **Orchestrator:** state machine `IDLE → ACTIVE → TRADING → DONE`; bracket gate; runtime-only `givenTo` (one trade per partner per prep); gate safety (stop trading N seconds before the gates open); silent retries with backoff (2/4/8 s, ×3).
- **Trade automation:** dependency-free port of the proven Gargul patterns — `UseContainerItem` placement into the open window, FIFO queue with one item per tick, `ITEM_UNLOCKED` re-add, completion via `ERR_TRADE_COMPLETE`. The player confirms the trade manually (auto-accept is impossible on 2.5.x — `AcceptTrade()` is restricted).
- **UI:** Interface Options panel (Settings canvas API) — General, Arena brackets, Ranks to pass, Timing; `/acp` slash commands (`status`, `enable`, `disable`, `debug`; bare `/acp` opens the panel). enUS + ruRU localization.
- **Settings:** SavedVariables wrapper with dot-path get/set, deep-merge of defaults, `ensureDefaults` migration, numeric-key normalization and rank-key cleanup.

### Fixed

- **Trade-open timeout (Phase 6 hardening):** `InitiateTrade` can fail silently (out of range, partner offline/dead) without firing `TRADE_SHOW` or `TRADE_CLOSED`, which previously left the controller stuck in `TRADING` forever. A one-shot `TradeOpen` timer (`TRADE_OPEN_TIMEOUT = 1 s`) now fires `ACP_TRADE_FAILED("timeout")` → retry with backoff; `TradeManager:cancel()` unwedges the low-level trade state; the new `ACP_TRADE_OPENED` event cancels the timeout when the window appears.
- **3v3 continuation (Phase 6 hardening):** after a successful trade the controller returns to `ACTIVE` while an unserved partner remains — a healthstone crafted *after* the first trade now goes to the next partner, matching the documented per-partner model (previously the controller went `DONE` and ignored later crafts).
- **Stray-failure guard (Phase 6 hardening):** `ACP_TRADE_FAILED` is only handled while `TRADING` — a failure verdict arriving after a reset (window closed after the buff faded / gates opened) no longer resumes trading after the gates open.
- **Death check (Phase 6 hardening):** no trade is initiated while the player is dead; trading resumes after revival if the buff is still active.

### Tested

- Decision logic covered by a deterministic in-game sandbox: bracket gate (2v2 default vs 3v3), `givenTo` (2v2 — one trade; 3v3 — second batch to the other partner, pre-crafted and post-craft), gate safety, trade-open timeout, stray failure, death check (superseded by the automated suite in `Tests/`).
- Stack counting / soulbound skip covered by the automated suite in `Tests/`.
- Live-verified in arenas (phases 1–5): buff/bracket/countdown detection, full 2v2 trade cycle, `givenTo` single-trade-per-partner, gate-safety and bracket-gate behavior.

### Notes

- The addon never crafts items itself, never sends gold, and never accepts trades — the player confirms manually.
- License: MIT.
