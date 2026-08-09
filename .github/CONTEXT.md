# ArenaChillPrep — Context (for AI agents)

> Source of truth: this directory (`.github/`). Entry point: `AGENTS.md` at the repo root.
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
6. **Optionally auto-accept the trade** (`autoAccept` setting).
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
├── AGENTS.md                 # Agent entry point → read .github/ (this directory)
├── ArenaChillPrep.toc        # TOC (Interface: 20506, SavedVariables: ArenaChillPrepDB)
├── bootstrap.lua             # Entry point: global ACP table, event frame, initialization
├── README.md                 # Human-facing description (users) — not technical docs
├── .github/                  # Agent documentation & instructions (source of truth)
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
│   └── OptionsUI.lua         # Interface Options panel + /acp slash command
└── Utils/                    # Utilities
    ├── Items.lua             # Item helpers (find by ID, counters, bag search)
    ├── Tables.lua            # Table helpers
    └── Timers.lua            # Named timers via C_Timer (after/interval/cancel)
```

---

## Code conventions

- **Lua 5.1**, no external libraries (no Ace — the addon is self-contained).
- Every file is a module table. The addon's global table is `ACP` (ArenaChillPrep).
- Modules receive the `ACP` reference via vararg: `local _, ACP = ...;`.
- Style follows the **Gargul** addon (same workspace): `---@class` annotations, `_G.` prefix for global APIs, local aliases for globals at the top of the file.
- UI strings go through `Data/Localization.lua` (table `L`, metatable fallback to the key, like `Gargul_L`).
- Cross-session state only via `ArenaChillPrepDB` (SavedVariables), accessed through `ACP.Settings`.

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
10. **Timers without Ace.** `C_Timer.After` / `C_Timer.NewTicker` are available on TBC Anniversary (20506) — use them (via a small named-timer helper) instead of Ace timers.
11. **Bracket detection.** An addon **can** determine the bracket. Primary signal: your party size in the arena — in TBC you must queue with a group of exactly the bracket size, so `GetNumPartyMembers() + 1` is `2`, `3` or `5` (and the group is locked once inside, so it's stable during prep). Cross-check when available (client ≥ 2.5.1): `GetNumArenaOpponents() + 1` — number of opponents (1/2/4); it may return `0` briefly at arena load, hence the fallback. Note: the API is `GetNumPartyMembers` in TBC — `GetNumSubgroupMembers` only exists from 5.0.4+.
12. **Gate-open countdown — use `CHAT_MSG_BG_SYSTEM_NEUTRAL`, not the aura.** Verified on 2.5.5: the prep buff's aura reports `duration=0` / `expirationTime=0` (treated as infinite), so `expirationTime - GetTime()` is useless. The working approach — proven by ArenaAnalytics and sArena_Reloaded on the same client — is listening to `CHAT_MSG_BG_SYSTEM_NEUTRAL` and matching the localized countdown messages ("One minute until the Arena battle begins!" = 60, "Thirty seconds..." = 30, "Fifteen seconds..." = 15, "The Arena battle has begun!" = 0; the map lives in `ACP.Data.Constants.ARENA_COUNTDOWN_MESSAGES`). Track `countdownEndTime = GetTime() + N`, seeded with `+60 s` on buff gain as a fallback. `GetBattlefieldTimeRemaining()` is a battleground match timer, not the pre-gate countdown.
13. **One trade per partner, not per prep.** The addon keeps a runtime `givenTo` set (reset on `ACP_BUFF_LOST`) of partners who already received items and never re-trades with them. In 2v2 this means one trade per prep; in 3v3/5v5 a newly crafted item goes to the next eligible partner. `givenTo` is runtime-only — never persist it to `ArenaChillPrepDB`.

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

```lua
ArenaChillPrepDB = {
    enabled        = true,   -- master switch
    partnerMode    = "auto", -- "auto" | "party1" (explicit party slot)
    manualPartner  = "party1",
    autoAccept     = false,  -- auto-click "Trade" after placing items
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
