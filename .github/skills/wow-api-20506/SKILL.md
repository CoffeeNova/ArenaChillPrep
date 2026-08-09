---
name: wow-api-20506
description: Verified knowledge base for the WoW TBC Anniversary client (Interface 20506 / build 2.5.x). Use whenever writing, fixing, or debugging WoW API calls in this addon — it lists the APIs that crash, the APIs that return shifted data, and the shims/patterns that are proven to work on this exact client.
---

# Wow API — TBC Anniversary (20506)

**Client:** WoW TBC Anniversary, build 2.5.x (the user's client prints `2.5.6 The Burning Crusade`). This client is a hybrid: it backports many modern `C_*` APIs but keeps some broken legacy wrappers. Do NOT assume a function behaves like retail OR like classic TBC — verify against this list, then against a working addon if unsure.

## The #1 rule

If a WoW API call errors or returns nonsense on this client, **check this list first**, then look at a **working addon** (see the `addon-research` skill) before inventing a workaround. Almost every "impossible" bug in this project was already solved by Gargul / sArena_Reloaded / BigDebuffs / WeakAuras / OmniCD / Auctionator running on the same client.

## Verified gotchas (all confirmed live in this project)

| API | What happens | Working alternative |
|---|---|---|
| `UnitBuff(unit, "name")` | **CRASHES** — the deprecated wrapper proxies to `C_UnitAuras.GetBuffDataByIndex(unit, index[, filter])` which only accepts a NUMERIC index | `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` → aura object with `.expirationTime/.spellId/.duration` |
| `UnitAura(unit, i, filter)` | Returns **SHIFTED legacy positions** — live dump: value #6 was `sourceUnit` ("player"/"pet"), #10 was boolean `isBossAura`; real spellID/expirationTime never captured | `C_UnitAuras.GetAuraDataByIndex(unit, i, filter)` → object with `.spellId/.expirationTime/.name/...` |
| `GetContainerNumSlots(bag)` | **NOT a global** — only `C_Container.GetContainerNumSlots` exists; calling the global → "attempt to call a nil value" | call-time shim: `_G.GetContainerNumSlots or (C_Container and C_Container.GetContainerNumSlots)` (call-time, so test stubs can override) |
| `GetContainerItemInfo(bag, slot)` | Not a global; `C_Container.GetContainerItemInfo` returns an **object** (not 11 positional values) | shim unpacks: `info.iconFileID, info.stackCount, info.isLocked, ...` (11th = `info.isBound`) |
| `C_Item.GetItemGUID(bag, slot)` | **CRASHES** — takes an `ItemLocation`, not `(bag, slot)` | `ItemLocation:CreateFromBagAndSlot(bag, slot)` → `C_Item.GetItemGUID(location)`; guard `not bag or not slot` (ITEM_UNLOCKED can pass bag-only) |
| `InterfaceOptions_AddCategory` | **NIL** on 2.5.5 — the legacy settings API is gone | `Settings.RegisterCanvasLayoutCategory` + `Settings.RegisterAddOnCategory`; subcategories via `Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, title)` |
| `frame:GetChildren()` | Returns **multiple values, not a table** — `pairs(frame:GetChildren())` → "bad argument to pairs" | wrap: `for _, child in ipairs({ frame:GetChildren() })` |
| `OptionsSliderTemplate` | Does **NOT** create a global `"<name>Text"` (unlike `UICheckButtonTemplate`) | create the label yourself: `parent:CreateFontString(...)` |
| `CreateFrame("Frame", ...)` + `SetBackdrop` | `SetBackdrop` is **nil** unless the frame is created with the `"BackdropTemplate"` mixin | `CreateFrame("Frame", nil, parent, "BackdropTemplate")` |
| `UI_INFO_MESSAGE` handler | The message is the **SECOND** argument: `function(_, message)` | Gargul's pattern — `local _, message = ...` |
| `CLASS_WARLOCK` (and other `CLASS_*`) | **NOT defined** on TBC FrameXML — `[CLASS_WARLOCK] = ...` throws "table index is nil" | `local CLASS_WARLOCK = _G.CLASS_WARLOCK or "WARLOCK"` |
| SavedVariables numeric keys | `[19013]` (number) and `"19013"` (string) are **DIFFERENT table keys** — dot-path get/set with string segments hit the string key while defaults use numeric | `Settings:normalizeSegment()` converts integer-looking path segments to numbers; `normalizeRankKeys()` collapses old string duplicates on load |

## Verified working patterns

### Arena prep buff (spell 32727)
```lua
local aura = C_UnitAuras.GetPlayerAuraBySpellID(32727);
if (aura) then return true, aura.expirationTime; end
```
> The aura reports `duration=0`/`expirationTime=0` — it CANNOT measure the pre-gate countdown.

### Gate-open countdown (NOT from the aura)
The countdown comes from **`CHAT_MSG_BG_SYSTEM_NEUTRAL`** + a localized message map (proven by ArenaAnalytics + sArena on the same client):
```lua
-- map: "One minute until the Arena battle begins!" = 60, "Thirty seconds..." = 30,
--       "Fifteen seconds..." = 15, "The Arena battle has begun!" = 0  (enUS + ruRU)
countdownEndTime = GetTime() + seconds;  -- seeded +60 on buff gain
getRemainingTime() = countdownEndTime - GetTime();
```
`GetBattlefieldTimeRemaining()` is a battleground match timer, NOT the pre-gate countdown.

### Trade automation (Gargul patterns, same client)
- `InitiateTrade(unit)` → `TRADE_SHOW` (window opened)
- Place items with `UseContainerItem(bag, slot)` while the window is open — the game auto-places into the next free trade slot. Shim: `_G.UseContainerItem or C_Container.UseContainerItem`.
- **One item per tick** (FIFO queue + repeating ticker, ~0.15 s) — adding too fast makes the game silently remove items.
- `ITEM_UNLOCKED` → re-queue items the game removed within 0.5 s (keyed by GUID).
- Completion: `UI_INFO_MESSAGE` == `ERR_TRADE_COMPLETE` (SECOND arg). `TRADE_CLOSED` alone means failure — delay the verdict ~1 s so the completion message arrives first.
- Auto-accept: click `TradeFrameTradeButton:Click("LeftButton")` only when `button:IsEnabled()` (i.e. after items are placed).
- Cursor hygiene: `ClearCursor()` on `TRADE_CLOSED`.

### Container API (call-time shims — resolve at call time so sandbox tests can stub)
```lua
-- Utils/Items:getContainerNumSlots(bag) / getContainerItemInfo(bag, slot)
-- resolve _G.* or C_Container.* at call time.
```

### Feature detection
Guard everything modern with `_G.X or (C_X and C_X.Y)` — never assume a global exists.

## Bracket detection
Primary = party size inside an arena: `GetNumPartyMembers() + 1` → `{ [2]="2v2", [3]="3v3", [5]="5v5" }` (group is locked once inside). `GetNumPartyMembers` is the TBC name — `GetNumSubgroupMembers` only exists from 5.0.4+. Cross-check with `GetNumArenaOpponents()` when available (may return 0 briefly at arena load — party size stays the source of truth). **The bracket may not be resolved at `ACP_BUFF_GAINED`** (party converts to raid later) — defer the gate, re-check on `GROUP_ROSTER_UPDATE` and the ticker.

## References to consult when unsure
- `Gargul/` — trade window, containers, item search (same client, proven)
- `sArena_Reloaded/` — arena prep detection, countdown, aura iteration
- `BigDebuffs/`, `OmniCD/`, `WeakAuras/` — aura object fields, `AuraUtil.ForEachAura`
- `Auctionator/`, `MiniFramework/`, `BetterBlizzFrames/` — settings/subcategory registration
- `Questie/Database/Classic/` and `TBC/tbcItemDB.lua` — item ID/name verification

See `Data/Constants.lua`, `Utils/Items.lua`, `Classes/ArenaPrep.lua`, `Classes/TradeManager.lua` for live examples of every pattern above.
