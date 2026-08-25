# convert-icon.ps1 - convert a PNG source icon into a WoW-compatible uncompressed
# 32-bit TGA (with alpha) that the client can render via the TOC's
# `## IconTexture` directive. PNG is only an intermediate format for WoW —
# the client loads .tga / .blp, never .png.
#
# Usage:
#   .\.ai\tools\convert-icon.ps1 [-Source icon.png] [-Dest icon.tga]
#
# Defaults: Source = <repo>\icon.png, Dest = <repo>\icon.tga.

param(
    [string]$Source = "",
    [string]$Dest   = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)  # .../ArenaChillPrep
if (-not $Source) { $Source = Join-Path $repoRoot "Textures\icon.png" }
if (-not $Dest)   { $Dest   = Join-Path $repoRoot "Textures\icon.tga" }

Add-Type -AssemblyName System.Drawing

if (-not (Test-Path $Source)) { throw "Source icon not found: $Source" }

$bmp = [System.Drawing.Bitmap]::FromFile($Source)
try {
    $w = $bmp.Width
    $h = $bmp.Height

    # Uncompressed truecolor TGA, 32 bpp, top-left origin, 8-bit alpha.
    $header = [byte[]]::new(18)
    $header[2] = 2          # image type: uncompressed truecolor
    $header[12] = $w -band 0xFF
    $header[13] = ($w -shr 8) -band 0xFF
    $header[14] = $h -band 0xFF
    $header[15] = ($h -shr 8) -band 0xFF
    $header[16] = 32         # pixel depth
    $header[17] = 0x28       # 8-bit alpha + top-left origin (bit 5 set)

    $pixels = [byte[]]::new($w * $h * 4)
    $i = 0
    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            $c = $bmp.GetPixel($x, $y)
            $pixels[$i++] = $c.B
            $pixels[$i++] = $c.G
            $pixels[$i++] = $c.R
            $pixels[$i++] = $c.A
        }
    }
}
finally {
    $bmp.Dispose()
}

[System.IO.File]::WriteAllBytes($Dest, ($header + $pixels))
Write-Output ("Wrote {0} ({1}x{2}, 32-bit TGA)" -f $Dest, $w, $h)
exit 0
