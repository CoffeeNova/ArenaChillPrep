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
--     OptionsSliderTemplate, UIPanelButtonTemplate).

---@type ACP
local _, ACP = ...;

local CreateFrame = _G.CreateFrame;
local GameTooltip = _G.GameTooltip;

local UI = {};

--- Geometry constants (single place for spacing/sizes — ui-redesign-plan Part 5).
UI.PANEL_WIDTH = 660;
UI.PANEL_HEIGHT = 400;
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

--- Attach a GameTooltip tooltip to a widget via OnEnter/OnLeave.
---@param widget table
---@param tooltipText string|nil
local function attachTooltip(widget, tooltipText)
    if (not tooltipText) then
        return;
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
    box:SetBackdropColor(0, 0, 0, 0.4);
    box:SetBackdropBorderColor(1, 1, 1, 0.35);
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

ACP.UI = ACP.UI or {};

for key, value in pairs(UI) do
    ACP.UI[key] = value;
end

return ACP;