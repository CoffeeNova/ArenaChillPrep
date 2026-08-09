---
name: debug-cycle
description: Methodology for debugging this addon when there is NO Lua error (silent failure). Covers adding debugPrint diagnostics, temporary /acp status output, reading the user's pasted log, and cleaning up afterwards. Use whenever a feature "does nothing" but the game loads fine.
---

# Debug cycle (silent failures)

Most bugs in this project were silent: the addon loaded, no errors, but the expected trade never happened. The diagnosis loop below resolved every one of them.

## 1. Add visibility FIRST

The addon has `ACP:debugPrint(msg, ...)` (only prints when `/acp debug` is on) and `ACP:print(msg, ...)` (always prints). Before changing logic, add targeted output at each decision point:

- **DeliveryController**: `canStartTrade()` prints its verdict (`disabled / not in arena / in combat / gate safety / ok`); `itemsReady()`/`categoryReady()` print per-rank `count vs needed`; `checkReady()` prints `scheduling trade with party1 in 1.5 s` / `no eligible partner` / bracket-gate messages.
- **ArenaPrep**: `handleCountdownMessage` prints `arena countdown message: N s remaining`; buff transitions print `prep buff gained/lost`.
- **Inventory**: `_recountAll` prints `item %d count changed -> %d`.
- **TradeManager**: every step — `initiating trade`, `trade window shown`, `placing item %d (bag %d, slot %d)`, `trade completed`, `trade failed: closed`.

Use `debugPrint` for the noisy per-tick spam (the 0.5 s ticker logs a LOT — keep that debug-only), `print` for user-meaningful single events (scheduling, handed items, bracket disabled).

## 2. Temporary diagnostics in `/acp status`

For things that only happen in-game (bags, auras, settings), add a TEMP block to the `status` handler in `Classes/OptionsUI.lua`:

```lua
-- TEMP diagnostics (describe bug here)
ACP:print("diag: %s=%s", key, tostring(ACP.Settings:get(key)));
```

Proven examples:
- dump `items.healthstone.ranks` contents → revealed the number-vs-string key bug;
- dump every bag slot `id/name` → revealed item 22105 was actually Master Healthstone;
- print `party=%d` → confirmed partner detection sees the group.

**Always remove TEMP diagnostics before finishing** — grep for `TEMP diagnostics` / `diag:` when done.

## 3. Ask the user for a structured report

Use the `debug-report` prompt template. Key: ask for `/acp debug` ON, reproduce, then paste the log AND `/acp status` output. Timestamps in the log let you correlate events (e.g. "craft at 18:29:57 → scheduling at 18:29:57 → window at 18:29:59").

## 4. Read the log — known phrases and what they mean

| Log line | Meaning |
|---|---|
| `itemsReady: category=healthstones setting missing or disabled` | Settings key missing/mismatch — check plural→singular mapping (`items.healthstones` vs `items.healthstone`) |
| `itemsReady: ... itemID=22105 count=1 needed=1 enabled=true` | items ARE ready — look downstream (partner, gate) |
| `bracket unknown disabled, skipping` | bracket not resolved yet at buff gain — the defer-gate path should engage; if not, GROUP_ROSTER_UPDATE didn't fire |
| `scheduling trade with party1 in 1.5 s` (repeated) | tradeDelay keeps re-scheduling — the check ticker and the delay timer race; `checkReady` should be re-entrant/skipped while a delay is pending |
| `trade window closed without completion` ×3 | partner never accepted — window opened but items may not have been placed (see `placing item` lines) or partner declined |
| `canStartTrade: gate safety` | too close to gates — expected |
| `state: TRADING -> ACTIVE` right after `failed` | retry cycle working |

## 5. The "it worked before the edit" case

If a change broke something that worked, diff the edit. Most UI regressions in this project came from: label anchoring (`CreateFontString` vs `_G[name.."Text"]`), box heights vs content, and `GetChildren()` misuse.

## 6. Cleanup checklist

- [ ] TEMP diagnostics removed
- [ ] debug lines that are useful long-term kept (they're guarded by `/acp debug`)
- [ ] Root cause recorded in repo memory (`arena-chill-prep-gotchas.md` if it's an API gotcha, else `phases`)
- [ ] If it's a new gotcha → add to the `wow-api-20506` skill
