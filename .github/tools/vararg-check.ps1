# vararg-check.ps1 - verify addon integrity after edits:
#   1. every .lua file ends with "return ACP;" (the vararg chain),
#   2. the TOC file order is bootstrap -> Data -> Utils -> Classes
#      (any file may only depend on earlier modules).
#
# Usage:  .\vararg-check.ps1 [-Root <addon path>]
# Default Root = the repo root (this script's parent's parent).
# Exit code 0 = OK, 1 = problems found.

param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$failures = 0

# --- 1. Every module file ends with return ACP; -----------------------------
# Excluded: .github (docs/tools) and Tests/ (unit tests + vendored libs —
# none are addon modules loaded through the vararg chain).
$luaFiles = Get-ChildItem $Root -Recurse -Filter *.lua -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch '\\.github\\' -and
        $_.FullName -notmatch '\\Tests\\'
    }

foreach ($file in $luaFiles) {
    $tail = Get-Content $file.FullName -Tail 20 | Out-String
    # Allow trailing blank lines/comments but require the return statement.
    $hasReturn = ($tail -match '(?m)^return\s+ACP\s*;\s*$')
    if (-not $hasReturn) {
        Write-Output ("FAIL: {0} does not end with 'return ACP;'" -f $file.FullName.Replace($Root, "."))
        $failures++
    }
}

# --- 2. TOC load order: bootstrap -> Data -> Utils -> Classes ---------------
$toc = Get-ChildItem $Root -Filter *.toc | Select-Object -First 1
if ($toc) {
    $lines = Get-Content $toc.FullName | Where-Object {
        $_ -match '\.lua$' -and $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*--'
    }

    $order = @()
    foreach ($line in $lines) {
        $f = ($line.Trim() -replace '^\s*', '' -replace '\s*$', '')
        if ($f -match 'bootstrap\.lua$') { $order += 'bootstrap' }
        elseif ($f -match '^Data\\') { $order += 'data' }
        elseif ($f -match '^Utils\\') { $order += 'utils' }
        elseif ($f -match '^Classes\\') { $order += 'classes' }
        elseif ($f -match '^Tests\\') { $order += 'tests' }
    }

    $rank = @{ bootstrap = 0; data = 1; utils = 2; classes = 3; tests = 4 }
    $prev = -1
    foreach ($o in $order) {
        if ($rank[$o] -lt $prev) {
            Write-Output ("FAIL: TOC order violation - {0} comes after a later-stage file" -f $o)
            $failures++
        }
        $prev = $rank[$o]
    }
}

if ($failures -eq 0) {
    Write-Output "OK: all $($luaFiles.Count) lua files end with 'return ACP;' and TOC order is correct."
    exit 0
} else {
    Write-Output ("FAILURES: {0}" -f $failures)
    exit 1
}
