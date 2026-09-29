<#
.SYNOPSIS
    Shared config-loading helper for this repo's PowerShell scripts.

.DESCRIPTION
    Every script needs the same fallback chain: config/config.local.json
    (gitignored, environment-specific) overrides config/config.example.json
    (committed, template defaults). Extracted here once a second script
    (Test-DiskSpaceAlert.ps1) needed the identical logic that
    Get-PasswordExpiryReport.ps1 already had inline -- see
    docs/DECISIONS.md for why now and not sooner.

    Returns $null if neither file exists or the file can't be parsed;
    callers are responsible for their own final hardcoded defaults, since
    each script's sensible default is specific to that script.
#>

function Get-ToolkitConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $LocalPath = Join-Path $RepoRoot "config\config.local.json"
    $ExamplePath = Join-Path $RepoRoot "config\config.example.json"

    $ConfigPath = if (Test-Path $LocalPath) { $LocalPath } else { $ExamplePath }

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "No config file found at $LocalPath or $ExamplePath"
        return $null
    }

    try {
        return Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Could not parse config at $ConfigPath -- $($_.Exception.Message)"
        return $null
    }
}

Export-ModuleMember -Function Get-ToolkitConfig
