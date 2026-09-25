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
| `New-BulkUsersFromCsv.ps1` | Create user accounts in bulk from a CSV | Built -- awaiting lab validation |
| `Get-PasswordExpiryReport.ps1` | Flag accounts nearing password expiry | Verified against lab |
| `Test-DiskSpaceAlert.ps1` | Monitor volumes, alert on low free space | Scaffold |

### Bash (Linux)

| Script | Purpose | Status |
|---|---|---|
| `rotate-logs.sh` | Rotate, compress, and prune application logs | Scaffold |
| `backup.sh` | Back up configured paths/databases, verify, prune | Scaffold |

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

## Status

Actively being built. See `docs/ROADMAP.md` for what is next.
