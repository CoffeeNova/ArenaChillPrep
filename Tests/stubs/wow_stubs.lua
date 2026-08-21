-- ArenaChillPrep — Tests/stubs/wow_stubs.lua
-- Minimal WoW API stubs so the addon loads and runs under plain LuaJIT.
--
-- Some modules capture globals at file scope (GetTime, IsInInstance,
-- UnitExists, UnitIsUnit, UnitAffectingCombat, UnitIsDeadOrGhost,
-- TradeFrame, ERR_TRADE_COMPLETE, C_UnitAuras, C_Timer, ...). Those stubs
-- read from the mutable `_G.__stub` state table, so tests mutate
-- `_G.__stub` instead of replacing the globals. Functions read at call
-- time (containers, UnitClass, GetNumPartyMembers, ...) can be overridden
-- directly by tests.

local _G = _G;

-- ---- mutable stub state (tests mutate this) ----
_G.__stub = {
    time = 0,
    inInstance = { false, "none" },
    aura = nil,          -- object returned by C_UnitAuras.GetPlayerAuraBySpellID
    auraByIndex = nil,   -- object returned by C_UnitAuras.GetAuraDataByIndex
    partyCount = 0,
    unitExists = true,
    unitIsUnit = false,
    unitGUID = nil,       -- string returned by UnitGUID("pet") (e.g. "Creature-0-...")
    inCombat = false,
    dead = false,
    tradeFrameShown = false,
    chatMessages = {},
    cTimerCallbacks = {},  -- { cb = fn, cancelled = bool }
    spellbookTabs = {},    -- { [tab] = { name, icon, offset, numSpells, isGuild } }
    spellbookItems = {},   -- { [slot] = { itemType, spellID, name, rankText, passive } }
    spellInfo = {},        -- { [spellID] = name } for GetSpellInfo
    knownSpells = {},      -- { [spellID] = true } for IsPlayerSpell (tests mutate)
};

-- ---- time (captured at file scope by Events/ArenaPrep/TradeManager) ----
_G.GetTime = function() return _G.__stub.time end;

-- ---- chat (captured by bootstrap) ----
_G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg) table.insert(_G.__stub.chatMessages, msg) end,
};

-- ---- addon metadata (captured by bootstrap) ----
_G.C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end };

-- ---- locale (captured by Localization) ----
_G.GetLocale = function() return "enUS" end;

-- ---- instance (captured by ArenaPrep) ----
_G.IsInInstance = function() return _G.__stub.inInstance[1], _G.__stub.inInstance[2] end;

-- ---- auras (captured by ArenaPrep) ----
_G.C_UnitAuras = {
    GetPlayerAuraBySpellID = function() return _G.__stub.aura end,
    GetAuraDataByIndex = function() return _G.__stub.auraByIndex end,
};

-- ---- units (UnitExists/UnitIsUnit/UnitAffectingCombat/UnitIsDeadOrGhost
--      captured by DeliveryController; UnitClass/UnitName/GetNumPartyMembers
--      read at call time) ----
_G.UnitExists = function(unit)
    if (unit == "pet" or unit == "player") then
        return true;
    end
    local n = tonumber((unit or ""):match("^party(%d+)$"));
    return n ~= nil and n <= _G.__stub.partyCount;
end;
_G.UnitGUID = function(unit) return _G.__stub.unitGUID end;
_G.UnitIsUnit = function() return _G.__stub.unitIsUnit end;
_G.UnitAffectingCombat = function() return _G.__stub.inCombat end;
_G.UnitIsDeadOrGhost = function() return _G.__stub.dead end;
_G.UnitClass = function() return "Warlock", "WARLOCK" end;
_G.UnitName = function() return "Player" end;
_G.GetNumPartyMembers = function() return _G.__stub.partyCount end;
_G.GetNumArenaOpponents = function() return 0 end;

-- ---- containers (read at call time) ----
-- C_Container.GetContainerItemInfo returns a TABLE (ContainerItemInfo);
-- the legacy global returns the 11-value tuple. Both are stubbed.
_G.C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemInfo = function() return nil end,
    UseContainerItem = function() end,
};
_G.GetContainerNumSlots = function() return 0 end;
_G.GetContainerItemInfo = function() return nil end;
_G.UseContainerItem = function() end;

-- ---- items (read at call time) ----
_G.C_Item = {
    GetItemGUID = function() return nil end,
    DoesItemExist = function() return false end,
};
_G.ItemLocation = { CreateFromBagAndSlot = function() return {} end };

-- ---- spellbook (read at call time; WorkflowSpellbook scan) ----
-- Legacy TBC spellbook API: GetNumSpellTabs / GetSpellTabInfo (offset +
-- numSpells per tab) / GetSpellBookItemInfo / GetSpellBookItemName /
-- IsPassiveSpell all take the bookType STRING "spell"/"pet" (BOOKTYPE_SPELL —
-- the 20506 form; "player" is retail-only and must return nothing here).
-- Default state is an empty book so scan() exercises the static fallback;
-- tests populate __stub.spellbookTabs / __stub.spellbookItems / spellInfo.
_G.GetNumSpellTabs = function()
    return #_G.__stub.spellbookTabs;
end;
_G.GetSpellTabInfo = function(tab)
    local t = _G.__stub.spellbookTabs[tab];
    if (not t) then
        return nil;
    end
    return t.name, t.icon, t.offset, t.numSpells, t.isGuild;
end;
_G.GetSpellBookItemInfo = function(slot, bookType)
    if (bookType ~= "spell") then
        return nil;
    end
    local item = _G.__stub.spellbookItems[slot];
    if (not item) then
        return nil;
    end
    return item.itemType, item.spellID;
end;
_G.GetSpellBookItemName = function(slot, bookType)
    if (bookType ~= "spell") then
        return nil;
    end
    local item = _G.__stub.spellbookItems[slot];
    if (not item) then
        return nil;
    end
    return item.name, item.rankText;
end;
_G.IsPassiveSpell = function(slot, bookType)
    if (bookType ~= "spell") then
        return false
    end
    local item = _G.__stub.spellbookItems[slot];
    return item and item.passive == true or false
end;
-- IsPlayerSpell is captured at file scope by several modules; a mutable stub
-- (reads _G.__stub.knownSpells) lets tests control which ranks are "known"
-- without replacing the global. Default: nothing known.
_G.IsPlayerSpell = function(id)
    return _G.__stub.knownSpells[id] == true
end;
_G.GetSpellInfo = function(idOrName)
    if (type(idOrName) == "number") then
        local name = _G.__stub.spellInfo[idOrName];
        if (not name) then
            return nil;
        end
        return name, "", 1, 0, 0, 0, idOrName;
    end
    return nil;
end;

-- ---- trade (TradeFrame/ERR_TRADE_COMPLETE captured at file scope) ----
_G.TradeFrame = { IsShown = function() return _G.__stub.tradeFrameShown end };
_G.ERR_TRADE_COMPLETE = "Trade complete";
_G.InitiateTrade = function() end;
_G.ClearCursor = function() end;

-- ---- timers (captured by Utils/Timers) ----
_G.C_Timer = {
    After = function(delay, cb)
        local entry = { cb = cb, cancelled = false };
        table.insert(_G.__stub.cTimerCallbacks, entry);
        return { Cancel = function() entry.cancelled = true end };
    end,
    NewTicker = function(period, cb)
        local entry = { cb = cb, cancelled = false };
        table.insert(_G.__stub.cTimerCallbacks, entry);
        return { Cancel = function() entry.cancelled = true end };
    end,
};

-- ---- misc ----
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end;
_G.strlower = string.lower;
_G.UIParent = {};
_G.tinsert = table.insert;
_G.tremove = table.remove;

-- ---- frames ----
local FrameMethods = {};
function FrameMethods:RegisterEvent() end;
function FrameMethods:UnregisterEvent() end;
function FrameMethods:SetScript(scriptType, fn)
    self.scripts = self.scripts or {};
    self.scripts[scriptType] = fn;
end;
function FrameMethods:SetPoint() end;
function FrameMethods:SetSize() end;
function FrameMethods:SetBackdrop() end;
function FrameMethods:SetBackdropColor() end;
function FrameMethods:SetBackdropBorderColor() end;
function FrameMethods:GetWidth() return 660 end;
function FrameMethods:GetHeight() return 400 end;
function FrameMethods:IsShown() return false end;
function FrameMethods:EnableMouse() end;
function FrameMethods:SetChecked() end;
function FrameMethods:GetChecked() return false end;
function FrameMethods:Click() end;
function FrameMethods:SetAttribute(attr, value)
    self.attributes = self.attributes or {};
    self.attributes[attr] = value;
end;
function FrameMethods:RegisterForClicks() end;
function FrameMethods:Hide() end;
function FrameMethods:Show() end;
function FrameMethods:Disable() end;
function FrameMethods:SetAlpha() end;
function FrameMethods:SetMinMaxValues() end;
function FrameMethods:SetValueStep() end;
function FrameMethods:SetValue() end;
function FrameMethods:CreateFontString()
    return {
        SetText = function() end, SetPoint = function() end,
        SetTextColor = function() end, SetWidth = function() end,
        SetJustifyH = function() end, SetWordWrap = function() end,
    };
end;

function _G.CreateFrame(frameType, name, parent, template)
    local frame = setmetatable({}, { __index = FrameMethods });
    frame.type = frameType;
    frame.name = name;
    if (name) then _G[name] = frame; end
    if (template == "UICheckButtonTemplate" and name) then
        _G[name .. "Text"] = {
            SetText = function() end, SetPoint = function() end,
            EnableMouse = function() end, SetScript = function() end,
        };
    end
    return frame;
end;

-- ---- keybindings (WorkflowEngine hotkey, read at call time) ----
-- Real-client semantics: binding a key to a button CLICK removes any command
-- binding on that key (and vice versa). resolveCastKey/takeoverCastKey depend
-- on this — after a takeover, GetBindingKey(command) must be nil.
function _G.SetBindingClick(key, buttonName)
    _G.__stub.bindingClicks = _G.__stub.bindingClicks or {};
    _G.__stub.bindingClicks[key] = buttonName;
    if (_G.__stub.bindingKeys) then
        for command, boundKey in pairs(_G.__stub.bindingKeys) do
            if (boundKey == key) then
                _G.__stub.bindingKeys[command] = nil;
            end
        end
    end
    if (_G.__stub.bindingActions) then
        _G.__stub.bindingActions[key] = nil;
    end
end;
function _G.SetBinding(key, command)
    _G.__stub.bindings = _G.__stub.bindings or {};
    _G.__stub.bindings[key] = command;
    _G.__stub.bindingKeys = _G.__stub.bindingKeys or {};
    _G.__stub.bindingActions = _G.__stub.bindingActions or {};
    if (command == "" or command == nil) then
        for cmd, boundKey in pairs(_G.__stub.bindingKeys) do
            if (boundKey == key) then
                _G.__stub.bindingKeys[cmd] = nil;
            end
        end
        _G.__stub.bindingActions[key] = nil;
    else
        _G.__stub.bindingKeys[command] = key;
        _G.__stub.bindingActions[key] = command;
    end
end;
function _G.SaveBindings() end;
function _G.GetCurrentBindingSet() return 1 end;
-- key -> action (used by takeoverCastKey's guard).
function _G.GetBindingAction(key)
    return _G.__stub.bindingActions and _G.__stub.bindingActions[key];
end;
-- command -> key (used by resolveCastKey).
function _G.GetBindingKey(command)
    return _G.__stub.bindingKeys and _G.__stub.bindingKeys[command];
end;

-- ---- override bindings (SetOverrideBindingClick/ClearOverrideBindings) ----
-- Real-client semantics: an override intercepts the key WITHOUT displacing
-- the player's command binding — bindingKeys/bindingActions stay intact
-- (that is the whole point vs SetBindingClick).
function _G.SetOverrideBindingClick(owner, isPriority, key, buttonName)
    _G.__stub.overrideClicks = _G.__stub.overrideClicks or {};
    _G.__stub.overrideClicks[key] = buttonName;
end;
function _G.ClearOverrideBindings(owner)
    _G.__stub.overrideClicks = {};
end;