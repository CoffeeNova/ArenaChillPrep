-- ArenaChillPrep — Classes/UI/WorkflowUI
-- Character-local workflow editor. The editor is built around:
--   select a slot -> assemble/check the sequence -> run it by key.
--
-- Layout (top -> bottom):
--   status line        — engine state + slot state + step count
--   workflow defaults  — skip-if-buffed default + description
--   workflow editor    — selector, add workflow, name, enabled, key bind
--   steps              — table header + scrollable step list filling the rest
--
-- Spell choices come from ACP.WorkflowSpellbook: Add Step shows one entry per
-- learned spell name (plain name only). Each step always uses the highest
-- learned rank — rank is not user-selectable.
---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local ipairs = _G.ipairs;
local tremove = _G.tremove;
local tostring = _G.tostring;
local tonumber = _G.tonumber;
local select = _G.select;
local table_concat = _G.table.concat;
local math_max = _G.math.max;
local math_ceil = _G.math.ceil;
local GetBindingKey = _G.GetBindingKey;
local GetBindingAction = _G.GetBindingAction;
local GetSpellInfo = _G.GetSpellInfo;
local UnitClass = _G.UnitClass;
local CreateFrame = _G.CreateFrame;
local SetBinding = _G.SetBinding;
local GetCurrentBindingSet = _G.GetCurrentBindingSet;
local SaveBindings = _G.SaveBindings;
local GameTooltip = _G.GameTooltip;

local SECTION_GAP = 8;
local STATUS_H = 24;
local DEFAULTS_H = 62;
local EDITOR_H = 114;
local STEP_ROW_H = 48;
local STEP_HEADER_H = 22;
local STEP_LIST_FLOOR = 40;
local STEP_NUM_W = 24;
local STEP_TARGET_W = 96;
local STEP_SKIP_W = 80;
local TARGET_X_SHIFT = 24;
local FIELD_X = 74;
local ACTIONS_GAP = 4;
local BUTTON_PAD = 10;

-- CLASS_WARLOCK is NOT a global on TBC Anniversary FrameXML — same guard as
-- Data/Items.lua and Classes/WorkflowSpellbook.lua.
local CLASS_WARLOCK = _G.CLASS_WARLOCK or "WARLOCK";

---@class WorkflowUI
local WorkflowUI = {
    ---@type number
    SelectedSlot = 1,
    ---@type boolean
    isBuilt = false,
    ---@type table<string, any>
    Controls = {},
    ---@type Frame[]
    StepRows = {},
    ---@type Frame|nil
    RecycleFrame = nil,
    ---@type FontString|nil
    EmptyLabel = nil
};

---@type WorkflowUI
ACP.WorkflowUI = WorkflowUI;

local measureFont;

local function textWidth(text)
    if (not measureFont) then
        local holder = CreateFrame("Frame");
        measureFont = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal");
        measureFont:Hide();
    end

    measureFont:SetText(text);
    return measureFont:GetStringWidth();
end

local actionLayoutCache;

local function actionLayout()
    if (actionLayoutCache) then
        return actionLayoutCache;
    end

    local L = ACP.L.workflow;
    local upW = math_ceil(textWidth(L.moveUpLabel) + BUTTON_PAD * 2);
    local downW = math_ceil(textWidth(L.moveDownLabel) + BUTTON_PAD * 2);
    local delW = math_ceil(textWidth(L.deleteStepLabel) + BUTTON_PAD * 2);

    actionLayoutCache = {
        upW = upW,
        downW = downW,
        delW = delW,
        total = upW + ACTIONS_GAP + downW + ACTIONS_GAP + delW
    };

    return actionLayoutCache;
end

local function setSetting(path, value)
    ACP.Settings:set(path, value);
end

local function persistSettings()
    if (ACP.Settings.persist) then
        ACP.Settings:persist();
    end
end

local function stepsPath(slot)
    return "workflows.definitions." .. tostring(slot) .. ".steps";
end

local function stepPath(slot, index)
    return stepsPath(slot) .. "." .. tostring(index);
end

local function selectedSteps(slot)
    local steps = ACP.Settings:get(stepsPath(slot));
    return (type(steps) == "table") and steps or {};
end

local function workflowCount()
    local C = ACP.Data.Constants;
    local count = tonumber(ACP.Settings:get("workflows.slotCount")) or C.WORKFLOW_DEFAULT_SLOTS;

    if (count < C.WORKFLOW_DEFAULT_SLOTS) then
        count = C.WORKFLOW_DEFAULT_SLOTS;
    end

    if (count > C.WORKFLOW_MAX_SLOTS) then
        count = C.WORKFLOW_MAX_SLOTS;
    end

    return count;
end

local function selectedKey(slot)
    local key = (GetBindingKey and GetBindingKey("ACP_WORKFLOW" .. tostring(slot))) or "";
    return (key ~= "") and key or nil;
end

-- Same key whitelist as UI.Keybind (letters/digits OR punctuation characters
-- like ";" / "[" / "/", optional SHIFT-/CTRL-/ALT- prefix, or named keys).
-- SetBinding with anything else could corrupt bindings-cache.wtf and kill ALL
-- keybindings after the next /reload.
-- NOTE: Lua patterns have no `|` alternation, so the modifier prefix is
-- stripped with gsub before the base check.
local function isSafeBindingKey(key)
    if (type(key) ~= "string" or key == "") then
        return false;
    end

    local base = key:gsub("SHIFT%-", ""):gsub("CTRL%-", ""):gsub("ALT%-", "");
    return base:match("^[%w%p]+$") ~= nil;
end

local function spellLabel(spellID, fallback)
    if (GetSpellInfo) then
        local name = select(1, GetSpellInfo(spellID));

        if (name) then
            return name;
        end
    end

    return fallback or ("#" .. tostring(spellID));
end

--- Display name for a spell step row. Stone-creating steps (Create Healthstone
--- / Create Spellstone) show the rank-specific stone label ("Create Master
--- Healthstone") — the plain GetSpellInfo name is just "Create Healthstone" for
--- every rank, so only the spellID would disambiguate. Other steps keep the
--- localized spell name.
---@param step table
---@param entry table|nil
---@return string
local function stepSpellLabel(step, entry)
    local stone = ACP.Data.Workflows and ACP.Data.Workflows.stoneRanks
        and ACP.Data.Workflows.stoneRanks[step.spellID];

    if (stone and ACP.WorkflowSpellbook and ACP.WorkflowSpellbook.stoneStepLabel) then
        return ACP.WorkflowSpellbook:stoneStepLabel(entry or { spellID = step.spellID });
    end

    return spellLabel(step.spellID, entry and entry.name);
end

--- Localized name of an item for an equipItem step row (GetItemInfo first —
--- the conjured item is in bags by the time it is equipped — then the step's
--- stored itemName fallback).
---@param step table
---@return string
local function itemLabel(step)
    if (GetItemInfo) then
        local ok, name = pcall(GetItemInfo, step.itemID);

        if (ok and name) then
            return name;
        end
    end

    return (type(step.itemName) == "string" and step.itemName ~= "") and step.itemName or ("#" .. tostring(step.itemID));
end

local function findSpell(spellID)
    if (ACP.WorkflowSpellbook and ACP.WorkflowSpellbook.getEntry) then
        local entry = ACP.WorkflowSpellbook:getEntry(spellID);

        if (entry) then
            return entry, entry.category;
        end
    end

    local spells = ACP.Data.Workflows and ACP.Data.Workflows.spells;

    if (spells) then
        -- Match by exact spellID first (covers the catalog's known rank IDs).
        for category, list in pairs(spells) do
            for _, entry in ipairs(list) do
                if (entry.spellID == spellID) then
                    entry.category = category;
                    return entry, category;
                end
            end
        end

        -- Fallback for a learned rank ID the static catalog does not list (the
        -- scan is class-gated to a limited fallback, so a saved step whose
        -- spellID is a non-catalog rank would otherwise lose its metadata and
        -- render "Not available" for Target/Skip). Match the spell by its
        -- localized name instead, then borrow the catalog entry's behavior.
        if (GetSpellInfo) then
            local ok, name = pcall(GetSpellInfo, spellID);

            if (ok and name) then
                for category, list in pairs(spells) do
                    for _, entry in ipairs(list) do
                        if (entry.name == name
                            or (GetSpellInfo and select(1, GetSpellInfo(entry.spellID)) == name)) then
                            entry.category = category;
                            return entry, category;
                        end
                    end
                end
            end
        end
    end

    return nil;
end

local function spellGroups()
    if (ACP.WorkflowSpellbook and ACP.WorkflowSpellbook.getGroupsByCategory) then
        return ACP.WorkflowSpellbook:getGroupsByCategory();
    end

    return {};
end

local function targetItems()
    local L = ACP.L.workflow;
    local items = {};

    for i, token in ipairs(ACP.Data.Workflows.targets) do
        local key = token:gsub("^%l", string.upper);
        items[i] = {
            value = token,
            label = L["target" .. key] or token
        };
    end

    return items;
end

--- Attach a GameTooltip tooltip to any mouse-capable widget (control or
--- FontString). FontStrings need EnableMouse(true) to receive OnEnter/OnLeave.
---@param widget Frame
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

--- Plain spell name for the Add Step menu. No rank/spellID decoration — the
--- step always uses the highest learned rank of that name.
---@param group table
---@return string
local function formatSpellGroup(group)
    return group.name or "";
end

local function spellItems()
    local L = ACP.L.workflow;
    local groups = spellGroups();
    local order = {"buffs", "summons", "createItem", "utility", "pets", "other"};
    local catKeys = {
        buffs = "catBuffs",
        summons = "catSummons",
        createItem = "catCreateItem",
        utility = "catUtility",
        pets = "catPets",
        other = "catOther"
    };
    local items = {};

    for _, category in ipairs(order) do
        local list = groups[category] or {};

        if (#list > 0) then
            items[#items + 1] = {
                value = nil,
                label = L[catKeys[category]] or category,
                isTitle = true
            };

            for _, group in ipairs(list) do
                local isStoneGroup = group.name == "Create Healthstone" or group.name == "Create Spellstone";

                if (isStoneGroup) then
                    -- Each learned/statically-known rank of a stone-creating
                    -- spell is listed separately with the stone's name so the
                    -- player can pick a specific rank: "Create Master
                    -- Healthstone", "Create Major Healthstone", etc.
                    for _, entry in ipairs(group.entries) do
                        items[#items + 1] = {
                            value = entry.spellID,
                            label = ACP.WorkflowSpellbook:stoneStepLabel(entry)
                        };
                    end
                else
                    items[#items + 1] = {
                        value = group.key,
                        label = formatSpellGroup(group)
                    };
                end
            end
        end
    end

    -- Equippable conjured items (spellstones): an equipItem step targets an
    -- item, not a spell — the values use the "item:<id>" key convention.
    -- The catalog is Warlock-specific, so it is only offered to Warlocks.
    local equipList = nil;

    if (UnitClass and select(2, UnitClass("player")) == CLASS_WARLOCK) then
        equipList = ACP.Data.Workflows and ACP.Data.Workflows.equipItems;
    end

    if (equipList and #equipList > 0) then
        items[#items + 1] = {
            value = nil,
            label = L.catEquipItems,
            isTitle = true
        };

        for _, entry in ipairs(equipList) do
            items[#items + 1] = {
                value = "item:" .. tostring(entry.itemID),
                label = entry.name
            };
        end
    end

    return items;
end

local function workflowItems()
    local items = {};

    for slot = 1, workflowCount() do
        local definition = ACP.Settings:get("workflows.definitions." .. slot);
        local name = type(definition) == "table" and definition.name or "";
        local label = tostring(slot);

        if (name and name ~= "") then
            label = label .. " - " .. name;
        end

        items[slot] = {
            value = slot,
            label = label
        };
    end

    return items;
end

function WorkflowUI:addWorkflow()
    local C = ACP.Data.Constants;
    local count = workflowCount();

    if (count >= C.WORKFLOW_MAX_SLOTS) then
        ACP:print(ACP.L.workflow.slotLimit, C.WORKFLOW_MAX_SLOTS);
        return;
    end

    local slot = count + 1;
    setSetting("workflows.slotCount", slot);
    setSetting("workflows.definitions." .. slot, {
        enabled = false,
        name = "",
        steps = {}
    });
    self.SelectedSlot = slot;
    self:refresh();
end

--- Delete the selected workflow. Keeps at least WORKFLOW_DEFAULT_SLOTS: at the
--- floor the definition is reset to empty instead. Above the floor the slot is
--- removed, later slots shift down, and their key bindings move with them
--- (ACP_WORKFLOW<i+1> -> ACP_WORKFLOW<i>) so hotkeys stay on the right content.
--- The selection moves to the PREVIOUS workflow (slot - 1) so the editor
--- immediately shows that workflow's steps; deleting slot 1 falls back to the
--- shifted-up former slot 2 (now slot 1).
function WorkflowUI:deleteWorkflow()
    local C = ACP.Data.Constants;
    local count = workflowCount();
    local slot = self.SelectedSlot;

    if (count <= C.WORKFLOW_DEFAULT_SLOTS) then
        setSetting("workflows.definitions." .. slot, {
            enabled = false,
            name = "",
            steps = {}
        });
        self:setSelectedKey(nil);
        self:refresh();
        return;
    end

    -- Capture the keys of the affected commands BEFORE unbinding anything, so
    -- the shifted workflows keep their bindings under their new slot numbers.
    local keys = {};
    local keys2 = {};
    local ok = true;

    if (SetBinding and SaveBindings and GetCurrentBindingSet) then
        for i = slot, count do
            local key1, key2 = GetBindingKey("ACP_WORKFLOW" .. tostring(i));
            keys[i] = key1;
            keys2[i] = key2;
        end

        ok = pcall(function()
            for i = slot, count do
                if (keys[i]) then
                    SetBinding(keys[i], nil);
                end
                if (keys2[i]) then
                    SetBinding(keys2[i], nil);
                end
            end

            for i = slot, count - 1 do
                local command = "ACP_WORKFLOW" .. tostring(i);
                if (keys[i + 1]) then
                    SetBinding(keys[i + 1], command);
                end
                if (keys2[i + 1]) then
                    SetBinding(keys2[i + 1], command);
                end
            end

            local bindingSet = GetCurrentBindingSet();

            if (bindingSet == 1 or bindingSet == 2) then
                SaveBindings(bindingSet);
            else
                error("binding set not loaded");
            end
        end);
    end

    for i = slot, count - 1 do
        setSetting("workflows.definitions." .. tostring(i),
            ACP.Settings:get("workflows.definitions." .. tostring(i + 1)));
    end

    setSetting("workflows.definitions." .. tostring(count), nil);
    setSetting("workflows.slotCount", count - 1);

    if (not ok) then
        ACP:print(ACP.L.workflow.bindingUnavailable);
    end

    self.SelectedSlot = math_max(slot - 1, 1);
    self:refresh();
end

function WorkflowUI:addStep(spellKey)
    -- Equip-item entries use the "item:<id>" key convention.
    local equipItemID = tonumber(type(spellKey) == "string" and spellKey:match("^item:(%d+)$") or nil);

    if (equipItemID) then
        self:addEquipItem(equipItemID);
        return;
    end

    local entry;
    local group;

    if (type(spellKey) == "number") then
        -- A specific rank (stone rank entry) or pet ability selected from the
        -- Add Step list — the entry IS the target, no group resolution needed.
        entry = ACP.WorkflowSpellbook and ACP.WorkflowSpellbook:getEntry(spellKey) or findSpell(spellKey);
    else
        group = ACP.WorkflowSpellbook and ACP.WorkflowSpellbook:getGroup(spellKey);

        if (not group or not group.entries or #group.entries == 0) then
            return;
        end

        entry = group.entries[#group.entries];
    end

    if (not entry) then
        return;
    end

    local C = ACP.Data.Constants;
    local category = entry.category or "other";
    local stepType = (category == "summons" and C.WORKFLOW_STEP_SUMMON) or
                         (category == "createItem" and C.WORKFLOW_STEP_CREATE_ITEM) or
                         (entry.isPetSpell and C.WORKFLOW_STEP_PET) or C.WORKFLOW_STEP_CAST;
    local step = {
        type = stepType,
        spellID = entry.spellID,
        spellName = entry.name or (group and group.name)
    };

    if (stepType == C.WORKFLOW_STEP_CAST or (stepType == C.WORKFLOW_STEP_PET and entry.canTargetParty)) then
        step.target = "player";
    end

    -- New buff-cast, summon and createItem steps default their skip flag to the
    -- global "skip already-completed steps" setting. A buff step only gets the
    -- flag when its cast actually applies a tracked buff (entry.buffSpellID).
    if ((stepType == C.WORKFLOW_STEP_CAST and entry.buffSpellID)
        or stepType == C.WORKFLOW_STEP_SUMMON
        or stepType == C.WORKFLOW_STEP_CREATE_ITEM) then
        step.skipIfBuffed = ACP.Settings:get("workflows.skipIfBuffedDefault") == true;
    end

    if (entry.itemID) then
        step.itemID = entry.itemID;
    end

    local steps = selectedSteps(self.SelectedSlot);
    steps[#steps + 1] = step;
    persistSettings();
    self:refresh();
    self:scrollToBottom();
end

--- Add an equipItem step (conjured item, e.g. a spellstone) to the end of the
--- selected workflow. The engine equips it through the secure hotkey, so the
--- row shows the item name and needs no rank/target/skip options.
---@param itemID number
function WorkflowUI:addEquipItem(itemID)
    local entry = ACP.Data.Workflows and ACP.Data.Workflows:getEquipItem(itemID);
    local step = {
        type = "equipItem",
        itemID = itemID,
        itemName = (entry and entry.name) or nil
    };
    local steps = selectedSteps(self.SelectedSlot);
    steps[#steps + 1] = step;
    persistSettings();
    self:refresh();
    self:scrollToBottom();
end

function WorkflowUI:removeStep(index)
    local steps = selectedSteps(self.SelectedSlot);

    if (steps[index]) then
        tremove(steps, index);
        persistSettings();
        self:refresh();
    end
end

function WorkflowUI:moveStep(index, delta)
    local steps = selectedSteps(self.SelectedSlot);
    local target = index + delta;

    if (not steps[index] or not steps[target]) then
        return;
    end

    steps[index], steps[target] = steps[target], steps[index];
    persistSettings();
    self:refresh();
end

--- Steal `key` from whatever command currently owns it, so binding it to a
--- workflow matches the Key Bindings UI (ESC -> Key Bindings -> ArenaChillPrep):
--- a physical key drives exactly one action. `SetBinding(key, command)` alone
--- does not reliably clear the previous command's claim on 20506, so we
--- explicitly unbind it first. `keepCommand` is skipped (re-binding the same
--- key to the same slot is a no-op otherwise).
---@param key string
---@param keepCommand string
local function unbindConflictingKey(key, keepCommand)
    if (key == nil or key == "" or not GetBindingAction or not SetBinding) then
        return;
    end

    local current = GetBindingAction(key);

    if (current and current ~= "" and current ~= keepCommand) then
        SetBinding(key, nil);
    end
end

--- Replace the current binding for the selected workflow slot. The active
--- binding set is saved immediately; 0 is rejected because SaveBindings(0)
--- crashes on 20506.
function WorkflowUI:setSelectedKey(key)
    if (not SetBinding or not SaveBindings or not GetCurrentBindingSet) then
        ACP:print(ACP.L.workflow.bindingUnavailable);
        return;
    end

    if (key and key ~= "" and not isSafeBindingKey(key)) then
        ACP:print(ACP.L.workflow.bindingInvalid);
        self:refresh();
        return;
    end

    local command = "ACP_WORKFLOW" .. tostring(self.SelectedSlot);
    local old1, old2 = GetBindingKey and GetBindingKey(command);

    local ok, err = pcall(function()
        -- Steal the chosen key from whatever else it is bound to (another
        -- workflow, a Blizzard default, or another addon) — same as the
        -- in-game Key Bindings menu, so the key no longer drives the old action.
        unbindConflictingKey(key, command);

        if (old1) then
            SetBinding(old1, nil);
        end
        if (old2) then
            SetBinding(old2, nil);
        end
        if (key and key ~= "") then
            SetBinding(key, command);
        end

        local bindingSet = GetCurrentBindingSet();

        if (bindingSet == 1 or bindingSet == 2) then
            SaveBindings(bindingSet);
        else
            error("binding set not loaded");
        end
    end);

    if (not ok) then
        ACP:print(ACP.L.workflow.bindingUnavailable);
    end

    self:refresh();
end

function WorkflowUI:scrollToBottom()
    local scroll = self.Controls.stepScroll;

    if (scroll and scroll.SetVerticalScroll) then
        scroll:SetVerticalScroll(scroll:GetVerticalScrollRange());
    end
end

--- Keep the step list filling the available panel height below the steps
--- table header. Re-evaluated on every refresh so the list adapts to the
--- current content size.
function WorkflowUI:updateStepScroll()
    local scroll = self.Controls.stepScroll;
    local box = self.Controls.stepsBox;

    if (not scroll or not box) then
        return;
    end

    local listH = math_max(STEP_LIST_FLOOR, self.contentHeight + self.stepListY - self.margin);
    box:SetHeight(listH);
    scroll:SetHeight(listH - 12);
end

function WorkflowUI:buildStepRow(parent, rowW, slot, index, count, step, y)
    local L = ACP.L.workflow;
    local UI = ACP.UI;
    local C = ACP.Data.Constants;
    local entry = findSpell(step.spellID);
    local row = CreateFrame("Frame", nil, parent);
    local controls = {};

    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y);
    row:SetSize(rowW, STEP_ROW_H);

    -- Subtle alternating strip so tall two-line rows stay separable.
    if (index % 2 == 0) then
        local bg = row:CreateTexture(nil, "BACKGROUND", nil, -8);
        bg:SetAllPoints(row);
        bg:SetTexture("Interface\\Buttons\\WHITE8x8");
        bg:SetVertexColor(1, 1, 1, 0.04);
    end

    -- # column
    local number = row:CreateFontString(nil, "ARTWORK", "GameFontNormal");
    number:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -6);
    number:SetText(tostring(index));
    number:SetTextColor(0.55, 0.55, 0.55, 1);

    -- Spell cell: line 1 = name, line 2 = spellID.
    local spellX = STEP_NUM_W;
    local spellW = rowW - STEP_NUM_W - STEP_TARGET_W - STEP_SKIP_W - actionLayout().total;

    local name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal");
    name:SetPoint("TOPLEFT", row, "TOPLEFT", spellX, -4);
    name:SetWidth(spellW - TARGET_X_SHIFT);
    name:SetJustifyH("LEFT");
    name:SetText(stepSpellLabel(step, entry));
    name:SetTextColor(0.9, 0.9, 0.9, 1);
    row.name = name;

    local idText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
    idText:SetPoint("TOPLEFT", row, "TOPLEFT", spellX, -26);

    if (step.type == C.WORKFLOW_STEP_EQUIP_ITEM) then
        -- Equip-item steps: the row shows the ITEM, not a spell. Line 1 keeps
        -- the item name (GetItemInfo fallback: the stored catalog name) and
        -- line 2 shows the item ID; rank/target/skip stay "Not available".
        name:SetText(itemLabel(step));
        idText:SetText((L.itemIDLabel):format(step.itemID));
    elseif (step.type == C.WORKFLOW_STEP_PET) then
        -- Pet-ability steps: cast by the player's pet (e.g. Imp Fire Shield,
        -- Voidwalker Sacrifice). Line 2 marks it as a pet ability.
        local petName = entry and (entry.pet or "pet") or "pet";
        name:SetText((L.petStepLabel):format(spellLabel(step.spellID, entry and entry.name), petName));
        idText:SetText(L.petStepHint);
    else
        name:SetText(stepSpellLabel(step, entry));
        idText:SetText((L.spellIDLabel):format(step.spellID));
    end

    idText:SetTextColor(0.5, 0.5, 0.5, 1);
    row.spellIDText = idText;

    -- Target column (fixed width; disabled state for non-party-castable steps).
    -- The dropdown is pulled LEFT of the spell column end (TARGET_X_SHIFT) so
    -- it sits closer to the spell name; its width is unchanged.
    local targetX = spellX + spellW - TARGET_X_SHIFT;

    -- Party-castable player spells AND party-castable pet abilities (e.g. the
    -- Imp's Fire Shield) offer a target dropdown; everything else is "Not
    -- available".
    local canTarget = entry and entry.canTargetParty
        and (step.type == C.WORKFLOW_STEP_CAST or step.type == C.WORKFLOW_STEP_PET);

    if (canTarget) then
        local target = UI.Dropdown(row, ("ACPWorkflowTarget%d_%d"):format(slot, index), L.targetPlayer, targetX, 0,
            STEP_TARGET_W - 16, targetItems, function()
                return step.target;
            end, function(value)
                setSetting(stepPath(slot, index) .. ".target", value);
            end, L.targetTooltip);
        controls[#controls + 1] = target;
    else
        local targetText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
        targetText:SetPoint("TOPLEFT", row, "TOPLEFT", targetX + 2, -8);
        targetText:SetText(L.notAvailable);
        targetText:SetTextColor(0.45, 0.45, 0.45, 1);
        attachTooltip(targetText, L.targetUnavailableTooltip);
    end

    -- Skip column (fixed width; applies to buff-cast, summon and createItem
    -- steps — "skip if the step's goal is already met"). Other step types
    -- (pet abilities, equip items) render an explicit disabled state.
    local skipX = targetX + STEP_TARGET_W + TARGET_X_SHIFT;

    local isBuff = entry and entry.buffSpellID and step.type == C.WORKFLOW_STEP_CAST;
    local skippable = isBuff
        or step.type == C.WORKFLOW_STEP_SUMMON
        or step.type == C.WORKFLOW_STEP_CREATE_ITEM;

    if (skippable) then
        local skip = UI.Checkbox(row, ("ACPWorkflowSkip%d_%d"):format(slot, index), "", skipX, -12, function()
            return ACP.WorkflowEngine:effectiveSkip(step);
        end, function(value)
            setSetting(stepPath(slot, index) .. ".skipIfBuffed", value);
        end, L.skipTooltip);
        controls[#controls + 1] = skip;
    else
        local skipText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
        skipText:SetPoint("TOPLEFT", row, "TOPLEFT", skipX + 2, -8);
        skipText:SetText(L.notAvailable);
        skipText:SetTextColor(0.45, 0.45, 0.45, 1);
        attachTooltip(skipText, L.skipUnavailableTooltip);
    end

    -- Actions column (fixed width, right-aligned). Text labels instead of
    -- ↑/↓ glyphs — the client font renders those arrows as boxes.
    local btnH = 24;
    local actionX = rowW - actionLayout().total;
    local btnY = -12;
    local sizes = actionLayout();

    local up = UI.Button(row, L.moveUpLabel, actionX, btnY, sizes.upW, btnH, function()
        self:moveStep(index, -1);
    end, L.moveUpTooltip);
    local down = UI.Button(row, L.moveDownLabel, actionX + sizes.upW + ACTIONS_GAP, btnY, sizes.downW, btnH, function()
        self:moveStep(index, 1);
    end, L.moveDownTooltip);
    local remove = UI.Button(row, L.deleteStepLabel, actionX + sizes.upW + ACTIONS_GAP + sizes.downW + ACTIONS_GAP,
        btnY, sizes.delW, btnH, function()
            self:removeStep(index);
        end, L.removeStepTooltip);

    if (index == 1) then
        up:Disable();
    end
    if (index == count) then
        down:Disable();
    end

    remove:SetScript("OnEnter", function(self)
        local fs = self:GetFontString();
        if (fs) then
            fs:SetTextColor(1, 0.35, 0.35, 1);
        end
    end);
    remove:SetScript("OnLeave", function(self)
        local fs = self:GetFontString();
        if (fs) then
            fs:SetTextColor(1, 1, 1, 1);
        end
    end);

    controls[#controls + 1] = up;
    controls[#controls + 1] = down;
    controls[#controls + 1] = remove;
    row.controls = controls;
    return row;
end

function WorkflowUI:renderSteps()
    local scroll = self.Controls.stepScroll;

    if (not scroll) then
        return;
    end

    local child = scroll.ScrollChild;

    if (not self.RecycleFrame) then
        self.RecycleFrame = CreateFrame("Frame", nil, self.content or child);
        self.RecycleFrame:Hide();
    end

    for _, old in ipairs({child:GetChildren()}) do
        old:Hide();
        old:ClearAllPoints();
        old:SetParent(self.RecycleFrame);
    end

    if (self.EmptyLabel) then
        self.EmptyLabel:Hide();
        self.EmptyLabel = nil;
    end

    self.StepRows = {};
    local steps = selectedSteps(self.SelectedSlot);
    local count = #steps;
    local rowW = scroll:GetWidth() - 8;

    if (count == 0) then
        local empty = child:CreateFontString(nil, "ARTWORK", "GameFontNormal");
        empty:SetPoint("TOPLEFT", child, "TOPLEFT", 6, -10);
        empty:SetText(ACP.L.workflow.emptyWorkflowEditor);
        empty:SetTextColor(0.65, 0.65, 0.65, 1);
        self.EmptyLabel = empty;
        child:SetHeight(40);
        scroll.Refresh();
        return;
    end

    child:SetHeight(math_max(count * STEP_ROW_H + 8, scroll:GetHeight() - 4));

    for i = 1, count do
        local row = self:buildStepRow(child, rowW, self.SelectedSlot, i, count, steps[i], -4 - (i - 1) * STEP_ROW_H);
        self.StepRows[#self.StepRows + 1] = row;
    end

    scroll.Refresh();
end

function WorkflowUI:buildStatusBar(content, x, y, width)
    local UI = ACP.UI;
    local line = content:CreateFontString(nil, "ARTWORK", "GameFontNormal");
    line:SetPoint("TOPLEFT", content, "TOPLEFT", x, y);
    line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -x, y);
    line:SetJustifyH("LEFT");

    local button = UI.Button(content, ACP.L.workflow.engineEnabledLabel, x, y, 180, 20, function()
        setSetting("workflows.enabled", true);
        self:refresh();
    end, ACP.L.workflow.engineEnabledTooltip);
    button:SetPoint("TOPRIGHT", content, "TOPRIGHT", -x, y);

    self.Controls.statusLine = line;
    self.Controls.enableButton = button;
    self.content = content;
    self.marginX = x;
    self.statusY = y;
    return STATUS_H;
end

--- Workflow defaults block: the skip-if-buffed default + its description,
--- kept separate from the per-workflow identity/binding form.
function WorkflowUI:buildDefaults(content, x, y, width)
    local L = ACP.L.workflow;
    local UI = ACP.UI;

    UI.Header(content, L.workflowDefaultsHeader, x, y);

    self.Controls.skipIfBuffedDefault = UI.Checkbox(content, "ACPWorkflowSkipDefaultCheck", L.skipIfBuffedDefaultLabel,
        x, y - 24, function()
            return ACP.Settings:get("workflows.skipIfBuffedDefault");
        end, function(value)
            setSetting("workflows.skipIfBuffedDefault", value);
        end, L.skipIfBuffedDefaultTooltip);

    local desc = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
    desc:SetPoint("TOPLEFT", content, "TOPLEFT", x + 2, y - 48);
    desc:SetText(L.workflowDefaultsDescription);
    desc:SetTextColor(0.55, 0.55, 0.55, 1);

    return DEFAULTS_H;
end

--- Workflow identity + activation block: selector + add workflow, name +
--- enabled, key bind + clear. The key is presented in this one editable place.
function WorkflowUI:buildEditor(content, x, y, width)
    local L = ACP.L.workflow;
    local UI = ACP.UI;
    local Controls = self.Controls;

    UI.Header(content, L.workflowEditorHeader, x, y);

    -- Row 1: workflow selector + add workflow.
    local row1 = y - 22;
    local selectorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal");
    selectorLabel:SetPoint("TOPLEFT", content, "TOPLEFT", x, row1 - 6);
    selectorLabel:SetText(L.workflowDropdownLabel);
    selectorLabel:SetTextColor(0.7, 0.7, 0.7, 1);

    Controls.workflowSelector = UI.Dropdown(content, "ACPWorkflowSelector", L.workflowDropdownLabel, x + FIELD_X,
        row1 - 2, 170, workflowItems, function()
            return self.SelectedSlot;
        end, function(value)
            if (Controls.keybind) then
                Controls.keybind.StopCapture();
            end
            self.SelectedSlot = value;
            self:refresh();
        end, L.workflowSelectorTooltip);

    Controls.addWorkflow = UI.Button(content, L.addWorkflowLabel, x + FIELD_X + 240, row1 - 4, 145, 24, function()
        self:addWorkflow();
    end, L.workflowAddTooltip);

    Controls.deleteWorkflow = UI.Button(content, L.deleteWorkflowLabel, x + FIELD_X + 240 + 145 + ACTIONS_GAP, row1 - 4,
        145, 24, function()
            self:deleteWorkflow();
        end, L.deleteWorkflowTooltip);

    -- Row 2: name + enabled.
    local row2 = row1 - 36;
    local nameLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal");
    nameLabel:SetPoint("TOPLEFT", content, "TOPLEFT", x, row2 - 6);
    nameLabel:SetText(L.nameLabel .. ":");
    nameLabel:SetTextColor(0.7, 0.7, 0.7, 1);

    Controls.workflowName = UI.TextInput(content, "ACPWorkflowNameInput", x + FIELD_X, row2 - 2, 240, 20, function()
        return ACP.Settings:get("workflows.definitions." .. self.SelectedSlot .. ".name");
    end, function(value)
        setSetting("workflows.definitions." .. self.SelectedSlot .. ".name", value);
    end, L.nameTooltip);

    Controls.workflowEnabled = UI.Checkbox(content, "ACPWorkflowSlotEnabledCheck", L.enabledLabel, x + FIELD_X + 254,
        row2, function()
            return ACP.Settings:get("workflows.definitions." .. self.SelectedSlot .. ".enabled");
        end, function(value)
            setSetting("workflows.definitions." .. self.SelectedSlot .. ".enabled", value);
        end, L.workflowEnabledTooltip);

    -- Row 3: key bind + clear.
    local row3 = row2 - 28;
    local keyLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal");
    keyLabel:SetPoint("TOPLEFT", content, "TOPLEFT", x, row3 - 9);
    keyLabel:SetText(L.keybindLabel);
    keyLabel:SetTextColor(0.7, 0.7, 0.7, 1);

    Controls.keybind = UI.Keybind(content, "ACPWorkflowKeybind", L.keybindEmptyLabel, x + FIELD_X, row3 - 4, 160, 24,
        function()
            return selectedKey(self.SelectedSlot);
        end, function(value)
            self:setSelectedKey(value);
        end, L.keybindTooltip, L.keybindCapturingLabel);

    Controls.keybindClear = UI.Button(content, L.clearKeybindLabel, x + FIELD_X + 170, row3 - 4, 70, 24, function()
        self:setSelectedKey(nil);
    end, L.clearKeybindTooltip);

    return EDITOR_H;
end

--- Header row above the step list with stable, subdued column labels.
--- `x`/`width` must be the STEP-ROW geometry (scroll frame space), not the
--- content geometry, so the labels line up with the row controls below.
function WorkflowUI:buildStepsHeader(content, x, y, width)
    local L = ACP.L.workflow;
    local spellX = x + STEP_NUM_W;
    local total = actionLayout().total;
    local spellW = width - STEP_NUM_W - STEP_TARGET_W - STEP_SKIP_W - total;

    local function col(text, colX, colW, align)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", colX, y);
        fs:SetWidth(colW);
        fs:SetJustifyH(align or "LEFT");
        fs:SetText(text);
        fs:SetTextColor(0.6, 0.6, 0.6, 1);
    end

    col("#", x, STEP_NUM_W, "LEFT");
    col(L.stepSpellColumn, spellX, spellW, "LEFT");
    col(L.targetColumn, spellX + spellW - TARGET_X_SHIFT, STEP_TARGET_W, "LEFT");
    col(L.skipColumn, spellX + spellW + STEP_TARGET_W, STEP_SKIP_W, "LEFT");
    col(L.actionsColumn, x + width - total, total, "RIGHT");
end

function WorkflowUI:buildStepsSection(content, x, y, width)
    local L = ACP.L.workflow;
    local UI = ACP.UI;

    UI.Header(content, L.stepsHeader, x, y);

    local addW = 160;
    self.Controls.addStep = UI.Dropdown(content, "ACPWorkflowAddStep", "+ " .. L.addStepLabel, x, y, addW, spellItems,
        function()
            return nil;
        end, function(value)
            self:addStep(value);
        end, L.addStepTooltip);
    self.Controls.addStep:ClearAllPoints();
    self.Controls.addStep:SetPoint("TOPRIGHT", content, "TOPRIGHT", -x, y);

    local headerY = y - 34;

    -- The list box fills everything left below the table header.
    local listY = headerY - STEP_HEADER_H - 2;
    local listH = math_max(STEP_LIST_FLOOR, self.contentHeight + listY - self.margin);

    local box = UI.Box(content, x, listY, width, listH);
    box:SetBackdropBorderColor(0.65, 0.65, 0.58, 0.35);
    self.Controls.stepsBox = box;

    self.Controls.stepScroll = UI.ScrollFrame(box, 6, -6, width - 32, listH - 12);
    self.stepListY = listY;

    -- Column labels are drawn over the SAME geometry as the step rows (which
    -- live inside the scroll frame: +6 box inset, scrollbar reduces the row
    -- width), so every label sits exactly above its row controls.
    self:buildStepsHeader(content, x + 6, headerY, self.Controls.stepScroll:GetWidth() - 8);
end

function WorkflowUI:build(content, w, h)
    local UI = ACP.UI;
    local margin = UI.PADDING;
    local width = w - margin * 2;
    local y = -margin;

    self.content = content;
    self.contentWidth = w;
    self.contentHeight = h;
    self.margin = margin;

    y = y - self:buildStatusBar(content, margin, y, width) - SECTION_GAP;
    y = y - self:buildDefaults(content, margin, y, width) - SECTION_GAP;
    y = y - self:buildEditor(content, margin, y, width) - SECTION_GAP;

    UI.Divider(content, margin, y, width);
    y = y - 8;

    self:buildStepsSection(content, margin, y, width);
    self.isBuilt = true;
    self:refresh();
end

function WorkflowUI:refresh()
    local Controls = self.Controls;
    local slot = self.SelectedSlot;
    local definition = ACP.Settings:get("workflows.definitions." .. slot);

    if (Controls.skipIfBuffedDefault) then
        Controls.skipIfBuffedDefault:SetChecked(ACP.Settings:get("workflows.skipIfBuffedDefault") == true);
    end
    if (Controls.workflowSelector) then
        Controls.workflowSelector.Refresh();
    end
    if (Controls.workflowEnabled) then
        Controls.workflowEnabled:SetChecked(type(definition) == "table" and definition.enabled == true or false);
    end
    if (Controls.workflowName) then
        Controls.workflowName.Refresh();
    end
    if (Controls.keybind) then
        Controls.keybind.Refresh();
    end
    if (Controls.keybindClear) then
        if (selectedKey(slot)) then
            Controls.keybindClear:Enable();
        else
            Controls.keybindClear:Disable();
        end
    end
    if (Controls.addStep) then
        Controls.addStep.Refresh();
    end

    self:updateStepScroll();
    self:renderSteps();
    self:refreshStatus();
end

function WorkflowUI:refreshStatus()
    local line = self.Controls.statusLine;
    local button = self.Controls.enableButton;
    local content = self.content;

    if (not line or not content) then
        return;
    end

    local L = ACP.L.workflow;
    local engineOn = ACP.Settings:get("workflows.enabled") == true;
    local slot = self.SelectedSlot;
    local definition = ACP.Settings:get("workflows.definitions." .. slot);
    local slotOn = type(definition) == "table" and definition.enabled == true or false;

    if (engineOn) then
        local parts = {L.engineStatusOn, (L.slotStatusLabel):format(slot, slotOn and L.enabledWord or L.disabledWord),
                       (L.stepsStatusLabel):format(#selectedSteps(slot))};
        line:ClearAllPoints();
        line:SetPoint("TOPLEFT", content, "TOPLEFT", self.marginX, self.statusY);
        line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -self.marginX, self.statusY);
        line:SetText(table_concat(parts, "   •   "));
        line:SetTextColor(0.82, 0.82, 0.82, 1);
        button:Hide();
    else
        line:ClearAllPoints();
        line:SetPoint("TOPLEFT", content, "TOPLEFT", self.marginX, self.statusY);
        line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(button:GetWidth() + self.marginX + 8), self.statusY);
        line:SetText(L.engineDisabledMessage);
        line:SetTextColor(1, 0.65, 0.35, 1);
        button:Show();
    end
end

function WorkflowUI:setEnabled(flag)
    if (self.Controls.statusLine) then
        self:refreshStatus();
    end
end

return ACP;
