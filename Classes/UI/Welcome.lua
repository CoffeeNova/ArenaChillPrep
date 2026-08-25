-- ArenaChillPrep — Classes/UI/Welcome
-- First-run welcome popup: shown once per account on PLAYER_LOGIN, Warlocks
-- only (the addon is Warlock-only). Two very short feature lines + two
-- buttons. The CTA dismisses the popup, opens the settings panel on the
-- Workflows tab and highlights the Key-capture button of workflow slot 1
-- (pulsing gold ring + auto-start of the key capture) so the player just
-- presses a key.
--
-- Client gotchas honored (see .ai/skills/wow-api-20506):
--   * CreateFrame(..., "BackdropTemplate") is MANDATORY before SetBackdrop;
--   * a Button can NOT hold keyboard focus on 2.5.5 (only EditBox can) —
--     Escape is captured by a hidden off-screen EditBox, the same pattern as
--     UI.Keybind;
--   * C_Timer handles are unreliable on this client — all pulse timers go
--     through ACP.Utils.Timers (named entries with an `active` flag).

---@type ACP
local _, ACP = ...;

local CreateFrame = _G.CreateFrame;

local WELCOME_W = 420;
local WELCOME_H = 330;
local ICON_SIZE = 128;
local PULSE_PERIOD = 0.4;
local PULSE_TIMEOUT = 20;

local WELCOME_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
};

local RING_BACKDROP = {
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
};

---@class Welcome
local Welcome = {
    _initialized = false,
    _hideHooked = false,

    ---@type Frame|nil
    Frame = nil,

    ---@type Frame|nil
    Pulse = nil,
};

---@type Welcome
ACP.Welcome = Welcome;

--- Stop the keybind highlight pulse (ring + timers).
function Welcome:stopPulse()
    ACP.Utils.Timers:cancel("WelcomePulse");
    ACP.Utils.Timers:cancel("WelcomePulseStop");

    if (self.Pulse) then
        self.Pulse:Hide();
        self.Pulse = nil;
    end
end

--- Dismiss the popup and persist the flag (shown at most once per account).
function Welcome:dismiss()
    self:stopPulse();

    ACP.Settings:set("welcomeSeen", true);

    if (self.Frame) then
        self.Frame:Hide();

        if (self.Frame.escBox) then
            if (self.Frame.escBox.ClearFocus) then
                self.Frame.escBox:ClearFocus();
            end
            self.Frame.escBox:Hide();
        end
    end
end

--- Pulse a gold ring around the Workflows-tab Key button until the key is
--- bound or the 20 s timeout fires. The ring KEEPS pulsing while the capture
--- is armed — it is the visual cue that draws the eye to the button (an
--- earlier version stopped the pulse on IsCapturing, which self-killed the
--- ring 0.4 s after the CTA armed the capture — "nothing happened").
---
--- Capture semantics (bug of 2026-08-25): the Key button is a TOGGLE — a click
--- while the capture is armed STOPS it. Auto-arming + the user's natural
--- "click the highlighted button, then press a key" left the capture off, so
--- the key press went to the game instead ("could not assign"). The capture is
--- therefore armed on the first tick (after the settings panel has settled)
--- and RE-ARMED by an OnClick hook whenever a click toggled it off while the
--- pulse is active; Escape deliberately stops the capture (no re-arm).
function Welcome:startPulse()
    local WorkflowUI = ACP.WorkflowUI;
    local keybind = WorkflowUI and WorkflowUI.Controls and WorkflowUI.Controls.keybind;

    if (not keybind) then
        return;
    end

    self:stopPulse();

    local ring = CreateFrame("Frame", nil, keybind, "BackdropTemplate");
    ring:SetBackdrop(RING_BACKDROP);
    ring:SetBackdropBorderColor(1, 0.84, 0, 1);
    ring:SetPoint("TOPLEFT", keybind, "TOPLEFT", -5, 5);
    ring:SetPoint("BOTTOMRIGHT", keybind, "BOTTOMRIGHT", 5, -5);
    ring:SetFrameLevel(keybind:GetFrameLevel() + 2);
    self.Pulse = ring;

    -- Re-arm the capture if a click on the button toggled it off (see the
    -- comment above). Guarded by self.Pulse: inactive once the pulse stops.
    if (not keybind._acpWelcomeHooked) then
        keybind._acpWelcomeHooked = true;
        keybind:HookScript("OnClick", function()
            if (self.Pulse and not (keybind.IsCapturing and keybind:IsCapturing())) then
                ACP.Utils.Timers:after("WelcomeRearm", 0.15, function()
                    if (self.Pulse and not (keybind.HasBinding and keybind:HasBinding())
                        and not (keybind.IsCapturing and keybind:IsCapturing())
                        and keybind.StartCapture) then
                        keybind:StartCapture();
                    end
                end);
            end
        end);
    end

    -- Arm the capture on the first tick (0.4 s after the CTA — the settings
    -- panel has settled and its own focus handling cannot steal the capture).
    local armed = false;
    local phase = false;
    ACP.Utils.Timers:interval("WelcomePulse", PULSE_PERIOD, function()
        if (keybind.HasBinding and keybind:HasBinding()) then
            self:stopPulse();
            return;
        end

        if (not armed) then
            armed = true;

            if (keybind:IsVisible() and keybind.StartCapture
                and not (keybind.IsCapturing and keybind:IsCapturing())) then
                keybind:StartCapture();
            end
        end

        phase = not phase;
        ring:SetAlpha(phase and 1 or 0.35);
    end);

    ACP.Utils.Timers:after("WelcomePulseStop", PULSE_TIMEOUT, function()
        self:stopPulse();
    end);
end

--- When the settings window closes, end the guidance: stop the pulse and drop
--- a still-armed capture, so a manual /acp reopen starts clean (no stale
--- "Press a key..." state that the next click would toggle OFF).
function Welcome:hookPanelHide()
    if (self._hideHooked) then
        return;
    end

    local frame = _G.InterfaceOptionsFrame;

    if (not frame or not frame.HookScript) then
        return;
    end

    self._hideHooked = true;
    frame:HookScript("OnHide", function()
        self:stopPulse();

        local keybind = ACP.WorkflowUI and ACP.WorkflowUI.Controls and ACP.WorkflowUI.Controls.keybind;

        if (keybind and keybind.IsCapturing and keybind:IsCapturing() and keybind.StopCapture) then
            keybind:StopCapture();
        end
    end);
end

--- Open the Workflows tab and pulse the Key button (the pulse arms the key
--- capture itself).
function Welcome:highlightKeybind()
    local WorkflowUI = ACP.WorkflowUI;
    local keybind = WorkflowUI and WorkflowUI.Controls and WorkflowUI.Controls.keybind;

    if (not keybind) then
        return;
    end

    if (keybind.HasBinding and keybind:HasBinding()) then
        local key = ACP.WorkflowKeybindController and ACP.WorkflowKeybindController:getSlotKey(1);
        ACP:print(ACP.L.welcomeKeyAlreadyBound, tostring(key or ""));
        return;
    end

    self:hookPanelHide();
    self:startPulse();
end

--- Primary CTA: dismiss → settings on the Workflows tab → highlight + capture.
function Welcome:onCta()
    self:dismiss();

    if (ACP.OptionsUI and ACP.OptionsUI.openPanel) then
        ACP.OptionsUI:openPanel("Workflows");
    end

    self:highlightKeybind();
end

--- Show the popup (built lazily on first show).
function Welcome:show()
    if (self.Frame) then
        self.Frame:Show();

        if (self.Frame.escBox) then
            self.Frame.escBox:Show();
            if (self.Frame.escBox.SetFocus) then
                self.Frame.escBox:SetFocus();
            end
        end
        return;
    end

    local L = ACP.L;

    local frame = CreateFrame("Frame", "ACPWelcomeFrame", UIParent, "BackdropTemplate");
    frame:SetSize(WELCOME_W, WELCOME_H);
    frame:SetPoint("CENTER");
    frame:SetFrameStrata("DIALOG");
    frame:SetBackdrop(WELCOME_BACKDROP);
    frame:SetBackdropColor(0.09, 0.09, 0.11, 0.92);
    frame:EnableMouse(true);
    self.Frame = frame;

    -- Large addon icon (the same texture as the TOC IconTexture).
    local icon = frame:CreateTexture(nil, "ARTWORK");
    icon:SetTexture("Interface\\AddOns\\ArenaChillPrep\\Textures\\icon.tga");
    icon:SetSize(ICON_SIZE, ICON_SIZE);
    icon:SetPoint("TOP", frame, "TOP", 0, -24);

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
    title:SetPoint("TOP", icon, "BOTTOM", 0, -10);
    title:SetText(L.panelTitle);

    local line1 = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
    line1:SetPoint("TOP", title, "BOTTOM", 0, -16);
    line1:SetPoint("LEFT", frame, "LEFT", 24, 0);
    line1:SetPoint("RIGHT", frame, "RIGHT", -24, 0);
    line1:SetJustifyH("CENTER");
    line1:SetText(L.welcomeLine1);

    local line2 = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
    line2:SetPoint("TOP", line1, "BOTTOM", 0, -8);
    line2:SetPoint("LEFT", frame, "LEFT", 24, 0);
    line2:SetPoint("RIGHT", frame, "RIGHT", -24, 0);
    line2:SetJustifyH("CENTER");
    line2:SetText(L.welcomeLine2);

    local cta = CreateFrame("Button", "ACPWelcomeCtaButton", frame, "UIPanelButtonTemplate");
    cta:SetSize(150, 24);
    cta:SetPoint("BOTTOM", frame, "BOTTOM", -84, 24);
    cta:SetText(L.welcomeCta);
    cta:SetScript("OnClick", function()
        self:onCta();
    end);

    local later = CreateFrame("Button", "ACPWelcomeLaterButton", frame, "UIPanelButtonTemplate");
    later:SetSize(100, 24);
    later:SetPoint("BOTTOM", frame, "BOTTOM", 84, 24);
    later:SetText(L.welcomeLater);
    later:SetNormalFontObject("GameFontNormal");
    later:SetScript("OnClick", function()
        self:dismiss();
    end);

    -- Escape closes the popup. A Button cannot hold focus on 2.5.5, so the
    -- key is captured by a hidden off-screen EditBox (the UI.Keybind pattern).
    local escBox = CreateFrame("EditBox", nil, frame);
    escBox:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200);
    escBox:SetSize(1, 1);
    escBox:Hide();
    escBox:SetAutoFocus(false);
    escBox:SetScript("OnKeyDown", function(_, key)
        if (key == "ESCAPE") then
            self:dismiss();
        end
    end);
    escBox:SetScript("OnEditFocusLost", function()
        if (self.Frame and self.Frame:IsShown()) then
            if (escBox.SetFocus) then
                escBox:SetFocus();
            end
        end
    end);
    frame.escBox = escBox;

    frame:Show();
    escBox:Show();
    if (escBox.SetFocus) then
        escBox:SetFocus();
    end
end

function Welcome:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    ACP.Events:register("Welcome.LOGIN", "PLAYER_LOGIN", function()
        if (ACP.OptionsUI and ACP.OptionsUI:isSupportedClass()
            and not ACP.Settings:get("welcomeSeen")) then
            self:show();
        end
    end);
end

return ACP;
