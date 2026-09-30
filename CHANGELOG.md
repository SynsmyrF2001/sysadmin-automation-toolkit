# Changelog

Dated, reverse-chronological log of project progress. This is the
skimmable layer -- for the reasoning behind any of these, see
`docs/DECISIONS.md`.

---

## 2026-09-30

- Fully verified the Pester suite on DC01: 11/11 passing. Took three
  wrong turns first -- block scoping, Discovery-vs-Run phase,
  BeforeAll placement -- each a real, well-reasoned Pester mechanism,
  none of them the actual problem. The real cause, found via a
  throwaway diagnostic test rather than a fourth theory: the module
  file (PasswordExpiry.psm1) had simply never been transferred to
  DC01. Also caught that an earlier "regression check" had likely been
  running the old pre-refactor script the whole time, not the current
  one -- a correct-looking result that wasn't actually confirming what
  it appeared to confirm. Both halves of the test harness (bats,
  Pester) are now fully run and passing, not just written.

## 2026-09-29 (cont'd 4)

- Started the test harness, deferred since 2026-09-25. Bash: installed
  bats and wrote 13 tests across rotate-logs.bats (7) and backup.bats
  (6), all run and passing -- including permanent regression tests for
  both bugs found earlier today. PowerShell: extracted the pure
  categorization logic from Get-PasswordExpiryReport.ps1 into
  modules/PasswordExpiry.psm1 (no AD dependency), and wrote Pester
  tests against it, including a direct regression test for the
  pwdLastSet=0 coercion bug from 2026-09-25. The Pester suite is
  written but not executable in this environment (no PowerShell
  runtime) -- needs a real run on DC01 to confirm, unlike the Bash
  suite, which is fully verified already.

## 2026-09-29 (cont'd 3)

- `backup.sh` verified for real against TOOLKIT01: creation,
  verification (4 entries, matching the sandbox result exactly), and
  dry-run all clean. Also re-confirmed `rotate-logs.sh` still works
  correctly after the `lib/config.sh` refactor, on the real VM this
  time, not just in the sandbox.
- **All 5 scripts from the original project card are now built and
  fully verified against real environments** -- AD user creation,
  password expiry reporting, disk space alert, log rotation, backup.
  This closes the literal scope of the original project.

## 2026-09-29 (cont'd 2)

- Extracted `bash/lib/config.sh` (`load_toolkit_config`) and refactored
  `rotate-logs.sh` to use it, once `backup.sh` needed the identical
  config-loading logic. Regression-tested `rotate-logs.sh` afterward --
  no breakage.
- Built `backup.sh`: tar+gzip archival with relative (not absolute)
  paths, verification via an independent `tar -tzf` read-back rather
  than trusting the write's exit code, retention pruning, `--dry-run`.
  Fully verified locally -- creation, verification, corruption
  detection, and retention all tested clean, no bugs found.
- **All 5 scripts from the original project card now exist**: AD user
  creation, password expiry reporting, disk space alert, log rotation,
  and backup.

## 2026-09-29 (cont'd)

- Built `rotate-logs.sh`: size-based trigger, copytruncate rotation,
  gzip compression, retention pruning, `--dry-run` support. First
  script tested by direct execution before ever reaching a real
  machine -- caught and fixed two real bugs this way: empty files being
  rotated forever under a low threshold, and retention pruning silently
  never running on days without a fresh rotation.

## 2026-09-29

- Built `TOOLKIT01`: Ubuntu 26.04.1 LTS (arm64) in VMware Fusion,
  SSH-reachable from the Mac. First real target for the Bash half of
  the toolkit.
- Built `bash/lib/logging.sh` (`write_log`), matching
  `Logging.psm1`'s shape so logs read the same across both languages.

## 2026-09-28

- Found and fixed a real bug in `Test-DiskSpaceAlert.ps1`'s cooldown
  check: a plain `[DateTime]` cast on a stored UTC timestamp silently
  reinterpreted it as local time, making the elapsed-time math wrong by
  a full timezone offset and causing the cooldown to be ignored.
  Switched state storage to Unix epoch seconds, which removes the
  timezone-parsing step -- and the whole bug class -- rather than just
  correcting this one occurrence of it. Re-verified against the lab:
  a forced alert fired, and a second run ~4 minutes later correctly
  computed "4.1 of 60 min elapsed" and suppressed it.

## 2026-09-25 (cont'd 2)

- Built `Test-DiskSpaceAlert.ps1`: per-volume cooldown tracked in a new
  `state/` directory, cooldown clears automatically once a volume
  recovers above threshold (rather than just expiring on a timer), no
  distribution channel yet (console + log only, by design, mirroring
  the earlier email deferral on the password expiry report). Pending
  lab validation.
- Extracted `Get-ToolkitConfig` into a shared `Config.psm1` module and
  updated `Get-PasswordExpiryReport.ps1` to use it, removing the
  duplicated inline config-loading block now that a second script
  needed the same logic.

## 2026-09-25 (cont'd)

- Fully verified `New-BulkUsersFromCsv.ps1` against the lab:
  `-WhatIf` accurate, creation clean, idempotency confirmed on a second
  run (skip, not duplicate or error). Cross-validated against
  `Get-PasswordExpiryReport.ps1`, which correctly picked up both new
  accounts as `MustChangeAtLogon` (6 -> 8). Also confirmed the explicit
  `-DisplayName` fix works, visible as new accounts showing a real name
  next to older accounts that still don't.
- Decided to leave the `sjohnson` enabled/disabled documentation
  mismatch (this repo's live data vs. `homelab-ad-ds`'s README) as-is --
  known drift, doesn't block anything here, not worth reconciling for
  its own sake.
- Added a "Milestones Completed" checklist to `README.md`, matching
  `homelab-ad-ds`'s convention.

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
