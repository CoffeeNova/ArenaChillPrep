-- ArenaChillPrep — Classes/UI/Widgets
-- Reusable options widgets (vanilla API, no libraries): boxed containers,
-- headers, dividers, checkboxes, sliders, buttons and the status line.
-- Every interactive widget attaches a GameTooltip tooltip when given one.
-- Widgets know nothing about ACP.Settings — callers pass getter/setter
-- closures. All geometry constants live here (one place to tune spacing).
--
-- Client gotchas honored (see .ai/skills/wow-api-20506):
--   * CreateFrame(..., "BackdropTemplate") is MANDATORY before SetBackdrop;
--   * OptionsSliderTemplate does NOT create a global "<name>Text" — the
--     label is built manually above the slider;
--   * no Ace — Blizzard templates only (UICheckButtonTemplate,
--     OptionsSliderTemplate, UIPanelButtonTemplate, UIDropDownMenuTemplate,
--     InputBoxTemplate, UIPanelScrollFrameTemplate);
--   * UIDropDownMenuTemplate / InputBoxTemplate name their children after the
--     frame's name ("<name>Text", "<name>Button", "<name>Left", ...) — every
--     dropdown/input needs a UNIQUE global name, otherwise anonymous frames
--     collide on the "Text"/"Button"/"Left" child globals.

---@type ACP
local _, ACP = ...;

local CreateFrame = _G.CreateFrame;
local GameTooltip = _G.GameTooltip;
local ipairs = _G.ipairs;
local tostring = _G.tostring;
local UIDropDownMenu_SetWidth = _G.UIDropDownMenu_SetWidth;
local UIDropDownMenu_SetText = _G.UIDropDownMenu_SetText;
local UIDropDownMenu_SetSelectedValue = _G.UIDropDownMenu_SetSelectedValue;
local UIDropDownMenu_Initialize = _G.UIDropDownMenu_Initialize;
local UIDropDownMenu_Refresh = _G.UIDropDownMenu_Refresh;
local UIDropDownMenu_CreateInfo = _G.UIDropDownMenu_CreateInfo;
local UIDropDownMenu_AddButton = _G.UIDropDownMenu_AddButton;
local CloseDropDownMenus = _G.CloseDropDownMenus;
local IsShiftKeyDown = _G.IsShiftKeyDown;
local IsControlKeyDown = _G.IsControlKeyDown;
local IsAltKeyDown = _G.IsAltKeyDown;

--- Unique name counter for ScrollFrames (UIPanelScrollFrameTemplate names its
--- embedded scrollbar "<name>ScrollBar", so anonymous frames would collide).
local scrollCounter = 0;

local UI = {};

--- Geometry constants (single place for spacing/sizes — ui-redesign-plan Part 5).
UI.PANEL_WIDTH = 660;
UI.PANEL_HEIGHT = 400;
UI.WORKFLOW_PANEL_HEIGHT = 600;
UI.PADDING = 14;
UI.ROW_HEIGHT = 24;
UI.GAP = 16;
UI.BOX_INSET = 10;
UI.DISABLED_ALPHA = 0.4;

local BOX_BACKGROUND = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
};

local HEADER_R = 1;
local HEADER_G = 0.82;
local HEADER_B = 0;

--- Attach a GameTooltip tooltip to a widget via OnEnter/OnLeave. FontStrings
--- need EnableMouse(true) to receive OnEnter/OnLeave, so it is applied here
--- (harmless for frames that already have it).
---@param widget table
---@param tooltipText string|nil
local function attachTooltip(widget, tooltipText)
    if (not tooltipText) then
        return;
    end

    if (widget.EnableMouse) then
        widget:EnableMouse(true);
    end

    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true);
        GameTooltip:Show();
    end);

    widget:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);
end

--- WoW binding keys are letters/digits OR punctuation characters (e.g. ";",
--- "[", "/") reported by OnKeyDown as the literal key name, optionally
--- prefixed by SHIFT-/CTRL-/ALT-, or named keys (F1, MOUSEWHEELUP, BUTTON3).
--- Reject anything else: an invalid key would corrupt bindings-cache.wtf on
--- save and kill ALL keybindings (Esc/Enter/movement/hotkeys) after /reload.
--- NOTE: Lua patterns have no `|` alternation, so the modifier prefix is
--- stripped with gsub (not a regex group) before the base check.
---@param key string
---@return boolean
local function isSafeBindingKey(key)
    if (type(key) ~= "string" or key == "") then
        return false;
    end

    local base = key:gsub("SHIFT%-", ""):gsub("CTRL%-", ""):gsub("ALT%-", "");
    return base:match("^[%w%p]+$") ~= nil;
end

--- Boxed container (dark bg + thin border).
---@param parent Frame
---@param x number
---@param y number
---@param w number
---@param h number
---@return Frame
function UI.Box(parent, x, y, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    box:SetSize(w, h);
    box:SetBackdrop(BOX_BACKGROUND);
    box:SetBackdropColor(0.02, 0.02, 0.02, 0.75);
    box:SetBackdropBorderColor(1, 1, 1, 0.25);
    return box;
end

--- Yellow section header (GameFontNormalLarge).
---@param parent Frame
---@param text string
---@param x number
---@param y number
---@return FontString
function UI.Header(parent, text, x, y)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
    header:SetText(text);
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    header:SetTextColor(HEADER_R, HEADER_G, HEADER_B, 1);
    return header;
end

--- Horizontal divider line between logical groups within a subcategory.
---@param parent Frame
---@param x number
---@param y number
---@param w number
---@return Frame
function UI.Divider(parent, x, y, w)
    local divider = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    divider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    divider:SetSize(w, 2);
    divider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    });
    divider:SetBackdropColor(1, 1, 1, 0.3);
    return divider;
end

--- Checkbox row: check button + clickable label + optional tooltip.
---@param parent Frame
---@param name string  global name for the check button ("<name>Text" = label)
---@param text string
---@param x number
---@param y number
---@param getter fun(): boolean
---@param setter fun(value: boolean)
---@param tooltipText string|nil
---@return CheckButton
function UI.Checkbox(parent, name, text, x, y, getter, setter, tooltipText)
    local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate");
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    check:SetChecked(getter() == true);

    local label = _G[name .. "Text"];
    label:SetText(text);
    label:SetPoint("LEFT", check, "RIGHT", 4, 0);
    label:EnableMouse(true);
    label:SetScript("OnMouseDown", function()
        check:Click();
    end);

    check:SetScript("OnClick", function(self)
        setter(self:GetChecked());
    end);

    check.label = label;

    attachTooltip(check, tooltipText);
    attachTooltip(label, tooltipText);

    return check;
end

--- Slider with its text label ABOVE it (so long labels never clip), a value
--- text to the right and an optional tooltip. OptionsSliderTemplate does NOT
--- create a global "<name>Text" — the label is built manually.
---@param parent Frame
---@param name string  global name for the slider
---@param text string
---@param x number
---@param y number
---@param min number
---@param max number
---@param step number
---@param getter fun(): number
---@param setter fun(value: number)
---@param tooltipText string|nil
---@return Slider
function UI.Slider(parent, name, text, x, y, min, max, step, getter, setter, tooltipText)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal");
    label:SetText(text);
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    label:SetWidth(180);
    label:SetJustifyH("LEFT");
    label:SetWordWrap(true);

    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate");
    slider:SetMinMaxValues(min, max);
    slider:SetValueStep(step);
    slider:SetWidth(150);
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 24);

    local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
    valueText:SetPoint("LEFT", slider, "RIGHT", 6, 0);

    slider:SetScript("OnValueChanged", function(_, value)
        valueText:SetText(("%.1f"):format(value));
        setter(value);
    end);

    slider.Refresh = function()
        local value = getter() or min;
        slider:SetValue(value);
        valueText:SetText(("%.1f"):format(value));
    end;
    slider.Refresh();

    slider.label = label;

    attachTooltip(label, tooltipText);
    attachTooltip(slider, tooltipText);

    return slider;
end

--- Standard options button (UIPanelButtonTemplate) with optional tooltip.
---@param parent Frame
---@param text string
---@param x number
---@param y number
---@param w number
---@param h number
---@param onClick fun()
---@param tooltipText string|nil
---@return Button
function UI.Button(parent, text, x, y, w, h, onClick, tooltipText)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate");
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    button:SetSize(w, h);
    button:SetText(text);
    button:SetScript("OnClick", onClick);

    attachTooltip(button, tooltipText);

    return button;
end

--- Dropdown (UIDropDownMenuTemplate) with a persistent value-based selection.
--- Items are rendered from the `items` array of { value, label, isTitle? }
--- (or a function returning such an array, evaluated on every menu open).
--- The collapsed label shows the label of the current getter() value, or the
--- `text` placeholder when getter() returns nil (e.g. an "add step" picker).
---
--- 20506 GOTCHA (live-verified 2026-08-20): the client's
--- UIDropDownMenu_SetSelectedValue / UIDropDownMenu_Refresh do NOT reliably
--- update the collapsed label — the box keeps the template's default "Custom"
--- (and stale selections after add/delete) until the menu is opened once.
--- The collapsed text is therefore always applied EXPLICITLY via
--- UIDropDownMenu_SetText — the same pattern every working 20506 addon
--- (Gargul, Ranker, BGHistorian, AtlasLoot, ItemRack, ...) uses. See
--- .ai/skills/wow-api-20506/SKILL.md.
---@param parent Frame
---@param name string  unique global name (the template names its children from it)
---@param text string  initial/placeholder label shown when nothing is selected
---@param x number
---@param y number
---@param width number
---@param items table|function  array of {value, label, isTitle?} or builder function
---@param getter fun(): any
---@param setter fun(value: any)
---@param tooltipText string|nil
---@return Frame
function UI.Dropdown(parent, name, text, x, y, width, items, getter, setter, tooltipText)
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate");
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    UIDropDownMenu_SetWidth(dd, width);

    local function list()
        return (type(items) == "function" and items() or items);
    end

    --- The item whose value equals the current getter() value (nil when the
    --- getter returns nil or the value is not in the list).
    ---@return table|nil
    local function currentItem()
        local current = getter();

        if (current == nil) then
            return nil;
        end

        for _, item in ipairs(list()) do
            if (item.value == current) then
                return item;
            end
        end

        return nil;
    end

    --- Write the collapsed label: the matching item's label, or the
    --- placeholder when nothing is selected. Also clears the stale template
    --- state when a dynamic dropdown changes context (the Add Step picker
    --- showed "Custom" after switching workflows — UIDropDownMenu_Refresh can
    --- retain the previous selectedValue).
    local function applyLabel()
        local item = currentItem();

        if (item) then
            UIDropDownMenu_SetText(dd, item.label);
        else
            dd.selectedValue = nil;
            dd.value = nil;
            UIDropDownMenu_SetText(dd, text or "");
        end
    end

    UIDropDownMenu_Initialize(dd, function()
        local current = getter();

        for _, item in ipairs(list()) do
            local info = UIDropDownMenu_CreateInfo();
            info.text = item.label;
            info.value = item.value;

            if (item.isTitle) then
                -- Section header inside the menu (not clickable, no checkmark).
                info.isTitle = true;
                info.notCheckable = true;
            else
                info.checked = (item.value == current);
                info.notCheckable = false;
                info.func = function(menuButton)
                    setter(menuButton.value);
                    UIDropDownMenu_SetSelectedValue(dd, menuButton.value);
                    -- 20506 GOTCHA: UIDropDownMenu_SetSelectedValue internally
                    -- calls UIDropDownMenu_Refresh, which writes the collapsed
                    -- label from the (now closed) menu's button state — the
                    -- fallback "Custom", the raw value, or a stale item — and
                    -- OVERRIDES the label the setter/refresh just applied. Re-
                    -- apply the label here so the addon's item label always
                    -- wins (also fixes Target dropdowns in workflow steps, where
                    -- the collapsed text otherwise shows a wrong value).
                    applyLabel();
                    CloseDropDownMenus();
                end;
            end

            UIDropDownMenu_AddButton(info);
        end

        if (current ~= nil) then
            -- Persistent selection state + open-menu checkmark.
            UIDropDownMenu_SetSelectedValue(dd, current);
        end

        applyLabel();
    end);

    dd.Refresh = function()
        -- Re-run the initializer (re-applies checked state + collapsed label).
        UIDropDownMenu_Refresh(dd, 1, 1);
        applyLabel();
    end;
    dd.Refresh();

    attachTooltip(dd, tooltipText);

    return dd;
end

--- Single-line text input (InputBoxTemplate) for free-form values (e.g. a
--- workflow name). Writes to the setter on EVERY user keystroke; programmatic
--- SetText (e.g. from Refresh) never writes back.
---@param parent Frame
---@param name string  unique global name (the template names its children from it)
---@param x number
---@param y number
---@param w number
---@param h number
---@param getter fun(): string
---@param setter fun(value: string)
---@param tooltipText string|nil
---@return EditBox
function UI.TextInput(parent, name, x, y, w, h, getter, setter, tooltipText)
    local input = CreateFrame("EditBox", name, parent, "InputBoxTemplate");
    input:SetSize(w, h);
    input:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    input:SetAutoFocus(false);
    input:SetText(getter() or "");
    input:SetScript("OnTextChanged", function(self, userChanged)
        if (userChanged) then
            setter(self:GetText());
        end
    end);
    input:SetScript("OnEscapePressed", function(self)
        self:ClearFocus();
    end);

    input.Refresh = function()
        input:SetText(getter() or "");
    end;

    attachTooltip(input, tooltipText);

    return input;
end

--- Direct key-binding capture button. Clicking the button enters capture mode;
--- the next key (with Shift/Ctrl/Alt modifiers) is written through setter().
--- Escape clears the binding; clicking again cancels capture. The pattern is
--- the same as Blizzard/Ace keybinding controls and works on 20506 because
--- keyboard input is captured by a focused frame, not by an insecure API.
---
--- KEYBOARD-CAPTURE GOTCHA (verified 2026-08-21): a `Button` frame does NOT
--- support `SetFocus()` on the 2.5.5 client (only `EditBox` does), so a Button
--- can never receive keyboard focus and its `OnKeyDown` never fires. The key is
--- therefore captured by a hidden off-screen `EditBox` that is focused only
--- while capturing; `stopCapture()` hides it and clears focus so the game
--- regains the keyboard. The capture handler is installed on the EditBox and is
--- re-focused if focus is lost mid-capture (e.g. a stray click) so a key press
--- is never lost.
---@param parent Frame
---@param name string
---@param text string  placeholder when unbound (caller-passed L.* value)
---@param x number
---@param y number
---@param w number
---@param h number
---@param getter fun(): string|nil
---@param setter fun(value: string|nil)
---@param tooltipText string|nil
---@param captureText string  text shown while capturing a key (caller-passed L.* value)
---@return Button
function UI.Keybind(parent, name, text, x, y, w, h, getter, setter, tooltipText, captureText)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate");
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    button:SetSize(w, h);
    button:RegisterForClicks("AnyDown");

    -- Hidden, off-screen EditBox that actually holds keyboard focus during
    -- capture (a Button cannot). Kept out of the visible layout so it never
    -- intercepts mouse clicks meant for the button.
    local captureBox = CreateFrame("EditBox", nil, parent);
    captureBox:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200);
    captureBox:SetSize(1, 1);
    captureBox:Hide();
    captureBox:SetAutoFocus(false);

    local ignored = {
        BUTTON1 = true,
        BUTTON2 = true,
        UNKNOWN = true,
        LSHIFT = true,
        RSHIFT = true,
        LCTRL = true,
        RCTRL = true,
        LALT = true,
        RALT = true,
    };

    local function refresh()
        local key = getter();

        if (button.waitingForKey) then
            -- Active capture state: gold text + highlighted frame so the
            -- player immediately sees that the next key is being captured.
            button:SetText(captureText);
            button:SetNormalFontObject("GameFontHighlight");
            button:LockHighlight();
        elseif (key and key ~= "") then
            button:SetText(key);
            button:SetNormalFontObject("GameFontHighlight");
            button:UnlockHighlight();
        else
            button:SetText(text);
            button:SetNormalFontObject("GameFontNormal");
            button:UnlockHighlight();
        end
    end

    local function stopCapture()
        if (not button.waitingForKey) then
            return;
        end

        button.waitingForKey = false;

        if (captureBox.ClearFocus) then
            captureBox:ClearFocus();
        end

        captureBox:Hide();
        button:UnlockHighlight();
        refresh();
    end

    local function capture(key)
        if (not button.waitingForKey) then
            return;
        end

        if (key == "ESCAPE") then
            setter(nil);
            stopCapture();
            return;
        end

        if (ignored[key]) then
            return;
        end

        if (IsShiftKeyDown and IsShiftKeyDown()) then
            key = "SHIFT-" .. key;
        end

        if (IsControlKeyDown and IsControlKeyDown()) then
            key = "CTRL-" .. key;
        end

        if (IsAltKeyDown and IsAltKeyDown()) then
            key = "ALT-" .. key;
        end

        if (not isSafeBindingKey(key)) then
            -- Stay in capture mode so the user can press a real key.
            return;
        end

        setter(key);
        stopCapture();
    end

    -- capture() must be declared before startCapture's closure references it
    -- (otherwise Lua resolves the upvalue as a global nil).
    local function startCapture()
        button.waitingForKey = true;

        captureBox:Show();
        if (captureBox.SetFocus) then
            captureBox:SetFocus();
        end

        button:LockHighlight();
        button:SetText(captureText);
    end

    -- Keyboard is captured exclusively by the focused EditBox. If focus is lost
    -- mid-capture (e.g. a stray click elsewhere) re-grab it so the next key is
    -- not lost; ignore the loss once capture has legitimately ended.
    captureBox:SetScript("OnKeyDown", function(_, key)
        capture(key);
    end);
    captureBox:SetScript("OnEditFocusLost", function()
        if (button.waitingForKey) then
            if (captureBox.SetFocus) then
                captureBox:SetFocus();
            end
        end
    end);

    button:SetScript("OnClick", function(self, mouseButton)
        if (mouseButton == "LeftButton" or mouseButton == "RightButton") then
            if (self.waitingForKey) then
                stopCapture();
            else
                startCapture();
            end
        end
    end);
    button:SetScript("OnMouseWheel", function(_, direction)
        capture(direction >= 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN");
    end);
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if (mouseButton == "MiddleButton") then
            capture("BUTTON3");
        elseif (mouseButton == "Button4") then
            capture("BUTTON4");
        elseif (mouseButton == "Button5") then
            capture("BUTTON5");
        end
    end);

    button.Refresh = refresh;
    button.StopCapture = stopCapture;
    button.StartCapture = startCapture;
    button.IsCapturing = function()
        return button.waitingForKey == true;
    end;
    button.HasBinding = function()
        local key = getter();
        return key ~= nil and key ~= "";
    end;
    attachTooltip(button, tooltipText);
    refresh();

    return button;
end

--- Scrollable container (UIPanelScrollFrameTemplate) for lists longer than the
--- visible area. The template's embedded scrollbar + mouse wheel handle the
--- scrolling; callers add child frames to ScrollChild and call sf:Refresh()
--- after resizing the child.
---@param parent Frame
---@param x number
---@param y number
---@param w number
---@param h number
---@return ScrollFrame
function UI.ScrollFrame(parent, x, y, w, h)
    scrollCounter = scrollCounter + 1;

    local sf = CreateFrame("ScrollFrame", ("ACPUI_Scroll%d"):format(scrollCounter), parent, "UIPanelScrollFrameTemplate");
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    sf:SetSize(w, h);

    local child = CreateFrame("Frame", nil, sf);
    child:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0);
    child:SetSize(w - 8, 1);
    sf:SetScrollChild(child);

    sf.ScrollChild = child;

    sf.Refresh = function()
        sf:UpdateScrollChildRect();
    end;

    return sf;
end

ACP.UI = ACP.UI or {};

-- Shared helpers re-exported for consumers (WorkflowUI reuses attachTooltip
-- and the key whitelist instead of keeping its own copies).
UI.attachTooltip = attachTooltip;
UI.isSafeBindingKey = isSafeBindingKey;

for key, value in pairs(UI) do
    ACP.UI[key] = value;
end

return ACP;
