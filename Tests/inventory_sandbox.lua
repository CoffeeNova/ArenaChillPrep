-- ArenaChillPrep — Tests/inventory_sandbox.lua
-- In-game sandbox: verifies stack-aware item counting and
-- findItemInBags WITHOUT touching real bags.
--
-- Usage: uncomment `Tests/inventory_sandbox.lua` in ArenaChillPrep.toc and
-- reload, then run:  /run ACP.Tests:run()
--
-- It stubs GetContainerItemInfo/GetContainerNumSlots with fake data, calls
-- Inventory:countItem / findItemInBags and prints PASS/FAIL to chat.
-- NOTE: it must load AFTER Classes/Inventory.lua (TOC order). Do NOT ship
-- this file in a release TOC.

---@type ACP
local _, ACP = ...;

local Tests = {
    ---@type table<number, {count: number, bound: boolean}>
    FakeBags = {},
};

ACP.Tests = Tests;

--- Replace the container API with fake data:
---   fake = { [bag] = { [slot] = { itemID = 19004, stackCount = 5, bound = false }, ... }, ... }
--- On 2.5.5 the shims prefer C_Container, so both the globals and the
--- C_Container functions are overridden (and restored afterwards).
---@param fake table
function Tests:installFake(fake)
    self.FakeBags = fake;
    self.Originals = {
        globalSlots = _G.GetContainerNumSlots,
        globalInfo = _G.GetContainerItemInfo,
        containerSlots = C_Container and C_Container.GetContainerNumSlots,
        containerInfo = C_Container and C_Container.GetContainerItemInfo,
    };

    local fakeSlots = function(bag)
        return fake[bag] and #fake[bag] or 0;
    end;

    local fakeInfo = function(bag, slot)
        local entry = fake[bag] and fake[bag][slot];

        if (not entry) then
            return nil;
        end

        return nil, entry.stackCount, false, 0, false, false, nil, false, false, entry.itemID, entry.bound;
    end;

    _G.GetContainerNumSlots = fakeSlots;
    _G.GetContainerItemInfo = fakeInfo;

    if (C_Container) then
        C_Container.GetContainerNumSlots = fakeSlots;
        C_Container.GetContainerItemInfo = fakeInfo;
    end
end

function Tests:restore()
    if (not self.Originals) then
        return;
    end

    _G.GetContainerNumSlots = self.Originals.globalSlots;
    _G.GetContainerItemInfo = self.Originals.globalInfo;

    if (C_Container) then
        C_Container.GetContainerNumSlots = self.Originals.containerSlots;
        C_Container.GetContainerItemInfo = self.Originals.containerInfo;
    end

    self.Originals = nil;
    self.FakeBags = {};
end

---@param label string
---@param expected number
---@param actual number
function Tests:check(label, expected, actual)
    local ok = expected == actual;
    ACP:print(("%s %s | expected=%s actual=%s"):format(ok and "PASS" or "FAIL", label, tostring(expected), tostring(actual)));
end

--- Run the sandbox checks.
function Tests:run()
    ACP:print("== ArenaChillPrep inventory sandbox ==");

    -- Case 1: two stacks of the same healthstone in different bags.
    self:installFake({
        [0] = { { itemID = 19004, stackCount = 5, bound = false } },
        [1] = { { itemID = 19004, stackCount = 3, bound = false } },
    });
    self:check("stacked count (5+3)", 8, ACP.Inventory:countItem(19004));
    self:check("findItem returns bag 0 slot 1", 0, (ACP.Inventory:findItem(19004)));

    -- Case 2: soulbound items are skipped by findItem but still counted.
    self:installFake({
        [0] = { { itemID = 19009, stackCount = 2, bound = true } },
        [1] = { { itemID = 19009, stackCount = 4, bound = false } },
    });
    self:check("soulbound still counted", 6, ACP.Inventory:countItem(19009));
    self:check("findItem skips soulbound -> bag 1", 1, (ACP.Inventory:findItem(19009)));

    -- Case 3: item absent.
    self:installFake({
        [0] = { { itemID = 19006, stackCount = 1, bound = false } },
    });
    self:check("absent item count 0", 0, ACP.Inventory:countItem(19009));
    self:check("absent item find nil", nil, (ACP.Inventory:findItem(19009)));

    self:restore();
    ACP:print("== sandbox done ==");
end

return ACP;
