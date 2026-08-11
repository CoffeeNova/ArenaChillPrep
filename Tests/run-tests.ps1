# run-tests.ps1 - run the ArenaChillPrep unit test suite (luaunit + luacov).
# Requires LuaJIT on PATH (install: winget install DEVCOM.LuaJIT).
# Exit codes: 0 = pass + coverage >= 90%, 1 = test failures, 2 = coverage < 90%.

$testsDir = $PSScriptRoot
$addonRoot = Split-Path -Parent $testsDir

$luajit = Get-Command luajit -ErrorAction SilentlyContinue
if (-not $luajit) {
    Write-Error "luajit not found on PATH. Install it: winget install DEVCOM.LuaJIT"
    exit 3
}

Push-Location $addonRoot
try {
    & $luajit.Source "Tests\run_tests.lua" @args
    exit $LASTEXITCODE
} finally {
    Pop-Location
}