-- ArenaChillPrep — Classes/ClassCatalogDispatch
-- Routes the static-catalog extension calls to the ACTIVE class's extender
-- (no-op for unknown classes). Editing one class never touches another.

---@type ACP
local _, ACP = ...;

local select = _G.select;

---@class ClassCatalogDispatch
local ClassCatalogDispatch = {
    ---@type table<string, table>
    extenders = {
        [ACP.Data.Constants.CLASS_WARLOCK] = ACP.WarlockCatalogExtender,
        [ACP.Data.Constants.CLASS_MAGE] = ACP.MageCatalogExtender,
    },
};

---@type ClassCatalogDispatch
ACP.ClassCatalogDispatch = ClassCatalogDispatch;

---@return table|nil
local function activeExtender()
    return ClassCatalogDispatch.extenders[select(2, UnitClass("player"))];
end

---@param spellbook table
function ClassCatalogDispatch:merge(spellbook)
    local extender = activeExtender();

    if (extender and extender.merge) then
        extender:merge(spellbook);
    end
end

---@param spellbook table
function ClassCatalogDispatch:addStaticFallback(spellbook)
    local extender = activeExtender();

    if (extender and extender.addStaticFallback) then
        extender:addStaticFallback(spellbook);
    end
end

return ACP;
