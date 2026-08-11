-- ArenaChillPrep — Utils/Items
-- Item helpers: container info shim + stack-aware counting and
-- findItemInBags(itemID, skipSoulbound).

---@type ACP
local _, ACP = ...;

---@class Items
local Items = {};

--- Read the number of slots in a bag with the TBC signature in mind.
--- Shim for both C_Container.GetContainerNumSlots and the legacy global.
--- Resolved at call time so sandbox tests can stub the global.
---@param bag number
---@return number
function Items:getContainerNumSlots(bag)
    local getNumSlots = _G.GetContainerNumSlots or (C_Container and C_Container.GetContainerNumSlots);

    if (getNumSlots) then
        return getNumSlots(bag);
    end

    return 0;
end

--- Read container item info with the TBC signature in mind.
--- Shim for both the modern C_Container API and the legacy
--- GetContainerItemInfo.
---
--- Returns the legacy-style tuple:
---   icon, stackCount, locked, quality, readable, hasLoot, link,
---   filtered, noValue, itemID, bound
---@param bag number
---@param slot number
---@return any
function Items:getContainerItemInfo(bag, slot)
    if (C_Container and C_Container.GetContainerItemInfo) then
        local info = C_Container.GetContainerItemInfo(bag, slot);

        if (not info) then
            return nil;
        end

        return info.iconFileID, info.stackCount, info.isLocked, info.quality, info.isReadable,
            info.hasLoot, info.hyperlink, info.isFiltered, info.hasNoValue, info.itemID, info.isBound;
    end

    if (GetContainerItemInfo) then
        return GetContainerItemInfo(bag, slot);
    end

    return nil;
end

--- Read the container fields callers actually use from one slot.
--- Centralizes the legacy-tuple positions (see getContainerItemInfo) so call
--- sites never read ten positional underscores; returns semantic values.
---@param bag number
---@param slot number
---@return number|nil itemID
---@return number|nil stackCount
---@return boolean|nil bound
---@return string|nil link
function Items:getItemData(bag, slot)
    local _, stackCount, _, _, _, _, link, _, _, itemID, bound = self:getContainerItemInfo(bag, slot);

    return itemID, stackCount, bound, link;
end

--- Find the first bag slot holding `itemID`, optionally skipping soulbound
--- items (bound = 11th container value, reliable on TBC). Bags 0..4 only, no
--- bank.
---@param itemID number
---@param skipSoulbound boolean|nil
---@return number|nil bag, number|nil slot
function Items:findItemInBags(itemID, skipSoulbound)
    local numBags = ACP.Data.Constants.NUM_BAGS;

    for bag = 0, numBags - 1 do
        local numSlots = self:getContainerNumSlots(bag);

        for slot = 1, numSlots do
            local bagItemID, _, bound = self:getItemData(bag, slot);

            if (bagItemID == itemID and (not skipSoulbound or not bound)) then
                return bag, slot;
            end
        end
    end

    return nil;
end

ACP.Utils = ACP.Utils or {};
ACP.Utils.Items = Items;

return ACP;
