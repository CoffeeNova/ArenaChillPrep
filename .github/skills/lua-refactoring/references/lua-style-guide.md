# Lua Style Guide

Distilled from the LuaRocks style guide, the Olivine-Labs style guide, and Programming in Lua, then adapted to the conventions proven in this workspace (ArenaChillPrep / Gargul).

**Rule of thumb: the file being edited wins.** Match its indentation, quotes, semicolons, and module pattern. Use this guide when the file has no established style or when asked for a general style opinion.

## Workspace Conventions (ArenaChillPrep / Gargul — highest priority)

- **Lua 5.1**, no external libraries (no Ace) — self-contained addon.
- **Module pattern**: every file is a module table; `local _, ACP = ...;` at the top, `return ACP;` at the end.
- **Type annotations**: `---@class`, `---@param`, `---@return` on all public functions (Pylance/LLS-friendly).
- **Globals**: accessed via `_G.` prefix; aliased to `local` at the top of the file (`local UnitExists = _G.UnitExists;`).
- **4-space indentation**, semicolons as statement terminators (this workspace's existing style — keep it).
- **Structure**: `Data/` (static tables), `Classes/` (service modules), `Utils/` (helpers).
- **UI strings** go through the localization table (`L`, metatable fallback to key) — never hard-code UI text in modules.
- **Cross-session state** only via SavedVariables (`ArenaChillPrepDB`) accessed through `ACP.Settings`; runtime state lives in module fields.
- All documentation and code comments in English.

## Naming

| Kind | Convention | Example |
|---|---|---|
| Variables & functions | `snake_case` | `total_count`, `find_item_in_bags` |
| Classes / modules (OOP) | `CamelCase` | `DeliveryController`, `TradeManager` |
| Constants | `UPPER_CASE` (sparingly — Lua has no real constants) | `MAX_TRADE_RETRIES`, `TRADE_ITEM_TICK` |
| Boolean functions | `is_` / `has_` prefix | `is_ready`, `has_charges` |
| Ignored values | `_` | `for _, item in ipairs(items)` |
| Loop counters | `i`, `j` only as numeric counters | `for i = 1, n do` |

- Larger scope → more descriptive name. One-letter names only inside tiny loops/functions (< ~10 lines).
- Don't use names starting with `_` + uppercase (reserved by Lua).
- Prefer `is_ready` over `check_ready` for predicates; `check_ready` implies side effects.

## Formatting

- **Indentation**: spaces, not tabs. Default 4 (this workspace) or 2 — pick per file and stay consistent.
- **LF line endings**, trailing newline at end of file.
- **Spaces**: after commas, around operators (`=`, `+`, `..`, `==`), after `--`.
- **No semicolons as statement separators** in the generic guides — but this workspace uses them; keep the file's style.
- **Blank line between functions.** Blank line after a multiline block.
- **Don't align variable declarations** (`local a = 1` / `local long_name = 2` — no padding) — reduces diff noise.
- **Line length**: no hard limit; if a line exceeds ~120 chars it usually means the expression is too complex — split into named subexpressions.
- **Multiline tables**: one field per line, trailing comma on the last field (shorter diffs when adding fields):

```lua
local player = {
    name = "Jack",
    class = "Rogue",
}
```

- **Function calls**: always use parentheses for single string/table args on one line. Multi-line table args may drop parens (`setmetatable(self, { ... })` style).

## Functions

- Prefer `local function name()` over `local name = function()` (clearly named, hoisted).
- **Validate early, return early** (guard clauses). Flatten nesting to ≤ 3 levels.
- Keep functions small (< ~30 lines). If it grows, split — names explain what each part does.
- Never name a parameter `arg`.
- Use method syntax when calling methods: `obj:method()` not `obj.method(obj)`.
- Multiple return values are idiomatic in Lua — `return nil, "error message"` for expected failures.
- Use `...` for varargs; don't rely on an implicit `arg` table.

## Tables

- Use constructor syntax; populate fields at declaration when possible.
- Use dot notation for known keys (`luke.jedi`), subscript notation for dynamic keys (`t[key]`).
- **Key type discipline**: decide per table whether keys are numbers or strings and stick to it. `t[19013]` and `t["19013"]` are different slots — normalize once (e.g. `tonumber(k)` when loading SavedVariables).
- Use `#` only on dense arrays. For lists that may hold `nil`, track `n` explicitly.
- When a table holds functions, use `self` in their bodies if they operate on the table.

## Conditionals

- `nil` and `false` are both falsy — use shortcuts: `if name then`, `local v = x or "default"`.
- Truthy-first: prefer `if thing then` over `if not thing then` when the positive branch is the main path.
- Prefer defaults over `else` where it reads better:

```lua
-- Prefer
local name = "John Smith"
if first and last then
    name = first .. " " .. last
end

-- Over
local name
if first and last then name = first .. " " .. last else name = "John Smith" end
```

- `x and y or z` pseudo-ternary: OK when `y` can never be `nil`/`false`. Never use it to return booleans — write an explicit `if`.
- Single-line blocks only for `then return`, `then break`, and lambda returns. Anything more complex gets a real block.

## Comments & Docs

- Prefer LDoc-style block comments above functions over inline "how" comments inside them:

```lua
--- Count items matching itemID across all bags (stack-aware).
---@param itemID number
---@return number
local function count_item_in_bags(itemID)
    ...
end
```

- Comments explain **why** (non-obvious invariants, client gotchas, intent), not **how**.
- `-- TODO:` missing feature; `-- FIXME:` problem in existing code.
- When a comment starts explaining a complicated body, that body probably should be its own function.

## Modules & OOP

- Modules return a table; `require`-free workspace uses the vararg pattern (`local _, ACP = ...;`).
- A module should not set globals and should not have hidden state at load; make configurable modules factories.
- OOP in Lua 5.1 (standard pattern):

```lua
---@class Healthstone
local Healthstone = {}

function Healthstone:use()
    -- code
end

---@return Healthstone
function Healthstone.new()
    local self = {}
    setmetatable(self, { __index = Healthstone })
    return self
end
```

- Keep the class table local; build the metatable once (shared), not per instance.
- Use colon notation for methods (`function Class:method()`) and when calling (`instance:method()`).
- Do not rely on `__gc` for resource cleanup other than memory — provide explicit `close()`/`cancel()` methods.

## Errors

- Expected failures (I/O, API missing on client) → return `nil, message`.
- API misuse → `error()` / `assert()`.
- In non-performance-critical code, lightweight type asserts are fine: `assert(type(x) == "string")`.
- Use `tostring()` / `tonumber()` explicitly; avoid coercion tricks (`"" .. value`).

## Static Quality

- Code should pass luacheck-style checks: no unused locals, no globals assigned, no undefined globals (use `_G.` explicitly).
- Prefer `local` always; smallest possible scope.
- Remove dead code — commented-out blocks, unused functions, unreachable branches. Git history preserves them.
