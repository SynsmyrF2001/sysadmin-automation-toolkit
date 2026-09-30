#
# Get-PasswordExpiryCategory.Tests.ps1
#
# Pester tests for the pure categorization function extracted from
# Get-PasswordExpiryReport.ps1 (modules/PasswordExpiry.psm1). No AD
# connection needed -- these run entirely against synthetic inputs, and
# specifically encode the edge cases discovered empirically against the
# real lab (see docs/DECISIONS.md) as permanent regression tests.
#
# Requires Pester 5+. Windows PowerShell 5.1 ships with the old Pester
# 3.4.0 by default, which does NOT understand this syntax (BeforeAll,
# Should -Be, etc. all changed between major versions). Check first:
#   Get-Module -ListAvailable Pester
# If it shows 3.4.0 and nothing newer:
#   Install-Module -Name Pester -Force -SkipPublisherCheck
#
# Run with: Invoke-Pester -Path .\Get-PasswordExpiryCategory.Tests.ps1

# Import-Module sits as bare top-level code here -- the placement this
# suite was verified with (11/11 passing on DC01). Its placement was
# never the actual problem: three attempts moved it around (BeforeAll
# outside Describe, BeforeAll inside it, then bare top-level) and all
# failed identically because PasswordExpiry.psm1 had simply never been
# copied to the test machine. If "Get-PasswordExpiryCategory is not
# recognized" shows up again, check that the module file exists first
# (docs/DECISIONS.md, 2026-09-30).
Import-Module "$PSScriptRoot\..\modules\PasswordExpiry.psm1" -Force

Describe "Get-PasswordExpiryCategory" {

    BeforeAll {
        # A fixed reference point so DaysRemaining assertions are exact
        # numbers, not dependent on the moment the suite happens to run.
        $Now = [DateTime]::Parse("2026-09-29T12:00:00")
    }

    Context "Accounts that should be excluded entirely" {

        It "excludes a disabled account by default" {
            $Result = Get-PasswordExpiryCategory `
                -Enabled $false -PasswordNeverExpires $false `
                -ExpiryRaw $Now.AddDays(5).ToFileTime() `
                -WarningDays 14 -Now $Now
            $Result | Should -BeNullOrEmpty
        }

        It "includes a disabled account when -IncludeDisabled is passed" {
            $Result = Get-PasswordExpiryCategory `
                -Enabled $false -PasswordNeverExpires $false `
                -ExpiryRaw $Now.AddDays(5).ToFileTime() `
                -WarningDays 14 -Now $Now -IncludeDisabled
            $Result.Category | Should -Be "ExpiringSoon"
        }

        It "excludes an account with PasswordNeverExpires set, regardless of ExpiryRaw" {
            $Result = Get-PasswordExpiryCategory `
                -Enabled $true -PasswordNeverExpires $true `
                -ExpiryRaw 0 `
                -WarningDays 14 -Now $Now
            $Result | Should -BeNullOrEmpty
        }

        It "excludes an account with ExpiryRaw = `$null" {
            $Result = Get-PasswordExpiryCategory `
                -Enabled $true -PasswordNeverExpires $false `
                -ExpiryRaw $null `
                -WarningDays 14 -Now $Now
            $Result | Should -BeNullOrEmpty
        }

        It "excludes an account with the Int64.MaxValue 'never expires' sentinel" {
            $Result = Get-PasswordExpiryCategory `
                -Enabled $true -PasswordNeverExpires $false `
                -ExpiryRaw ([Int64]::MaxValue) `
                -WarningDays 14 -Now $Now
            $Result | Should -BeNullOrEmpty
        }

        It "excludes an account whose expiry is well outside the warning window" {
            $Result = Get-PasswordExpiryCategory `
                -Enabled $true -PasswordNeverExpires $false `
                -ExpiryRaw $Now.AddDays(90).ToFileTime() `
                -WarningDays 14 -Now $Now
            $Result | Should -BeNullOrEmpty
        }
    }

    Context "MustChangeAtLogon -- the exact bug fixed 2026-09-25" {

        It "categorizes ExpiryRaw = 0 as MustChangeAtLogon, not excluded" {
            # This is THE regression test. A truthy/falsy check here
            # ("-not `$ExpiryRaw") would treat 0 the same as `$null and
            # silently exclude the account -- exactly the bug found
            # against the real lab. The function under test uses an
            # explicit `$null check instead, so this must categorize,
            # not exclude.
            $Result = Get-PasswordExpiryCategory `
                -Enabled $true -PasswordNeverExpires $false `
                -ExpiryRaw 0 `
                -WarningDays 14 -Now $Now
            $Result.Category | Should -Be "MustChangeAtLogon"
        }

        It "reports no ExpiryDate or DaysRemaining for MustChangeAtLogon -- there is no countdown" {
            $Result = Get-PasswordExpiryCategory `
                -Enabled $true -PasswordNeverExpires $false `
                -ExpiryRaw 0 `
                -WarningDays 14 -Now $Now
            $Result.ExpiryDate | Should -BeNullOrEmpty
            $Result.DaysRemaining | Should -BeNullOrEmpty
        }
    }

    Context "ExpiringSoon" {

        It "categorizes an account expiring inside the window as ExpiringSoon" {
            $Result = Get-PasswordExpiryCategory `
                -Enabled $true -PasswordNeverExpires $false `
                -ExpiryRaw $Now.AddDays(5).ToFileTime() `
                -WarningDays 14 -Now $Now
            $Result.Category | Should -Be "ExpiringSoon"
        }

        It "computes DaysRemaining accurately" {
            $Result = Get-PasswordExpiryCategory `
                -Enabled $true -PasswordNeverExpires $false `
                -ExpiryRaw $Now.AddDays(5).ToFileTime() `
                -WarningDays 14 -Now $Now
            $Result.DaysRemaining | Should -Be 5
        }

        It "includes an account expiring exactly at the cutoff boundary" {
            $Result = Get-PasswordExpiryCategory `
                -Enabled $true -PasswordNeverExpires $false `
                -ExpiryRaw $Now.AddDays(14).ToFileTime() `
                -WarningDays 14 -Now $Now
            $Result.Category | Should -Be "ExpiringSoon"
        }
    }
}
