-- ArenaChillPrep — Tests/run_tests.lua
-- Test runner: luacov (coverage) + luaunit (tests) + WoW stubs + loader.
-- Usage:  luajit Tests/run_tests.lua   (or .\Tests\run-tests.ps1)
-- Exit codes: 0 = all tests pass and coverage >= 90%; 1 = test failures;
--             2 = coverage below 90%.
local script = arg and arg[0] or "run_tests.lua";
local ROOT = script:match("^(.*)[/\\][^/\\]+$") or ".";
local ADDON_ROOT = ROOT:match("^(.*)[/\\][^/\\]+$") or ".";

package.path = ROOT .. "/lib/luaunit/?.lua;" .. ROOT .. "/lib/luacov/?.lua;" .. package.path;

-- ---- coverage ----
local covRunner = require("luacov.runner");
covRunner.init({
    statsfile = ROOT .. "/luacov.stats.out",
    reportfile = ROOT .. "/luacov.report.out",
    runreport = true,
    include = {"bootstrap$", "Data/Constants$", "Data/Items$", "Data/DefaultSettings$", "Data/Localization$",
               "Utils/Tables$", "Utils/Items$", "Utils/Timers$", "Classes/Events$", "Classes/Settings$",
               "Classes/ArenaPrep$", "Classes/Inventory$", "Classes/DeliveryController$", "Classes/TradeManager$"}
});

-- ---- luaunit (exposed as global `lu` for the suites) ----
local lu = require("luaunit");
_G.lu = lu;

-- ---- WoW stubs + addon load ----
dofile(ROOT .. "/stubs/wow_stubs.lua");
local ACP = (loadfile(ROOT .. "/loader.lua"))(ADDON_ROOT);
_G.__TESTS_ROOT = ROOT;
_G.__ADDON_ROOT = ADDON_ROOT;

-- The event bus needs its frame before any register() call.
ACP.Events:_init(ACP.Frame);

-- Settings must be initialized so tests can read/write via ACP.Settings.
_G.ArenaChillPrepDB = nil;
ACP.Settings:_init();

-- Init the remaining modules in real order (OptionsUI is UI code — excluded
-- from coverage and not initialized here).
ACP.ArenaPrep:_init();
ACP.Inventory:_init();
ACP.TradeManager:_init();
ACP.DeliveryController:_init();

-- ---- test suites (each defines global test* functions) ----
-- Paths mirror the addon structure: bootstrap at the root, the rest under
-- Data/ Utils/ Classes/. Order matters (some suites capture file-scope state,
-- e.g. test_deliverycontroller saves the real Timers).
local suites = {"test_bootstrap", "Data/test_constants", "Data/test_items", "Data/test_defaultsettings",
                "Data/test_localization", "Utils/test_tables", "Utils/test_utils_items", "Utils/test_timers",
                "Classes/test_events", "Classes/test_settings", "Classes/test_arenaprep", "Classes/test_inventory",
                "Classes/test_deliverycontroller", "Classes/test_trademanager"};
for _, suite in ipairs(suites) do
    dofile(ROOT .. "/" .. suite .. ".lua");
end

-- ---- run ----
local failures = lu.LuaUnit.run();

covRunner.shutdown();

-- ---- coverage gate ----
local function coveragePercent()
    local f = io.open(ROOT .. "/luacov.report.out", "r");
    if (not f) then
        return nil;
    end
    local total;
    for line in f:lines() do
        if (line:match("^Total")) then
            total = line;
        end
    end
    f:close();
    if (not total) then
        return nil;
    end
    return tonumber(total:match("(%d+%.?%d*)%%"));
end

local cov = coveragePercent();
print(string.format("Coverage: %s", cov and ("%.2f%%"):format(cov) or "n/a"));

if (cov and cov >= 90) then
    print("Coverage OK (>= 90%)");
else
    print("Coverage BELOW 90%");
    if (failures == 0) then
        failures = 2;
    end
end

os.exit(failures);
