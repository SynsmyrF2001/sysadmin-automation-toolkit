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
- [ ] Test harness: Pester (PowerShell), bats (Bash)
- [ ] CI (GitHub Actions) running tests on push

## PowerShell

- [x] Test `Get-PasswordExpiryReport.ps1` against the lab AD -- verified
      2026-09-25, one real bug found and fixed along the way
- [ ] Write Pester tests for the filtering/computation logic
- [x] `New-BulkUsersFromCsv.ps1` -- built and fully verified: -WhatIf,
      creation, and idempotency (skip-on-rerun) all confirmed against
      the lab, plus a cross-check against Get-PasswordExpiryReport.ps1
- [x] `Test-DiskSpaceAlert.ps1` -- built and verified against the lab;
      one real timezone bug found and fixed in the cooldown check
      (see docs/DECISIONS.md, 2026-09-28)

## Bash

- [x] `rotate-logs.sh` -- built and locally verified (rotation,
      empty-file skip, retention pruning, dry-run all tested against a
      real harness); pending a first run against TOOLKIT01
- [x] `backup.sh` -- built and fully verified locally (creation,
      verification/corruption detection, retention, dry-run); pending
      a first run against TOOLKIT01
