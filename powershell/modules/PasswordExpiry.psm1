<#
.SYNOPSIS
    Pure categorization logic for Get-PasswordExpiryReport.ps1, split
    out specifically so it can be unit tested without live AD access.

.DESCRIPTION
    This logic used to live directly inside the AD-query loop in
    Get-PasswordExpiryReport.ps1, which meant the only way to exercise
    it was against a real domain controller. Extracted into a plain
    function -- primitive values in, a category out, no Get-ADUser
    anywhere near it -- it can be tested with synthetic inputs instead.

    powershell/tests/Get-PasswordExpiryCategory.Tests.ps1 encodes every
    edge case discovered empirically against the real lab, including
    the pwdLastSet = 0 coercion bug (docs/DECISIONS.md, 2026-09-25), as
    permanent regression tests.
#>

function Get-PasswordExpiryCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Enabled,

        [Parameter(Mandatory)]
        [bool]$PasswordNeverExpires,

        # The raw msDS-UserPasswordExpiryTimeComputed value. $null is a
        # legitimate, meaningful INPUT here (the attribute being
        # absent), not just an unset parameter -- typed as [object]
        # rather than [Int64] specifically to allow that.
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$ExpiryRaw,

        [Parameter(Mandatory)]
        [int]$WarningDays,

        [Parameter(Mandatory)]
        [DateTime]$Now,

        [switch]$IncludeDisabled
    )

    if (-not $IncludeDisabled -and -not $Enabled) { return $null }
    if ($PasswordNeverExpires) { return $null }

    # $null explicitly, not "-not $ExpiryRaw": PowerShell treats integer
    # 0 as boolean $false, so a truthy/falsy check here would swallow
    # the pwdLastSet = 0 case below before it's ever reached. This is
    # the exact bug found and fixed 2026-09-25 -- see the first test in
    # the "MustChangeAtLogon" context of the Pester suite.
    if ($null -eq $ExpiryRaw -or $ExpiryRaw -eq [Int64]::MaxValue) { return $null }

    # pwdLastSet = 0 means "must change password at next logon." There
    # is no countdown to compute -- the password is already invalid
    # until changed, a more urgent, different kind of risk than a slow
    # drift toward expiry, so it's categorized distinctly instead of
    # either hiding it or faking a day-count for it.
    if ($ExpiryRaw -eq 0) {
        return [PSCustomObject]@{
            Category      = "MustChangeAtLogon"
            ExpiryDate    = $null
            DaysRemaining = $null
        }
    }

    $ExpiryDate = [DateTime]::FromFileTime($ExpiryRaw)
    $Cutoff = $Now.AddDays($WarningDays)

    if ($ExpiryDate -le $Cutoff) {
        return [PSCustomObject]@{
            Category      = "ExpiringSoon"
            ExpiryDate    = $ExpiryDate
            DaysRemaining = [math]::Round(($ExpiryDate - $Now).TotalDays, 1)
        }
    }

    return $null
}

Export-ModuleMember -Function Get-PasswordExpiryCategory
