# Phase start prompt

Use this template to begin work on a phase (or major feature) of ArenaChillPrep in a fresh session. Replace the placeholders in `[...]`.

---

Start **[Phase N — Name]** for the ArenaChillPrep addon (WoW TBC Anniversary, Interface 20506).

**READ FIRST (in this order):**
1. `AGENTS.md` (repo root) — entry point.
2. `.ai/CONTEXT.md`, `.ai/ARCHITECTURE.md` — source of truth.
3. Repo memory `/.ai/memories/repo/` (main file + gotchas/decisions/phases).
4. The relevant skill(s): `wow-api-20506`, `addon-research`, `debug-cycle`, `settings-savedvars`, `phase-workflow` (and `lua-refactoring` for code cleanup).

**Context (already done, phases 0–5 complete and verified in game):**
- Addon: auto-trades healthstones to the partner during arena prep. v0.1: Warlock only, 2v2 only (3v3/5v5 disabled in UI, code kept).
- Stack: Lua 5.1, no libraries, one global `ACP`, modules via vararg ending in `return ACP;`.
- Key verified mechanics (2.5.5): buff via `C_UnitAuras.GetPlayerAuraBySpellID(32727)`; countdown via `CHAT_MSG_BG_SYSTEM_NEUTRAL` + localized map; trade via `InitiateTrade` → FIFO `UseContainerItem` → `UI_INFO_MESSAGE` (2nd arg) == `ERR_TRADE_COMPLETE`; settings with numeric-key dot paths; controller state machine IDLE/ACTIVE/TRADING/DONE with `givenTo` and gate safety.
- Gotchas (2.5.5): see `wow-api-20506` skill — do NOT use `UnitBuff(name)`, bare `GetContainerNumSlots`, `C_Item.GetItemGUID(bag,slot)`, `InterfaceOptions_AddCategory`, or `pairs(frame:GetChildren())`.

**This phase's tasks:** [paste the phase's tasks]

**Definition of Done:** [paste the phase's Definition of Done]

**Workflow:**
1. Follow the `phase-workflow` skill: contract-first, todo list, implement per conventions, update `.ai/` first when behavior changes, update repo memory.
2. Verify: no editor errors; run `tools/vararg-check.ps1` (and `tools/syntax-check.ps1` if a Lua interpreter is available).
3. Finish with: list of changed/created files, in-game verification steps (exact commands + expected output), and any expectations/limitations.

Begin by reading the contract files and showing a short plan, then implement.
