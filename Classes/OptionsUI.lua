-- ArenaChillPrep — Classes/OptionsUI
-- Interface Options panel + slash commands.
-- Panel structure (see .ai/docs/ui-redesign-plan.md):
--   General   — master switch, "Reset to defaults" button, status line
--   Autotrade — bracket checkboxes, rank checkboxes, timing sliders
--               (header divider between Ranks and Timing)
-- All control creation lives in Classes/UI/Widgets.lua (ACP.UI.*); this
-- module only registers subcategories, assembles the layouts and syncs
-- controls from Settings.

---@type ACP
local _, ACP = ...;

local strlower = _G.strlower;
local tinsert = _G.tinsert;
local pairs = _G.pairs;
local ipairs = _G.ipairs;

---@class OptionsUI
local OptionsUI = {
    _initialized = false,

    ---@type Frame
    Panel = nil,

    ---@type table<string, any>
    Controls = {},

    ---@type table<string, table<number, table<number, number>>>
    rankToIDs = {},

    ---@type table<string, table<number, string>>
    rankToName = {},

    ---@type table<{settingsKey: string, rank: number, check: CheckButton, label: FontString}>
    rankEntries = {},

    ---@type number|nil
    categoryID = nil,
};

---@type OptionsUI
ACP.OptionsUI = OptionsUI;

--- True when the addon fully supports the player's class (Warlock only).
---@return boolean
function OptionsUI:isSupportedClass()
    local _, englishClass = UnitClass("player");
    return englishClass == "WARLOCK";
end

--- The incompatibility message shown in the panel and printed to chat for
--- non-Warlock players (with a friendly "reroll to Warlock" joke). Rogues get
--- a special demon-flavored dismissal (pure Warcraft lore, not personal).
---@return string
function OptionsUI:getCompatibilityMessage()
    local L = ACP.L;
    local className, englishClass = UnitClass("player");

    if (englishClass == "ROGUE") then
        return L.compatMessageRogue;
    end

    return (L.compatMessage):format(className or "Adventurer");
end

--- Build the single "Compatibility" page shown to unsupported classes: a
--- centered message explaining the addon is Warlock-only and inviting a reroll.
---@param content Frame
---@param w number
---@param h number
function OptionsUI:buildCompatibility(content, w, h)
    local L = ACP.L;
    local UI = ACP.UI;
    local PADDING = UI.PADDING;

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
    title:SetPoint("TOP", content, "TOP", 0, -40);
    title:SetText(L.compatSection);

    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge");
    fs:SetPoint("TOP", title, "BOTTOM", 0, -24);
    fs:SetPoint("LEFT", content, "LEFT", PADDING, 0);
    fs:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0);
    fs:SetJustifyH("CENTER");
    fs:SetJustifyV("TOP");
    fs:SetNonSpaceWrap(true);
    fs:SetText(self:getCompatibilityMessage());
end

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

--- Write a boolean setting (Settings:set persists the SavedVariables itself).
---@param path string
---@param value any
local function setSetting(path, value)
    ACP.Settings:set(path, value);
end

--- Handler for the /acp slash command.
---@param input string
local function handleCommand(input)
    local L = ACP.L;
    local command = strlower((input or ""):match("^%s*(%S*)") or "");

    if (command == "status") then
        -- Initialized + state.
        ACP:print(L.status, tostring(ACP._initialized), tostring(ACP.DeliveryController.state));

        -- Workflow engine state (Phase 8).
        if (ACP.WorkflowEngine) then
            ACP:print("workflow: %s", ACP.WorkflowEngine:getStatus());
        end

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
    elseif (command == "dumplog") then
        -- Reprint the in-memory chat log (handy when the "blocked addon"
        -- popup makes the chat un-copyable). Snapshot so re-printed lines
        -- do not re-append and grow the buffer.
        local snapshot = {};
        for i = 1, #ACP.DebugLog do
            snapshot[i] = ACP.DebugLog[i];
        end

        if (#snapshot == 0) then
            ACP:print("debug log empty");
        else
            ACP:print("debug log (%d entries):", #snapshot);

            for i = 1, #snapshot do
                ACP:print("[%d] %s", i, snapshot[i]);
            end
        end
    elseif (command == "workflow") then
        -- /acp workflow <N> — start/resume workflow slot N (test driver; the
        -- real trigger is the key binding added in Phase 9).
        local slot = tonumber((input or ""):match("^%s*%S+%s+(%S+)") or "1") or 1;

        if (ACP.WorkflowEngine) then
            ACP.WorkflowEngine:start(slot);
        end
    elseif (command == "workflowtest") then
        -- DEBUG: run a workflow slot OUTSIDE an arena (bypasses the prep
        -- requirement in start() and the notArena gate). Diagnostic only.
        -- Each command starts ONE fresh run: the engine is reset first, so
        -- re-issuing the command re-runs the workflow from step 1 (a plain
        -- key press after DONE does NOT restart — 2026-08-22). Prints a
        -- visible chat message so the player knows the test started.
        local slot = tonumber((input or ""):match("^%s*%S+%s+(%S+)") or "1") or 1;

        if (ACP.WorkflowEngine) then
            ACP.WorkflowEngine:startTest(slot);
        end
    elseif (command == "bind") then
        -- /acp bind <key> — set/change the workflow hotkey (SetBindingClick
        -- to the engine's secure cast button). /acp bind off clears it.
        local key = (input or ""):match("^%s*%S+%s+(%S+)");

        if (ACP.WorkflowEngine and key and key ~= "off" and key ~= "none") then
            ACP.Settings:set("workflows.hotkey", key);
            ACP.WorkflowEngine:applyBinding();
            ACP:print(L.workflow.keyBound, key);
        elseif (ACP.WorkflowEngine) then
            ACP.Settings:set("workflows.hotkey", nil);
            ACP.WorkflowEngine:clearBinding();
            ACP:print(L.workflow.keyCleared);
        else
            ACP:print(L.unknownCommand, command);
        end
    elseif (command == "help" or command == "") then
        ACP:print(L.help);
    else
        ACP:print(L.unknownCommand, command);
    end
end

--- Build the rank checkbox rows for the given category inside `box`.
---@param box Frame
---@param settingsKey string  singular ("healthstone")
---@param category string     plural catalog key ("healthstones")
function OptionsUI:buildRankRows(box, settingsKey, category)
    local L = ACP.L;
    local UI = ACP.UI;
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
        local rankName = self.rankToName[settingsKey][rank];

        local check = UI.Checkbox(box, name, rankName,
            UI.BOX_INSET, -8 - (i - 1) * UI.ROW_HEIGHT,
            function() return self:rankIsEnabled(settingsKey, rank); end,
            function(checked)
                for _, id in ipairs(ids) do
                    setSetting("items." .. settingsKey .. ".ranks." .. id, checked);
                end
            end,
            (L.rankTooltip):format(rankName));

        local entry = { check = check, label = check.label, settingsKey = settingsKey, rank = rank };
        self.rankEntries[#self.rankEntries + 1] = entry;
    end
end

--- Build the "General" subcategory: master switch, workflow engine switch,
--- reset button, status line.
---@param content Frame
---@param w number
---@param h number
function OptionsUI:buildGeneral(content, w, h)
    local L = ACP.L;
    local UI = ACP.UI;
    local Controls = self.Controls;
    local PADDING = UI.PADDING;

    -- Master switch. Toggling it re-syncs the panel so the Autotrade
    -- controls gray out immediately.
    Controls.enabled = UI.Checkbox(content, "ACPEnabledCheck",
        L.enabledLabel, PADDING, -8,
        function() return ACP.Settings:get("enabled"); end,
        function(value)
            setSetting("enabled", value);
            self:refresh();
        end,
        L.enabledTooltip);

    -- Workflow engine master switch; toggling it grays out the Workflows tab
    -- via setWorkflowsEnabled (in refresh()).
    Controls.workflowsEnabled = UI.Checkbox(content, "ACPWorkflowsEnabledCheck",
        L.workflow.engineEnabledLabel, PADDING, -38,
        function() return ACP.Settings:get("workflows.enabled"); end,
        function(value)
            setSetting("workflows.enabled", value);
            self:refresh();
        end,
        L.workflow.engineEnabledTooltip);

    Controls.resetButton = UI.Button(content, L.resetButton,
        PADDING, -70, 160, 24,
        function()
            ACP.Settings:reset();
        end,
        L.resetTooltip);
end

--- Build the "Autotrade" subcategory content (two columns so the right side
--- is used): brackets + timing on the left, ranks on the right.
---@param content Frame
---@param w number
---@param h number
function OptionsUI:buildAutotrade(content, w, h)
    local L = ACP.L;
    local UI = ACP.UI;
    local Controls = self.Controls;
    local colW = math.floor((w - UI.PADDING * 2 - UI.GAP) / 2);

    -- ---- LEFT COLUMN: brackets + timing ----
    local leftX = UI.PADDING;
    local leftY = -4;

    -- Brackets box (3v3/5v5 stay permanently disabled — code kept for the future).
    UI.Header(content, L.bracketsHeader, leftX, leftY);
    leftY = leftY - 28;

    local bracketBox = UI.Box(content, leftX, leftY, colW, 3 * UI.ROW_HEIGHT + 22);
    Controls.brackets = {};
    local bracketY = -8;

    for _, bracket in ipairs({ "2v2", "3v3", "5v5" }) do
        Controls.brackets[bracket] = UI.Checkbox(bracketBox, "ACPBracketCheck" .. bracket,
            bracket, 10, bracketY,
            function() return ACP.Settings:get("brackets." .. bracket); end,
            function(value) setSetting("brackets." .. bracket, value); end,
            L["bracket" .. bracket .. "Tooltip"]);
        bracketY = bracketY - UI.ROW_HEIGHT;
    end

    -- Divider between the Brackets and Timing groups (Prat header pattern).
    leftY = leftY - (3 * UI.ROW_HEIGHT + 22) - 20;
    UI.Divider(content, leftX, leftY + 12, colW);

    -- Timing box (sliders draw their own labels above them).
    UI.Header(content, L.timingHeader, leftX, leftY);
    leftY = leftY - 28;

    local timingBox = UI.Box(content, leftX, leftY, colW, 184);

    Controls.tradeDelay = UI.Slider(timingBox, "ACPTradeDelaySlider",
        L.tradeDelayLabel, 16, -8, 0, 5, 0.5,
        function() return ACP.Settings:get("tradeDelay"); end,
        function(value) setSetting("tradeDelay", value); end,
        L.tradeDelayTooltip);

    Controls.gateSafety = UI.Slider(timingBox, "ACPGateSafetySlider",
        L.gateSafetyLabel, 16, -64, 0, 60, 1,
        function() return ACP.Settings:get("gateSafetySeconds"); end,
        function(value) setSetting("gateSafetySeconds", value); end,
        L.gateSafetyTooltip);

    Controls.tradeRetries = UI.Slider(timingBox, "ACPTradeRetriesSlider",
        L.tradeRetriesLabel, 16, -120, 0, 5, 1,
        function() return ACP.Settings:get("tradeRetries"); end,
        function(value) setSetting("tradeRetries", value); end,
        L.tradeRetriesTooltip);

    -- "Do not trade to <own class>" — skip auto-trade to teammates of the
    -- player's own class (e.g. other Warlocks). Label is built dynamically so
    -- it names the player's class.
    local playerClassName = select(1, UnitClass("player")) or "???";
    Controls.noTradeSameClass = UI.Checkbox(content, "ACPNoTradeSameClassCheck",
        (L.noTradeSameClassLabel):format(playerClassName),
        leftX, leftY - 184 - 16,
        function() return ACP.Settings:get("noTradeSameClass"); end,
        function(value) setSetting("noTradeSameClass", value); end,
        L.noTradeSameClassTooltip);

    -- ---- RIGHT COLUMN: ranks ----
    local rightX = leftX + colW + UI.GAP;
    local rightY = -4;

    -- Ranks box: built from the class's categories.
    UI.Header(content, L.ranksLabel, rightX, rightY);
    rightY = rightY - 28;

    local classItems = ACP.Data.Items.classItems;
    local englishClass = select(2, UnitClass("player"));
    local categories = classItems[englishClass] or {};
    self.rankEntries = {};

    -- 6 rank rows + comfortable top/bottom padding (no inner category label
    -- for a single category — it collided with the first row).
    local ranksBox = UI.Box(content, rightX, rightY, colW, 6 * UI.ROW_HEIGHT + 24);

    for _, category in ipairs(categories) do
        local settingsKey = category:sub(1, -2);
        self:buildRankRows(ranksBox, settingsKey, category);
    end

    -- Apply the master-switch state (and the permanent 3v3/5v5 lock) now.
    self:setAutotradeEnabled(ACP.Settings:get("enabled") == true);
end

--- Build the settings: a top-level category "ArenaChillPrep" with tabbed
--- subcategories (General, Autotrade). Subcategories render in the Settings
--- list (Settings.RegisterCanvasLayoutSubcategory).
function OptionsUI:buildPanel()
    local L = ACP.L;
    local UI = ACP.UI;
    local panel = CreateFrame("Frame", "ArenaChillPrepOptionsPanel", UIParent);
    panel.name = L.panelTitle;
    self.Panel = panel;
    panel:SetSize(UI.PANEL_WIDTH, UI.PANEL_HEIGHT);

    -- Subcategories (extensible: Profiles/Abilities later). Unsupported
    -- classes (anything but Warlock) get a single compatibility page.
    if (self:isSupportedClass()) then
        self.Subcategories = {
            {
                key = "General",
                title = L.generalSection,
                build = function(_, content, w, h)
                    self:buildGeneral(content, w, h);
                end,
            },
            {
                key = "Workflows",
                title = L.workflow.section,
                build = function(_, content, w, h)
                    self:buildWorkflows(content, w, h);
                end,
            },
            {
                key = "Autotrade",
                title = L.autotradeSection,
                build = function(_, content, w, h)
                    self:buildAutotrade(content, w, h);
                end,
            },
        };
    else
        self.Subcategories = {
            {
                key = "Compatibility",
                title = L.compatSection,
                build = function(_, content, w, h)
                    self:buildCompatibility(content, w, h);
                end,
            },
        };
    end

    if (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory
        and Settings.RegisterCanvasLayoutSubcategory) then
        -- Modern API: parent category + subcategories.
        local parentCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name);
        Settings.RegisterAddOnCategory(parentCategory);
        self.categoryID = parentCategory and parentCategory.ID;

        for _, sub in ipairs(self.Subcategories) do
            local frame = CreateFrame("Frame", nil, UIParent);
            frame.name = sub.title;
            local panelH = (sub.key == "Workflows") and UI.WORKFLOW_PANEL_HEIGHT or UI.PANEL_HEIGHT;
            frame:SetSize(UI.PANEL_WIDTH, panelH);

            sub.frame = frame;
            sub.build(self, frame, frame:GetWidth(), frame:GetHeight());

            -- The settings system may invoke these when the subcategory is
            -- shown/committed — re-sync the controls so e.g. the Workflows
            -- keybind display is current after switching tabs.
            frame.OnCommit = function() end;
            frame.OnDefault = function() end;
            frame.OnRefresh = function()
                self:refresh();
            end;

            local subCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, sub.title);
            Settings.RegisterAddOnCategory(subCategory);
            sub.subCategoryID = subCategory and subCategory.ID;
        end
    elseif (InterfaceOptions_AddCategory) then
        -- Legacy fallback: a single panel (no subcategories) — Autotrade only.
        local content = CreateFrame("Frame", nil, panel);
        content:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -18);
        content:SetSize(UI.PANEL_WIDTH - 28, UI.PANEL_HEIGHT - 30);
        self.Content = content;
        self:buildAutotrade(content, content:GetWidth(), content:GetHeight());

        InterfaceOptions_AddCategory(panel);
        self.categoryID = nil;
    end
end

--- Build the "Workflows" subcategory content (delegated to ACP.WorkflowUI).
---@param content Frame
---@param w number
---@param h number
function OptionsUI:buildWorkflows(content, w, h)
    if (ACP.WorkflowUI and ACP.WorkflowUI.build) then
        ACP.WorkflowUI:build(content, w, h);
    end
end

--- Sync the Workflows status banner/CTA when the workflow engine gate changes.
--- The editor remains usable while the engine is disabled so users can still
--- prepare and persist a workflow.
---@param flag boolean
function OptionsUI:setWorkflowsEnabled(flag)
    if (ACP.WorkflowUI and ACP.WorkflowUI.setEnabled) then
        ACP.WorkflowUI:setEnabled(flag);
    end
end

--- Apply the enabled state to all Autotrade controls: when the master switch
--- is off every control is disabled and grayed. 3v3/5v5 stay permanently
--- disabled on top of that (v0.1 decision).
---@param flag boolean
function OptionsUI:setAutotradeEnabled(flag)
    local Controls = self.Controls;
    local alpha = ACP.UI.DISABLED_ALPHA;

    -- Brackets: 2v2 follows the master switch; 3v3/5v5 stay permanently locked.
    if (Controls.brackets) then
        for _, bracket in ipairs({ "2v2", "3v3", "5v5" }) do
            local check = Controls.brackets[bracket];

            if (check) then
                local active = flag and bracket == "2v2";

                if (active) then
                    check:Enable();
                else
                    check:Disable();
                end

                check:SetAlpha(active and 1 or alpha);
            end
        end
    end

    -- Rank rows (label + checkbox).
    for _, entry in ipairs(self.rankEntries) do
        local check = entry.check;
        local label = entry.label;

        if (flag) then
            check:Enable();
            check:SetAlpha(1);

            if (label) then
                label:EnableMouse(true);
                label:SetAlpha(1);
            end
        else
            check:Disable();
            check:SetAlpha(alpha);

            if (label) then
                label:EnableMouse(false);
                label:SetAlpha(alpha);
            end
        end
    end

    -- Timing sliders (label + slider share the state).
    for _, key in ipairs({ "tradeDelay", "gateSafety", "tradeRetries" }) do
        local slider = Controls[key];

        if (slider) then
            if (flag) then
                slider:Enable();
                slider:SetAlpha(1);

                if (slider.label) then
                    slider.label:SetAlpha(1);
                end
            else
                slider:Disable();
                slider:SetAlpha(alpha);

            if (slider.label) then
                slider.label:SetAlpha(alpha);
            end
        end
    end

    -- "Do not trade to <own class>" checkbox follows the master switch.
    if (Controls.noTradeSameClass) then
        if (flag) then
            Controls.noTradeSameClass:Enable();
            Controls.noTradeSameClass:SetAlpha(1);
        else
            Controls.noTradeSameClass:Disable();
            Controls.noTradeSameClass:SetAlpha(alpha);
        end
    end
end
end

--- Re-sync all controls from Settings.
function OptionsUI:refresh()
    local Controls = self.Controls;
    local enabled = ACP.Settings:get("enabled") == true;

    if (Controls.enabled) then
        Controls.enabled:SetChecked(enabled);
    end

    if (Controls.brackets) then
        for _, bracket in ipairs({ "2v2", "3v3", "5v5" }) do
            local check = Controls.brackets[bracket];

            if (check) then
                check:SetChecked(ACP.Settings:get("brackets." .. bracket) == true);
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

    if (Controls.tradeRetries) then
        Controls.tradeRetries.Refresh();
    end

    if (Controls.noTradeSameClass) then
        Controls.noTradeSameClass:SetChecked(ACP.Settings:get("noTradeSameClass") == true);
    end

    if (Controls.workflowsEnabled) then
        Controls.workflowsEnabled:SetChecked(ACP.Settings:get("workflows.enabled") == true);
    end

    if (ACP.WorkflowUI and ACP.WorkflowUI.isBuilt) then
        ACP.WorkflowUI:refresh();
    end

    self:setAutotradeEnabled(enabled);
    self:setWorkflowsEnabled(ACP.Settings:get("workflows.enabled") == true);
end

--- Open the options panel (works with both the modern and legacy Settings API).
--- Prefers the General subcategory if registered.
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

    -- Settings:reset() re-syncs the panel via the event bus (no reverse
    -- data → UI call — see W6).
    ACP.Events:register("OptionsUI.SETTINGS_RESET", "ACP_SETTINGS_RESET", function()
        self:refresh();
    end);

    SLASH_ACP1 = "/acp";
    SLASH_ACP2 = "/arenachillprep";
    SlashCmdList["ACP"] = function(input)
        local command = strlower((input or ""):match("^%s*(%S*)") or "");

        if (not self:isSupportedClass()) then
            -- Bare /acp still opens the (compatibility) panel; every other
            -- sub-command just prints the incompatibility message to chat.
            if (command == "") then
                self:openPanel();
                return;
            end

            ACP:print(self:getCompatibilityMessage());
            return;
        end

        if (command == "") then
            -- /acp with no args opens the settings panel.
            self:openPanel();
            return;
        end

        handleCommand(input);
    end;
end

return ACP;
