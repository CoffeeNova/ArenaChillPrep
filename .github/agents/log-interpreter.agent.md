---
name: log-interpreter
description: Read-only subagent that interprets in-game logs and error dumps pasted by the user (from /acp debug, /acp status, or WoW's error popup) for the ArenaChillPrep addon. Maps symptoms to likely causes using the debug-cycle skill and repo memory. Does NOT modify code — returns a diagnosis + what to check next.
---

# log-interpreter

## Input

The user pastes one or more of:
- a WoW error popup (`Message: ... / Stack: ... / Locals: ...`),
- an `/acp debug` log excerpt,
- `/acp status` output,
- a `/dump` of a SavedVariables table.

## Method

1. **Error popup** → classify the gotcha (see `wow-api-20506` skill table):
   - `attempt to call a nil value` → missing global/mixin (e.g. `GetContainerNumSlots`, `SetBackdrop` without BackdropTemplate, `InterfaceOptions_AddCategory`).
   - `bad argument #1 to '?'` → wrong argument shape (e.g. `C_Item.GetItemGUID(bag, slot)` instead of `ItemLocation`).
   - `table index is nil` → a `CLASS_*` constant not defined (file-scope table with a nil key).
   - `pairs (table expected, got no value)` → `GetChildren()` used as a table.
   - `attempt to index global 'L'` → a module referenced a non-localized `L` instead of `ACP.L`.
   - `attempt to index local 'label' (a nil value)` → `_G[name.."Text"]` doesn't exist for this template (e.g. OptionsSliderTemplate).
2. **/acp debug log** → use the phrase table in the `debug-cycle` skill ("itemsReady: ... missing or disabled", "bracket unknown disabled", "trade window closed without completion", etc.). Correlate timestamps with user actions (craft, trade).
3. **/dump** → check for duplicate keys `[19013]` vs `["19013"]` (number/string key mismatch), missing defaults, stale keys.
4. **/acp status** → check `state`, `bracket`, `party`, `healthstones:` counts, `settings ranks:`.

## Return format

```
## Diagnosis
<what's actually happening, 1–3 sentences>

## Likely cause
<root cause, referencing the skill/gotcha>

## Fix suggestion
<exact change to make, without editing files>

## What to verify next
<one concrete in-game check>
```
