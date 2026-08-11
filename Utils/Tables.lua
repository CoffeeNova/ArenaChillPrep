-- ArenaChillPrep — Utils/Tables
-- Basic table helpers: deep merge (for SavedVariables + defaults) and
-- shallow copy.

---@type ACP
local _, ACP = ...;

local pairs = _G.pairs;
local type = _G.type;

---@class Tables
local Tables = {};

--- Deep-merge `source` into `target` in place and return `target`.
--- Tables are merged recursively; any other value overwrites the target key.
---@param target table
---@param source table
---@return table
function Tables:deepMerge(target, source)
    for key, value in pairs(source) do
        if (type(value) == "table" and type(target[key]) == "table") then
            Tables:deepMerge(target[key], value);
        else
            target[key] = value;
        end
    end

    return target;
end

--- Shallow copy of a table (nested tables are shared, not copied).
---@param source table
---@return table
function Tables:shallowCopy(source)
    local copy = {};

    for key, value in pairs(source) do
        copy[key] = value;
    end

    return copy;
end

ACP.Utils = ACP.Utils or {};
ACP.Utils.Tables = Tables;

return ACP;
