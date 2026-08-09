# ArenaChillPrep — Agent Instructions

This file is the **entry point** for AI agents working in this repository.

Everything an agent needs — project context, architecture, as well as skills, agents and instructions — lives in the **`.github/`** directory. It is the single source of truth.

## Reading order

1. `.github/CONTEXT.md` — what the addon does, code conventions, key mechanics & gotchas, proven patterns, settings reference
2. `.github/ARCHITECTURE.md` — module design, state machine, data flow, edge cases, ADR decisions
3. `.github/skills/wow-api-20506/SKILL.md` — **before writing/fixing any WoW API call**: verified client gotchas & patterns (many APIs crash or return shifted data on 2.5.5)

## Rules

- Follow everything in `.github/`. It is the source of truth.
- When the design or plan changes, update the files in `.github/` **first** — they are the contract.
- `README.md` at the repo root is for **human users** — do not treat it as technical documentation.
- All documentation and code in this workspace must be written in English.
- **Contract-first, memory-last**: update `.github/` before code; record outcomes in `/memories/repo/` after.

## Skills (`.github/skills/`)

| Skill | When to use |
|---|---|
| `wow-api-20506` | Any WoW API call: verified gotchas (crashes/shifted APIs) + working patterns for this client |
| `addon-research` | Researching API behavior in working addons (workspace search does NOT index the WoW folder) |
| `debug-cycle` | Silent failures (no Lua error): debugPrint, TEMP diagnostics, log reading, cleanup |
| `settings-savedvars` | Settings/`ArenaChillPrepDB`: dot-path get/set, numeric-vs-string keys, migration, rank logic |
| `phase-workflow` | End-to-end phase/feature workflow (contract-first, todo, verify, document, hand back) |
| `lua-refactoring` | Refactoring/cleanup/restructuring of Lua files |

## Agents (`.github/agents/`)

- `acp-developer` — main agent for any phase/feature/bugfix (startup ritual + rules + output format).
- `wow-api-researcher` — research-only subagent: answers API questions with evidence from working addons.
- `log-interpreter` — read-only subagent: interprets pasted logs/error dumps → diagnosis + next check.

## Prompts (`.github/prompts/`)

- `phase-start.md` — template to begin a phase in a fresh session (context + tasks + DoD + workflow).
- `debug-report.md` — structured request for an in-game debug log from the user.
- `ui-review.md` — structured UI review request (section-by-section, so layout fixes are precise).

## Tools (`.github/tools/`)

- `research.ps1` — search working addons via PowerShell `Select-String` (workspace search misses the WoW folder).
- `vararg-check.ps1` — every `.lua` ends with `return ACP;` + TOC load-order check.
- `syntax-check.ps1` — `luac/luajit -p` syntax check (requires a Lua interpreter; none installed yet).
