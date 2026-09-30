# Sysadmin Automation Toolkit

Windows + Linux sysadmin automation, built like production tooling rather
than a folder of one-off scripts: idempotent, logged, configurable, and
tested.

## Contents

| Path | What's in it |
|---|---|
| [`README.md`](README.md) | This file -- overview, scripts, target environment |
| [`CHANGELOG.md`](CHANGELOG.md) | Dated, reverse-chronological log of project progress |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Every design decision and bug, with reasoning and root cause |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | What's built, what's next |
| [`powershell/`](powershell/) | PowerShell scripts + shared logging module |
| [`bash/`](bash/) | Bash scripts + shared shell library |
| [`config/`](config/) | Config templates and test fixtures |

## Scripts

### PowerShell (Windows / Active Directory)

| Script | Purpose | Status |
|---|---|---|
| `New-BulkUsersFromCsv.ps1` | Create user accounts in bulk from a CSV | Verified against lab |
| `Get-PasswordExpiryReport.ps1` | Flag accounts nearing password expiry | Verified against lab |
| `Test-DiskSpaceAlert.ps1` | Monitor volumes, alert on low free space | Verified against lab |

### Bash (Linux)

| Script | Purpose | Status |
|---|---|---|
| `rotate-logs.sh` | Rotate, compress, and prune application logs | Verified on TOOLKIT01 |
| `backup.sh` | Back up configured paths/databases, verify, prune | Verified on TOOLKIT01 |

## Design principles

These are not optional polish -- they are what makes a script safe to hand
to an ops team:

- **Idempotent.** Running a script twice never double-creates a user or
  corrupts a backup.
- **Dry-run first.** Anything destructive supports `-WhatIf` (PowerShell)
  or `--dry-run` (Bash) before it supports actually doing the thing.
- **Config over hardcoding.** Thresholds, paths, and targets live in
  `config/`, not inline in the script.
- **Structured logging.** Every run leaves an audit trail: what happened,
  when, and whether it succeeded.
- **Fail loud, fail safe.** A partial failure should be obvious and
  recoverable, never silently swallowed.
- **Tested logic.** Pester for PowerShell, bats for Bash -- the parts
  that do not require live AD/prod access get covered.

## Target environment

This toolkit is built and tested against a real (homelab) Active
Directory domain, documented separately in
[`homelab-ad-ds`](https://github.com/SynsmyrF2001/homelab-ad-ds):

| | |
|---|---|
| Domain (FQDN) | `corp.local` |
| NetBIOS | `CORP` |
| Domain controller | `DC01.corp.local` (192.168.64.10) |
| OUs | `IT` (`Admins`, `Helpdesk`), `HR`, `Finance`, `Contractors` |
| Test fixtures | `sjohnson`, `kpark` -- intentionally disabled accounts reserved for account-lifecycle testing |

The two repos stay separate on purpose: `homelab-ad-ds` is the one-time
build of the domain itself (OU/user provisioning, GPOs, a troubleshooting
log). This repo is the recurring operational tooling that runs *against*
that domain afterward -- different lifecycle, different audience when
someone's reviewing the portfolio. See `docs/DECISIONS.md` for the full
reasoning.

## Repo layout

```
sysadmin-automation-toolkit/
├── README.md
├── .gitignore
├── docs/
│   ├── DECISIONS.md      # running design decision log (ADR-lite)
│   └── ROADMAP.md
├── powershell/
│   ├── New-BulkUsersFromCsv.ps1
│   ├── Get-PasswordExpiryReport.ps1
│   ├── Test-DiskSpaceAlert.ps1
│   ├── modules/          # shared helper functions (logging, config)
│   └── tests/            # Pester tests
├── bash/
│   ├── rotate-logs.sh
│   ├── backup.sh
│   ├── lib/               # shared shell functions (logging.sh, etc.)
│   └── tests/             # bats tests
└── config/
    └── config.example.json
```

## Decision log

`docs/DECISIONS.md` tracks every meaningful design decision as we make it,
in a lightweight ADR (Architecture Decision Record) format -- context,
decision, reasoning, alternatives considered. It is the "why," kept next
to the code instead of buried in chat history.

## Getting started

```bash
cd sysadmin-automation-toolkit
git init
git add .
git commit -m "Scaffold: repo structure, script stubs, decision log"
git branch -M main
git remote add origin <your-repo-url>
git push -u origin main
```

## Milestones Completed

- [x] Repo scaffolded: directory structure, `docs/` (DECISIONS.md,
      ROADMAP.md), `CHANGELOG.md`, `.gitignore`
- [x] Shared PowerShell logging module built (`Logging.psm1`) --
      timestamped, leveled, console + append-only file
- [x] `Get-PasswordExpiryReport.ps1` built and validated against the
      real lab (`corp.local`, 13-15 accounts depending on run); uses
      `msDS-UserPasswordExpiryTimeComputed` to correctly account for
      Fine-Grained Password Policies; reports `MustChangeAtLogon`
      (`pwdLastSet = 0`) as a distinct category rather than hiding or
      misrepresenting it
- [x] `New-BulkUsersFromCsv.ps1` built and fully validated against the
      lab: `-WhatIf` accuracy confirmed, clean creation confirmed,
      idempotency confirmed on a second identical run, cross-validated
      against `Get-PasswordExpiryReport.ps1` (6 -> 8 flagged accounts,
      exactly as predicted)
- [x] `Test-DiskSpaceAlert.ps1` built and fully verified against the
      lab: per-volume cooldown state (`state/disk-space-alert-state.json`),
      threshold check overridable for testing without filling a disk,
      no distribution channel wired up yet (console + log only, by
      design)
- [x] `TOOLKIT01` built: Ubuntu 26.04.1 LTS (arm64), VMware Fusion,
      SSH-reachable from the Mac -- the real target for the Bash half
      of the toolkit, deliberately not domain-joined (see
      docs/DECISIONS.md for why this is separate from the still-unbuilt
      hybrid-identity LNX01 project)
- [x] Shared Bash logging module built (`bash/lib/logging.sh`,
      `write_log`), matching `Logging.psm1`'s shape so logs read the
      same across both languages
- [x] `rotate-logs.sh` built and fully verified, sandbox AND real
      (TOOLKIT01): copytruncate
      rotation (not rename, so a process with the file already open
      keeps writing correctly), gzip compression, retention pruning,
      `--dry-run`. Two real bugs caught by directly executing the
      script before it ever reached a real machine -- a path the
      PowerShell scripts never had, since there's no PowerShell runtime
      available to run those against
- [x] Shared Bash config-loading module (`bash/lib/config.sh`)
      extracted once `backup.sh` needed the same logic
      `rotate-logs.sh` already had inline; `rotate-logs.sh` refactored
      and regression-tested afterward
- [x] `backup.sh` built and fully verified, sandbox AND real
      (TOOLKIT01): tar+gzip with relative paths (not absolute, so
      restores don't fight you), verification via an independent
      read-back rather than trusting the write's exit code, retention
      pruning, `--dry-run`. No bugs found on either pass -- the first
      script in either language to work correctly the first time
- [x] **All 5 scripts from the original project card are now built and
      fully verified against real environments**: AD user creation,
      password expiry reporting, disk space alert, log rotation, and
      backup. This closes the literal scope of the original project.
- [x] Test harness fully verified: **13 bats tests + 11 Pester tests,
      all passing** (`rotate-logs.bats`, `backup.bats`,
      `Get-PasswordExpiryCategory.Tests.ps1`). Extracted
      `Get-PasswordExpiryReport.ps1`'s categorization logic into a
      pure, testable function (`modules/PasswordExpiry.psm1`). The
      Pester run took three wrong turns first (Pester scoping/phase
      theories) before the real cause -- a module file that had simply
      never been transferred -- surfaced via a throwaway diagnostic
      test rather than a fourth guess. Both halves of the harness are
      now on equal footing: fully run and passing, not just written.
- [x] Shared config-loading module extracted (`Config.psm1`) once a
      second script needed the same local-vs-example fallback logic
- [x] Cryptographically secure temporary-password generation
      implemented (`RandomNumberGenerator`, not `Get-Random`) for new
      account creation, with forced change-at-next-logon
- [x] Cross-linked to `homelab-ad-ds`; repo-separation and
      documentation-consistency decisions made and logged
- [x] Three real bugs found through empirical testing against the lab --
      none caught by code review alone -- root-caused, fixed, and
      verified with a second lab run each:
  * A PowerShell array-unwrapping issue (`.Count` unreliable on a 0- or
    1-item pipeline result)
  * A truthy/falsy coercion bug (`-not $ExpiryRaw`) that silently
    swallowed every `pwdLastSet = 0` account, making an entire report
    category unreachable from the day it was written
  * A `[DateTime]` Kind mismatch that silently reinterpreted a stored
    UTC timestamp as local time, making the disk-alert cooldown's
    elapsed-time math wrong by a full timezone offset -- fixed by
    switching to Unix epoch seconds, which removes the bug class
    rather than one instance of it

## In Progress / Next Steps

- [ ] Resolve blank `DisplayName` on `jsmith`/`mgarcia`/`edavis`
      (existing lab accounts, predates this toolkit) -- diagnostic
      query given, results pending
- [ ] Pester tests for `New-BulkUsersFromCsv.ps1` and
      `Test-DiskSpaceAlert.ps1` -- needs `Mock` for AD/`Get-Volume`
      calls, not started
- [ ] CI (GitHub Actions) running tests on push -- once there are tests
      to run

See `docs/ROADMAP.md` for the full task-level breakdown.
