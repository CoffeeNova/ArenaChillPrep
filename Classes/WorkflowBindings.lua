-- ArenaChillPrep — Classes/WorkflowBindings
-- Key Bindings UI entries for the workflow slots + secure-button creation and
-- the per-slot key overrides (extracted from WorkflowEngine).

local _, ACP = ...;

local string_format = _G.string.format;
local tostring = _G.tostring;

---@class WorkflowBindings
local WorkflowBindings = {
    _initialized = false,
};

---@type WorkflowBindings
ACP.WorkflowBindings = WorkflowBindings;

BINDING_HEADER_ACP = "ArenaChillPrep";

for slot = 1, ACP.Data.Constants.WORKFLOW_MAX_SLOTS do
    _G["BINDING_NAME_ACP_WORKFLOW" .. slot] = string_format(ACP.L.workflow.bindingWorkflow, slot);

    local boundSlot = slot;
    _G["ACP_WORKFLOW" .. slot] = function()
        ACP.WorkflowEngine:start(boundSlot);
    end;
end

--- Hidden secure buttons: the /acp bind hotkey button plus one per slot.
--- PreClick starts/resumes the slot; the SAME press's click casts the armed
--- step. PostClick is the reliable press signal for pet abilities.
---@param engine WorkflowEngine
function WorkflowBindings:createButtons(engine)
    if (CreateFrame and not engine.castButton) then
        local btn = CreateFrame("Button", ACP.Data.Constants.WORKFLOW_BUTTON_NAME, nil, "SecureActionButtonTemplate");

        if (btn and btn.SetAttribute) then
            btn:SetAttribute("type", "spell");
            btn:SetAttribute("spell", "");
            if (btn.RegisterForClicks) then
                btn:RegisterForClicks("AnyDown");
            end
            if (btn.Hide) then
                btn:Hide();
            end
            btn:SetScript("PostClick", function()
                engine:onSecurePress(nil);
            end);
            engine.castButton = btn;
        end
    end

    if (CreateFrame and not next(engine.castButtons)) then
        for slot = 1, ACP.Data.Constants.WORKFLOW_MAX_SLOTS do
            local sbtn = CreateFrame("Button",
                ACP.Data.Constants.WORKFLOW_BUTTON_NAME .. tostring(slot), nil, "SecureActionButtonTemplate");

            if (sbtn and sbtn.SetAttribute) then
                sbtn:SetAttribute("type", "spell");
                sbtn:SetAttribute("spell", "");
                if (sbtn.RegisterForClicks) then
                    sbtn:RegisterForClicks("AnyDown");
                end
                if (sbtn.Hide) then
                    sbtn:Hide();
                end
                sbtn:SetScript("PreClick", function()
                    engine:onPreClick(slot);
                end);
                sbtn:SetScript("PostClick", function()
                    engine:onSecurePress(slot);
                end);
                engine.castButtons[slot] = sbtn;
            end
        end
    end
end

---@param engine WorkflowEngine
---@return string|nil
function WorkflowBindings:boundKey(engine)
    return ACP.Settings:get("workflows.hotkey");
end

--- The loaded binding set (1|2), or nil before bindings load. 0 is truthy in
--- Lua, so SaveBindings(0) must be guarded with an explicit 1|2 check.
---@param engine WorkflowEngine
---@return number|nil
function WorkflowBindings:bindingSet(engine)
    local bs = GetCurrentBindingSet and GetCurrentBindingSet();
    return (bs == 1 or bs == 2) and bs or nil;
end

---@param engine WorkflowEngine
function WorkflowBindings:applyBinding(engine)
    if (not SetBindingClick or not engine.castButton) then
        return;
    end

    local key = self:boundKey(engine);

    if (engine._boundKey and engine._boundKey ~= key and SetBinding) then
        SetBinding(engine._boundKey, "");
    end

    engine._boundKey = nil;

    if (not key or key == "none" or key == "off") then
        return;
    end

    if (not self:bindingSet(engine)) then
        ACP.Utils.Timers:after("WorkflowKeyBindRetry", 1, function()
            engine:applyBinding();
        end);
        return;
    end

    if (InCombatLockdown and InCombatLockdown()) then
        ACP.Utils.Timers:after("WorkflowKeyBindRetry", 2, function()
            engine:applyBinding();
        end);
        return;
    end

    SetBindingClick(key, ACP.Data.Constants.WORKFLOW_BUTTON_NAME);

    local bs = self:bindingSet(engine);

    if (SaveBindings and bs) then
        SaveBindings(bs);
    end

    engine._boundKey = key;
end

---@param engine WorkflowEngine
function WorkflowBindings:clearBinding(engine)
    if (engine._boundKey and SetBinding) then
        SetBinding(engine._boundKey, "");

        local bs = self:bindingSet(engine);

        if (SaveBindings and bs) then
            SaveBindings(bs);
        end

        engine._boundKey = nil;
    end
end

--- The active cast key: the slot's Key Bindings UI key, else the /acp bind
--- hotkey. The workflow key wins so ONE key starts/resumes and casts.
---@param engine WorkflowEngine
---@param slot number|nil
---@return string|nil
function WorkflowBindings:resolveCastKey(engine, slot)
    slot = slot or engine.currentSlot;

    local key = slot and engine.slotKeys[slot];

    if (key and key ~= "") then
        return key;
    end

    return self:boundKey(engine);
end

---@param engine WorkflowEngine
---@return frame|nil
function WorkflowBindings:currentButton(engine)
    return engine.currentSlot and engine.castButtons[engine.currentSlot] or nil;
end

--- Applies `attr = value` to the /acp bind button and the CURRENT slot's
--- button; every other slot button is reset to the inert value first.
---@param engine WorkflowEngine
---@param attr string
---@param value any
function WorkflowBindings:setCastAttribute(engine, attr, value)
    if (engine.castButton and engine.castButton.SetAttribute) then
        engine.castButton:SetAttribute(attr, value);
    end

    for _, btn in pairs(engine.castButtons) do
        if (btn and btn.SetAttribute) then
            btn:SetAttribute(attr, "");
        end
    end

    local btn = self:currentButton(engine);

    if (btn and btn.SetAttribute) then
        btn:SetAttribute(attr, value);
    end
end

---@param engine WorkflowEngine
---@param slot number
function WorkflowBindings:onPreClick(engine, slot)
    if (engine.state == ACP.Data.Constants.WORKFLOW_STATE.IDLE or engine.state == ACP.Data.Constants.WORKFLOW_STATE.PAUSED
        or (engine.state == ACP.Data.Constants.WORKFLOW_STATE.RUNNING and engine.currentSlot ~= slot)) then
        engine:start(slot);
    end
end

--- Priority overrides (SetOverrideBindingClick) point each slot's Key
--- Bindings UI key at that slot's secure button — a full resync from the
--- authoritative binding table (which is never modified). Overrides do NOT
--- displace the player's command binding.
---@param engine WorkflowEngine
function WorkflowBindings:applySlotBindings(engine)
    if (not SetOverrideBindingClick or not GetBindingKey or not engine.castButton) then
        return;
    end

    if (not self:bindingSet(engine)) then
        ACP.Utils.Timers:after("WorkflowSlotBindRetry", 1, function()
            engine:applySlotBindings();
        end);
        return;
    end

    self:clearSlotOverrides(engine);

    for slot = 1, ACP.Data.Constants.WORKFLOW_MAX_SLOTS do
        local action = "ACP_WORKFLOW" .. tostring(slot);
        local key, key2 = GetBindingKey(action);

        if (key and key ~= "") then
            engine.slotKeys[slot] = key;
            SetOverrideBindingClick(engine.castButton, true, key, ACP.Data.Constants.WORKFLOW_BUTTON_NAME .. tostring(slot));

            -- A command can be bound to TWO keys — override both.
            if (key2 and key2 ~= "") then
                SetOverrideBindingClick(engine.castButton, true, key2, ACP.Data.Constants.WORKFLOW_BUTTON_NAME .. tostring(slot));
            end
        else
            engine.slotKeys[slot] = nil;
        end
    end
end

---@param engine WorkflowEngine
function WorkflowBindings:clearSlotOverrides(engine)
    if (ClearOverrideBindings and engine.castButton) then
        ClearOverrideBindings(engine.castButton);
    end
end

---@param engine WorkflowEngine
function WorkflowBindings:onBindingsUpdated(engine)
    self:applySlotBindings(engine);
end

---@param engine WorkflowEngine|nil
function WorkflowBindings:_init(engine)
    if (self._initialized) then
        return;
    end
    self._initialized = true;
    engine = engine or ACP.WorkflowEngine;

    self:createButtons(engine);
    self:applyBinding(engine);
    self:applySlotBindings(engine);

    ACP.Events:register("WB.PLAYER_LOGIN", "PLAYER_LOGIN", function()
        engine:applySlotBindings();
    end);
    ACP.Events:register("WB.UPDATE_BINDINGS", "UPDATE_BINDINGS", function()
        engine:onBindingsUpdated();
    end);
    ACP.Events:register("WB.REGEN_ENABLED", "PLAYER_REGEN_ENABLED", function()
        engine:applySlotBindings();
    end);

    -- Drop the overrides while the Blizzard Key Bindings UI is open so its
    -- capture dialog receives the presses; re-apply on close.
    if (_G.KeyBindingFrame and _G.KeyBindingFrame.HookScript) then
        _G.KeyBindingFrame:HookScript("OnShow", function()
            engine:clearSlotOverrides();
        end);
        _G.KeyBindingFrame:HookScript("OnHide", function()
            engine:applySlotBindings();
        end);
    end

    ACP.Events:register("WB.LOGOUT", "PLAYER_LOGOUT", function()
        engine:clearSlotOverrides();
    end);

    ACP:debugPrint(ACP.L.workflow.bindingsInit, ACP.Data.Constants.WORKFLOW_MAX_SLOTS);
end

return ACP;
