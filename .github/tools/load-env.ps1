# load-env.ps1 - load the repo's local environment from .env into the current
# session (or the caller's scope when dot-sourced).
#
# Usage:
#   . .\.github\tools\load-env.ps1        # dot-source: sets $env: vars in your session
#   .\.github\tools\load-env.ps1          # run: prints the resolved values
#
# Reads .env from the repo root (KEY=VALUE lines, '#' = comment). Missing .env
# is not an error - scripts that need a path fail with a clear message instead.
#
# Variables defined here:
#   $env:addons_path_anniversary  - WoW TBC Anniversary AddOns folder (from .env)

$envFile = Join-Path $PSScriptRoot "..\..\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $key, $value = $line.Split("=", 2)
            $value = $value.Trim()
            # Strip surrounding quotes (single or double) — standard .env behavior.
            if ($value.Length -ge 2 -and
                (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            Set-Item -Path "Env:$($key.Trim())" -Value $value
        }
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    # Ran as a script (not dot-sourced): report what we resolved.
    Write-Output ("addons_path_anniversary = '{0}'" -f $env:addons_path_anniversary)
}