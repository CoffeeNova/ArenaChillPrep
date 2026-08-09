# Lua Refactoring Playbook

The full catalog of smells and techniques, with before/after examples in Lua 5.1 (WoW addon flavor, matching the workspace module pattern).

## Refactoring Mindset

- One refactor at a time; verify each step.
- Structure changes only — same events, same state, same settings paths, same return values.
- If a step would change behavior, stop and separate it into a feature/bugfix change instead.
- Prefer the simplest construct that is obviously correct. "Clever" Lua hurts both humans and AI readers.

---

## Smell Catalog

### S1. Global pollution
Assignments without `local` leak into `_G` (or the file's environment) — name collisions, state bleed, hard-to-trace bugs.

```lua
-- Bad
total_count = 0  -- global!

-- Good
local total_count = 0
```

### S2. God function / god module
A function > ~30 lines doing several things, or a module that scans bags, opens trades, and renders UI at once.

**Symptoms**: many `self.` fields mutated in one method, many `and`/`or` chains, several responsibilities in the name.

**Fix**: extract functions (T2), extract modules (T3).

### S3. Arrow code (deep nesting)
More than 3 levels of `if`/`for`. Hard to read; easy to misplace an `end`.

```lua
-- Bad
function check_ready()
    if self.state == "ACTIVE" then
        if is_in_arena() then
            if not UnitAffectingCombat("player") then
                if remaining() >= GATE_SAFETY then
                    start_trade()
                end
            end
        end
    end
end

-- Good (T1 guard clauses)
function check_ready()
    if self.state ~= "ACTIVE" then return end
    if not is_in_arena() then return end
    if UnitAffectingCombat("player") then return end
    if remaining() < GATE_SAFETY then return end
    start_trade()
end
```

### S4. Magic numbers and strings
Inline IDs, timings, thresholds with no name.

```lua
-- Bad
C_Timer.After(0.15, tick)
if item_id == 19013 then ...

-- Good
local TRADE_ITEM_TICK = 0.15  -- or Data/Constants
C_Timer.After(TRADE_ITEM_TICK, tick)
```

### S5. Duplicated logic
The same loop/check copy-pasted in several modules (e.g. bag scans, item counting). One fix site later turns into three.

**Fix**: extract to `Utils/` or a shared helper (T3), then delete the copies.

### S6. Long parameter lists
More than ~4 positional parameters — call sites are unreadable and order mistakes compile silently.

```lua
-- Bad
function create_trade(partner, delay, retries, timeout, auto_accept) ...

-- Good (T5 options table)
---@class TradeOptions
---@field delay number
---@field retries number
---@field timeout number
---@field auto_accept boolean
function create_trade(partner, options) ...
```

### S7. Stringly-typed if-chains
`if category == "healthstones" then ... elseif category == "soulstones"` — grows forever, easy to typo.

```lua
-- Bad
if category == "healthstones" then
    self:prepare_healthstones()
elseif category == "soulstones" then
    self:prepare_soulstones()
end

-- Good (T6 table lookup)
local PREPARERS = {
    healthstones = function(self) self:prepare_healthstones() end,
    soulstones = function(self) self:prepare_soulstones() end,
}
local preparer = PREPARERS[category]
if preparer then preparer(self) end
```

### S8. Primitive obsession
Passing bare strings/numbers where a small structured value communicates intent — e.g. two parallel arrays `{item_ids}`, `{counts}` that must stay in sync.

```lua
-- Bad
local ids = {19012, 19013, 22105}
local counts = {1, 1, 1}  -- must always be edited together

-- Good
---@class RankSpec
---@field id number
---@field count number
local ranks = {
    { id = 19012, count = 1 },
    { id = 19013, count = 1 },
    { id = 22105, count = 1 },
}
```

### S9. Unclear names
`t`, `tmp`, `hnd`, `cnt`, abbreviations. AI models (and humans) read names as documentation.

**Fix**: intention-revealing names (T8). `local items_ready = ...` instead of `local rdy`.

### S10. Table key type confusion (Lua-specific, real bug)
`t[19013]` and `t["19013"]` are **different slots**. Classic in WoW SavedVariables: defaults use numeric keys, dot-path setters write strings — the code then reads the other type and gets `nil`.

```lua
-- Bad
settings["19013"] = true   -- string key
if settings[19013] then    -- number key -> nil! silent bug

-- Good
settings[19013] = true     -- numeric key everywhere
if settings[19013] then ...

-- Or normalize once on load:
local function normalize_keys(t)
    for k, v in pairs(t) do
        if type(k) == "string" and tonumber(k) then
            t[tonumber(k)] = v
            t[k] = nil
        end
    end
    return t
end
```

### S11. Dead code
Unused functions, unreachable branches, commented-out blocks, unused parameters. Remove them — the refactor is the cleanup moment.

### S12. Unsafe boolean ternaries
`local ok = cond and x or y` breaks when `x` is `nil`/`false`. Never use it to compute booleans.

```lua
-- Bad
local is_ready = self.state == "ACTIVE" and self.items_ready or false

-- Good
local is_ready = false
if self.state == "ACTIVE" and self.items_ready then
    is_ready = true
end
```

---

## Technique Catalog

### T1. Guard clauses (early return)
Flatten nested conditionals by inverting conditions and returning early. See S3.

- Do this *first* when a function is deeply nested — it unlocks all other extractions.
- Keep the function's public signature identical.

### T2. Extract function
Split a god function into named `local function`s. Place helpers **below** the caller or at the bottom of the module (Lua hoists `local function` within its scope — but only if declared before use at runtime, so put helpers above the first call site or use forward `local f` declarations).

```lua
-- Before: bag-counting loop buried inside a big method
local total = 0
for bag = 0, NUM_BAGS - 1 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID == target_id then
            total = total + (info.stackCount or 1)
        end
    end
end

-- After: named helper with a contract
--- Count items matching itemID across all bags (stack-aware).
---@param itemID number
---@return number
local function count_item_in_bags(itemID)
    local total = 0
    for bag = 0, NUM_BAGS - 1 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                total = total + (info.stackCount or 1)
            end
        end
    end
    return total
end
```

- Good extraction boundaries: one clear input → one clear output; no hidden side effects.
- When extracting, move the `---@param`/`---@return` annotations with the code.

### T3. Extract module / move to Utils
Logic reused by several modules belongs in a shared helper.

- Move generic helpers (table ops, bag scans, timers) to `Utils/`.
- Move a cohesive service (e.g. trade window automation) to its own `Classes/` module.
- In this workspace: update `bootstrap.lua` load order and `.github/` docs if the file list changes.
- Keep the module API small and stable: few public functions, everything else `local`.

### T4. Extract constants
Replace inline values with named constants — module-local `local` at the top, or `Data/Constants` when shared.

```lua
-- Before
if remaining_time < 15 then return end
C_Timer.After(1.0, retry)

-- After
local GATE_SAFETY_SECONDS = 15   -- local when file-private
-- shared: ACP.Data.Constants.GATE_SAFETY_SECONDS
if remaining_time < GATE_SAFETY_SECONDS then return end
C_Timer.After(TRADE_OPEN_TIMEOUT, retry)
```

### T5. Options / parameter table
Bundle long positional parameter lists into a single options table with `or` defaults. See S6.

- Document the table shape with a `---@class` annotation.
- Use `options.delay or DEFAULT` for optional fields; keep required fields positional.

### T6. Table lookup over if-chains
Replace `if/elseif` dispatch on strings with a map from key → handler. See S7.

- Build the map once as a module-level `local` (not per call).
- Fall through gracefully: `local handler = map[key]` then `if handler then handler(...) end`.

### T7. Local aliases for globals
Alias frequently used globals at the top of the file. Faster (no `_G` chain lookup on old clients) and signals dependencies.

```lua
-- Before
if _G.UnitAffectingCombat("player") then return end
local name = _G.UnitName(_G.UnitExists("party1") and "party1" or "player")

-- After
local UnitAffectingCombat = _G.UnitAffectingCombat
local UnitName = _G.UnitName
local UnitExists = _G.UnitExists
...
if UnitAffectingCombat("player") then return end
```

- Guard optional globals: `local CLASS_WARLOCK = _G.CLASS_WARLOCK or "WARLOCK"` (verified: some constants are missing on TBC Anniversary — an unguarded alias becomes `nil` and crashes at call time).
- For APIs that may not exist at all, use call-time shims instead of load-time aliases:

```lua
local function get_container_num_slots(bag)
    local fn = _G.GetContainerNumSlots or C_Container.GetContainerNumSlots
    return fn(bag)
end
```

### T8. Rename for intention
Make names state *what* the code does:

```lua
-- Bad
local function upd(t, i) t[i] = t[i] + 1 end

-- Good
--- Increment the count for itemID.
---@param counts table<number, number>
---@param itemID number
local function increment_count(counts, itemID)
    counts[itemID] = counts[itemID] + 1
end
```

- Boolean predicates: `is_ready`, `has_charges`, `can_trade` (T8 with S9).
- Renaming a **public** method/field requires updating every call site — grep for usages first.

### T9. Remove dead code
Delete unused locals/functions, commented-out blocks, and unreachable branches. If a branch is intentionally a no-op ("pass"), keep it with a `-- pass` comment instead of deleting (preserves switch-style case lists).

---

## Verification Checklist

After each refactor step:

1. **Read the changed region** in full. Reading the whole file is cheap and catches context breaks.
2. **Block balance**: every `function`/`if`/`do`/`for`/`while`/`repeat` has its `end`. A quick count of `end` keywords vs opening keywords catches unbalanced blocks.
3. **Module contract intact**: `return ACP;` present; `---@class` annotations updated; public names unchanged (or call sites updated).
4. **No behavior drift**: same events fired, same state transitions, same Settings paths, same timings.
5. **Tests**: run sandbox tests if they exist (`ACP.Tests:run()` or the Tests/ harness). Run before and after to prove no behavior change.
6. **Gotchas re-checked**: no `x and y or z` returning booleans, no mixed number/string keys, no `#` on sparse tables, no unguarded globals.
7. If no interpreter is available (common for WoW addons), say verification was manual and list what was checked.

## End-to-End Mini Case

A `check_ready()` with 4 levels of nesting, inline magic values, and a duplicated bag loop:

1. **T1** guard clauses → flat linear flow.
2. **T4** extract `GATE_SAFETY_SECONDS`, `TRADE_OPEN_TIMEOUT` → named constants.
3. **T2** extract the bag-counting loop → `count_item_in_bags(itemID)` with `---@param`/`---@return`.
4. **T7** alias `UnitAffectingCombat`/`C_Container` at the top of the file.
5. **T9** delete the now-unused local that the extraction replaced.
6. **Verify** → read file, balance check, run `ACP.Tests:run()` if available.
