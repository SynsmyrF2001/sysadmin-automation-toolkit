<#
.SYNOPSIS
    Shared logging function for this repo's PowerShell scripts.

.DESCRIPTION
    Writes a timestamped, leveled log line to both the console
    (color-coded by level) and a log file. The file write is what
    matters most in practice: when a script runs as a scheduled task,
    nobody is watching the console, so the file is the only record that
    a run happened and what it did.
#>

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Timestamp] [$Level] $Message"

    switch ($Level) {
        "ERROR" { Write-Host $Line -ForegroundColor Red }
        "WARN"  { Write-Host $Line -ForegroundColor Yellow }
        default { Write-Host $Line }
    }

    # Append, not overwrite -- each run adds to the history instead of
    # erasing the last run's record. This IS the audit trail.
    Add-Content -Path $LogPath -Value $Line
}

Export-ModuleMember -Function Write-Log
