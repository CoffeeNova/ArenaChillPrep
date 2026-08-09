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

- The user tests IN GAME (there's no automated test runner in the repo; `Tests/inventory_sandbox.lua` exists but must be loaded via a commented TOC line).
- Give exact commands: `/reload`, `/acp status`, `/acp debug`, `/dump <var>`.
- Ask for the log output when behavior is wrong (see `debug-cycle` skill).

## Definition of Done per phase

Always check the phase's Definition of Done (see repo memory `arena-chill-prep-phases.md`). If you can't verify in-game yourself, state clearly what the user must verify.
