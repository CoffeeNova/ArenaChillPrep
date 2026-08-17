# deploy.ps1 - copy the addon's game artifacts to the WoW client's AddOns folder,
# or build a release bundle (zip) for CurseForge / CI pipelines.
#
# What is "a game artifact"? Everything the game actually loads:
#   - the .toc file (the manifest),
#   - every file listed in the .toc (Lua modules, XML, textures, sounds, fonts),
#   - the LICENSE file (CurseForge requires it in the package).
# Everything else (Tests/, .ai/, .env, docs, git) is NOT copied.
#
# Usage:
#   .\.ai\tools\deploy.ps1                     # copy to $env:addons_path_anniversary
#   .\.ai\tools\deploy.ps1 -Bundle             # build a zip in .\dist\ instead
#   .\.ai\tools\deploy.ps1 -Target "D:\tmp"    # copy to an explicit folder
#   .\.ai\tools\deploy.ps1 -Bundle -OutDir "D:\releases"
#
# The AddOns folder comes from the .env variable `addons_path_anniversary`
# (see .env.example). The bundle is named <addon>-<version>.zip, where the
# version is read from the .toc (## Version:).

param(
    [switch]$Bundle,              # build a zip instead of copying to the client
    [string]$Target = "",         # explicit destination; default = $env:addons_path_anniversary
    [string]$OutDir = ""          # bundle output dir; default = <repo>\dist
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "load-env.ps1")

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$toc = Get-ChildItem $repoRoot -Filter *.toc | Select-Object -First 1
if (-not $toc) { throw "No .toc file found in $repoRoot" }

# --- Resolve the file list from the TOC -------------------------------------
# Lines that are not comments/blank and reference a file (any extension).
$tocFiles = Get-Content $toc.FullName | Where-Object {
    $line = $_.Trim()
    $line -and
    -not $line.StartsWith("#") -and
    -not $line.StartsWith("--") -and
    -not $line.StartsWith("##") -and
    $line -notmatch '^\s*$'
}

$files = @()
# The .toc manifest itself is always part of the package.
$files += $toc.FullName

foreach ($rel in $tocFiles) {
    $src = Join-Path $repoRoot $rel
    if (Test-Path $src) {
        $files += $src
    }
    else {
        Write-Warning "TOC references missing file: $rel"
    }
}

# LICENSE is required by CurseForge packaging; include it if present.
$license = Join-Path $repoRoot "LICENSE"
if (Test-Path $license) { $files += $license }

if ($files.Count -eq 0) { throw "No files to deploy (empty TOC?)" }

# --- Version from the TOC ----------------------------------------------------
$version = (Get-Content $toc.FullName | Where-Object { $_ -match '^## Version:\s*(.+)$' } |
    ForEach-Object { $Matches[1] } | Select-Object -First 1)
if (-not $version) { $version = "0.0.0" }
$addonName = $toc.BaseName

# --- Deploy mode -------------------------------------------------------------
if ($Bundle) {
    if (-not $OutDir) { $OutDir = Join-Path $repoRoot "dist" }
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    $zip = Join-Path $OutDir ("{0}-{1}.zip" -f $addonName, $version)
    if (Test-Path $zip) { Remove-Item $zip -Force }

    # Zip entries must be relative to the addon folder (no leading path).
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("acp-deploy-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        foreach ($f in $files) {
            $rel = $f.Substring($repoRoot.Length + 1)
            $dest = Join-Path $tmp $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            Copy-Item $f $dest -Force
        }
        Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $zip -CompressionLevel Optimal
    }
    finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Output ("Bundle: {0} ({1} files)" -f $zip, $files.Count)
    Write-Output ("Size:   {0:N1} KB" -f ((Get-Item $zip).Length / 1KB))
}
else {
    if (-not $Target) { $Target = $env:addons_path_anniversary }
    if (-not $Target) {
        throw "No target. Set addons_path_anniversary in .env (see .env.example) or pass -Target."
    }

    $dest = Join-Path $Target $addonName
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    foreach ($f in $files) {
        $rel = $f.Substring($repoRoot.Length + 1)
        $target = Join-Path $dest $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item $f $target -Force
    }

    Write-Output ("Deployed {0} files to {1}" -f $files.Count, $dest)
}

exit 0