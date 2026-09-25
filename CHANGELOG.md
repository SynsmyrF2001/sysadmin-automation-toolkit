# Changelog

Dated, reverse-chronological log of project progress. This is the
skimmable layer -- for the reasoning behind any of these, see
`docs/DECISIONS.md`.

---

## 2026-09-25

- Built `New-BulkUsersFromCsv.ps1`: validates the whole CSV before
  creating anything, idempotent (re-running is safe), generates a
  cryptographically random policy-compliant temp password per account,
  forces change-at-next-logon, supports `-WhatIf`. Pending validation
  against the lab.
- Added `config/sample-new-users.csv` as a test fixture, targeting the
  real `Contractors` OU.
- Validated `Get-PasswordExpiryReport.ps1` against the lab (13
  accounts). Found and fixed a real bug: a truthy/falsy check
  (`-not $ExpiryRaw`) was silently treating `pwdLastSet = 0` the same
  as "no value," making the `MustChangeAtLogon` category unreachable
  since the day it was written. Confirmed fixed on a second lab run
  (6/6 expected accounts correctly categorized).
- Caught and fixed a related PowerShell array-unwrapping issue
  (`.Count` unreliable on a 0- or 1-item pipeline result) in the same
  file, before it ever reached the lab.

## 2026-09-11

- Scaffolded the repo: 5 script stubs (3 PowerShell, 2 Bash) split by
  language, `docs/`, `config/`, `.gitignore`.
- Built the shared PowerShell logging module
  (`powershell/modules/Logging.psm1`).
- Implemented `Get-PasswordExpiryReport.ps1` v1: uses
  `msDS-UserPasswordExpiryTimeComputed` rather than manual FILETIME
  math, so Fine-Grained Password Policies are accounted for correctly.
- Cross-linked to `homelab-ad-ds` once the real lab (domain
  `corp.local`, DC01, OU structure) was confirmed; decided to keep the
  two repos separate rather than merge or duplicate documentation.
- Decided how to categorize `pwdLastSet = 0` accounts
  (`MustChangeAtLogon`, reported separately rather than skipped or
  folded into a fake countdown).
