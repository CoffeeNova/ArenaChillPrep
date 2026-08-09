-- ArenaChillPrep — Data/Items
-- Static item catalog + class → items mapping. v0.1: Warlock → healthstones only.
-- Future categories (v0.2+): food, water, totems, ...
--
-- Healthstone IDs (verified from Questie classic/TBC item DB, the client you
-- play): each rank has a PAIR of IDs — historical duplicates. Both IDs of a
-- rank must be tracked (a player may hold either).

---@type ACP
local _, ACP = ...;

local tinsert = _G.tinsert;

-- CLASS_WARLOCK is NOT defined as a global on TBC Anniversary FrameXML
-- (retail-only constant). Guard it so the classItems table keys never go nil.
local CLASS_WARLOCK = _G.CLASS_WARLOCK or "WARLOCK";

ACP.Data = ACP.Data or {};

---@class Items
ACP.Data.Items = {
    healthstones = {
        -- Minor (lvl 10)
        [19004] = { id = 19004, rank = 1, name = "Minor Healthstone" },
        [19005] = { id = 19005, rank = 1, name = "Minor Healthstone" },
        -- Lesser (lvl 22)
        [19006] = { id = 19006, rank = 2, name = "Lesser Healthstone" },
        [19007] = { id = 19007, rank = 2, name = "Lesser Healthstone" },
        -- Healthstone (lvl 34)
        [19008] = { id = 19008, rank = 3, name = "Healthstone" },
        [19009] = { id = 19009, rank = 3, name = "Healthstone" },
        -- Greater (lvl 46)
        [19010] = { id = 19010, rank = 4, name = "Greater Healthstone" },
        [19011] = { id = 19011, rank = 4, name = "Greater Healthstone" },
        -- Major (lvl 58)
        [19012] = { id = 19012, rank = 5, name = "Major Healthstone" },
        [19013] = { id = 19013, rank = 5, name = "Major Healthstone" },
        -- Master (lvl 70, TBC max rank)
        [22105] = { id = 22105, rank = 6, name = "Master Healthstone" },
    },
    -- Future categories:
    -- food = { ... },
    -- water = { ... },

    classItems = {
        [CLASS_WARLOCK] = { "healthstones" },
        -- [CLASS_MAGE]   = { "food", "water" },
    },
};

--- Flattened list of item records the given class can pass.
---@param classID number
---@return table<number, table>
function ACP.Data.Items:getForClass(classID)
    local items = {};
    local categories = self.classItems[classID];

    if (not categories) then
        return items;
    end

    for _, category in ipairs(categories) do
        for _, item in pairs(self[category] or {}) do
            tinsert(items, item);
        end
    end

    return items;
end

return ACP;
