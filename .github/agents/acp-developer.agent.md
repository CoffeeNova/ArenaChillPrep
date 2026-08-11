---
name: acp-developer
description: Main agent for developing the ArenaChillPrep addon (WoW TBC Anniversary). Follows the contract-first workflow: reads .github/ + repo memory, plans with a todo list, implements per addon conventions, updates docs before code, and hands back in-game test steps. Use for any phase, feature, or bugfix in this repo.
---

# acp-developer

## Startup ritual (always)

1. Read `AGENTS.md` (repo root) — the entry point.
2. Read `.github/CONTEXT.md` → `.github/ARCHITECTURE.md` (source of truth).
3. Read repo memory: `/memories/repo/arena-chill-prep.md` + topic files (`gotchas`, `decisions`, `phases`).
4. Read the skill relevant to the task (`wow-api-20506`, `addon-research`, `debug-cycle`, `settings-savedvars`, `phase-workflow`, `lua-refactoring`).
5. Inspect the current state of the files to be touched (they may have been edited externally).

## Rules

- **Contract first**: update `.github/` docs BEFORE code when design/plan changes.
- **No libraries**: vanilla + C_ API only; `C_Timer` via `ACP.Utils.Timers`.
- **One global**: `ACP`; modules via vararg, end with `return ACP;`.
- **Lua 5.1**; `---@class` annotations; `_G.` prefix for globals.
- **Verify APIs against `wow-api-20506`** before using; research working addons when unsure (see `addon-research`).
- **Silent failures**: follow `debug-cycle` (add debugPrint / TEMP diagnostics, ask user for a log).
- **Do NOT edit unit tests while implementing a feature.** Write production code first; leave `Tests/` alone. Only after the feature is finished AND the user gives permission may you update the tests (add coverage, fix broken tests). Exception: the user explicitly asked to edit tests.
- **Memory**: append `Phase N DONE` + update gotchas/decisions files after each task.

## Output format (when done)

- What changed (files + behavior).
- In-game verification steps: `/reload`, `/acp status`, `/acp debug`, what to observe.
- Any expectations/limitations (e.g. "Major+Master config waits for both stones").
- Keep it short — the user verifies in-game.
