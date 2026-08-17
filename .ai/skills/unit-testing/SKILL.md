---
name: unit-testing
description: How to write and run the ArenaChillPrep unit tests (luaunit + luacov under LuaJIT, outside the game). Covers the runner, the WoW stub environment, suite layout, AAA conventions, and the cross-suite state-pollution gotchas learned the hard way. Use whenever adding, fixing, or running tests, or when a change touches module logic.
---

# Unit testing (ArenaChillPrep)

The addon is unit-tested **outside the game** under LuaJIT (Lua 5.1 — the same version WoW uses). No game client needed. Coverage target: **≥ 90%** of all non-UI modules (currently 96%+). `OptionsUI.lua` is excluded (UI code — checkboxes/forms/labels).

## When to touch the tests

- **Do NOT edit the unit tests while implementing a feature.** Write/fix production code first; leave `Tests/` alone during the implementation phase.
- **Only after the feature is finished AND the user gives permission** may you update the tests (add coverage for the new behavior, fix tests broken by the change).
- **Exception:** the user explicitly asked to edit tests — then this skill applies in full.

## Run the suite

```powershell
.\Tests\run-tests.ps1
```

or from the addon root:

```powershell
luajit Tests\run_tests.lua
```

Requires LuaJIT on PATH (`winget install DEVCOM.LuaJIT`).

**Exit codes:** `0` = all tests pass AND coverage ≥ 90%, `1` = test failures, `2` = coverage < 90%.

**Outputs:** test results to stdout; coverage report to `Tests/luacov.report.out` (per-file Hits/Missed/Coverage + Total). Both `luacov.stats.out` and `luacov.report.out` are gitignored (regenerated every run).

## Architecture

```
Tests/
├── run_tests.lua         # Runner: luacov + luaunit + stubs + loader + coverage gate
├── run-tests.ps1         # PowerShell wrapper (exit codes above)
├── loader.lua            # Loads every addon module in TOC order via the vararg chain
├── helpers.lua           # SINGLETON (cached on _G.__TEST_HELPERS): SyncTimers, deepCopy,
│                         #   reloadModule, resetAll()
├── stubs/wow_stubs.lua   # WoW API stubs; mutable state in _G.__stub
├── lib/                  # Vendored: luaunit 3.5 + luacov 0.17 (do not edit)
├── test_bootstrap.lua    # bootstrap suite (mirrors bootstrap.lua at the addon root)
├── Data/                 # Suites mirror the addon structure
│   └── test_*.lua        #   constants, items, defaultsettings, localization
├── Utils/
│   └── test_*.lua        #   tables, items, timers
└── Classes/
    └── test_*.lua        #   events, settings, arenaprep, inventory,
                          #   deliverycontroller, trademanager
```

- **Suite layout mirrors the addon structure**: `Classes/ArenaPrep.lua` → `Tests/Classes/test_arenaprep.lua`. `test_bootstrap.lua` stays at the `Tests/` root.
- **The runner keeps an explicit ordered list of suite paths** — order matters because some suites capture file-scope state (e.g. `test_deliverycontroller` saves the real Timers at load). When adding a suite, add its path to the `suites` list in `run_tests.lua`.
- **luaunit discovers `test*` functions alphabetically across ALL suites** — a test in one suite can break a test in another. This is the #1 gotcha (see below).

## The WoW stub environment

`Tests/stubs/wow_stubs.lua` replaces the WoW API so modules load and run under plain LuaJIT:

- **Mutable state lives in `_G.__stub`**: `time`, `inInstance`, `aura`, `auraByIndex`, `partyCount`, `unitExists`, `unitIsUnit`, `inCombat`, `dead`, `tradeFrameShown`, `bags`, `cTimerCallbacks`, `chatMessages`.
- **File-scope captures read `_G.__stub`**: `GetTime`, `IsInInstance`, `C_UnitAuras.GetPlayerAuraBySpellID`, `TradeFrame:IsShown`, `ERR_TRADE_COMPLETE`, `C_Timer.After/NewTicker`, `DEFAULT_CHAT_FRAME`. To change these, mutate `_G.__stub` — do NOT replace the globals (the modules already captured them).
- **Call-time reads can be overridden directly**: containers (`GetContainerNumSlots`, `GetContainerItemInfo`), `UnitClass`, `UnitName`, `GetNumPartyMembers`, `InitiateTrade`, `UseContainerItem`, `ClearCursor`, `C_Item.GetItemGUID`.

### Container stubs — two forms!

- `C_Container.GetContainerItemInfo` returns a **TABLE** (`ContainerItemInfo` with `.itemID .stackCount .isBound ...`).
- The legacy global `GetContainerItemInfo` returns the **11-value tuple** (`nil, stackCount, locked, quality, readable, hasLoot, link, filtered, noValue, itemID, bound`).
- `Utils/Items` prefers the GLOBAL `GetContainerNumSlots` but `C_Container` for `GetContainerItemInfo` — **override all four** in bag stubs:

```lua
local fakeSlots = function(bag) return fake[bag] and #fake[bag] or 0 end;
local fakeInfo = function(bag, slot)  -- C_Container form (table)
    local e = fake[bag] and fake[bag][slot];
    if (not e) then return nil; end
    return { iconFileID = nil, stackCount = e.stackCount, isLocked = false,
             quality = 0, isReadable = false, hasLoot = false, hyperlink = nil,
             isFiltered = false, hasNoValue = false, itemID = e.itemID, isBound = e.bound };
end;
local fakeLegacyInfo = function(bag, slot)  -- legacy global form (tuple)
    local e = fake[bag] and fake[bag][slot];
    if (not e) then return nil; end
    return nil, e.stackCount, false, 0, false, false, nil, false, false, e.itemID, e.bound;
end;
_G.GetContainerNumSlots = fakeSlots;
_G.GetContainerItemInfo = fakeLegacyInfo;
_G.C_Container.GetContainerNumSlots = fakeSlots;
_G.C_Container.GetContainerItemInfo = fakeInfo;
```

## Helpers (`Tests/helpers.lua`)

`helpers.lua` is a **singleton** — `dofile` it in every suite; it returns the same table (`_G.__TEST_HELPERS`), so all suites share one `SyncTimers` recorder:

```lua
local H = dofile(_G.__TESTS_ROOT .. "/helpers.lua");
```

- **`H.SyncTimers`** — synchronous timer recorder. `after`/`interval` STORE the callback, nothing runs on its own. Swap it in: `ACP.Utils.Timers = H.SyncTimers;`. Advance explicitly: `H.advance("TradeDelay")` (runs the callback and removes it), check with `H.hasTimer("TradeDelay")`.
- **`H.deepCopy(t)`** — recursive copy (for snapshotting Settings/defaults).
- **`H.reloadModule(relPath)`** — re-loads an addon module through the vararg chain (to re-capture file-scope globals, e.g. the ArenaPrep fallback branch).
- **`H.resetAll()`** — re-inits ALL modules + wipes the event bus + clears timers. **REQUIRED at the start of every event-driven test** (events cascade across modules: `BAG_UPDATE` → `ACP_ITEMS_CHANGED` → DeliveryController).

## Writing tests — conventions

- **Compact**: each test ≤ 15 lines (preferably ≤ 10). No shared data factories — each test builds its own data.
- **AAA comments**: `-- Arrange` / `-- Act` / `-- Assert`.
- **Assert both result AND mock behavior**: e.g. check `InitiateTrade` was called, `UseContainerItem` was called, `ClearCursor` was called — not just the return value.
- **Use the real modules where possible**: drive `ArenaPrep`/`Inventory` through `_G.__stub` + module state (no method overrides → no cross-suite leakage). Only swap `ACP.Utils.Timers` for `H.SyncTimers`.
- **Event-driven tests** fire bus events via `ACP.Events:fire("EVENT", ...)` and must call `H.resetAll()` first, then re-register the module's handlers (`reinitX()` pattern: `X._initialized = false; X:_init();`).
- **Restore everything you mutate**: Settings DB, module state, globals, event bus. A test that doesn't restore WILL break a later test in another suite.

## Gotchas (learned the hard way — read before writing tests)

1. **luaunit runs tests alphabetically across suites.** A test in one suite can break a test in another. Every test must restore what it mutates.
2. **`Settings:_init` deep-copies the defaults** — the live `Data` is fully detached from `ACP.Data.DefaultSettings` (a historical `shallowCopy` shared nested tables and let `Settings:set` corrupt the defaults permanently; fixed). Settings tests still restore pristine defaults before each test (`freshSettings`) so no state leaks across suites:
   ```lua
   local PristineDefaults = H.deepCopy(ACP.Data.DefaultSettings);
   local function freshSettings()
       ACP.Data.DefaultSettings = H.deepCopy(PristineDefaults);
       _G.ArenaChillPrepDB = H.deepCopy(PristineDefaults);
       Settings._initialized = false;
       Settings:_init();
   end
   ```
3. **`TradeManager.startTrade` bails when `self.trading` is true.** DC tests must stub `startTrade` directly (`ACP.TradeManager.startTrade = function(_, unit) State.LastTradeUnit = unit; end`) — NOT via `InitiateTrade` — or the `trading` flag leaks between tests.
4. **`test_events.lua`'s `resetEvents()` wipes the bus.** Event-driven tests in other suites must re-register handlers (`reinitX()`) after it runs.
5. **`ACP.Events:_init(ACP.Frame)` overwrites bootstrap's OnEvent.** Bootstrap tests must re-run bootstrap on a fresh frame to capture its handler.
6. **`testScanBuffFallback` reloads ArenaPrep** (to capture the nil primary lookup) — must re-init after to restore event registrations.
7. **`testInitMergesDefaults` leaves `enabled=false` in the DB** — must restore pristine defaults after.
8. **`testCanStartTradeCombat`/`testCanStartTradeDead` leave `_G.__stub.inCombat`/`dead` true** — `installStubs()` must re-sync them from State.
9. **State fields must be set BEFORE `installStubs()`** — `installStubs` copies State into module state; setting fields after is a no-op.
10. **`testQueueConfiguredItems*` override `ACP.Inventory.getCount`** — must restore the original, or later Inventory tests read the stub.

## Adding a new test suite

1. Create `Tests/<Data|Utils|Classes>/test_<module>.lua` mirroring the addon structure.
2. Add its path to the `suites` list in `Tests/run_tests.lua` (order matters — keep it near its dependency group).
3. Add the module to the luacov `include` list in `run_tests.lua` if it's a new addon module.
4. Run `.\Tests\run-tests.ps1` — must exit 0 (pass + coverage ≥ 90%).
5. If coverage drops below 90%, add tests for the uncovered branches (check `Tests/luacov.report.out` for `*0` lines).

## When a test fails

- Run the failing test in isolation first: `luajit -e "package.path='Tests/lib/luaunit/?.lua;Tests/lib/luacov/?.lua;'..package.path; dofile('Tests/stubs/wow_stubs.lua'); local ACP=(loadfile('Tests/loader.lua'))('.'); _G.lu=require('luaunit'); ACP.Events:_init(ACP.Frame); _G.ArenaChillPrepDB=nil; ACP.Settings:_init(); ACP.ArenaPrep:_init(); ACP.Inventory:_init(); ACP.TradeManager:_init(); ACP.DeliveryController:_init(); _G.__TESTS_ROOT='Tests'; _G.__ADDON_ROOT='.'; dofile('Tests/helpers.lua'); dofile('Tests/Classes/test_<module>.lua'); lu.LuaUnit.run('testName');"` — if it passes alone, it's cross-suite pollution (see gotchas).
- Check the coverage report for the exact uncovered lines (`*0` prefix).
- Remember: a test that passes in isolation but fails in the full run is ALWAYS cross-suite state pollution — find what the previous alphabetical test left behind.