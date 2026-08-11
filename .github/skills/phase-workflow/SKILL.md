---
name: phase-workflow
description: The end-to-end workflow for implementing a phase or feature of the ArenaChillPrep addon (and for most feature work in this repo). Use at the start of every phase or feature: contract-first, todo list, implement, verify, document, hand back to the user with test steps.
---

# Phase workflow

## Golden rule

**.github/ is the contract.** When the design or plan changes, update `.github/CONTEXT.md` and `ARCHITECTURE.md` FIRST, then code. Never let code drift from the docs.

## The loop (repeat for every phase/feature)

1. **Read the contract**: `AGENTS.md` → `.github/CONTEXT.md` → `.github/ARCHITECTURE.md`.
2. **Read repo memory**: `/memories/repo/arena-chill-prep.md` + topic files (gotchas, decisions, phases) — they carry the verified history; don't re-learn what's there.
3. **Check current state**: read the files you'll touch; note any drift from the docs (the user or tooling may have edited them).
4. **Create a todo list** for the phase (manage_todo_list tool) — one item per deliverable, mark in-progress/completed as you go.
5. **Update the contract FIRST** if the phase changes behavior (rule 1).
6. **Implement** per the addon's conventions:
   - Lua 5.1, no libraries, single global `ACP`;
   - modules via `local _, ACP = ...` and end with `return ACP;`;
   - `---@class` annotations, `_G.` for globals, local aliases at the top;
   - UI strings through `Data/Localization.lua` (`ACP.L`);
   - timers via `ACP.Utils.Timers` (C_Timer wrapper), never Ace;
   - cross-session state only via `ArenaChillPrepDB` through `ACP.Settings`.
7. **Verify in the sandbox**: no editor errors; run `tools/vararg-check.ps1` (every file ends `return ACP;`) and `tools/syntax-check.ps1` if a Lua interpreter is available.
8. **Update memory**: append a `Phase N DONE` line to `/memories/repo/`; add NEW gotchas to `arena-chill-prep-gotchas.md` and the `wow-api-20506` skill; update decisions/status files.
9. **Hand back to the user** with:
   - what changed (files + behavior);
   - the Definition of Done as concrete in-game test steps (`/reload`, what to observe);
   - known expectations/limitations (e.g. "config Major+Master waits for BOTH stones").
   Keep it short; the user verifies in-game and reports back.

## Order of module init (bootstrap)

`Events` → `Settings` → `ArenaPrep` → `Inventory` → `TradeManager` → `DeliveryController` → `OptionsUI` → `ArenaPrep:checkNow()`.
A module may only assume earlier modules exist during its `_init`.

## Load order in the TOC

`bootstrap.lua` → `Data/*` → `Utils/*` → `Classes/*`. Never reference another module at file scope — only inside functions (everything is loaded by ADDON_LOADED time).

## Testing etiquette

- **Do NOT touch the unit tests while implementing a feature.** Write/fix production code first; leave `Tests/` alone during the implementation phase.
- **Only after the feature is finished AND the user gives permission** may you update the unit tests (add coverage for the new behavior, fix tests broken by the change). Exception: the user explicitly asked to edit tests.
- **Automated unit tests exist** (`Tests/`, run outside the game under LuaJIT): `.\Tests\run-tests.ps1` — exit 0 = pass + coverage ≥ 90%. Run them after any logic change (see repo memory `arena-chill-prep-tests.md` for the gotchas).
- The user ALSO tests IN GAME (the automated suite can't verify real client behavior).
- Give exact commands: `/reload`, `/acp status`, `/acp debug`, `/dump <var>`.
- Ask for the log output when behavior is wrong (see `debug-cycle` skill).

## Definition of Done per phase

Always check the phase's Definition of Done (see repo memory `arena-chill-prep-phases.md`). If you can't verify in-game yourself, state clearly what the user must verify.
