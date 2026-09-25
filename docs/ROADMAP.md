# Roadmap

Source: project tracker card -- Priority 3, "Build next."

## Cross-cutting

- [x] Shared logging convention -- PowerShell (`powershell/modules/Logging.psm1`)
- [ ] Shared logging convention -- Bash (`bash/lib/logging.sh`)
- [ ] Config/secrets handling pattern (partially in place via
      `config/config.example.json`; needs a real `.local.json` convention
      documented once more scripts use it)
- [ ] Test harness: Pester (PowerShell), bats (Bash)
- [ ] CI (GitHub Actions) running tests on push

## PowerShell

- [x] Test `Get-PasswordExpiryReport.ps1` against the lab AD -- verified
      2026-09-25, one real bug found and fixed along the way
- [ ] Write Pester tests for the filtering/computation logic
- [x] `New-BulkUsersFromCsv.ps1` -- built; needs -WhatIf run against
      lab, then a real run, before marking done
- [ ] `Test-DiskSpaceAlert.ps1` -- disk space alert (deferred pick, see
      docs/DECISIONS.md)

## Bash

- [ ] `rotate-logs.sh` -- log rotation
- [ ] `backup.sh` -- backup script
