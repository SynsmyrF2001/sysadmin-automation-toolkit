<#
.SYNOPSIS
    Reports on user accounts with passwords nearing expiration.

.DESCRIPTION
    Queries Active Directory for accounts whose password will expire
    within a configurable warning window. Read-only -- this script never
    modifies an account.

    Uses msDS-UserPasswordExpiryTimeComputed rather than computing
    pwdLastSet + MaxPasswordAge by hand, because that constructed
    attribute correctly accounts for Fine-Grained Password Policies
    (FGPP), which can override the domain default per OU/group. Manual
    math gets this silently wrong for any user under a non-default
    policy.

    Output has two categories, not one flat list:
      - "ExpiringSoon"      -- a real countdown, inside the warning window
      - "MustChangeAtLogon" -- pwdLastSet = 0; there's no countdown to
        compute because the password is already invalid until the user
        changes it. This is a different, more urgent kind of risk than a
        slow drift toward expiry, so it's labeled separately rather than
        silently skipped or folded into the same day-count logic.

.PARAMETER WarningDays
    Report accounts whose password expires within this many days.
    Defaults to config/config.local.json (falling back to
    config.example.json, then to 14) if not supplied.

.PARAMETER SearchBase
    Optional distinguished name to scope the query, e.g. a specific OU.
    Defaults to the whole domain.

.PARAMETER IncludeDisabled
    Disabled accounts are excluded by default -- an expiring password on
    an account nobody can log into is not actionable. Pass this switch
    to include them anyway.

.PARAMETER OutputCsv
    Optional path to also export the report as CSV.

.PARAMETER Credential
    Optional PSCredential to run the AD query as a different identity,
    e.g. a dedicated read-only service account rather than the
    interactive user's own credentials.

.EXAMPLE
    .\Get-PasswordExpiryReport.ps1 -WarningDays 14

.EXAMPLE
    .\Get-PasswordExpiryReport.ps1 -SearchBase "OU=IT,DC=corp,DC=local" -OutputCsv C:\Reports\expiry.csv

.NOTES
    Design decisions for this script are logged in docs/DECISIONS.md.
#>

[CmdletBinding()]
param(
    [int]$WarningDays,

    [string]$SearchBase,

    [switch]$IncludeDisabled,

    [string]$OutputCsv,

    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty
)

# ---------------------------------------------------------------------------
# Setup: shared logging module
# ---------------------------------------------------------------------------

# $PSScriptRoot is the directory THIS SCRIPT lives in, not the caller's
# working directory -- using it means the script finds its module and
# config no matter where it was launched from (interactive shell,
# scheduled task, another script).
$RepoRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot "modules\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\Config.psm1") -Force

$LogDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}
$LogPath = Join-Path $LogDir "password-expiry-report_$(Get-Date -Format 'yyyyMMdd').log"

Write-Log -LogPath $LogPath -Level INFO -Message "Starting password expiry report"

# ---------------------------------------------------------------------------
# Config: the warning window is a config value, not a hardcoded number
# ---------------------------------------------------------------------------

if (-not $WarningDays) {
    $Config = Get-ToolkitConfig -RepoRoot $RepoRoot
    $WarningDays = $Config.passwordExpiry.warningWindowDays
    if (-not $WarningDays) { $WarningDays = 14 }
}

Write-Log -LogPath $LogPath -Level INFO -Message "Warning window: $WarningDays day(s)"

# ---------------------------------------------------------------------------
# Query AD
# ---------------------------------------------------------------------------

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Log -LogPath $LogPath -Level ERROR -Message "ActiveDirectory module not available: $($_.Exception.Message)"
    exit 1
}

$Properties = @(
    "DisplayName",
    "SamAccountName",
    "Enabled",
    "PasswordNeverExpires",
    "msDS-UserPasswordExpiryTimeComputed"
)

$GetADUserParams = @{
    Filter      = "*"
    Properties  = $Properties
    ErrorAction = "Stop"
}
if ($SearchBase) { $GetADUserParams["SearchBase"] = $SearchBase }
if ($Credential.UserName) { $GetADUserParams["Credential"] = $Credential }

try {
    # @() for the same reason as the Sort-Object result below: a query
    # that happens to match exactly one account would otherwise return a
    # bare object instead of a one-item array, breaking .Count.
    $Users = @(Get-ADUser @GetADUserParams)
}
catch {
    Write-Log -LogPath $LogPath -Level ERROR -Message "AD query failed: $($_.Exception.Message)"
    exit 1
}

Write-Log -LogPath $LogPath -Level INFO -Message "Queried $($Users.Count) account(s)"

# ---------------------------------------------------------------------------
# Filter + compute
# ---------------------------------------------------------------------------

$Now = Get-Date
$Cutoff = $Now.AddDays($WarningDays)

$Report = [System.Collections.Generic.List[object]]::new()

foreach ($User in $Users) {

    if (-not $IncludeDisabled -and -not $User.Enabled) { continue }
    if ($User.PasswordNeverExpires) { continue }

    $ExpiryRaw = $User."msDS-UserPasswordExpiryTimeComputed"

    # "Never expires" even without the flag above -- possible when a
    # fine-grained policy sets no max age for this user. Nothing to
    # report either way.
    #
    # $null explicitly, not "-not $ExpiryRaw": PowerShell treats integer
    # 0 as boolean $false, so a truthy/falsy check here would swallow
    # the pwdLastSet=0 case below before it's ever reached. Caught this
    # against the lab -- see docs/DECISIONS.md, 2026-09-25.
    if ($null -eq $ExpiryRaw -or $ExpiryRaw -eq [Int64]::MaxValue) { continue }

    # pwdLastSet = 0 means "must change password at next logon." There
    # is no countdown to compute -- the password is already invalid
    # until changed, which is a more urgent, different kind of risk than
    # a slow drift toward expiry. Categorize it distinctly instead of
    # either hiding it or faking a day-count for it.
    if ($ExpiryRaw -eq 0) {
        $Report.Add([PSCustomObject]@{
            DisplayName    = $User.DisplayName
            SamAccountName = $User.SamAccountName
            Category       = "MustChangeAtLogon"
            ExpiryDate     = $null
            DaysRemaining  = $null
        })
        continue
    }

    $ExpiryDate = [DateTime]::FromFileTime($ExpiryRaw)

    if ($ExpiryDate -le $Cutoff) {
        $Report.Add([PSCustomObject]@{
            DisplayName    = $User.DisplayName
            SamAccountName = $User.SamAccountName
            Category       = "ExpiringSoon"
            ExpiryDate     = $ExpiryDate
            DaysRemaining  = [math]::Round(($ExpiryDate - $Now).TotalDays, 1)
        })
    }
}

# MustChangeAtLogon leads (it's immediate, pending action right now);
# within each category, soonest-first. DaysRemaining is $null for the
# MustChangeAtLogon group, so it has nothing to break ties on -- fine,
# since those rows are already equally "now."
#
# Wrapped in @() deliberately: piping a collection through Sort-Object
# and reassigning unwraps a single result to a bare object (no .Count)
# and an empty result to $null. @() forces it back into an array either
# way, so .Count below is reliable whether 0, 1, or many rows match --
# which matters a lot in a 10-account lab, where 0 or 1 is the likely
# outcome, not "many."
$Report = @($Report | Sort-Object @{Expression = { $_.Category -ne "MustChangeAtLogon" } }, DaysRemaining)

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if ($Report.Count -gt 0) {
    $Report | Format-Table -AutoSize
    $ExpiringCount   = @($Report | Where-Object Category -eq "ExpiringSoon").Count
    $MustChangeCount = @($Report | Where-Object Category -eq "MustChangeAtLogon").Count
    Write-Log -LogPath $LogPath -Level INFO -Message "$ExpiringCount account(s) expiring within $WarningDays day(s); $MustChangeCount flagged must-change-at-next-logon"
}
else {
    Write-Host "No accounts expiring within $WarningDays day(s) and none flagged must-change-at-next-logon."
    Write-Log -LogPath $LogPath -Level INFO -Message "No accounts expiring within $WarningDays day(s) and none flagged must-change-at-next-logon"
}

if ($OutputCsv) {
    $Report | Export-Csv -Path $OutputCsv -NoTypeInformation
    Write-Log -LogPath $LogPath -Level INFO -Message "Report exported to $OutputCsv"
}

Write-Log -LogPath $LogPath -Level INFO -Message "Password expiry report complete"
