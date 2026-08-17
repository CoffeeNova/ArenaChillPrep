---
name: lua-refactoring
description: 'Refactor Lua code (WoW addons, Lua 5.1) for readability, extensibility, reliability, and consistent formatting. Use when asked to refactor, clean up, restructure, simplify, or improve Lua files; when fixing code smells (god functions, global pollution, duplicated logic, magic numbers, deep nesting, unclear naming, primitive obsession); when making Lua code easier to read by humans and AI models; when splitting large modules or extracting helpers. Covers style rules, code smell detection, refactoring techniques with before/after examples, and Lua 5.1 pitfalls (nil vs false, number vs string table keys, # operator, metatables).'
---

# Lua Refactoring

Restructure Lua code so it is **easy to read by humans and AI models**, **easy to extend**, **reliable**, and **consistently formatted** — without changing observable behavior.

This skill is a Lua-specific adaptation of the general refactoring specialist mindset (small steps, behavior-preserving, intention-revealing). It combines researched Lua best practices (LuaRocks style guide, Olivine-Labs style guide, Programming in Lua) with the conventions already proven in this workspace (`ArenaChillPrep`, `Gargul`).

## When to Use

- User asks to **refactor, clean up, restructure, simplify, or improve** Lua files.
- Code has smells: god functions/modules, global pollution, duplicated logic, magic numbers, deep nesting, unclear naming, primitive obsession.
- A module has grown too large and needs splitting into coherent units.
- Making code friendlier for **AI models** (predictable structure, explicit naming, no ambiguous idioms) and for **humans** (clear flow, good comments).
- Normalizing formatting and style across files.

## When NOT to Use

- Adding new features or changing behavior — that is implementation work, not refactoring.
- Debugging a runtime error — fix the bug first, then refactor.
- Rewriting from scratch — prefer small, incremental refactors over massive rewrites.
- Refactoring code whose behavior you cannot verify (no tests, no sandbox) without extra care.

## Core Principles

1. **Behavior-preserving.** Refactoring changes *structure*, never *behavior*. Same events, same state transitions, same settings paths, same return values.
2. **Small incremental steps.** One refactor per change. Verify after each step. Never mix refactoring with bug fixes or feature work in the same edit.
3. **Readability for humans AND AI.** Prefer predictable patterns, explicit naming, linear control flow, and idiomatic Lua. AI models read code structurally — the more regular the code, the better both parse it.
4. **Reliability first.** Lua 5.1 has sharp edges (see pitfalls below). Refactored code must be *more* defensive, never less.
5. **Match existing conventions.** The project's `.ai/CONTEXT.md` and the surrounding file are the source of truth for style (indentation, semicolons, module pattern). The style guide in this skill is the fallback when the file has no established style. Consistency within a file beats any guide.

## Workflow

### Step 1 — Analyze

1. Read the file(s) fully (prefer large reads over many small ones).
2. Read `.ai/CONTEXT.md` and `.ai/ARCHITECTURE.md` if the file touches addon behavior.
3. Identify smells against the checklist in the [refactoring playbook](./references/refactoring-playbook.md).
4. Note the module's **public surface**: functions/fields other modules call. These form the contract — renaming them requires updating every call site.

### Step 2 — Plan

1. Produce a short plan: list each refactor as a separate item (e.g. "extract `countItemInBags`", "add guard clauses to `checkReady`", "move helper to `Utils/Tables`").
2. Order by risk: low-risk pure-structure changes first (extract, rename-local, guard clauses), then module moves.
3. If sandbox tests exist (`Tests/*_sandbox.lua`, e.g. `ACP.Tests`), plan to run them after the risky steps. If not, plan a careful manual re-read as verification.
4. Show the plan to the user and get consent before editing (per workspace rule: plan before editing files).

### Step 3 — Refactor

Apply one refactor at a time using the [technique catalog](./references/refactoring-playbook.md). Rules:

- Keep the file's existing indentation, quote style, and semicolon usage.
- Preserve the module pattern: `local _, ACP = ...;` at top, `return ACP;` at the end of every module file in this workspace.
- Keep `---@class` / `---@param` / `---@return` annotations accurate — they are part of the contract for AI tooling.
- Preserve local aliases of globals at the top of the file; add new ones when you introduce new globals (performance + readability).
- Do not convert working patterns to "more clever" Lua. Favor the simplest construct that is obviously correct.

### Step 4 — Verify

1. Re-read every changed region (the whole file if edits were extensive).
2. Check block balance: every `function ... end`, `if ... end`, `do ... end`, `for ... end` is closed. Counting `end` keywords is a cheap sanity check.
3. Confirm `return ACP;` still terminates module files and no `local` declarations were dropped.
4. Confirm public function names/signatures are unchanged (or all call sites updated).
5. Run sandbox tests if available (e.g. `/run ACP.Tests:run()` in game, or via the Tests/ harness). If a test suite covers the changed area, run it *before and after* to prove behavior is unchanged.
6. If no interpreter/tests are available, state that verification was manual.

### Step 5 — Document

- If the refactor changed structure that other agents depend on (module moved, function renamed, data layout changed), update `.ai/` docs **first** — they are the contract (per `AGENTS.md`).
- Update repo memory (`/.ai/memories/repo/`) with any new verified gotchas or decisions.
- Never update `README.md` (human-facing) for technical refactors.

## Quick Smell Checklist

| Smell | Fix |
|---|---|
| Missing `local` (global pollution) | Add `local`, smallest scope |
| God function > ~30 lines | Extract functions (guard clauses, named helpers) |
| Deep nesting (arrow code) | Guard clauses / early return |
| Magic numbers & strings | Named constants (module-local or `Data/Constants`) |
| Duplicated logic across modules | Extract to `Utils/` or a shared helper |
| Long parameter lists (> 4) | Options/parameter table |
| Stringly-typed if-chains | Table lookup (map key → handler) |
| Primitive obsession | Small value tables (`{id, count, rank}`) |
| Unclear names (`t`, `tmp`, abbreviations) | Intention-revealing names, `is_`/`has_` for booleans |
| Table key type confusion (`[13]` vs `["13"]`) | One key type everywhere; normalize on load |
| Dead code, commented-out blocks | Remove |
| `x and y or z` returning booleans | Rewrite as `if x then return y else return z end` |

## Quick Techniques

1. **Guard clauses** — flatten nested `if`s into early returns.
2. **Extract function** — split god functions into named `local function`s below the caller.
3. **Extract module** — move related helpers into `Utils/` or a new `Classes/` module.
4. **Extract constants** — replace inline IDs/timings with UPPER_CASE locals or `Data/Constants`.
5. **Options table** — bundle long parameter lists into a config table.
6. **Table lookup over if-chains** — replace `if x == "a" then ... elseif x == "b"` with `map[x]`.
7. **Local aliases** — `local UnitExists = _G.UnitExists;` at the top of the file.
8. **Rename for intention** — make names say *what* the code does, not *how*.

## Lua 5.1 Pitfalls (must-know for safe refactors)

- **`nil` and `false` are both falsy.** Prefer truthiness shortcuts, but do not build APIs that distinguish them unless needed.
- **`x and y or z` breaks when `y` is `nil`/`false`** — never use it to return booleans; use an `if`.
- **Table keys: numbers and strings are different keys.** `t[13]` and `t["13"]` are two distinct slots — a classic WoW SavedVariables bug. Pick one type and normalize on load (`tonumber(key)`).
- **`#` is undefined on sparse tables** (holes in the `1..n` array part). Use it only on dense array tables; track length explicitly for lists that may contain `nil`.
- **`table.insert/remove` shift indices** — don't iterate with `ipairs` while removing elements; iterate backwards.
- **No real constants in Lua.** UPPER_CASE is a convention; treat constants as module-local to prevent accidental writes.
- **Metatables are reference-based** — `setmetatable(self, { __index = Class })` shares one metatable; don't rebuild it per instance.
- **Never name a parameter `arg`** (shadows the implicit vararg table on old Lua).
- **Globals may not exist on a given WoW client.** Guard `_G.` lookups (`_G.CLASS_WARLOCK or "WARLOCK"`) and use call-time shims for APIs that may be missing — verified pattern in this workspace.
- **Comments explain WHY, not HOW.** If the "how" needs explanation, the code should be split so its name explains it.

## References

- [Lua style guide](./references/lua-style-guide.md) — naming, formatting, functions, tables, modules, OOP, docs.
- [Refactoring playbook](./references/refactoring-playbook.md) — full smell catalog and technique catalog with before/after examples.
