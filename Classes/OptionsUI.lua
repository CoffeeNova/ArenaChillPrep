-- ArenaChillPrep — Classes/OptionsUI
-- Interface Options panel + slash commands.
-- Panel fields: master switch, bracket checkboxes, partner mode
-- (auto / manual slot), healthstone rank checkboxes + count per rank,
-- tradeDelay, gateSafetySeconds.

---@type ACP
local _, ACP = ...;

local strlower = _G.strlower;
local tinsert = _G.tinsert;
local pairs = _G.pairs;

---@class OptionsUI
local OptionsUI = {
    _initialized = false,

    ---@type Frame
    Panel = nil,

    ---@type table<string, CheckButton>
    Controls = {},

    ---@type table<string, table<number, table<number, number>>>
    rankToIDs = {},

    ---@type table<string, table<number, string>>
    rankToName = {},

    ---@type table<{settingsKey: string, rank: number}>
    rankEntries = {},

    ---@type number|nil
    categoryID = nil,
};

---@type OptionsUI
ACP.OptionsUI = OptionsUI;

--- Enabled if ANY itemID of this rank is checked (in Settings).
---@param settingsKey string  singular category key ("healthstone")
---@param rank number
---@return boolean
function OptionsUI:rankIsEnabled(settingsKey, rank)
    local ids = (self.rankToIDs[settingsKey] or {})[rank] or {};

    for _, id in ipairs(ids) do
        if (ACP.Settings:get("items." .. settingsKey .. ".ranks." .. id)) then
            return true;
        end
    end

    return false;
end

--- Write a boolean setting and update the persisted SavedVariables.
---@param path string
---@param value any
local function setSetting(path, value)
    ACP.Settings:set(path, value);
    ArenaChillPrepDB = ACP.Settings.Data;
end

--- Handler for the /acp slash command.
---@param input string
local function handleCommand(input)
    local L = ACP.L;
    local command = strlower((input or ""):match("^%s*(%S*)") or "");

    if (command == "status") then
        -- Initialized + state.
        ACP:print(L.status, tostring(ACP._initialized), tostring(ACP.DeliveryController.state));

        -- Buff / instance / bracket / remaining (gate countdown).
        local ArenaPrep = ACP.ArenaPrep;
        local remaining = ArenaPrep:getRemainingTime();

        ACP:print("buff active: %s | instance: %s | bracket: %s | remaining: %s",
            tostring(ArenaPrep:isActive()),
            ArenaPrep:getInstanceType(),
            ArenaPrep:getBracket() or "nil",
            remaining and ("%.1f s"):format(remaining) or "n/a");

        -- Controller detail (partner, brackets, gate safety).
        local DC = ACP.DeliveryController;
        local bracket = ArenaPrep:getBracket();
        local bracketInfo = {
            ["2v2"] = ACP.Settings:get("brackets.2v2"),
            ["3v3"] = ACP.Settings:get("brackets.3v3"),
            ["5v5"] = ACP.Settings:get("brackets.5v5"),
        };
        local partyCount = ACP.ArenaPrep:getPartySize();

        ACP:print("controller: state=%s | partner=%s | party=%d | brackets: 2v2=%s 3v3=%s 5v5=%s%s",
            DC.state,
            DC.currentPartner or "nil",
            partyCount,
            tostring(bracketInfo["2v2"]),
            tostring(bracketInfo["3v3"]),
            tostring(bracketInfo["5v5"]),
            bracket and (not bracketInfo[bracket]) and " | CURRENT BRACKET DISABLED" or "");

        -- Healthstone counts in bags (stack-aware).
        local Inventory = ACP.Inventory;
        local healthstones = ACP.Data.Items.healthstones;
        local names = {};

        for itemID, item in pairs(healthstones) do
            tinsert(names, ("%s=%d"):format(item.name, Inventory:getCount(itemID)));
        end

        table.sort(names);
        ACP:print("healthstones: %s", table.concat(names, ", "));
    elseif (command == "enable") then
        setSetting("enabled", true);
        ACP:print(L.enabled);
    elseif (command == "disable") then
        setSetting("enabled", false);
        ACP:print(L.disabled);
    elseif (command == "debug") then
        ACP.debug = not ACP.debug;
        ACP:print(L.debugToggled, ACP.debug and "on" or "off");
    elseif (command == "help" or command == "") then
        ACP:print(L.help);
    else
        ACP:print(L.unknownCommand, command);
    end
end

--- Options panel geometry (compact single-form layout, two columns).
local PANEL_WIDTH = 660;
local PANEL_HEIGHT = 400;
local CONTENT_PADDING = 14;
local ROW_HEIGHT = 24;
local COLUMN_GAP = 16;

--- Create a boxed container (thin border + dark bg).
---@param parent Frame
---@param x number
---@param y number
---@param w number
---@param h number
---@return Frame
local function createBox(parent, x, y, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate");
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    box:SetSize(w, h);
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    });
    box:SetBackdropColor(0, 0, 0, 0.4);
    box:SetBackdropBorderColor(1, 1, 1, 0.35);
    return box;
end

--- Create a section header (yellow title) inside a parent at (x, y).
---@return FontString
local function createHeader(parent, text, x, y)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
    header:SetText(text);
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    header:SetTextColor(1, 0.82, 0, 1);
    return header;
end

--- Create a checkbox row at (x, y) inside parent; clicking the label toggles.
--- Returns the checkbox.
---@return CheckButton
local function createCheckbox(parent, name, text, x, y, getter, setter)
    local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate");
    local label = _G[name .. "Text"];
    label:SetText(text);
    label:SetPoint("LEFT", check, "RIGHT", 4, 0);
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    check:SetChecked(getter() == true);

    label:EnableMouse(true);
    label:SetScript("OnMouseDown", function()
        check:Click();
    end);

    check:SetScript("OnClick", function()
        setter(check:GetChecked());
    end);

    return check;
end

--- Create a slider with its text label ABOVE it (so long labels never clip).
--- OptionsSliderTemplate does NOT create a global "...Text" — the label is
--- built manually. The label wraps so long texts never clip.
---@return Slider
local function createSlider(parent, name, text, x, y, min, max, step, getter, setter)
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

    return slider;
end

--- Build the rank checkbox rows for the given category inside `box`.
---@param box Frame
---@param settingsKey string  singular ("healthstone")
---@param category string     plural catalog key ("healthstones")
function OptionsUI:buildRankRows(box, settingsKey, category)
    local L = ACP.L;
    local catalog = ACP.Data.Items[category] or {};
    self.rankToIDs[settingsKey] = self.rankToIDs[settingsKey] or {};
    self.rankToName[settingsKey] = self.rankToName[settingsKey] or {};

    -- Group itemIDs by catalog rank.
    local rankGroups = {};

    for itemID, record in pairs(catalog) do
        rankGroups[record.rank] = rankGroups[record.rank] or {};
        tinsert(rankGroups[record.rank], itemID);
        self.rankToIDs[settingsKey][record.rank] = rankGroups[record.rank];
        self.rankToName[settingsKey][record.rank] = L.ranks[record.rank] or record.name;
    end

    local sorted = {};

    for rank in pairs(rankGroups) do
        tinsert(sorted, rank);
    end

    table.sort(sorted);

    for i, rank in ipairs(sorted) do
        local ids = rankGroups[rank];
        local name = "ACPRankCheck" .. settingsKey .. rank;
        local check = CreateFrame("CheckButton", name, box, "UICheckButtonTemplate");
        check:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8 - (i - 1) * ROW_HEIGHT);
        check:SetChecked(self:rankIsEnabled(settingsKey, rank));

        local function applyRank()
            local checked = check:GetChecked();

            for _, id in ipairs(ids) do
                setSetting("items." .. settingsKey .. ".ranks." .. id, checked);
            end
        end

        check:SetScript("OnClick", applyRank);

        local label = _G[name .. "Text"];
        label:SetText(self.rankToName[settingsKey][rank]);
        label:SetPoint("LEFT", check, "RIGHT", 4, 0);
        label:EnableMouse(true);
        label:SetScript("OnMouseDown", function()
            check:SetChecked(not check:GetChecked());
            applyRank();
        end);

        local entry = { check = check, settingsKey = settingsKey, rank = rank };
        self.rankEntries[#self.rankEntries + 1] = entry;
    end
end

--- Build the "Autotrade" section content (two columns so the right side is used).
---@param content Frame
---@param w number
---@param h number
function OptionsUI:buildAutotrade(content, w, h)
    local L = ACP.L;
    local Controls = self.Controls;
    local colW = math.floor((w - CONTENT_PADDING * 2 - COLUMN_GAP) / 2);

    -- ---- LEFT COLUMN ----
    local leftX = CONTENT_PADDING;
    local leftY = -4;

    -- General box
    createHeader(content, L.generalHeader, leftX, leftY);
    leftY = leftY - 28;

    local generalBox = createBox(content, leftX, leftY, colW, 72);
    Controls.enabled = createCheckbox(generalBox, "ACPEnabledCheck",
        L.enabledLabel, 10, -8,
        function() return ACP.Settings:get("enabled"); end,
        function(value) setSetting("enabled", value); end);
    leftY = leftY - 62 - 18;

    -- Brackets box (3v3/5v5 disabled for now — code kept for the future).
    createHeader(content, L.bracketsHeader, leftX, leftY);
    leftY = leftY - 28;

    local bracketBox = createBox(content, leftX, leftY, colW, 3 * ROW_HEIGHT + 22);
    Controls.brackets = {};
    local bracketY = -8;

    for _, bracket in ipairs({ "2v2", "3v3", "5v5" }) do
        Controls.brackets[bracket] = createCheckbox(bracketBox, "ACPBracketCheck" .. bracket,
            bracket, 10, bracketY,
            function() return ACP.Settings:get("brackets." .. bracket); end,
            function(value) setSetting("brackets." .. bracket, value); end);

        -- Only 2v2 is enabled. The checkboxes stay visible but disabled.
        if (bracket ~= "2v2") then
            Controls.brackets[bracket]:Disable();
            Controls.brackets[bracket]:SetAlpha(0.4);
        end

        bracketY = bracketY - ROW_HEIGHT;
    end

    -- ---- RIGHT COLUMN ----
    local rightX = leftX + colW + COLUMN_GAP;
    local rightY = -4;

    -- Ranks box: built from the class's categories.
    createHeader(content, L.ranksLabel, rightX, rightY);
    rightY = rightY - 28;

    local classItems = ACP.Data.Items.classItems;
    local englishClass = select(2, UnitClass("player"));
    local categories = classItems[englishClass] or {};
    self.rankEntries = {};

    -- 6 rank rows + comfortable top/bottom padding (no inner category label
    -- for a single category — it collided with the first row).
    local ranksBox = createBox(content, rightX, rightY, colW, 6 * ROW_HEIGHT + 24);
    local ranksInnerY = -12;

    for _, category in ipairs(categories) do
        local settingsKey = category:sub(1, -2);
        self:buildRankRows(ranksBox, settingsKey, category);
    end

    rightY = rightY - (6 * ROW_HEIGHT + 24) - 20;

    -- Timing box (sliders draw their own labels above them).
    createHeader(content, L.timingHeader, rightX, rightY);
    rightY = rightY - 28;

    -- Two rows of label+slider; generous padding so nothing hugs the border.
    local timingBox = createBox(content, rightX, rightY, colW, 128);

    Controls.tradeDelay = createSlider(timingBox, "ACPTradeDelaySlider",
        L.tradeDelayLabel, 16, -8, 0, 5, 0.5,
        function() return ACP.Settings:get("tradeDelay"); end,
        function(value) setSetting("tradeDelay", value); end);

    Controls.gateSafety = createSlider(timingBox, "ACPGateSafetySlider",
        L.gateSafetyLabel, 16, -64, 0, 60, 1,
        function() return ACP.Settings:get("gateSafetySeconds"); end,
        function(value) setSetting("gateSafetySeconds", value); end);
end

--- Build the settings: a top-level category "ArenaChillPrep" with subcategories
--- (Autotrade for now). Subcategories render in the Settings list
--- (Settings.RegisterCanvasLayoutSubcategory).
function OptionsUI:buildPanel()
    local L = ACP.L;
    local panel = CreateFrame("Frame", "ArenaChillPrepOptionsPanel", UIParent);
    panel.name = L.panelTitle;
    self.Panel = panel;
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT);

    -- Subcategories (extensible: General/Abilities/Custom/Profiles later).
    self.Subcategories = {
        {
            key = "Autotrade",
            title = L.autotradeSection,
            build = function(_, content, w, h)
                self:buildAutotrade(content, w, h);
            end,
        },
    };

    if (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory
        and Settings.RegisterCanvasLayoutSubcategory) then
        -- Modern API: parent category + subcategory.
        local parentCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name);
        Settings.RegisterAddOnCategory(parentCategory);
        self.categoryID = parentCategory and parentCategory.ID;

        for _, sub in ipairs(self.Subcategories) do
            local frame = CreateFrame("Frame", nil, UIParent);
            frame.name = sub.title;
            frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT);

            sub.frame = frame;
            sub.build(self, frame, frame:GetWidth(), frame:GetHeight());

            local subCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, sub.title);
            Settings.RegisterAddOnCategory(subCategory);
            sub.subCategoryID = subCategory and subCategory.ID;
        end
    elseif (InterfaceOptions_AddCategory) then
        -- Legacy fallback: a single panel (no subcategories).
        local content = CreateFrame("Frame", nil, panel);
        content:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -18);
        content:SetSize(PANEL_WIDTH - 28, PANEL_HEIGHT - 30);
        self.Content = content;
        self:buildAutotrade(content, content:GetWidth(), content:GetHeight());

        InterfaceOptions_AddCategory(panel);
        self.categoryID = nil;
    end
end

--- Re-sync all controls from Settings.
function OptionsUI:refresh()
    local Controls = self.Controls;

    if (Controls.enabled) then
        Controls.enabled:SetChecked(ACP.Settings:get("enabled") == true);
    end

    if (Controls.brackets) then
        for _, bracket in ipairs({ "2v2", "3v3", "5v5" }) do
            if (Controls.brackets[bracket]) then
                Controls.brackets[bracket]:SetChecked(ACP.Settings:get("brackets." .. bracket) == true);
            end
        end
    end

    for _, entry in ipairs(self.rankEntries) do
        entry.check:SetChecked(self:rankIsEnabled(entry.settingsKey, entry.rank));
    end

    if (Controls.tradeDelay) then
        Controls.tradeDelay.Refresh();
    end

    if (Controls.gateSafety) then
        Controls.gateSafety.Refresh();
    end
end

--- Open the options panel (works with both the modern and legacy Settings API).
--- Prefers the Autotrade subcategory if registered.
function OptionsUI:openPanel()
    local targetID = self.categoryID;

    if (self.Subcategories and self.Subcategories[1] and self.Subcategories[1].subCategoryID) then
        targetID = self.Subcategories[1].subCategoryID;
    end

    if (targetID and Settings and Settings.OpenToCategory) then
        Settings.OpenToCategory(targetID);
    elseif (self.Panel and InterfaceOptionsFrame_OpenToCategory) then
        InterfaceOptionsFrame_OpenToCategory(self.Panel);
    end

    self:refresh();
end

function OptionsUI:_init()
    if (self._initialized) then
        return;
    end
    self._initialized = true;

    self:buildPanel();

    SLASH_ACP1 = "/acp";
    SLASH_ACP2 = "/arenachillprep";
    SlashCmdList["ACP"] = function(input)
        local command = strlower((input or ""):match("^%s*(%S*)") or "");

        if (command == "") then
            -- /acp with no args opens the settings panel.
            self:openPanel();
            return;
        end

        handleCommand(input);
    end;
end

return ACP;
