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
    inCombat = false,
    dead = false,
    tradeFrameShown = false,
    chatMessages = {},
    cTimerCallbacks = {},  -- { cb = fn, cancelled = bool }
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
    local n = tonumber((unit or ""):match("^party(%d+)$"));
    return n ~= nil and n <= _G.__stub.partyCount;
end;
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