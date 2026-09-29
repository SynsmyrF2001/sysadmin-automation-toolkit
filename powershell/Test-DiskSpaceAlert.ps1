<#
.SYNOPSIS
    Checks disk free space and alerts when a volume drops below threshold.

.DESCRIPTION
    Checks configured volumes' free space percentage against a warning
    threshold. When a volume is below threshold, logs and prints a loud
    alert -- but only once per cooldown window per volume, using a small
    local state file to remember the last time each volume alerted. A
    script that runs every few minutes on a schedule would otherwise
    re-alert on the exact same ongoing problem every single run.

    No -WhatIf / idempotency machinery, unlike the AD scripts in this
    toolkit -- this script only ever mutates its own local state and log
    files, not a shared system of record like Active Directory, so
    there's nothing meaningful for -WhatIf to preview.

.PARAMETER WarningThresholdPercent
    Alert when free space drops below this percentage. Falls back to
    config (diskSpaceAlert.warningThresholdPercent), then to 15.

.PARAMETER Volumes
    Drive letters to check, e.g. "C:". Falls back to config
    (diskSpaceAlert.volumes), then to @("C:").

.PARAMETER CooldownMinutes
    Minimum time between repeat alerts for the same volume while it
    stays below threshold. Falls back to config
    (diskSpaceAlert.cooldownMinutes), then to 60.

.PARAMETER StatePath
    Where per-volume last-alert state is stored. Defaults to
    state/disk-space-alert-state.json under the repo root.

.EXAMPLE
    .\Test-DiskSpaceAlert.ps1

.EXAMPLE
    .\Test-DiskSpaceAlert.ps1 -WarningThresholdPercent 95
    # Forces an alert on almost any real volume -- for testing the
    # cooldown/state logic without actually filling a disk to trigger it.

.NOTES
    Design decisions for this script are logged in docs/DECISIONS.md.
#>

[CmdletBinding()]
param(
    [int]$WarningThresholdPercent,
    [string[]]$Volumes,
    [int]$CooldownMinutes,
    [string]$StatePath
)

$RepoRoot = Split-Path $PSScriptRoot -Parent

# ---------------------------------------------------------------------------
# Setup: shared logging + config modules
# ---------------------------------------------------------------------------

Import-Module (Join-Path $PSScriptRoot "modules\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\Config.psm1") -Force

$LogDir = Join-Path $RepoRoot "logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}
$LogPath = Join-Path $LogDir "disk-space-alert_$(Get-Date -Format 'yyyyMMdd').log"

Write-Log -LogPath $LogPath -Level INFO -Message "Starting disk space check"

# ---------------------------------------------------------------------------
# Config -- same override > config.local > config.example > hardcoded
# fallback chain as Get-PasswordExpiryReport.ps1, now shared rather than
# duplicated (see powershell/modules/Config.psm1)
# ---------------------------------------------------------------------------

$Config = Get-ToolkitConfig -RepoRoot $RepoRoot

if (-not $WarningThresholdPercent) {
    $WarningThresholdPercent = $Config.diskSpaceAlert.warningThresholdPercent
}
if (-not $WarningThresholdPercent) { $WarningThresholdPercent = 15 }

if (-not $Volumes) {
    $Volumes = $Config.diskSpaceAlert.volumes
}
if (-not $Volumes) { $Volumes = @("C:") }

if (-not $CooldownMinutes) {
    $CooldownMinutes = $Config.diskSpaceAlert.cooldownMinutes
}
if (-not $CooldownMinutes) { $CooldownMinutes = 60 }

if (-not $StatePath) {
    $StateDir = Join-Path $RepoRoot "state"
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir | Out-Null }
    $StatePath = Join-Path $StateDir "disk-space-alert-state.json"
}

Write-Log -LogPath $LogPath -Level INFO -Message "Threshold: $WarningThresholdPercent% free; Volumes: $($Volumes -join ', '); Cooldown: $CooldownMinutes min"

# ---------------------------------------------------------------------------
# Load state: each volume's last-alert time, if any. Missing/unreadable
# state is treated as "no prior alerts" rather than a fatal error -- losing
# the cooldown memory means one possible extra alert, not a broken script.
# ---------------------------------------------------------------------------

$State = @{}
if (Test-Path $StatePath) {
    try {
        $Loaded = Get-Content $StatePath -Raw | ConvertFrom-Json
        foreach ($Prop in $Loaded.PSObject.Properties) {
            $State[$Prop.Name] = $Prop.Value
        }
    }
    catch {
        Write-Log -LogPath $LogPath -Level WARN -Message "Could not read state file at $StatePath -- starting fresh: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Check each volume
# ---------------------------------------------------------------------------

$Now = Get-Date
$AlertsFired = 0

foreach ($VolumeLetter in $Volumes) {
    $Letter = $VolumeLetter.TrimEnd(':')

    try {
        $Volume = Get-Volume -DriveLetter $Letter -ErrorAction Stop
    }
    catch {
        Write-Log -LogPath $LogPath -Level ERROR -Message "${VolumeLetter}: could not query volume -- $($_.Exception.Message)"
        continue
    }

    if (-not $Volume.Size -or $Volume.Size -eq 0) {
        Write-Log -LogPath $LogPath -Level WARN -Message "${VolumeLetter}: reports zero size, skipping (no media?)"
        continue
    }

    $PercentFree = [math]::Round(($Volume.SizeRemaining / $Volume.Size) * 100, 1)
    Write-Log -LogPath $LogPath -Level INFO -Message "${VolumeLetter}: $PercentFree% free"

    if ($PercentFree -ge $WarningThresholdPercent) {
        # Above threshold: clear any stale cooldown entry so a FUTURE dip
        # alerts immediately rather than being suppressed by a leftover
        # timestamp from an already-resolved problem.
        if ($State.ContainsKey($VolumeLetter)) {
            $State.Remove($VolumeLetter)
        }
        continue
    }

    # Below threshold -- but only alert if this volume hasn't already
    # alerted within the cooldown window. Otherwise a script running every
    # few minutes on the same ongoing problem would alert every run.
    #
    # Comparison is done in Unix epoch seconds, not by parsing a stored
    # ISO string back into a [DateTime]. A plain [DateTime] cast on a
    # "Z"-suffixed string silently converts it to LOCAL time and mislabels
    # it Kind=Local -- no error, just wrong math -- so comparing it
    # against $Now.ToUniversalTime() silently mixes two different clocks.
    # Epoch seconds have no timezone to misinterpret in the first place.
    $LastAlertUnixSeconds = $null
    if ($State.ContainsKey($VolumeLetter)) {
        $LastAlertUnixSeconds = $State[$VolumeLetter].lastAlertUnixSeconds
    }

    if ($LastAlertUnixSeconds) {
        $NowUnixSeconds = [DateTimeOffset]::new($Now.ToUniversalTime()).ToUnixTimeSeconds()
        $ElapsedMinutes = ($NowUnixSeconds - $LastAlertUnixSeconds) / 60
        if ($ElapsedMinutes -lt $CooldownMinutes) {
            Write-Log -LogPath $LogPath -Level INFO -Message "${VolumeLetter}: below threshold but within cooldown ($([math]::Round($ElapsedMinutes, 1)) of $CooldownMinutes min elapsed), not re-alerting"
            continue
        }
    }

    $Message = "${VolumeLetter}: LOW DISK SPACE -- $PercentFree% free (threshold: $WarningThresholdPercent%)"
    Write-Log -LogPath $LogPath -Level ERROR -Message $Message
    Write-Host $Message -ForegroundColor Red

    $NowUtc = $Now.ToUniversalTime()
    $State[$VolumeLetter] = @{
        lastAlertUnixSeconds = [DateTimeOffset]::new($NowUtc).ToUnixTimeSeconds()
        # For a human glancing at the state file only -- never read back
        # or parsed by this script, so it can't reintroduce the bug above.
        lastAlertUtcDisplay  = $NowUtc.ToString("o")
    }
    $AlertsFired++
}

# ---------------------------------------------------------------------------
# Save state
# ---------------------------------------------------------------------------

try {
    $State | ConvertTo-Json | Set-Content -Path $StatePath
}
catch {
    Write-Log -LogPath $LogPath -Level ERROR -Message "Could not write state file at $StatePath -- $($_.Exception.Message)"
}

Write-Log -LogPath $LogPath -Level INFO -Message "Disk space check complete -- $AlertsFired alert(s) fired"
