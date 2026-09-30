# tests/ (PowerShell)

Pester tests for the scripts in `powershell/`.

- `Get-PasswordExpiryCategory.Tests.ps1` -- tests the pure
  categorization function in `modules/PasswordExpiry.psm1`, extracted
  from `Get-PasswordExpiryReport.ps1` specifically so it could be
  tested without a live AD connection. Encodes every edge case found
  empirically against the real lab as a permanent regression test,
  including the pwdLastSet = 0 coercion bug (docs/DECISIONS.md,
  2026-09-25).

Requires Pester 5+. Windows PowerShell 5.1 ships with the old Pester
3.4.0 by default, which doesn't understand this syntax:

```powershell
Get-Module -ListAvailable Pester
# If it shows only 3.4.0:
Install-Module -Name Pester -Force -SkipPublisherCheck
```

Run with:

```powershell
Invoke-Pester -Path .\Get-PasswordExpiryCategory.Tests.ps1
```

`New-BulkUsersFromCsv.ps1` and `Test-DiskSpaceAlert.ps1` don't have
tests yet -- their logic is more entangled with mutating AD calls and
`Get-Volume`, which would need Pester's `Mock` to exercise safely
without touching real infrastructure. Natural next step, not done yet.
