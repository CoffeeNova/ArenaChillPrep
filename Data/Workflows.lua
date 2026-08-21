-- ArenaChillPrep — Data/Workflows
-- Warlock workflow spell catalog + target tokens + step schema validator.
-- Static data only, like Data/Items.lua. Consumed by the WorkflowEngine
-- (Phase 8) and the WorkflowUI editor (Phase 10).
--
-- The static IDs are metadata/fallback entries. Runtime WorkflowSpellbook
-- replaces them with the exact learned spellbook rank IDs; `name` remains the
-- English reference label and runtime code resolves localized names as needed.
-- Verified on 2026-08-18 via in-game GetSpellInfo and the TBC spell lists of
-- working addons on this client (GladiatorlosSA2 spelllist_TBC.lua,
-- OmniBar_TBC, Details spells.lua, LibClassicDurations classAbilities.lua).

---@type ACP
local _, ACP = ...;

local ipairs = _G.ipairs;

---@class Workflows
local Workflows = {
    -- Warlock spell catalog, grouped by category. Entry schema (§3.5/§3.15):
    --   { spellID, name, category, isCastTime, canTargetParty, needsShard,
    --     buffSpellID, itemID }
    spells = {
        -- Self-only armors (canTargetParty = false), all instant.
        buffs = {
            -- Fel Armor rank 1 (verified in-game: GetSpellInfo(28176) = "Fel Armor").
            -- The TBC max-rank ID was not located in addons (28275/28276 are
            -- other spells); casting is name-based so the rank is irrelevant.
            { spellID = 28176, name = "Fel Armor",          isCastTime = false, canTargetParty = false, buffSpellID = 28176 },
            -- Fel Armor rank 2 (wowhead TBC spell=28189). Same metadata as
            -- rank 1; skip-if-buffed matches the aura by NAME.
            { spellID = 28189, name = "Fel Armor",          isCastTime = false, canTargetParty = false, buffSpellID = 28189 },
            -- Demon Armor ranks 706/1086/11733/11734/11735 (LibClassicDurations).
            { spellID = 706,   name = "Demon Armor",        isCastTime = false, canTargetParty = false, buffSpellID = 706 },
            -- Unending Breath (LibClassicDurations).
            { spellID = 5697,  name = "Unending Breath",    isCastTime = false, canTargetParty = true,  buffSpellID = 5697 },
            -- Soul Link (Demonology talent — cast 19028, the applied buff aura
            -- is 25228, also named "Soul Link"; skip-if-buffed matches by NAME).
            -- 6307 is the IMP's Blood Pact passive, NOT Soul Link — verified
            -- against WeakAurasTemplates TBC data 2026-08-22 (the old 6307 entry
            -- made the UI show "Blood Pact" and the skip check matched the imp's
            -- always-on aura, so Soul Link was never cast).
            { spellID = 19028, name = "Soul Link",          isCastTime = false, canTargetParty = false, buffSpellID = 19028 },
            -- Shadow Ward ranks 6229/11739/11740/28610 (OmniCD Modifiers_TBC,
            -- OmniBar_TBC, GladiatorlosSA2 spelllist_TBC). Self-only Magic absorb
            -- shield (30 s); max-rank 28610 stored so a level-70 cast uses the
            -- learned rank (the catalog cannot know the player's level).
            { spellID = 28610, name = "Shadow Ward",         isCastTime = false, canTargetParty = false, buffSpellID = 28610 },
            -- Detect Invisibility rank 1 (Necrosis [132] = "invisible"; the
            -- classic warlock stealth-detection buff, instant).
            { spellID = 132,   name = "Detect Invisibility", isCastTime = false, canTargetParty = true,  buffSpellID = 132 },
        },
        summons = {
            { spellID = 688,   name = "Summon Imp",        isCastTime = true, needsShard = false, petEntry = 416 },
            { spellID = 697,   name = "Summon Voidwalker", isCastTime = true, needsShard = true,  petEntry = 1860 },
            { spellID = 712,   name = "Summon Succubus",   isCastTime = true, needsShard = true,  petEntry = 1863 },
            { spellID = 691,   name = "Summon Felhunter",  isCastTime = true, needsShard = true,  petEntry = 417 },
            { spellID = 30146, name = "Summon Felguard",   isCastTime = true, needsShard = true,  petEntry = 17252 },
        },
        -- Pet abilities — cast by the player's current pet (not the player).
        -- Fire Shield (Imp) and Sacrifice (Voidwalker). The pet casts these
        -- independently, so a pet step is exempt from the player-casting gate
        -- and can be applied DURING the previous step's cast. Spell IDs are
        -- the TBC pet-ability IDs (rank 1 shown; the engine casts by name).
        pets = {
            -- Imp Fire Shield (TBC rank 6 = 27269; rank-1 19483 resolves to
            -- "Immolation" on 2.5.5, so the higher rank must be used). Party-
            -- castable: the Imp shields the Warlock or a nearby party member,
            -- so it carries canTargetParty for the step-row target dropdown.
            { spellID = 27269, name = "Fire Shield",  isPetSpell = true, pet = "imp",        isCastTime = false, canTargetParty = true },
            { spellID = 7812,  name = "Sacrifice",    isPetSpell = true, pet = "voidwalker", isCastTime = false, canTargetParty = false },
        },
        createItem = {
            -- Create Healthstone: TBC ranks 6201/6202/5699/11729/11730/27230
            -- (GladiatorlosSA2 spelllist_TBC.lua); 22105 = Master Healthstone
            -- (Questie tbcItemDB.lua).
            { spellID = 6201, name = "Create Healthstone", isCastTime = true, needsShard = true, itemID = 19004 },
            -- Create Healthstone rank 5 (GladiatorlosSA2: 11730 = Rank 5) ->
            -- Major Healthstone 19012 (rankResultItem). On TBC 2.5.5 the stone
            -- ranks COEXIST: a rank-5 cast really creates Major 19012 (the
            -- client does NOT auto-upgrade it to the max rank), so a rank-5
            -- step expects exactly a Major — verified in-game.
            { spellID = 11730, name = "Create Healthstone", isCastTime = true, needsShard = true, itemID = 19012 },
            -- Create Healthstone rank 6 / TBC max (GladiatorlosSA2: 27230 =
            -- Rank 6) -> Master Healthstone 22105.
            { spellID = 27230, name = "Create Healthstone", isCastTime = true, needsShard = true, itemID = 22105 },
            -- Create Spellstone rank 4 (TBC max; Necrosis [28172] SpellRank 4)
            -- -> Master Spellstone 22646 (Questie tbcItemDB.lua). 5 s cast.
            { spellID = 28172, name = "Create Spellstone", isCastTime = true, needsShard = true, itemID = 22646 },
            -- TODO: verify in game. 693 is rank 1 (Minor Soulstone); the TBC
            -- max rank 5 is 14301 and creates Major Soulstone 22103. A max-rank
            -- cast (by name) produces 22103, which is what the step waits for.
            { spellID = 693,  name = "Create Soulstone",   isCastTime = true, needsShard = true, itemID = 22103 },
        },
        utility = {
            -- Ritual of Souls TBC rank 1 (OmniBar_TBC, GladiatorlosSA2).
            { spellID = 29893, name = "Ritual of Souls",     isCastTime = true, needsShard = true },
            { spellID = 698,   name = "Ritual of Summoning", isCastTime = true, needsShard = true },
        },
    },

    -- Target unit tokens a `cast` step may use. Single source of truth is
    -- ACP.Data.Constants.WORKFLOW_TARGETS (Constants loads before this file).
    targets = nil,

    -- Equippable conjured items an `equipItem` step may equip (spellstone
    -- family — the arena prep use case; item IDs from Questie tbcItemDB.lua).
    -- Entry schema: { itemID, name }.
    equipItems = {
        { itemID = 5522,  name = "Spellstone" },
        { itemID = 13602, name = "Greater Spellstone" },
        { itemID = 13603, name = "Major Spellstone" },
        { itemID = 22646, name = "Master Spellstone" },
    },

    -- Full rank data for the stone-creating spells. The Add Step menu lists
    -- each rank separately with the stone's name (e.g. "Create Master
    -- Healthstone") so the player can add a step for a specific rank. Keyed by
    -- spellID; spellName is the plain spell name (grouping key), itemName is
    -- the stone the cast creates at that rank. Healthstone ranks 1-5 exist as
    -- historical item-ID PAIRS (see Data/Items.lua) — the client conjures one
    -- variant per rank (rank 5 → 19013, live-verified 2026-08-22), so
    -- `itemIDs` lists BOTH variants and the engine accepts either.
    -- Healthstone ranks 1-6: 6201/6202/5699/11729/11730/27230 (TBC order);
    -- Spellstone ranks 1-4: 2362/28171/28173/28172 (28172 = TBC max).
    stoneRanks = {
        [6201]  = { spellID = 6201,  spellName = "Create Healthstone", itemID = 19004, itemIDs = { 19004, 19005 }, itemName = "Minor Healthstone", rank = 1 },
        [6202]  = { spellID = 6202,  spellName = "Create Healthstone", itemID = 19006, itemIDs = { 19006, 19007 }, itemName = "Lesser Healthstone", rank = 2 },
        [5699]  = { spellID = 5699,  spellName = "Create Healthstone", itemID = 19008, itemIDs = { 19008, 19009 }, itemName = "Healthstone", rank = 3 },
        [11729] = { spellID = 11729, spellName = "Create Healthstone", itemID = 19010, itemIDs = { 19010, 19011 }, itemName = "Greater Healthstone", rank = 4 },
        [11730] = { spellID = 11730, spellName = "Create Healthstone", itemID = 19012, itemIDs = { 19012, 19013 }, itemName = "Major Healthstone", rank = 5 },
        [27230] = { spellID = 27230, spellName = "Create Healthstone", itemID = 22105, itemIDs = { 22105 }, itemName = "Master Healthstone", rank = 6 },
        [2362]  = { spellID = 2362,  spellName = "Create Spellstone", itemID = 5522,  itemIDs = { 5522 },  itemName = "Spellstone", rank = 1 },
        [28171] = { spellID = 28171, spellName = "Create Spellstone", itemID = 13602, itemIDs = { 13602 }, itemName = "Greater Spellstone", rank = 2 },
        [28173] = { spellID = 28173, spellName = "Create Spellstone", itemID = 13603, itemIDs = { 13603 }, itemName = "Major Spellstone", rank = 3 },
        [28172] = { spellID = 28172, spellName = "Create Spellstone", itemID = 22646, itemIDs = { 22646 }, itemName = "Master Spellstone", rank = 4 },
    },
};

---@type Workflows
ACP.Data.Workflows = Workflows;
Workflows.targets = ACP.Data.Constants.WORKFLOW_TARGETS;

--- Catalog entry for an equippable conjured item (equipItems list).
---@param itemID number
---@return table|nil
function Workflows:getEquipItem(itemID)
    for _, entry in ipairs(self.equipItems) do
        if (entry.itemID == itemID) then
            return entry;
        end
    end

    return nil;
end

--- Whether `token` is a valid workflow target unit token.
---@param token any
---@return boolean
function Workflows:isValidTarget(token)
    for _, allowed in ipairs(self.targets) do
        if (allowed == token) then
            return true;
        end
    end

    return false;
end

--- Validate a workflow step against the step schema (§3.5).
--- Used by the engine before executing a step and by the UI editor on save.
---@param step any
---@return boolean ok True if the step is valid.
---@return string|nil errorMessage Localized error, or nil when valid.
function Workflows:validateStep(step)
    if (type(step) ~= "table") then
        return false, ACP.L.workflow.errNotTable;
    end

    local C = ACP.Data.Constants;
    local stepType = step.type;

    if (stepType ~= C.WORKFLOW_STEP_CAST
        and stepType ~= C.WORKFLOW_STEP_SUMMON
        and stepType ~= C.WORKFLOW_STEP_CREATE_ITEM
        and stepType ~= C.WORKFLOW_STEP_EQUIP_ITEM
        and stepType ~= C.WORKFLOW_STEP_PET) then
        return false, ACP.L.workflow.errBadType:format(tostring(stepType));
    end

    -- equipItem steps identify the target ITEM, not a spell.
    if (stepType == C.WORKFLOW_STEP_EQUIP_ITEM) then
        if (type(step.itemID) ~= "number") then
            return false, ACP.L.workflow.errBadItemID;
        end

        if (step.itemName ~= nil and type(step.itemName) ~= "string") then
            return false, ACP.L.workflow.errBadItemName;
        end

        return true;
    end

    if (type(step.spellID) ~= "number") then
        return false, ACP.L.workflow.errBadSpellID;
    end

    if (stepType == C.WORKFLOW_STEP_CAST) then
        if (step.target ~= nil and not self:isValidTarget(step.target)) then
            return false, ACP.L.workflow.errBadTarget:format(tostring(step.target));
        end
    elseif (stepType == C.WORKFLOW_STEP_CREATE_ITEM) then
        if (type(step.itemID) ~= "number") then
            return false, ACP.L.workflow.errBadItemID;
        end
    end

    -- skipIfBuffed may appear on buff-cast, summon and createItem steps
    -- (the engine skips them when their goal is already met).
    if ((stepType == C.WORKFLOW_STEP_CAST
            or stepType == C.WORKFLOW_STEP_SUMMON
            or stepType == C.WORKFLOW_STEP_CREATE_ITEM)
        and step.skipIfBuffed ~= nil and type(step.skipIfBuffed) ~= "boolean") then
        return false, ACP.L.workflow.errBadSkip;
    end

    return true;
end

return ACP;
