# syntax-check.ps1 - syntax-check all Lua files with luac/luajit -p, if available.
# (No Lua interpreter is currently installed on this machine — see the end of the
#  script for how to install one, or run it manually after installing.)
#
# Usage:  .\syntax-check.ps1 [-Root <addon path>]
# Default Root = the repo root (this script's parent's parent).

param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

# Locate a Lua 5.1-compatible compiler (luac / luajit prefer -p).
$lua = Get-Command luac, luac5.1, luac5.4, luajit -ErrorAction SilentlyContinue |
    Where-Object { $_.Source } | Select-Object -First 1

if (-not $lua) {
    Write-Warning @"
No Lua interpreter found. To enable syntax checks, install one, e.g.:
  - LuaBinaries 5.1 (luac.exe) from https://luabinaries.sourceforge.net/
  - or via winget:  winget install Lua.Lua
  - or Chocolatey:  choco install lua
Then re-run this script.
"@
    exit 2
}

Write-Output ("Using: {0}" -f $lua.Source)

$failures = 0
$files = Get-ChildItem $Root -Recurse -Filter *.lua -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\.ai\\' }

foreach ($file in $files) {
    # luac -p = parse only (no output file); luajit -bl is for bytecode, so use -b with /dev/null or -p fallback.
    $arg = if ($lua.Name -like 'luajit*') { @('-b', $file.FullName, 'NUL') } else { @('-p', $file.FullName) }
    & $lua.Source @arg 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output ("FAIL: {0}" -f $file.FullName.Replace($Root, "."))
        & $lua.Source @arg 2>&1 | ForEach-Object { Write-Output ("   " + $_) }
        $failures++
    }
}

if ($failures -eq 0) {
    Write-Output "OK: all $($files.Count) lua files pass syntax check."
    exit 0
} else {
    Write-Output ("FAILURES: {0}" -f $failures)
    exit 1
}
