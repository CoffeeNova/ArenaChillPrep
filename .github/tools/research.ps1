# research.ps1 - search working WoW addons for API patterns (the workspace search
# does NOT index the WoW folder, so we use Select-String).
#
# Usage (from .github/tools):
#   .\research.ps1 -Pattern "RegisterCanvasLayoutSubcategory"          # all addons, all files
#   .\research.ps1 -Pattern "GetPlayerAuraBySpellID" -Addons Gargul,sArena_Reloaded
#   .\research.ps1 -Pattern "C_Item.GetItemGUID" -Context 3            # show 3 lines before/after
#   .\research.ps1 -Pattern "22105" -Addons Questie                    # item DB lookup
#   .\research.ps1 -Pattern "TradeFrameTradeButton" -SimpleMatch       # literal (no regex)
#
# Notes:
#   - Case-insensitive by default.
#   - Results print as: Addon\File:Line: text  (trimmed to -MaxLen chars).
#   - Use -Context N to include surrounding lines for understanding.

param(
    [Parameter(Mandatory = $true)]
    [string]$Pattern,

    [string[]]$Addons = @(),          # e.g. @("Gargul","BigDebuffs"); empty = all addons
    [int]$Context = 0,                # lines of context before/after each match
    [int]$MaxLen = 160,               # trim matched line length
    [int]$MaxResults = 40,            # total matches to report
    [switch]$SimpleMatch              # treat -Pattern as a literal string
)

$root = "G:\games\World of Warcraft\_anniversary_\Interface\AddOns"

if (-not (Test-Path $root)) {
    Write-Error "AddOns folder not found: $root"
    exit 1
}

if ($Addons.Count -eq 0) {
    $Addons = Get-ChildItem $root -Directory | Select-Object -ExpandProperty Name
}

$count = 0
foreach ($addon in $Addons) {
    $dir = Join-Path $root $addon
    if (-not (Test-Path $dir)) { continue }

    $files = Get-ChildItem $dir -Recurse -Filter *.lua -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        $params = @{
            Path = $file.FullName
            Pattern = $Pattern
            ErrorAction = 'SilentlyContinue'
        }
        if ($SimpleMatch) { $params.SimpleMatch = $true }
        if ($Context -gt 0) { $params.Context = $Context }

        $hits = Select-String @params | Select-Object -First ([Math]::Max(1, $MaxResults - $count))
        if (-not $hits) { continue }

        foreach ($m in $hits) {
            if ($count -ge $MaxResults) { break }

            if ($Context -gt 0) {
                Write-Output ("=== {0}\{1}:{2} ===" -f $addon, $file.Name, $m.LineNumber)
                foreach ($line in $m.Context.PreContext) { Write-Output ("  " + $line) }
                Write-Output (">> " + $m.Line)
                foreach ($line in $m.Context.PostContext) { Write-Output ("  " + $line) }
            } else {
                $text = $m.Line.Trim()
                if ($text.Length -gt $MaxLen) { $text = $text.Substring(0, $MaxLen) + "..." }
                Write-Output ("{0}\{1}:{2}: {3}" -f $addon, $file.Name, $m.LineNumber, $text)
            }
            $count++
        }

        if ($count -ge $MaxResults) { break }
    }
    if ($count -ge $MaxResults) { break }
}

Write-Output ("--- {0} match(es) shown (max {1}) ---" -f $count, $MaxResults)
