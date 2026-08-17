---
name: addon-research
description: How to research WoW API behavior by reading the working addons installed in the WoW client's AddOns folder (Gargul, sArena_Reloaded, BigDebuffs, WeakAuras, OmniCD, Auctionator, Questie and ~80 others). Use when the wow-api-20506 skill doesn't cover a question, when a call errors unexpectedly, or when you need a proven pattern for a feature (trade, arena, auras, settings, items).
---

# Addon research (working addons as ground truth)

## Why this exists

The workspace search (`file_search` / `grep` used by IDEs and AI agents) does **not index** the WoW AddOns folder (the path comes from the `.env` variable `addons_path_anniversary` — see `.env.example`). Searching it via the built-in search returns nothing. The reliable way to search the addons is **PowerShell `Select-String`** (see `tools/research.ps1`).

Working addons on THIS client are the best documentation: every pattern in this project (trade, arena countdown, aura iteration, settings subcategories, item DBs) was verified by reading them.

## Map: which addon proves what

| Topic | Addon(s) | Notes |
|---|---|---|
| Trade window automation | `Gargul/Classes/TradeWindow.lua` | open() + callback + timeout; FIFO placement; ITEM_UNLOCKED re-add; completion via ERR_TRADE_COMPLETE; partner verify |
| Arena prep buff / countdown | `sArena_Reloaded/` (sArena.lua, Modules/Auras.lua), `ArenaAnalytics/` (ArenaConstants.arenaMessages, Tracker/ArenaTracker_GatesOpened.lua) | GetPlayerAuraBySpellID(32727); CHAT_MSG_BG_SYSTEM_NEUTRAL countdown map (full locale list) |
| Aura object fields | `BigDebuffs/BigDebuffs.lua` (UnpackAura), `WeakAuras/BuffTrigger2.lua` (HandleAura), `OmniCD/Modules/Party/Core.lua` (GetBuffDuration) | `.spellId .expirationTime .duration .name .icon .applications ...`; AuraUtil.ForEachAura signature |
| Container API | `Gargul/Utils/Inventory.lua`, `ItemRack/ItemRack.lua` | C_Container object unpacking, GetContainerNumSlots shim |
| Settings / subcategories | `Auctionator/.../PanelConfig.lua`, `MiniFramework.lua`, `idTip/idTip.lua`, `CurseArena/CurseArena.lua` | RegisterCanvasLayoutCategory / Subcategory / AddOnCategory; OpenToCategory |
| Item IDs / names | `Questie/Database/Classic/classicItemDB.lua`, `TBC/tbcItemDB.lua`, `Wotlk/wotlkItemDB.lua` | format: `[22105] = {'Master Healthstone', nil, ..., 70, 60, 0, 0, 8}` (name, ..., level, ...) |
| Aura iteration (positional vs object) | `BigDebuffs` (UnitBuff=GetBuffDataByIndex on non-mainline), `sArena` (GetAuraDataByIndex) | confirms which API returns what on 2.5.5 |
| General UI patterns | `BetterBlizzFrames/gui.lua`, `Leatrix_Maps/`, `WeakAuras/` | GetChildren() wrapping, sliders, checkboxes, scrollframes |

## Recommended workflow

1. **Know the target**: pick the addon that obviously does the feature (see map).
2. **Search with context**: use `tools/research.ps1` — it runs `Select-String` with `-Context` and prints `Addon:file:line: text`. Example:
   ```powershell
   .\research.ps1 -Pattern "RegisterCanvasLayoutSubcategory" -Context 3
   ```
   or directly (replace `<addons>` with the value of `addons_path_anniversary` from `.env`):
   ```powershell
   Select-String -Path "<addons>\Auctionator\Source\Config\Mixins\PanelConfig.lua" -Pattern "RegisterCanvasLayoutSubcategory" -Context 2,5
   ```
3. **Read a focused slice**: `Get-Content <file> | Select-Object -Skip <start> -First <n>` — read only the function that matters, not the whole file.
4. **Port WITHOUT libraries**: copy the *pattern*, reimplement dependency-free (no Ace/etc.) using `C_Timer`, `ACP.Utils.Timers`, call-time shims.
5. **Record what you learned**: add the verified fact to the `wow-api-20506` skill and/or repo memory so it's not re-researched.

## PowerShell search caveats

- **Quoting**: patterns with quotes break `-Pattern` when passed inline with spaces. Use `-SimpleMatch` for literal strings, or single quotes inside double-quoted PS strings, or the wrapper script.
- **Files may report weird sizes** via `Get-ChildItem` (reparse points) — ignore `Length`, content is real (verified: `Get-Content -Raw` returns the true size).
- Search top-level `*.lua` of each addon first; deep modules live in `Modules/`, `Source/`, `Libs/`.
- `Select-String` is case-insensitive by default.

## When NOT to research

- The `wow-api-20506` skill already answers it → use that.
- The project's own code already implements it → read the addon's own module first (self-documenting).
- It's a Lua-language question (not WoW API) → the `lua-refactoring` skill covers style/smells.

## Dead-end rule

- **No addon implements the feature → that is the answer.** If a feature is absent from ALL working addons on this client, the most likely truth is that the client does not allow it (e.g. auto-accept: `AcceptTrade()` is restricted on 2.5.x). Conclude that and report it — do NOT keep searching for a pattern that does not exist.
- **Never repeat a search.** Keep a mental/session ledger of queries already run ("checked X → empty"). Before any search, check it; if the same query was already run, stop and synthesize instead.
- **Two failed attempts = stop.** After 2 searches that return nothing useful for the same question, stop researching and present the best conclusion + options to the user.
- **Identical tool calls in a row = loop signal.** If you are about to call a tool with the same arguments as a previous call in this session, that is a loop — stop and write the answer.
