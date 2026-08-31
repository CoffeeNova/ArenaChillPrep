# Spell-ranks CVar fix — start prompt

Use this to begin work on the "Show all spell ranks" CVar fix in a fresh
session. The full implementation contract is already written — read it first
and follow it exactly.

---

Fix the **spellbook "Show all spell ranks" toggle dependency** in the
ArenaChillPrep addon (WoW TBC Anniversary, Interface 20506). The standard
Warlock workflows 1-2 stall silently at the "Create Healthstone (rank 5)" step
because a secure-button cast of a hidden rank fizzles with the CVar
`showAllSpellRanks` at "0".

**READ FIRST (in this order):**

1. `AGENTS.md` (repo root) — entry point.
2. **`.ai/docs/spell-ranks-cvar-fix-guide.md` — the full contract for THIS
   fix: root cause with the debug-log evidence, the proven M6/WeakAuras
   pattern, the exact code for every file, the tests to add, the docs to
   update, and the non-goals. Implement it as written; do not deviate.**
3. `.ai/CONTEXT.md` (gotchas #19-25, code conventions, test conventions) and
   `.ai/ARCHITECTURE.md` (§2.10, §5 ADRs) — source of truth.
4. `.ai/skills/unit-testing/SKILL.md` — before writing or running any test
   (runner, stubs, suite layout, gotchas).

**Context (already done — do not redo):**

- Root cause was diagnosed and user-confirmed: the CVar `showAllSpellRanks`
  gates hidden-rank castability on this client. Working-addon evidence: M6
  `Libs/ActionBook/Categories.lua:82-101` and WeakAuras
  `Libs/LibDispel/LibDispel.lua:158/220`.
- Design was approved by the user: a RUN-SCOPED override ("1" while a workflow
  runs, restored on DONE/reset/stopTest/PLAYER_LOGOUT), enabled only when the
  definition has a createItem step below its family's max rank. The stored
  rank stays honored — 11730 still creates the Major stone; do NOT touch
  `resolveCastInfo`.

**Tasks (from the guide):**

1. `Data/Constants.lua` — add `SPELL_RANKS_CVAR = "showAllSpellRanks"`.
2. `Classes/WorkflowItemSteps.lua` — add `familyMaxRank` (local),
   `needsSpellRanks`, `enableSpellRanks`, `restoreSpellRanks` (exact code in
   the guide §5.2).
3. `Classes/WorkflowEngine.lua` — new state fields, enable calls in both
   `start()` paths, restore in `reset()`/DONE, `PLAYER_LOGOUT` handler in
   `_init()`, three thin delegates (§5.3).
4. `Tests/stubs/wow_stubs.lua` — `GetCVar`/`SetCVar` stubs over
   `_G.__stub.cvars` (§5.4).
5. `Tests/Classes/test_workflowexecution.lua` — extend `teardownEngine` and add
   the tests from §5.5.
6. Docs (contract-first): CONTEXT gotcha #26, ARCHITECTURE ADR 23,
   `wow-api-20506` skill row (§6).

**Definition of Done:**

- `.\Tests\run-tests.ps1` exits **0** (all tests green AND coverage ≥ 90% on a
  clean luacov stats file — see the unit-testing skill).
- `.\.ai\tools\vararg-check.ps1` and `.\.ai\tools\syntax-check.ps1` clean.
- The three doc updates from §6 are written (English only).
- `.\.ai\tools\deploy.ps1` deployed so the user can live-test.
- NO changes outside the guide's file list; the non-goals (§8) are respected.
- Repo memory is NOT written (memory comes AFTER the user's live verification).

**Workflow:**

1. Follow the guide file section by section; keep a todo list.
2. Run the checks; if coverage drops below 90%, add the missing test paths.
3. Finish with a short report: files changed, test/check results (with the
   exact numbers), and the live-verification checklist for the user (guide §9).

Begin by reading the guide and the contract files, show a 5-line plan, then
implement.
