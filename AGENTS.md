# ArenaChillPrep — Agent Instructions

This file is the **entry point** for AI agents working in this repository.

Everything an agent needs — project context, architecture, as well as skills, agents and instructions — lives in the **`.ai/`** directory. It is the single source of truth.

## Reading order

1. `.ai/CONTEXT.md` — what the addon does, code conventions, key mechanics & gotchas, proven patterns, settings reference
2. `.ai/ARCHITECTURE.md` — module design, state machine, data flow, edge cases, ADR decisions
3. `.ai/skills/wow-api-20506/SKILL.md` — **before writing/fixing any WoW API call**: verified client gotchas & patterns (many APIs crash or return shifted data on 2.5.5)

## Rules

- Follow everything in `.ai/`. It is the source of truth.
- When the design or plan changes, update the files in `.ai/` **first** — they are the contract.
- `README.md` at the repo root is for **human users** — do not treat it as technical documentation.
- All documentation and code in this workspace must be written in English.
- **Contract-first, memory-last**: update `.ai/` before code; record outcomes in `/.ai/memories/repo/` after.

## Skills (`.ai/skills/`)

| Skill | When to use |
|---|---|
| `wow-api-20506` | Any WoW API call: verified gotchas (crashes/shifted APIs) + working patterns for this client |
| `addon-research` | Researching API behavior in working addons (workspace search does NOT index the WoW AddOns folder — path from `.env` `addons_path_anniversary`) |
| `debug-cycle` | Silent failures (no Lua error): debugPrint, TEMP diagnostics, log reading, cleanup |
| `settings-savedvars` | Settings/`ArenaChillPrepDB`: dot-path get/set, numeric-vs-string keys, migration, rank logic |
| `phase-workflow` | End-to-end phase/feature workflow (contract-first, todo, verify, document, hand back) |
| `lua-refactoring` | Refactoring/cleanup/restructuring of Lua files |
| `unit-testing` | Writing/running the unit tests (luaunit + luacov under LuaJIT): runner, stubs, suite layout, AAA conventions, cross-suite gotchas |

## Agents (`.ai/agents/`)

- `acp-developer` — main agent for any phase/feature/bugfix (startup ritual + rules + output format).
- `wow-api-researcher` — research-only subagent: answers API questions with evidence from working addons.
- `log-interpreter` — read-only subagent: interprets pasted logs/error dumps → diagnosis + next check.

## Prompts (`.ai/prompts/`)

- `phase-start.md` — template to begin a phase in a fresh session (context + tasks + DoD + workflow).
- `debug-report.md` — structured request for an in-game debug log from the user.
- `ui-review.md` — structured UI review request (section-by-section, so layout fixes are precise).

## Tools (`.ai/tools/`)

- `research.ps1` — search working addons via PowerShell `Select-String` (workspace search misses the WoW AddOns folder; path from `.env` `addons_path_anniversary`).
- `vararg-check.ps1` — every `.lua` ends with `return ACP;` + TOC load-order check.
- `syntax-check.ps1` — `luac/luajit -p` syntax check (requires a Lua interpreter; LuaJIT is installed via winget).
- `load-env.ps1` — loads `.env` (machine-specific paths, e.g. `addons_path_anniversary`) into the session.
- `deploy.ps1` — copies only the game artifacts (TOC + files it references + LICENSE) to `addons_path_anniversary`, or builds a release zip (`-Bundle`) for CurseForge/CI.

## Local development environment (`.env`)

Machine-specific paths live in `.env` at the repo root (copy `.env.example` → `.env`, fill in the values). The WoW TBC Anniversary client with its addons is NOT part of this repo — it lives wherever `addons_path_anniversary` points (e.g. `G:\games\World of Warcraft\_anniversary_\Interface\AddOns`). Scripts and docs read that variable instead of hardcoding a path.

## Unit tests (`Tests/`)

- Run: `.\Tests\run-tests.ps1` (or `luajit Tests\run_tests.lua` from the addon root). Requires LuaJIT on PATH.
- Exit codes: `0` = pass + coverage ≥ 90%, `1` = test failures, `2` = coverage < 90%.
- Covers all non-UI modules (96%+ line coverage); `OptionsUI.lua` excluded.
- **Before writing or running tests, read the `unit-testing` skill** (`.ai/skills/unit-testing/SKILL.md`) — runner, stubs, suite layout, conventions, and the cross-suite gotchas.
- Gotchas also in repo memory `arena-chill-prep-tests.md` (`/.ai/memories/repo/`).
