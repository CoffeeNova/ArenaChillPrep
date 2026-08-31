---
name: wow-api-20506
description: Verified knowledge base for the WoW TBC Anniversary client (Interface 20506 / build 2.5.x). Use whenever writing, fixing, or debugging WoW API calls in this addon — it lists the APIs that crash, the APIs that return shifted data, and the shims/patterns that are proven to work on this exact client.
---

# Wow API — TBC Anniversary (20506)

**Client:** WoW TBC Anniversary, build 2.5.x (the user's client prints `2.5.6 The Burning Crusade`). This client is a hybrid: it backports many modern `C_*` APIs but keeps some broken legacy wrappers. Do NOT assume a function behaves like retail OR like classic TBC — verify against this list, then against a working addon if unsure.

## The #1 rule

If a WoW API call errors or returns nonsense on this client, **check this list first**, then look at a **working addon** (see the `addon-research` skill) before inventing a workaround. Almost every "impossible" bug in this project was already solved by Gargul / sArena_Reloaded / BigDebuffs / WeakAuras / OmniCD / Auctionator running on the same client.

**But absence is evidence too** if NO working addon implements a feature, the honest conclusion is usually that the client does not allow it (e.g. auto-accept — `AcceptTrade()` is restricted on 2.5.x, `C_SecureTransfer` does not exist). Do NOT keep searching for a pattern that does not exist; conclude "impossible on this client" and report it. Never repeat the same search query in one session — after 2 failed attempts, stop and synthesize.

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
| `CastSpellByID` / `CastSpellByName` | **PROTECTED in combat** AND **blocked even out of combat for CAST-TIME spells AND for INSTANT spells outside safe zones**. Live-verified: (1) 2026-08-18 in a safe zone, OOC (`inCombat=false affectingCombat=false`, 22 Soul Shards) — `CastSpellByName("Fel Armor")` (instant) cast fine (GCD registered), but ANY spell with a cast time — Summon Succubus (6 s, via name AND id), Inferno, Create Healthstone (3 s), Shadow Bolt — is dropped/blocked with the `ForceTaint_Strong` "blocked from an action" popup; (2) 2026-08-19 in the OPEN WORLD — even `CastSpellByName("Fel Armor")` (instant) pops "blocked from an action" (no GCD, no buff; ACP engine reported "workflow cast dropped (instant)"). Same signature as the `AcceptTrade()` hardware-event restriction. No working 20506 addon casts via the insecure API beyond TrackingEye's INSTANT tracking spells (in-zone). `SecureActionButtonTemplate:Click()` is silently dropped and `RunBinding()` (spell or macro) is also blocked — **only a real hardware key press can cast** | use a hidden `SecureActionButtonTemplate` bound via `SetBindingClick(key, button)` + `RegisterForClicks("AnyDown")` and WAIT for the user's key press — this is the ONLY reliable casting path on 20506 (M6/ItemRack pattern; live-verified 2026-08-19 for cast-time AND instant spells) |
| `CastSpellByName(name, target)` | the `target` argument is a pre-4.0 legacy — do NOT rely on it on 2.5.6 | `TargetUnit(unit)` + cast + `TargetLastTarget()` out of combat, or the secure `unit` attribute |
| `showAllSpellRanks` CVar = "0" | Trained-but-HIDDEN ranks silently fizzle on a `SecureActionButtonTemplate` cast (no SENT/FAILED/error); `IsPlayerSpell` still reports them. Live-verified 2026-08-31 | Temporarily `SetCVar("showAllSpellRanks", "1")` for the operation and restore the previous value (M6 `Libs/ActionBook/Categories.lua:82-101`, WeakAuras `Libs/LibDispel/LibDispel.lua:158/220` — same client) |
| `UNIT_SPELLCAST_SUCCEEDED` args | **AMBIGUOUS on 2.5.6** — TrackingEye (20506) reads `select(2, ...)` as the spellID (Features/Core.lua:613) while the retail signature is `(unit, castGUID, spellID)`; no 20506 addon contradicts TrackingEye | consume the event as a "player's cast finished" SIGNAL ONLY and verify real state (`UnitCastingInfo("player") == nil`, GCD); if the spellID is needed, dump the args once in-game and pick the position |
| `SpellStopCasting()` global | **presence unverified** — no 20506 addon uses it (only retail stubs) | `/stopcasting` macro command works (used as secure macrotext by NovaWorldBuffs); for the pause-on-movement design rely on the natural interrupt + `IsPlayerMoving()` instead |
| `UIDropDownMenu_SetSelectedValue` / `UIDropDownMenu_Refresh` (collapsed label) | **DO NOT update the collapsed box text on 2.5.x** — the label stays the template default "Custom" (or a stale previous selection) until the menu is opened once. Live-verified 2026-08-20 in the Workflows tab: the workflow selector showed "Custom" on panel open and "+ Add workflow"/"Delete workflow" left the label stale (selection state + steps updated fine — only the visible text was wrong) | set the collapsed label EXPLICITLY: resolve the current value's item from YOUR item list and call `UIDropDownMenu_SetText(frame, label)` on every build/refresh; when nothing is selected, clear `frame.selectedValue` + set the placeholder text (dynamic pickers otherwise retain the previous selection's label). This is the pattern of every working 20506 addon (Gargul, Ranker, BGHistorian, AtlasLoot, ItemRack, WeakAuras). Keep `UIDropDownMenu_SetSelectedValue` only for the persistent selection state / open-menu checkmark. **ALSO re-apply the label inside the menu-button click handler** (`info.func`) right after `UIDropDownMenu_SetSelectedValue` — that call internally triggers `UIDropDownMenu_Refresh`, which overwrites the just-set collapsed label with stale state ("Custom"/raw value/wrong by-index item), so the selection would visually revert; calling `applyLabel()` again after it makes the addon's label win. Verified 2026-08-21 fixing the step-row Target dropdowns (Unending Breath etc.). Lives in `UI.Dropdown` (Classes/UI/Widgets.lua) |
| `SecureActionButtonTemplate` with `type="item"` | used by `equipItem` steps (2026-08-20) as the M6-equivalent of the `/equip <name>` macro line — the button temporarily switches from `type="spell"` to `type="item"` + `item=<localized name>` and the user's hardware key press equips the stone. **NOT yet live-verified** on 20506 (unlike the spell path) | the item name must be resolvable (`GetItemInfo(itemID)` — the conjured item is in bags so the info is cached; fallbacks: stored name, `item:<id>`); no `UNIT_SPELLCAST_*` fires for item use → completion is poll-driven (item leaves the bags) and user-paced; ALWAYS restore `type="spell"` when returning to cast steps / clearing the button, or stray key presses will USE items instead of casting |
| Party-targeted casts via `TargetUnit("party1")` + secure spell button | **BROKEN on 20506 — pops "blocked action" AND mis-targets.** Live-verified 2026-08-22: (1) `Unending Breath` (cast step, target=party1) buffed the warlock, and the pet macro `[target=party1]` form ALSO fell through to the player (imp Fire Shield shielded the warlock instead of the mate) while in a 2-man group; (2) calling `TargetUnit("party1")` from INSECURE code on the first party-targeted cast popped "Interface action failed because of an AddOn" (ForceTaint_Strong) — the swap was removed entirely. Working 20506 addons that target units do it by NAME from user-triggered flows (`TargetUnit(name, true)` — unitscan.lua:42, NovaWorldBuffs.lua:10277) or via the secure `unit` attribute (M6 ActionBook.lua:260-261) | **Player spells:** set the button's `unit` attribute next to `type="spell"`/`spell=<id>`: `btn:SetAttribute("unit", "party1")` — the M6 ActionBook pattern (numbered group `type-<id>`/`spell-<id>`/`unit-<id>`); the client casts directly on the unit regardless of the current target; `unit=nil` = current-target default; ALWAYS clear the attribute afterwards (stale unit retargets later steps). **Pet abilities:** bake `[@unit]` macro conditionals — `/cast [@party1] Fire Shield` (TBC Classic guides use [@arena1]/[@mouseover] for pet abilities); the legacy `[target=unit]` form does NOT redirect pet casts on this client. **Gate first:** pause with a clear reason when `UnitExists(target)` is false (solo test/raid group/member left) — never silently buff the wrong unit. NEVER call `TargetUnit` from insecure engine code |

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
- **`C_Timer` handle `Cancel()` is UNRELIABLE on 2.5.x — a "cancelled" timer can still fire.** Verified live 2026-08-10: a cancelled `TradeOpen` timer fired after `TRADE_SHOW` (false "window did not open" timeout killed a live trade; the partner attribution was lost → repeat trades), and a cancelled poll ticker kept re-trading with no backoff. AceTimer-3.0 (what Gargul runs on the same client) never relies on `Cancel()` — its callback checks a `cancelled` flag. Pattern: each named timer stores an entry `{active = true, handle}`; `cancel()` sets `active = false` and removes the entry; the C_Timer callback bails unless `entry.active` AND the entry is still the one registered under the name (`Handles[name] == entry`). `handle:Cancel()` is best-effort only. See `Utils/Timers.lua`.
- **Auto-accept is IMPOSSIBLE on 2.5.x — do not implement it.** Verified: the Trade button's XML is `<OnClick function="AcceptTrade"/>`, and `AcceptTrade()` is **RESTRICTED (requires a hardware event)** on the 2.5.6 bcc anniversary client. A programmatic `AcceptTrade()` call OR `TradeFrameTradeButton:Click("LeftButton")` is silently blocked by the client (live log: `Interface action failed because of an AddOn`). `C_SecureTransfer.AcceptTrade()` (the non-restricted retail equivalent) does NOT exist on 2.5.x. The player must confirm the trade manually; the addon only places the items.
- Cursor hygiene: `ClearCursor()` on `TRADE_CLOSED`.

### Spell casting & cast sequences (workflow platform — verified on 20506)

- **Cast out of combat — INSTANT spells only:** `CastSpellByID(spellID)` — TrackingEye casts its
  instant tracking spells with it (`pcall(CastSpellByID, spellId)`, Features/Core.lua:187).
  Name→ID resolution: `select(7, GetSpellInfo(spellNameOrID))` (M6 Categories.lua:44/126,
  Handlers.lua:290). **CAUTION: cast-time spells are blocked OOC (see the gotcha row above)** —
  do not design a workflow step that relies on insecure casting of a cast-time spell.
- **Per-spell gates (all proven 20506):** `IsPlayerSpell` (TrackingEye), `IsUsableSpell`,
  `IsSpellInRange(spell, unit)`, `IsCurrentSpell` (M6 Handlers.lua:317/344), plus the
  `CanCast()` gate from TrackingEye Utilities.lua:141 — `not UnitIsDeadOrGhost("player")`,
  `not IsStealthed()`, `not UnitCastingInfo("player")`, `not UnitAffectingCombat("player")`.
- **GCD / cooldown:** `GetSpellCooldown(spellID)` returns 5 values
  `start, duration, enabled, modRate, active` (M6 Handlers.lua:195; TrackingEye uses
  `start, duration` at Features/Core.lua:172/302). GCD shows as a short `duration` on ANY spell
  → wait `GetSpellCooldown(nextSpell)` until `duration == 0` (or `start + duration <= GetTime()`)
  before the next step. Modern `C_Spell.GetSpellCooldownDuration` / `GetSpellChargeDuration` /
  `GetSpellDisplayCount` / `GetSpellName` also exist (M6 Handlers.lua:96-100).
- **Cast-lifecycle events — ALL registered on 20506:** `UNIT_SPELLCAST_SENT/START/STOP/
  SUCCEEDED/INTERRUPTED/FAILED` (ItemRack ItemRack.lua:294-298/817-821, GatherMate2
  Collector.lua:74-77, M6 Rewire.lua:707). `UNIT_SPELLCAST_SENT` = modern
  `(unit, target, castGUID, spellID)` — GatherMate2 reads the 4th arg as spellID
  (Collector.lua:206). **Sequence advance pattern:** use the events as signals, not data —
  verify state via `UnitCastingInfo("player")` + GCD afterwards (see the SUCCEEDED-args gotcha).
- **Targeted casts (party members):**
  - Combat-safe + prep: M6 ActionBook casts via a `SecureActionButtonTemplate`
    (`Libs/ActionBook/ActionBook.lua:258-263`): `SetAttribute("spell-<id>", sid)` +
    `SetAttribute("unit-<id>", unit)` then click. The only cast path that works in combat —
    and it needs a hardware event per click, so an autonomous in-combat chain stays impossible.
  - **VERIFIED 2026-08-22 — the secure `unit` attribute is the ONLY reliable path**
    (see the gotcha row): `btn:SetAttribute("unit", unit)` next to `type="spell"`/
    `spell=<id>`. The `TargetUnit("party1")` swap is broken on 20506 (mis-targets AND pops
    "blocked action" from insecure code — removed from the engine); pet abilities
    need `[@unit]` macro conditionals, not `[target=unit]`.
  - `SpellIsTargeting()` (active target-cursor check) — ItemRack (20506), ItemRack.lua:1679/2495.
    `SpellCanTargetUnit` / `SpellTargetUnit` are classic-era companions — verify live before use.
- **Movement (pause-on-move):** `IsPlayerMoving()` — BetterFishing (20506) BetterFishing.lua:182,
  M6 Conditionals.lua:262. `PLAYER_STOPPED_MOVING` fires (NovaWorldBuffs.lua:9641/9781). A cast
  broken by movement fires `UNIT_SPELLCAST_INTERRUPTED`. Instant self-buffs cast while moving —
  so "pause when moving" is a design rule (check `IsPlayerMoving()` per step), not a client rule.
- **Warlock IDs:** Soul Shard = item `6265`, Create Healthstone = spell `6201`, summons
  `688/697/712/691/30146` (Imp/Voidwalker/Succubus/Felhunter/Felguard). Resolve names at runtime.
- **Soul Link vs Blood Pact (verified 2026-08-22 via WeakAurasTemplates TBC data):** Soul Link
  (Demonology talent) = spell **19028**; its applied buff aura = 25228 (also named "Soul Link" —
  match buffs by NAME). **6307 is the IMP's Blood Pact passive, NOT Soul Link** — using 6307 as a
  Soul Link step shows "Blood Pact" in the UI and the always-on imp aura satisfies the
  skip-if-buffed check, so the buff is never cast.

### Keybindings (verified on 20506)

- **Menu bindings:** define `BINDING_HEADER_<ADDON> = "<Addon>"` and `BINDING_NAME_<X> = "..."`
  globals (BetterFishing BetterFishing.lua:29) — the player binds them in the Key Bindings UI.
- **Programmatic:** `GetBindingKey(binding)` (BetterFishing:142/297), `SetBinding(key, cmd)`,
  `GetBindingAction(key)`, `SaveBindings(GetCurrentBindingSet())` (GatherMate2 Config.lua:198-246).
- **`GetCurrentBindingSet()` returns `0` (not `nil`) before bindings load** — and
  `SaveBindings(0)` THROWS `Usage: SaveBindings(1||2)`. Live-verified 2026-08-19: this crashed
  `WorkflowEngine:_init()` at `ADDON_LOADED`, taking down the whole addon (`/acp` unregistered).
  Guard with an explicit `1|2` check, NOT a truthiness check (0 is truthy in Lua); retry later
  while `bindingSet() ~= 1 and bindingSet() ~= 2`. Applies to EVERY `SaveBindings` call site.
- **Bindings.xml on 20506:** the client AUTO-LOADS a file named `Bindings.xml` from the addon
  folder by filename convention — it must NOT be listed in the TOC. Listing it double-parses it
  with the UI XML parser, raising `Unrecognized XML: Binding` / `Unrecognized XML attribute: name`
  errors per entry (live-verified 2026-08-19 — 15 error popups with scriptErrors on; every working
  addon on this client ships `Bindings.xml` WITHOUT a TOC reference). deploy.ps1 ships it explicitly.
  Use `category="BINDING_HEADER_<ADDON>"` (resolves via `_G[category]` to the addon's name) so the
  category button appears under the addon's own name, not buried under "ADDONS" (see Phase 9).
- **Direct key-capture control: a `Button` can NOT hold keyboard focus** (verified 2026-08-21). On 2.5.5 `Button` has no `SetFocus()` (only `EditBox` does), so `Button:EnableKeyboard(true)` + `OnKeyDown` NEVER fires — clicking shows "press a key" but no key is ever captured. Capture the key with a **hidden, off-screen `EditBox`** that is `SetFocus()`-ed only while capturing; `OnKeyDown` on that EditBox calls the capture handler; `OnEditFocusLost` re-grabs focus (so a stray click doesn't lose the key); `stopCapture` `ClearFocus()` + `Hide()`s it so the game regains the keyboard. Also validate the captured key before `SetBinding` (uppercase letters/digits + optional `SHIFT-/CTRL-/ALT-` prefix): an invalid key string saved to `bindings-cache.wtf` breaks the WHOLE binding set on the next `/reload` (all hotkeys, movement, Esc/Enter die until the cache is reset). Pattern lives in `UI.Keybind` (Classes/UI/Widgets.lua).
- **`ADDON_UNLOADING` is NOT registerable on 20506** — `Frame:RegisterEvent("ADDON_UNLOADING")`
  throws `Attempt to register unknown event "ADDON_UNLOADING"` (live-verified 2026-08-19; it
  crashed `WorkflowEngine:_init` and killed `/acp`). Use `PLAYER_LOGOUT` for logout-time cleanup;
  for `/reload`-safety rely on NOT persisting transient in-memory binding changes (the reload
  re-reads the saved bindings from disk).
- **Click-bind (ItemRack pattern, in-combat safe):** create a hidden
  `SecureActionButtonTemplate`, `SetBindingClick(key, buttonName)`, run addon logic from the
  button's `PreClick`, and `RegisterForClicks("AnyDown")` — a keybind delivers BOTH a down and an
  up click (ItemRack.lua:2331-2382). Retry while `GetCurrentBindingSet()` is nil (bindings load late).
- **Permanent slot-key override + PreClick = one press starts AND casts (2026-08-22):** point
  each workflow slot's Key Bindings UI key at a per-slot secure button via
  **`SetOverrideBindingClick(owner, true, key, buttonName)`** — a PRIORITY OVERRIDE (verified on
  20506: BetterFishing.lua:276/290). Unlike `SetBindingClick`, an override does NOT displace the
  player's command binding — `GetBindingKey`/`GetBindingAction` keep returning the real binding, so
  the Blizzard Key Bindings UI and addon key-capture fields keep working (a permanent
  `SetBindingClick` takeover made keys UNASSIGNABLE — the UI shows them unbound and every save gets
  re-displaced, live 2026-08-22). The button's **PreClick** runs insecure Lua (`start(slot)` → arm
  the step) and the SAME press's click executes the armed spell/macro (ItemRack pattern). Overrides
  are session-scoped (die on logout — nothing to restore or persist); resync on PLAYER_LOGIN /
  UPDATE_BINDINGS / PLAYER_REGEN_ENABLED by `ClearOverrideBindings(owner)` + re-applying from
  `GetBindingKey` (the binding table itself is never touched). **While the Blizzard Key Bindings UI
  is shown, CLEAR the overrides** (KeyBindingFrame OnShow) — a priority override steals the presses
  from the capture dialog; re-apply on OnHide. **Macro conditionals:**
  `/cast [pet:imp,@party1] Fire Shield` — `[pet:<type>]` makes the press a no-op when that pet is
  not out (prevents the player-cast fallback that interrupted casts and popped "blocked action").
  **Pet-ability timing (verified 2026-08-22):** the client silently swallows a pet ability pressed
  EARLY in the player's cast — Sacrifice at +2 s of a 6 s summon did nothing; +5 s fired. The
  addon must NOT treat the button press as proof — verify the effect instead: buff aura on the
  target by NAME (`GetAuraDataByIndex`), or the Voidwalker unit gone while the player's summon
  cast is still in progress (`waitingForCast and not UnitExists("pet")`).
- **Slash/click trigger:** `/run ACP.Workflows:start(1)` or `/click <buttonName>` works out of combat.

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
- `M6/` (`Core.lua`, `Libs/ActionBook/`) — secure spell/unit casting, `GetSpellCooldown`,
  `GetSpellInfo`, `IsUsableSpell`, event handling (Interface 20506)
- `TrackingEye/` (`Features/Core.lua`, `Features/Utilities.lua`) — `CastSpellByID` out of combat,
  `GetSpellCooldown`, `IsPlayerSpell`, `CanCast()` gate, `UNIT_SPELLCAST_SUCCEEDED` arg2=spellID
- `GatherMate2/` (`Collector.lua`) — `UNIT_SPELLCAST_SENT` modern signature,
  `UNIT_SPELLCAST_STOP/FAILED/INTERRUPTED`, `SetBinding`/`SaveBindings`
- `ItemRack/` (`ItemRack.lua`) — `UNIT_SPELLCAST_*` registration, `SpellIsTargeting`,
  `SetBindingClick` + secure-button keybinding pattern
- `BetterFishing/` (`BetterFishing.lua`) — `BINDING_NAME_*`, `GetBindingKey`, `IsPlayerMoving`,
  `UnitChannelInfo` spellID at pos 8, `SetOverrideBindingSpell`
- CAUTION: `BetterBlizzFrames/` and `Details/` in this workspace are RETAIL builds (Interface
  120007) — their `UnitCastingInfo`/`C_Spell`/luaserver usage is NOT 20506 proof; verify against
  a 20506 addon first (see `.ai/docs/workflow-engine-research.md` for the full evidence index).

See `Data/Constants.lua`, `Utils/Items.lua`, `Classes/ArenaPrep.lua`, `Classes/TradeManager.lua` for live examples of every pattern above.
