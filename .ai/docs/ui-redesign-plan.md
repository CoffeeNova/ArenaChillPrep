# ArenaChillPrep — Settings UI: Specification and Implementation Plan

> Goal: rework `Classes/OptionsUI.lua` into a clean, modern, user-friendly settings interface inspired by the Prat-3.0 style (dark WoW aesthetics, tidy sections, logical hierarchy, compact controls, good readability, consistent spacing and sizes).

**Date:** 2026-08-11.

> **Implemented deviations (2026-08-18):** the status line (Steps 3/6, pattern #12) was **removed** at the user's request — the General tab shows only the master switch and the reset button, so the status localization keys (`statusLineFormat`/`statusEnabled`/`statusDisabled`) and the `ACP.UI.StatusLine` widget were dropped. In the Autotrade tab the **Timing section moved to the left column** below Arena Brackets (divider between Brackets and Timing); the right column holds only Ranks, balancing the columns. The optional Profiles stub (Step 3) remains not implemented.

---

## Important note about available data

The original request said "I will attach: 1. A brief description of the current ArenaChillPrep interface. 2. A brief description of the Prat-3.0 interface", but **no textual screenshot descriptions were provided** — only the old plan (`addon-v1-development-plan.md`) was attached. Therefore the specification is based on:

- **Code** `Classes/OptionsUI.lua` (current ACP implementation) and `addon/options.lua` + `modules/*.lua` (Prat-3.0).
- **Old plan** v0.1 (attached).
- **Repo memory** (`arena-chill-prep-decisions.md`, `arena-chill-prep-gotchas.md`, `arena-chill-prep-phases.md`) — already-decided UI decisions and client constraints are recorded there.

Anything not covered by these sources is marked as **"insufficient data"** in Part 4.

---

## Part 1 — Executive summary

**What needs to be done:** rework `Classes/OptionsUI.lua` from "a single subcategory with two columns" into a **modular panel with tabbed subcategories** (like Prat: General / Autotrade / future), extract control creation into **reusable UI components** (`UI/Widgets.lua`), add **header dividers, tooltips on every control, a "Reset to defaults" button and a status line** at the bottom. Keep the no-libraries rule (vanilla + `Settings.*` API) and all already-decided decisions (partner always auto, no autoAccept, no count slider, 3v3/5v5 disabled).

**Key constraints (from repo memory, must not be violated):**
- `InterfaceOptions_AddCategory` = nil on 2.5.5 → only `Settings.RegisterCanvasLayoutCategory` / `RegisterCanvasLayoutSubcategory` / `RegisterAddOnCategory` / `OpenToCategory`.
- `CreateFrame` + `SetBackdrop` → the `"BackdropTemplate"` mixin is mandatory.
- `OptionsSliderTemplate` does not create a global `...Text` → the label is built manually via `CreateFontString`.
- `frame:GetChildren()` returns multiple values → wrap in `{ ... }`.
- No Ace → `AceConfigDialog-3.0` cannot be used (as Prat does). All controls are built manually on Blizzard templates (`UICheckButtonTemplate`, `OptionsSliderTemplate`, `UIDropDownMenuTemplate`).

---

## Part 2 — Visual patterns table

| # | Prat-3.0 pattern | How it applies to ArenaChillPrep | Confirmed by data? |
|---|---|---|---|
| 1 | Top category + tabbed subcategories (`childGroups = "tab"`, `display`/`formatting`/`extras`/`modulecontrol`/`profiles`) | Top category "ArenaChillPrep" + subcategories: **General**, **Autotrade** (done), reserve **Profiles** for the future. Implemented via `Settings.RegisterCanvasLayoutSubcategory` (already in the code). | ✅ Prat `options.lua` L12-47 + ACP `OptionsUI.lua` `buildPanel` |
| 2 | Header dividers inside a section (`type = "header"`, `order = 129`) | Horizontal line + text between logical groups within one subcategory (e.g., inside Autotrade: "Items" → line → "Timing"). Implementation: `Frame` with `SetBackdrop` edge-only + `FontString` `GameFontNormal`. | ✅ Prat `Timestamps.lua` L87-89, L141-143 |
| 3 | Tooltip (`desc`) on every control | `check.tooltipText = L.xxxTooltip` + `OnEnter`/`OnLeave` show `GameTooltip`. Every checkbox/slider has its own tooltip. | ✅ Prat — `desc =` on every arg; ACP currently has NO tooltips |
| 4 | Boxed sections with dark background + thin border | Already exists (`createBox`: `WHITE8x8` bg + `UI-Tooltip-Border` edge, alpha 0.4/0.35). Keep, standardize colors. | ✅ ACP `OptionsUI.lua` `createBox` |
| 5 | Yellow section headers | Already exists (`GameFontNormalLarge`, color `1, 0.82, 0, 1`). Keep. | ✅ ACP `createHeader` |
| 6 | Two-column layout | Already exists (left General+Brackets, right Ranks+Timing). Keep for Autotrade. | ✅ ACP `buildAutotrade` |
| 7 | Disabled state with reduced alpha | Already exists for 3v3/5v5 (`Disable()` + `SetAlpha(0.4)`). Extend to all conditional controls (e.g., ranks disabled if `enabled=false`). | ✅ ACP + decisions |
| 8 | "Reset to defaults" button (Prat profiles) | Add at the bottom of the panel: `UIPanelButtonTemplate`, restores `DefaultSettings` via `Settings:reset()`. | ✅ Prat `profiles` group; ACP currently does NOT have it |
| 9 | Standard Blizzard control templates | `UICheckButtonTemplate` (checkbox), `OptionsSliderTemplate` (slider), `UIDropDownMenuTemplate` (dropdown — future, for partner mode). | ✅ Both addons |
| 10 | Localization of all strings via `L[key]` | Already exists (`Data/Localization.lua`, enUS+ruRU). Add new keys for tooltips, reset button, new headers. | ✅ ACP `Localization.lua` |
| 11 | Consistent spacing/sizes (constants in one place) | Move `PANEL_WIDTH`, `PADDING`, `ROW_HEIGHT`, `GAP`, `BOX_INSET` into a constants block at the top of the file (currently partial). | ✅ ACP — partial; standardize |
| 12 | Status line at the bottom (shows state) | New: `FontString` at the bottom of the panel, shows `enabled: on/off \| bracket: 2v2 \| state: IDLE`. Updated in `refresh()`. | ⚠️ Prat doesn't have it; proposal by analogy with `/acp status` |
| 13 | Hover highlight on boxed sections | Optional: `OnEnter`/`OnLeave` on box → `SetBackdropBorderColor` brighter. | ⚠️ Prat doesn't have it (AceConfigDialog renders itself); **insufficient data** — mark as optional |
| 14 | Icons on menu items | Prat doesn't use icons in options. **Do not implement** (no data, no addon textures). | ❌ Insufficient data |

---

## Part 3 — Detailed implementation plan

### Step 0. Preparation (contract-first)

1. Update `.github/ARCHITECTURE.md` §2.8 (description of `OptionsUI`) **before changing code**: describe the new structure (General + Autotrade + reserved subcategories, widgets module, reset button, status line, tooltips).
2. Update `.github/CONTEXT.md` (settings section) — add new localization keys, describe `Settings:reset()`.
3. Write the plan to `/memories/session/` (todo list).

### Step 1. Refactor the settings structure

**Goal:** move geometry and control creation out of `OptionsUI.lua` into a separate module.

1. Create `Classes/UI/Widgets.lua` (new file, add to TOC after `OptionsUI.lua` OR before it — check load order; widgets must be available before `buildPanel`).
   - `ACP.UI = ACP.UI or {}`
   - `ACP.UI.Box(parent, x, y, w, h, opts)` — boxed container (parameterized colors/alpha).
   - `ACP.UI.Header(parent, text, x, y)` — yellow header.
   - `ACP.UI.Divider(parent, x, y, w)` — horizontal divider line (Prat header pattern).
   - `ACP.UI.Checkbox(parent, name, text, x, y, getter, setter, tooltipText)` — checkbox + clickable label + tooltip.
   - `ACP.UI.Slider(parent, name, text, x, y, min, max, step, getter, setter, tooltipText)` — slider with label above + value text + tooltip.
   - `ACP.UI.Button(parent, text, x, y, w, h, onClick)` — `UIPanelButtonTemplate`.
   - `ACP.UI.StatusLine(parent, x, y, w)` — `FontString` for the status line.
2. Move geometry constants to the top of `Widgets.lua`:
   - `PANEL_WIDTH = 660`, `PANEL_HEIGHT = 400` (keep current — verified in game).
   - `PADDING = 14`, `ROW_HEIGHT = 24`, `GAP = 16`, `BOX_INSET = 10` (current values from `OptionsUI.lua`).
3. In `OptionsUI.lua`, replace local `createBox`/`createHeader`/`createCheckbox`/`createSlider` with `ACP.UI.*` calls.

### Step 2. Separate logic from presentation

1. `OptionsUI.lua` keeps only: subcategory registration, `buildPanel`, `refresh`, `openPanel`, slash commands.
2. Widgets don't know about `ACP.Settings` — they take `getter`/`setter` callbacks (already the case in the current code, keep it).
3. Tooltip text is passed as a parameter to the widget; the widget itself attaches `OnEnter`/`OnLeave` to `GameTooltip`.

### Step 3. Subcategories (inspired by Prat `childGroups = "tab"`)

1. Add **General** to `OptionsUI.Subcategories` before Autotrade:
   - `key = "General"`, `title = L.generalSection`.
   - Content: master switch (`enabled`), "Reset to defaults" button, status line.
2. Keep Autotrade as is (Brackets + Ranks + Timing), but add **header dividers** (`ACP.UI.Divider`) between Ranks and Timing.
3. Reserve `Profiles` (stub: empty frame + "Coming soon" header) — do not implement, just a placeholder for the future structure. **Optional** — if the user wants it.

### Step 4. Tooltips on every control

1. Add keys to `Data/Localization.lua` (enUS + ruRU):
   - `enabledTooltip`, `bracket2v2Tooltip`, `bracket3v3Tooltip`, `bracket5v5Tooltip`, `rankTooltip`, `tradeDelayTooltip`, `gateSafetyTooltip`, `resetTooltip`.
2. Pass tooltipText to every `ACP.UI.Checkbox` / `ACP.UI.Slider`.
3. Tooltip implementation in the widget:
   ```lua
   widget:SetScript("OnEnter", function(self)
       GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
       GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true);
       GameTooltip:Show();
   end);
   widget:SetScript("OnLeave", function()
       GameTooltip:Hide();
   end);
   ```
   The label must also inherit the tooltip (`label.tooltipText = ...` + the same scripts).

### Step 5. "Reset to defaults" button

1. Add `ACP.Settings:reset()` to `Classes/Settings.lua`:
   - `self.Data = deepCopy(ACP.Data.DefaultSettings)`.
   - `ArenaChillPrepDB = self.Data`.
   - `ACP.OptionsUI:refresh()`.
2. In the General subcategory: `ACP.UI.Button(parent, L.resetButton, x, y, 160, 24, function() ACP.Settings:reset(); end)`.
3. Tooltip on the button: `L.resetTooltip` ("Restore all settings to defaults").

### Step 6. Status line at the bottom

1. In the General subcategory (or in a shared panel footer — check whether `Settings.RegisterCanvasLayoutSubcategory` allows a shared footer; **insufficient data** — see Part 4).
2. `ACP.UI.StatusLine` — `FontString` `GameFontHighlightSmall`, updated in `refresh()`:
   - Text: `enabled: on | bracket: 2v2 | state: IDLE` (format like `/acp status`).
3. If a shared footer is impossible — put the status line in the General subcategory.

### Step 7. Disabled states (conditional controls)

1. If `enabled = false` → disable all controls in Autotrade (brackets, ranks, timing) + `SetAlpha(0.4)`.
2. Implementation: in `refresh()`, check `ACP.Settings:get("enabled")` and call enable/disable on the control group.
3. 3v3/5v5 stay disabled always (as now) — on top of the conditional disable.

### Step 8. Localization

1. Add all new keys to `Data/Localization.lua` (enUS + ruRU):
   - `generalSection`, `resetButton`, `resetTooltip`, `statusEnabled`, `statusBracket`, `statusState`, `statusLineFormat`.
   - Tooltip keys (see Step 4).
2. Check that there are no hardcoded strings in the code (grep `OptionsUI.lua` and `Widgets.lua`).

### Step 9. Visual consistency testing

1. `/reload` → open `/acp` → check:
   - Two subcategories (General, Autotrade) visible in the Settings list.
   - General: master switch, reset button, status line.
   - Autotrade: Brackets + Ranks + Timing with a divider.
   - Tooltips show on hover for every control.
   - Disabled state: turn off the master switch → Autotrade controls gray out.
2. Check in a 2v2 arena: the status line shows `bracket: 2v2 | state: ACTIVE/TRADING/DONE`.
3. Check `/console scriptErrors 1` — no Lua errors.

### Step 10. Alignment with Prat-3.0

1. Compare screenshots (user provides) with the result:
   - Spacing between controls (target: ~10-12px, like AceConfigDialog).
   - Boxed section height (target: compact, no excess whitespace).
   - Text contrast on dark background.
2. If there are discrepancies — fix the constants in `Widgets.lua` (one place for everything).
3. **Do not copy** AceConfigDialog-specific elements (the options tree on the left — ACP has its own native Settings list).

### Step 11. Documentation and memory

1. Update `ARCHITECTURE.md` §2.8 with the final description.
2. Update `CONTEXT.md` (settings section).
3. Record the outcome in `/memories/repo/arena-chill-prep-decisions.md` (section "UI decisions").

---

## Part 4 — Unknown parameters (cannot be determined without manual verification)

| # | Parameter | Why unknown | How to verify |
|---|---|---|---|
| 1 | **Exact spacing/sizes from Prat screenshots** | Textual screenshot descriptions were not provided in the message. | User provides a textual description: "spacing between checkboxes = N px, box height = M px" — or a screenshot + work from AceConfigDialog code (but that gives standard Blizzard values, not Prat specifics). |
| 2 | **Prat color palette (exact RGB)** | In code, Prat uses AceConfigDialog (standard Blizzard colors). Screenshots may show custom themes. | User reports RGB from the screenshot (with an eyedropper) OR we accept standard Blizzard colors (`UI-Tooltip-Border`, `WHITE8x8` bg alpha 0.4 — already in ACP). |
| 3 | **Is a shared footer for all subcategories possible** | `Settings.RegisterCanvasLayoutSubcategory` creates a separate frame per subcategory; unknown whether a shared element can be added outside subcategories. | Check in game: after `RegisterCanvasLayoutSubcategory` — is there access to the parent canvas frame for a shared footer. If not — the status line lives in the General subcategory. |
| 4 | **Are icons needed on menu items** | ACP has no textures; Prat has no icons in options. | User decision: are icons needed (then a texture is needed). Default — no. |
| 5 | **Prat header font/size** | Prat uses `GameFontNormal` via AceConfigDialog. Exact size/family — standard Blizzard. | Accept `GameFontNormalLarge` for section headers (already in ACP), `GameFontNormal` for labels. |
| 6 | **Hover behavior on boxed sections** | Prat doesn't have it (AceConfigDialog renders itself). | Optional — implement and show the user; if they don't like it — remove. |
| 7 | **Is a Profiles subcategory needed** | Prat has one (via AceDBOptions). ACP has no AceDB. | User decision: is a profiles/stub needed. Default — don't do it (no AceDB). |

---

## Part 5 — Recommended safe defaults

| Parameter | Safe default | Rationale |
|---|---|---|
| `PANEL_WIDTH` / `PANEL_HEIGHT` | **660 × 400** (current) | Already verified in game (Phase 5 closed). Don't change without need. |
| `PADDING` (content) | **14** (current) | Verified. |
| `ROW_HEIGHT` | **24** (current) | Verified; standard WoW checkbox + label fits. |
| `GAP` (between columns) | **16** (current) | Verified. |
| `BOX_INSET` (box inner padding) | **10** (current) | Verified. |
| Box bg color | `0, 0, 0, 0.4` (current) | Dark semi-transparent — WoW standard. |
| Box border color | `1, 1, 1, 0.35` (current) | Thin light border — readable on dark. |
| Header color | `1, 0.82, 0, 1` (yellow, current) | `GameFontNormalLarge` — Blizzard standard for headers. |
| Disabled alpha | **0.4** (current) | Verified for 3v3/5v5. |
| Tooltip anchor | `ANCHOR_RIGHT` | Standard for options — doesn't cover the control. |
| Reset button size | **160 × 24** | Standard `UIPanelButtonTemplate` + fits "Reset to defaults" (en) / "Сбросить" (ru). |
| Status line font | `GameFontHighlightSmall` | Compact, readable, doesn't compete with headers. |
| Divider height | **2 px** line + **8 px** padding top/bottom | Minimal visual pause between groups. |
| Tooltip wrap width | `GameTooltip:SetText(text, r, g, b, 1, true)` (`wrap=true`) | Long tooltips are not truncated. |

---

**Conclusion:** the plan is implementable on the vanilla API (no Ace), preserves all decided decisions and client constraints, and is inspired by Prat structurally (tabbed subcategories, header dividers, tooltips, reset button), not by copying AceConfigDialog. For precise alignment of spacing/colors with Prat screenshots, **textual screenshot descriptions** are needed (Part 4, items 1-2) — until then, in-game-verified values are used.
