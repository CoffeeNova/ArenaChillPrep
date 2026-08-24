-- ArenaChillPrep — Classes/WorkflowBindings
-- Registers the in-game Key Bindings entries (ESC -> Key Bindings ->
-- ArenaChillPrep) that START/RESUME each workflow slot, and owns the
-- secure-button / binding management extracted from WorkflowEngine
-- (refactor Phase 5): button creation, the /acp bind hotkey, the per-slot
-- priority overrides and the binding event subscriptions.
--
-- NOTE: this is the start/resume key. The per-step CAST key is a SEPARATE
-- mechanism — the engine's hidden secure button bound via /acp bind <key>
-- (SetBindingClick) — because 20506 only allows casting from a real hardware
-- event (verified 2026-08-19). WorkflowEngine:start() already guards all the
-- start/resume cases: no-op while RUNNING, resume while PAUSED (same slot),
-- no-op once DONE, "not in arena prep" outside an arena.

local _, ACP = ...;

local string_format = _G.string.format;
local tostring = _G.tostring;

---@class WorkflowBindings
local WorkflowBindings = {
    _initialized = false,
};

---@type WorkflowBindings
ACP.WorkflowBindings = WorkflowBindings;

-- Binding entry names shown in the Key Bindings UI. Must exist at file scope
-- before the player opens the Key Bindings window — the client reads these
-- globals directly (verified pattern on 20506: BetterFishing).
BINDING_HEADER_ACP = "ArenaChillPrep";

for slot = 1, ACP.Data.Constants.WORKFLOW_MAX_SLOTS do
    _G["BINDING_NAME_ACP_WORKFLOW" .. slot] = string_format(ACP.L.workflow.bindingWorkflow, slot);

    -- Capture the loop value for Lua 5.1 closures.
    local boundSlot = slot;
    _G["ACP_WORKFLOW" .. slot] = function()
        ACP.WorkflowEngine:start(boundSlot);
    end;
end

--- Create the hidden secure cast buttons on the engine: the /acp bind hotkey
--- button plus one per workflow slot. The per-slot buttons are click-bound to
--- the Key Bindings UI slot keys (applySlotBindings); PreClick starts/resumes
--- the slot and the SAME press's click casts the armed step (one press =
--- start + cast, 2026-08-22).
---@param engine WorkflowEngine
function WorkflowBindings:createButtons(engine)
    -- Secure cast button (M6 pattern): pressing the hotkey clicks this button
    -- (a real hardware event), and the client casts the spell set via its
    -- "spell" attribute. A programmatic :Click() is silently dropped on 20506,
    -- so the engine NEVER clicks it — it waits for the user's key press
    -- (waitingForKey) on cast-time steps. This is the /acp bind hotkey button.
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
            -- The hardware key press clicks this button (SetBindingClick), so
            -- PostClick is the reliable "the user pressed the key" signal for
            -- pet abilities (no UNIT_SPELLCAST_* fires for the pet's cast).
            btn:SetScript("PostClick", function()
                engine:onSecurePress(nil);
            end);
            engine.castButton = btn;
        end
    end

    -- Per-slot secure cast buttons: the Key Bindings UI slot keys are
    -- click-bound to these (applySlotBindings). PreClick starts/resumes the
    -- slot and the SAME press's click casts the armed step — ONE press both
    -- starts and casts (2026-08-22).
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

--- The configured workflow hotkey (Settings "workflows.hotkey"), or nil.
---@param engine WorkflowEngine
---@return string|nil
function WorkflowBindings:boundKey(engine)
    return ACP.Settings:get("workflows.hotkey");
end

--- The loaded binding set (1 = account, 2 = character), or nil when bindings
--- aren't loaded yet. On 20506 GetCurrentBindingSet() returns 0 before the
--- bindings load, and SaveBindings(0) throws "Usage: SaveBindings(1||2)" (it
--- crashed the whole _init at ADDON_LOADED — verified 2026-08-19). 0 is truthy
--- in Lua, so a plain truthiness guard is NOT enough — the value must be 1|2.
---@param engine WorkflowEngine
---@return number|nil
function WorkflowBindings:bindingSet(engine)
    local bs = GetCurrentBindingSet and GetCurrentBindingSet();
    return (bs == 1 or bs == 2) and bs or nil;
end

--- Bind the hotkey to the secure cast button (SetBindingClick). Safe to call
--- repeatedly: rebinds the current key and unbinds a previous one. No-op when
--- no hotkey is set or the button/binding APIs are unavailable; retries while
--- the binding set has not loaded yet or during combat (bindings can't change
--- in combat).
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
        -- Bindings load late — retry shortly.
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

--- Remove the current hotkey binding (used by `/acp bind off`).
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

--- The active cast key for a run: the Key Bindings UI key of the workflow
--- slot (remembered by applySlotBindings — the slot key is permanently
--- click-bound to the slot's secure button for the session), else the
--- configured /acp bind hotkey. The workflow key wins so ONE key both
--- starts/resumes and casts.
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

--- The secure button the current slot's key clicks (per-slot buttons created
--- in createButtons), or nil while no slot is running.
---@param engine WorkflowEngine
---@return frame|nil
function WorkflowBindings:currentButton(engine)
    return engine.currentSlot and engine.castButtons[engine.currentSlot] or nil;
end

--- Apply `attr = value` to the live cast buttons. The /acp bind hotkey button
--- always receives it, and so does the CURRENT slot's button (the one whose key
--- is armed for this run). Every OTHER slot button is first reset to the inert
--- value, so a spell/macro never lingers on a button whose run has ended —
--- without this, the slot key would keep re-casting the last step's spell after
--- the workflow is stopped/reset (the engine nulls currentSlot before clearing,
--- so a per-slot button would otherwise keep its armed attribute).
---@param engine WorkflowEngine
---@param attr string
---@param value any
function WorkflowBindings:setCastAttribute(engine, attr, value)
    if (engine.castButton and engine.castButton.SetAttribute) then
        engine.castButton:SetAttribute(attr, value);
    end

    -- Wipe the attribute from every slot button first (guarantees only the
    -- current slot's button ends up armed), then arm the current one.
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

--- Insecure PreClick hook (ItemRack pattern, verified on 20506): runs BEFORE
--- the button's secure action, so ONE press can start/resume the workflow AND
--- cast the freshly armed step. No-op while the button is already armed
--- (waitingForKey/waitingForPet) and after DONE (one run per prep — the button
--- is inert, see executeCurrentStep's DONE branch).
---@param engine WorkflowEngine
---@param slot number
function WorkflowBindings:onPreClick(engine, slot)
    if (engine.state == ACP.Data.Constants.WORKFLOW_STATE.IDLE or engine.state == ACP.Data.Constants.WORKFLOW_STATE.PAUSED
        or (engine.state == ACP.Data.Constants.WORKFLOW_STATE.RUNNING and engine.currentSlot ~= slot)) then
        engine:start(slot);
    end
    -- RUNNING + same slot: the button is already armed (cast/pet/equip) or
    -- inert (mid-cast) — leave it alone. DONE: no-op.
end

--- Point each workflow slot's Key Bindings UI key at that slot's secure cast
--- button via SetOverrideBindingClick(owner, true, ...) — a PRIORITY OVERRIDE
--- (BetterFishing pattern, verified on 20506: BetterFishing.lua:276/290).
---
--- Unlike SetBindingClick, an override does NOT displace the player's command
--- binding: GetBindingKey/GetBindingAction keep returning the real binding, so
--- the Key Bindings UI and the Workflows-tab key capture keep working — the
--- user can rebind ";"/any key at any time (the displaced-command approach
--- broke key assignment entirely, live 2026-08-22). Overrides die with the
--- session (nothing to restore or persist on logout). With the key on the
--- button, one press starts AND casts (PreClick → start → arm; click → cast).
---
--- This is a FULL RESYNC: previous overrides are cleared, then re-applied from
--- the authoritative binding table — safe because the table itself is never
--- modified. Deferred (with retry) until the binding set is loaded.
---@param engine WorkflowEngine
function WorkflowBindings:applySlotBindings(engine)
    if (not SetOverrideBindingClick or not GetBindingKey or not engine.castButton) then
        return;
    end

    if (not self:bindingSet(engine)) then
        -- Bindings load late — retry shortly.
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

            -- SECONDARY key (2026-08-24 fix): a command can be bound to TWO
            -- keys in the Key Bindings UI. Without the override on the second
            -- key, pressing it only fires the ACP_WORKFLOW<i> start action
            -- (a no-op while the workflow is already running) and can never
            -- cast an armed step. Both keys must press the slot's secure
            -- button.
            if (key2 and key2 ~= "") then
                SetOverrideBindingClick(engine.castButton, true, key2, ACP.Data.Constants.WORKFLOW_BUTTON_NAME .. tostring(slot));
            end
        else
            engine.slotKeys[slot] = nil;
        end
    end
end

--- Remove every slot-key override. Called by applySlotBindings (resync), when
--- the Blizzard Key Bindings UI opens (so its key-capture dialog receives the
--- presses) and on PLAYER_LOGOUT (hygiene — overrides die with the session).
---@param engine WorkflowEngine
function WorkflowBindings:clearSlotOverrides(engine)
    if (ClearOverrideBindings and engine.castButton) then
        ClearOverrideBindings(engine.castButton);
    end
end

--- The player saved bindings (UPDATE_BINDINGS): the binding table changed —
--- full resync of the overrides. Keys the player unbound/rebound simply stop
--- being overridden (GetBindingKey reflects the fresh state).
---@param engine WorkflowEngine
function WorkflowBindings:onBindingsUpdated(engine)
    self:applySlotBindings(engine);
end

--- Init hook (called from WorkflowEngine:_init — the engine owns the buttons
--- and state, this module wires them). The binding globals and handlers are
--- registered at file scope, and the client persists the player's bindings
--- itself (survives /reload and game restart).
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

    -- Slot-key overrides are re-applied when bindings load/change and after
    -- combat (a full resync — the override table is rebuilt from the real
    -- bindings, which are never modified).
    ACP.Events:register("WB.PLAYER_LOGIN", "PLAYER_LOGIN", function()
        engine:applySlotBindings();
    end);
    ACP.Events:register("WB.UPDATE_BINDINGS", "UPDATE_BINDINGS", function()
        engine:onBindingsUpdated();
    end);
    ACP.Events:register("WB.REGEN_ENABLED", "PLAYER_REGEN_ENABLED", function()
        engine:applySlotBindings();
    end);

    -- While the Blizzard Key Bindings UI is open, drop the priority overrides
    -- so its key-capture dialog receives the presses (a priority override
    -- would steal them). Re-apply when the frame closes. NOT ADDON_UNLOADING —
    -- the client throws "Attempt to register unknown event ADDON_UNLOADING"
    -- on 20506 (verified 2026-08-19; it crashed the whole _init).
    if (_G.KeyBindingFrame and _G.KeyBindingFrame.HookScript) then
        _G.KeyBindingFrame:HookScript("OnShow", function()
            engine:clearSlotOverrides();
        end);
        _G.KeyBindingFrame:HookScript("OnHide", function()
            engine:applySlotBindings();
        end);
    end

    -- Logout hygiene: clear the overrides (they are session-scoped and would
    -- die with the session anyway; the binding table itself is untouched, so
    -- nothing needs restoring or persisting).
    ACP.Events:register("WB.LOGOUT", "PLAYER_LOGOUT", function()
        engine:clearSlotOverrides();
    end);

    ACP:debugPrint(ACP.L.workflow.bindingsInit, ACP.Data.Constants.WORKFLOW_MAX_SLOTS);
end

return ACP;
