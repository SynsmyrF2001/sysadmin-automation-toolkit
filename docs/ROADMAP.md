# Roadmap

Source: project tracker card -- Priority 3, "Build next."

## Cross-cutting

- [x] Shared logging convention -- PowerShell (`powershell/modules/Logging.psm1`)
- [x] Shared config-loading convention -- PowerShell (`powershell/modules/Config.psm1`)
- [x] Shared logging convention -- Bash (`bash/lib/logging.sh`)
- [x] Shared config-loading convention -- Bash (`bash/lib/config.sh`)
- [ ] Config/secrets handling pattern (partially in place via
      `config/config.example.json`; needs a real `.local.json` convention
      documented once more scripts use it)
- [x] Test harness: bats fully verified (13 tests passing,
      rotate-logs.sh + backup.sh); Pester fully verified (11 tests
      passing, Get-PasswordExpiryCategory.Tests.ps1) -- both halves on
      equal footing now
- [ ] CI (GitHub Actions) running tests on push

## PowerShell

- [x] Test `Get-PasswordExpiryReport.ps1` against the lab AD -- verified
      2026-09-25, one real bug found and fixed along the way
- [x] Pester tests for the filtering/computation logic -- written and
      fully verified on DC01 (11/11 passing)
- [ ] Pester tests for New-BulkUsersFromCsv.ps1 and
      Test-DiskSpaceAlert.ps1 -- needs Mock for AD/Get-Volume calls,
      not started
- [x] `New-BulkUsersFromCsv.ps1` -- built and fully verified: -WhatIf,
      creation, and idempotency (skip-on-rerun) all confirmed against
      the lab, plus a cross-check against Get-PasswordExpiryReport.ps1
- [x] `Test-DiskSpaceAlert.ps1` -- built and verified against the lab;
      one real timezone bug found and fixed in the cooldown check
      (see docs/DECISIONS.md, 2026-09-28)

## Bash

- [x] `rotate-logs.sh` -- built and fully verified, sandbox AND real
      (TOOLKIT01): rotation, empty-file skip, retention pruning, dry-run
      all clean; regression-checked on TOOLKIT01 after the
      `lib/config.sh` refactor
- [x] `backup.sh` -- built and fully verified, sandbox AND real
      (TOOLKIT01): creation, verification, corruption detection,
      retention, dry-run all clean on both
