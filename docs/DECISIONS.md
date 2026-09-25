# Decision Log

Lightweight ADR (Architecture Decision Record) format. Every meaningful
design decision made while building this toolkit gets an entry: context,
decision, reasoning, alternatives considered, status. This is the "why,"
kept in the repo so it survives independently of any one conversation.

Template for new entries:

```
## YYYY-MM-DD -- Short title

**Context:** What problem/question prompted this decision.

**Decision:** What was decided.

**Reasoning:** Why, and what alternatives were considered.

**Status:** Proposed / Accepted / Superseded by ADR-XXXX

**Open questions / follow-ups:**
- [ ] ...
```

---

## 2026-09-11 -- Repo structure & project scope

**Context:** Kicking off the "Sysadmin automation scripts" project (5
scripts: 3 PowerShell targeting Windows/AD, 2 Bash targeting Linux) from
the project tracker. Needed a structure that could hold ongoing design
decisions, not just code.

**Decision:** One toolkit repo, split by language (`powershell/`,
`bash/`), with shared `docs/` for the decision log and roadmap.

**Reasoning:**
- One repo keeps the portfolio narrative coherent -- "an ops automation
  toolkit" reads better than five unrelated single-script repos.
- Split by language rather than mixed together: PowerShell and Bash have
  different test tooling (Pester vs. bats), different naming conventions
  (approved Verb-Noun vs. snake_case), and mostly do not share code, so
  keeping them in separate folders avoids confusion.
- Decision log lives in the repo, not just in chat, so the reasoning is
  visible to anyone reviewing the code later -- including future me.

**Status:** Accepted

**Open questions / follow-ups:**
- [x] Confirm target test environment -- dedicated AD/Windows lab VM
- [x] Decide the shared logging approach -- see 2026-09-11 entry below
- [ ] Decide alert/notification channel for `Test-DiskSpaceAlert.ps1`
      (email? webhook? something else?)
- [ ] Decide backup destination and verification method for `backup.sh`


## 2026-09-11 -- Shared logging convention (PowerShell)

**Context:** Every script needs an audit trail, and it is much cheaper to
build this once than to retrofit it into five scripts later. Building
`Get-PasswordExpiryReport.ps1` first made this the natural moment.

**Decision:** `powershell/modules/Logging.psm1` exports a single
`Write-Log` function: timestamped, leveled (INFO/WARN/ERROR), writes to
both console (color-coded) and an append-only log file under `logs/`.

**Reasoning:**
- File output matters more than console output in practice -- a
  scheduled task has no one watching the console, so the file is the
  only record a run happened at all.
- Append-only (not overwrite) so the log is a history, not a snapshot.
- Kept deliberately small (one function, three levels) rather than
  pulling in a logging framework -- this is five scripts, not a
  distributed system.
- The Bash side will get an equivalent `lib/logging.sh` with the same
  shape (timestamp, level, console + file) so the two languages produce
  visually consistent logs, even though the implementations differ.

**Status:** Accepted

---

## 2026-09-11 -- Password expiry computation and report scope

**Context:** Building `Get-PasswordExpiryReport.ps1` against the lab AD.

**Decision:**
- Use `msDS-UserPasswordExpiryTimeComputed` instead of computing
  `pwdLastSet + MaxPasswordAge` manually.
- Exclude disabled accounts by default (`-IncludeDisabled` opts back in).
- Treat this script as strictly read-only: no `-WhatIf`, no idempotency
  handling -- neither applies when nothing is mutated.
- Ship without an email/notification channel for now; just a report
  (console + optional `-OutputCsv`).

**Reasoning:**
- Manual expiry math breaks under Fine-Grained Password Policies (FGPP),
  which override the domain default per OU/group. The computed attribute
  gets this right; hand-rolled math would be silently wrong for anyone
  under a non-default policy.
- A disabled account's password expiring is not actionable by anyone --
  reporting it by default would just be noise.
- Adding an email/Slack/etc. distribution channel now would be building
  a feature before we know which channel is actually wanted -- that
  decision is deferred, not forgotten (tracked in ROADMAP.md).

**Status:** Accepted

**Open questions / follow-ups:**
- [ ] Validate the sentinel-value handling (`0` and `Int64.MaxValue` for
      msDS-UserPasswordExpiryTimeComputed) against real accounts in the
      lab -- confirm both cases actually occur as expected
- [ ] Decide a distribution channel once the report itself is validated


## 2026-09-11 -- Target environment confirmed; relationship to homelab-ad-ds

**Context:** A real AD lab already exists --
[`homelab-ad-ds`](https://github.com/SynsmyrF2001/homelab-ad-ds): domain
`corp.local`, DC01 at 192.168.64.10, an OU structure (`IT/Admins`,
`IT/Helpdesk`, `HR`, `Finance`, `Contractors`), and 10 provisioned users
including two intentionally-disabled fixtures (`sjohnson`, `kpark`).

**Decision:** Keep `homelab-ad-ds` and this repo separate, cross-linked
via README rather than merged or duplicated.

**Reasoning:**
- `homelab-ad-ds` is a one-time build artifact (provision the domain,
  document the build). This repo is recurring operational tooling that
  runs against an already-built domain -- different lifecycle.
- Duplicating environment details (domain name, OU DNs) into this repo's
  docs would drift the moment the lab changes. Linking to the source of
  truth avoids that; the README table only mirrors what's needed to run
  the scripts.

**Status:** Accepted

**Open questions / follow-ups:**
- [x] `pwdLastSet = 0` handling -- resolved below (2026-09-11, "pwdLastSet
      = 0 handling")
- [ ] `sjohnson` / `kpark` are disabled -- doesn't confirm anything about
      the `pwdLastSet = 0` path specifically; still need an *enabled*
      fixture in that state to see the new MustChangeAtLogon category
      actually populate
- [ ] Freshly provisioned accounts likely will NOT fall inside a 14-day
      warning window yet -- an empty report on first run is expected,
      not necessarily a bug


## 2026-09-11 -- pwdLastSet = 0 handling

**Context:** `msDS-UserPasswordExpiryTimeComputed` returns 0 when
`pwdLastSet = 0` ("must change password at next logon"). The original
scaffold silently skipped this case along with the "never expires"
sentinel. Two options considered: keep skipping it, or report it as
"already expired."

**Decision:** Neither. Added a third category, `MustChangeAtLogon`,
reported separately from `ExpiringSoon` in the same output (console
table and CSV both carry a `Category` column), sorted to the top since
it's the most immediate of the two.

**Reasoning:**
- Silently skipping it hides the single most urgent state an account can
  be in -- defeats the purpose of a report meant to catch risk before it
  becomes a problem.
- Folding it into "expiring soon" with a fake day-count (e.g. "0 days
  remaining") misrepresents it -- it isn't a countdown, it's already true
  right now, and conflating the two makes the "days remaining" column
  meaningless for anyone scanning the report quickly.
- A distinct category preserves the information without corrupting the
  one column (`DaysRemaining`) that the "expiring soon" rows depend on to
  be sorted and acted on sensibly.

**Status:** Accepted

**Bug caught while implementing this:** switching `$Report` from an
implicit `foreach`-yielded array to a `List[object]`, then piping it
through `Sort-Object` and reassigning, reintroduces PowerShell's
array-unwrapping behavior -- a single-item result becomes a bare object
(no `.Count`) and an empty result becomes `$null`. Wrapped every such
reassignment in `@()`. Matters concretely here: a 10-account lab makes 0
or 1 matches the *likely* case, not the edge case.


## 2026-09-25 -- Bug: pwdLastSet = 0 accounts were being skipped, not categorized

**Context:** First real run against the lab (`-WarningDays 9999`)
surfaced a contradiction. Raw `Get-ADUser` output showed 6 enabled
accounts (`dchen`, `sjohnson`, `mbrown`, `jwilson`, `rtaylor`, `anguyen`)
with `msDS-UserPasswordExpiryTimeComputed = 0`, but the script's own log
line reported "0 flagged must-change-at-next-logon."

**Root cause:**

```
if (-not $ExpiryRaw -or $ExpiryRaw -eq [Int64]::MaxValue) { continue }
```

PowerShell treats integer `0` as boolean `$false`, so `-not $ExpiryRaw`
evaluates to `$true` when `$ExpiryRaw` is exactly `0`. This `continue`
fired before execution ever reached the dedicated `$ExpiryRaw -eq 0`
branch a few lines below -- the entire `MustChangeAtLogon` category
(added 2026-09-11) was unreachable dead code from the moment it was
written. Same class of coercion bug as the array-unwrapping issue caught
earlier, but more damaging: it silently defeated the exact feature it
was sitting next to, and passed a structural sanity check because
nothing about the bug is a syntax error.

**Fix:** Explicit null check instead of a truthy/falsy one:

```
if ($null -eq $ExpiryRaw -or $ExpiryRaw -eq [Int64]::MaxValue) { continue }
```

`$null` on the left is also the idiomatic PowerShell convention -- it
avoids a related, separate gotcha where `$collection -eq $null` filters
a collection instead of doing a scalar comparison, for anything that
isn't already guaranteed to be a single value.

**Status:** Fixed and verified against the lab, 2026-09-25 10:38 --
re-run shows 6/6 expected accounts (`rtaylor`, `mbrown`, `jwilson`,
`sjohnson`, `anguyen`, `dchen`) correctly categorized `MustChangeAtLogon`
and sorted first, with the same 3 `ExpiringSoon` rows unchanged beneath
them.

**Also observed while reading this output (informational, not a script
bug):**
- `jsmith`, `mgarcia`, `edavis` have no `DisplayName` set in AD -- the
  report correctly shows it blank; this reflects the source data, not a
  script defect.
- Live data shows `sjohnson` as `Enabled = True`, though
  `homelab-ad-ds`'s README lists it as an intentionally disabled fixture
  alongside `kpark`. Only `kpark` is actually disabled right now --
  worth reconciling over there; unrelated to this repo, noted here only
  because it's how it surfaced.

**Lesson:** this bug shipped in the same commit as the fix for a
different coercion bug (the array-unwrapping one), in code that was
read multiple times before this response. Reasoning about PowerShell's
truthy/falsy rules line-by-line didn't catch it; running it against real
data with real zero values did. Empirical testing against the lab is
pulling more weight here than code review is -- worth keeping that
asymmetry in mind for the remaining scripts.


## 2026-09-25 -- New-BulkUsersFromCsv.ps1: password handling, idempotency, and validation posture

**Context:** First mutating script in the toolkit -- everything built so
far only read AD. This one creates accounts, so `-WhatIf`, idempotency,
and failure handling all matter for real here in a way they didn't for
the read-only report.

**Decisions:**

1. **No passwords in the CSV.** The script generates a cryptographically
   random, policy-compliant temporary password per account
   (`RandomNumberGenerator`, not `Get-Random`, which is a fast PRNG, not
   built for anything credential-shaped) and forces
   `ChangePasswordAtLogon`. Matches the lab's existing convention -- 6 of
   8 real accounts are already in that state.

2. **Idempotency via `-Identity` + a specific caught exception type,
   not a string-built `-Filter`.** Interpolating CSV data into a filter
   string is the AD-filter equivalent of concatenating SQL -- untrusted
   input going straight into a query. `-Identity` accepts a bare
   SamAccountName directly, and catching
   `ADIdentityNotFoundException` specifically distinguishes "doesn't
   exist yet" (expected, proceed) from any other failure (not safe to
   assume, don't proceed).

3. **Two different failure postures, on purpose.** CSV validation
   happens in full before any account is created -- one bad row halts
   the whole run, because there's no reason to create accounts 1-46 and
   then discover row 47 is broken. Once creation actually starts, one
   row failing does NOT stop the batch -- it's logged and the rest
   proceed, because by then each row is an independent operation, not a
   precondition for the others.

4. **`-DisplayName` set explicitly**, not left to `-Name` to imply it.
   `New-ADUser` does not auto-populate DisplayName from `-Name` -- this
   is almost certainly why `jsmith`/`mgarcia`/`edavis` showed a blank
   DisplayName when `Get-PasswordExpiryReport.ps1` was tested against
   the lab. Explicit here so this script doesn't produce the same gap.

**Status:** Accepted, pending validation against the lab (`-WhatIf`
first, per the sample CSV at `config/sample-new-users.csv`, targeting
the real `Contractors` OU).
