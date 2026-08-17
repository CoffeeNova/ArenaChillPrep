# ArenaChillPrep — repo memory

Working record for AI agents. Source of truth is `.ai/`; this mirrors verified outcomes and phase status.

## Status (2026-08-11)

- **v0.1.0 released** (2026-08-09) — Warlock only: auto-trades Healthstones of all ranks to the arena partner during arena preparation (TBC Anniversary, Interface 20506). Default bracket **2v2 only** (3v3/5v5 code kept, checkboxes locked in the UI for v0.1).
- **Automated unit-test suite added** (2026-08-11): `Tests/` runs outside the game under LuaJIT (luaunit 3.5 + luacov 0.17). **169 tests, 96.45% line coverage** of all non-UI modules (bootstrap, Data, Utils, Classes logic); `OptionsUI.lua` excluded (UI code). Runner: `Tests/run-tests.ps1` (exit `0` = pass + coverage ≥ 90%).
- **AI library migrated to `.ai/`** (2026-08-18): the agent toolkit moved from `.github/` to `.ai/` (same layout as the sibling addon BloomBuddy) — entry point `AGENTS.md` → `.ai/CONTEXT.md` → `.ai/ARCHITECTURE.md` → skills. `.github/` now holds only GitHub Actions workflows (none yet).

## Verified client facts (TBC Anniversary 2.5.x — verified in game phases 1–5 + working addons)

- **Prep buff:** `C_UnitAuras.GetPlayerAuraBySpellID(32727)` returns an aura object. `UnitBuff("player", name)` crashes on 2.5.5 (deprecated wrapper proxies to `C_UnitAuras.GetBuffDataByIndex`, numeric index only); `UnitAura(unit, i, filter)` returns shifted legacy positions with no spellID/expirationTime.
- **Gate countdown is NOT the aura:** the prep buff reports `duration=0`/`expirationTime=0`. The working source (ArenaAnalytics + sArena on the same client) is `CHAT_MSG_BG_SYSTEM_NEUTRAL` + the localized message map (`ACP.Data.Constants.ARENA_COUNTDOWN_MESSAGES`, 60/30/15/0 s, enUS + ruRU). `GetBattlefieldTimeRemaining()` is a battleground match timer, not the pre-gate countdown.
- **Bracket detection:** `GetNumPartyMembers() + 1` → 2/3/5 (the group is locked inside the arena, so it is stable during prep); cross-check `GetNumArenaOpponents()` (2.5.1+, may be 0 briefly at load). `GetNumPartyMembers` is the TBC name — `GetNumSubgroupMembers` only exists from 5.0.4+.
- **Trading (Gargul patterns, same client):** `InitiateTrade(unit)` → `TRADE_SHOW`; place items with `UseContainerItem(bag, slot)` (the game auto-places into the next free slot); one item per tick (FIFO + ~0.15 s ticker) — too-fast adds get silently removed; `ITEM_UNLOCKED` re-add for items removed within 0.5 s; completion = `UI_INFO_MESSAGE` (SECOND arg) == `ERR_TRADE_COMPLETE`, never `TRADE_CLOSED` alone; `ClearCursor()` on close.
- **Auto-accept is IMPOSSIBLE on 2.5.x** — `AcceptTrade()` is restricted (requires a hardware event); a programmatic call or `TradeFrameTradeButton:Click()` is silently blocked (`Interface action failed because of an AddOn`). The addon places items; the player confirms manually.
- **`C_Timer` handle `Cancel()` is UNRELIABLE (verified 2026-08-10):** a "cancelled" timer can still fire — a cancelled `TradeOpen` timer fired after `TRADE_SHOW` (false timeout killed a live trade, lost the partner attribution → repeat trades). Fix pattern in `Utils/Timers.lua`: named entries `{active = true, handle}`; the callback bails unless `active` and still registered; `handle:Cancel()` is best-effort.
- **Container API:** `GetContainerNumSlots` is NOT a global (only `C_Container`); `C_Container.GetContainerItemInfo` returns an OBJECT (not the legacy 11-tuple); `C_Item.GetItemGUID(bag, slot)` crashes — needs an `ItemLocation`. Call-time shims in `Utils/Items`.
- **`CLASS_*` constants are NOT defined** on TBC FrameXML — guard `local CLASS_WARLOCK = _G.CLASS_WARLOCK or "WARLOCK"`.
- **Settings keys:** `[19013]` (number) and `"19013"` (string) are DIFFERENT Lua keys — dot-path get/set with string segments hit the string key while defaults use numeric. `Settings:normalizeSegment()` converts integer-looking segments; `normalizeRankKeys()` collapses old string duplicates on load.
- **Settings UI:** `InterfaceOptions_AddCategory` is NIL on 2.5.5 — use `Settings.RegisterCanvasLayoutCategory` + `RegisterAddOnCategory` (+ `RegisterCanvasLayoutSubcategory`).

## Decisions

- **No Ace libraries.** Vanilla + `C_*` API only; timers via `ACP.Utils.Timers` (thin C_Timer wrapper mirroring Gargul's `GL:after/interval` API).
- **Orchestrator separate from execution.** `DeliveryController` (what to do) vs `TradeManager` (how) — decision logic unit-testable without the game.
- **One trade per partner, not per prep.** Runtime-only `givenTo` set (reset on `ACP_BUFF_LOST`, never persisted) — 2v2 = one trade per prep; 3v3/5v5 = next eligible partner.
- **Bracket gate on `ACP_BUFF_GAINED`** via `Settings:get("brackets." .. bracket)`; default 2v2 only.
- **Gate safety:** no new trades once `getRemainingTime() < gateSafetySeconds` (default 15); an open window is left untouched.
- **`givenTo` is runtime-only** — never persist to `ArenaChillPrepDB`.

## To verify in game (pending)

- 3v3/5v5 end-to-end (code kept, UI locked for v0.1) — per-partner continuation when a second batch is crafted after the first trade.
- Master healthstone item 22105 rank pairing with 19012/19013 (Major) on a max-rank Warlock client.

## Phases

- Phase 0 — scaffold: DONE.
- Phases 1–5 — prep/bracket/countdown detection, bag scan, orchestrator, trade automation, UI/settings: **live-verified in arenas** (2v2 full cycle, `givenTo`, gate safety, bracket gate).
- Phase 6 — hardening (trade-open timeout, 3v3 continuation, stray-failure guard, death check): DONE (2026-08-09, CHANGELOG).
- Tests — automated suite (169 tests, 96.45%): DONE (2026-08-11). In-game acceptance per change remains user-driven.