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
  alongside `kpark`. Only `kpark` is actually disabled right now.
  **Decision (2026-09-25): leave both as they are.** Not touching
  `sjohnson`'s state and not editing `homelab-ad-ds`'s docs to match --
  the drift is known, doesn't block anything in this repo, and is noted
  here rather than "resolved" for its own sake.

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

**Status:** Fully verified against the lab, 2026-09-25 19:42 --
`-WhatIf` correctly showed both target operations with nothing created;
the real run created `amartinez` and `jlee2` cleanly; a second identical
run correctly skipped both (`0 created, 2 skipped, 0 failed`), confirming
idempotency rather than just asserting it in a comment.

Bonus cross-validation: `Get-PasswordExpiryReport.ps1`, re-run after
creation, went from 6 to 8 accounts flagged `MustChangeAtLogon` --
`amartinez` and `jlee2` picked up exactly as expected, since
`ChangePasswordAtLogon = $true` at creation sets `pwdLastSet = 0` under
the hood. Two independently-built scripts agreeing about the same AD
state. Also visible in that same output: `amartinez`/`jlee2` show real
`DisplayName` values next to `jsmith`/`edavis`/`mgarcia`, which are
still blank -- direct evidence the explicit `-DisplayName` decision
above actually closes the gap it was meant to close.


## 2026-09-25 -- DisplayName gap on jsmith/mgarcia/edavis: root cause confirmed

**Context:** `Get-PasswordExpiryReport.ps1` showed blank `DisplayName`
for `jsmith`, `mgarcia`, `edavis` when first tested against the lab.
Diagnosed rather than assumed: queried `GivenName`/`Surname`/`DisplayName`
directly.

**Finding:** `GivenName`/`Surname` are correctly populated (John Smith,
Maria Garcia, Emily Davis) -- only `DisplayName` is empty. Confirms the
theory from `New-BulkUsersFromCsv.ps1`'s design: these accounts were
almost certainly created via `New-ADUser` with `-GivenName`/`-Surname`
set but no explicit `-DisplayName`, which `New-ADUser` does not derive
automatically.

**Decision:** Fix by deriving `DisplayName` from each account's own
existing `GivenName`/`Surname` (not hardcoded literal names) -- single
source of truth, no risk of a typo introducing new bad data while fixing
old bad data:

```
'jsmith','mgarcia','edavis' | ForEach-Object {
    $User = Get-ADUser -Identity $_ -Properties GivenName,Surname
    Set-ADUser -Identity $_ -DisplayName "$($User.GivenName) $($User.Surname)"
}
```

This is a one-time data remediation for pre-existing accounts, not a
toolkit script -- not added to `powershell/`, since there's no recurring
need for it once applied.

**Status:** Fix identified, not applied. Explicitly deprioritized
2026-09-29 in favor of finishing `backup.sh` and the test harness --
not abandoned because the fix is wrong, just not worth further time
right now. The one-liner above is still valid whenever it's picked back
up.


## 2026-09-25 -- Test-DiskSpaceAlert.ps1: state, cooldown, and shared config

**Context:** First script with no AD involvement at all -- local system
monitoring, meant to run repeatedly on a schedule (e.g. every 15
minutes via Task Scheduler). That repetition introduces a problem
neither prior script had: without memory between runs, a volume stuck
below threshold would re-alert every single run, forever, for the same
unresolved problem.

**Decisions:**

1. **A small local JSON state file** (`state/disk-space-alert-state.json`,
   new top-level `state/` directory -- distinct from `config/`, which is
   user-set, and `logs/`, which is an audit trail) tracks each volume's
   last-alert timestamp. Below threshold + within the configured
   cooldown window = suppress; the alert already fired recently for the
   same problem.

2. **Cooldown state clears once a volume recovers above threshold**,
   rather than just expiring on a timer. Without this, a volume that
   dips, alerts, recovers, and dips again shortly after would stay
   suppressed by the old timestamp -- silencing a genuinely new
   occurrence of the problem because an old one happened to be recent.

3. **No distribution channel (email/webhook) for v1** -- alerts are a
   loud console line plus an ERROR-level log entry. Same reasoning as
   deferring email on `Get-PasswordExpiryReport.ps1`: the detection and
   cooldown logic is the part worth getting right first and is fully
   testable without one. `-Volumes`/`-WarningThresholdPercent` are
   plumbed as parameters specifically so a channel can be added later
   without restructuring anything.

4. **No `-WhatIf` / `SupportsShouldProcess`.** Unlike the AD scripts,
   this one only ever mutates its own local state and log files, not a
   shared system of record -- there's nothing for a dry run to
   meaningfully preview.

5. **`-WarningThresholdPercent` as an overridable parameter, not just a
   config value** -- same reason `Get-PasswordExpiryReport.ps1` supports
   `-WarningDays 9999`: DC01's disk isn't actually low on space, so
   there's no way to observe the alert path with real data. Setting the
   threshold artificially high (e.g. `-WarningThresholdPercent 95`)
   forces the condition without touching the disk itself.

6. **Extracted `Get-ToolkitConfig` into `powershell/modules/Config.psm1`**,
   removing the config-loading block `Get-PasswordExpiryReport.ps1` had
   inline. This is the second script needing the identical
   local-then-example-then-hardcoded-default fallback chain -- the
   right time to share it, not before (one script needing something
   isn't duplication yet) and not never (a third copy-paste would have
   been).

**Status:** Built and lab-tested, 2026-09-28. Found a real bug during
testing -- see the entry below.

---

## 2026-09-28 -- Bug: cooldown silently ignored due to a DateTime Kind mismatch

**Context:** Testing the cooldown against the lab: forced an alert with
`-WarningThresholdPercent 95`, confirmed the state file wrote a real UTC
timestamp (`"2026-09-28T21:30:32.7484958Z"`), then re-ran the identical
command ~11 minutes later expecting suppression (cooldown = 60 min). It
alerted again.

**Root cause:**

```
$LastAlert = [DateTime]$State[$VolumeLetter].lastAlertUtc
```

A plain `[DateTime]` cast on a `Z`-suffixed ISO 8601 string does not
preserve it as UTC. .NET's default parser converts it to the equivalent
LOCAL time and returns a value labeled `Kind = Local` -- silently, no
error. On DC01 (UTC-7), the stored `21:30:32 UTC` became a `DateTime`
whose numeric value was `14:30:32`, still marked local. Comparing that
against `$Now.ToUniversalTime()` (`21:41:21`, correctly UTC) subtracted
two values measured in different clocks: `21:41:21 - 14:30:32` computed
roughly **7 hours 11 minutes** of elapsed time instead of the real
**~11 minutes** -- comfortably past the 60-minute cooldown, so it fired
again. Confirmed by working the actual numbers from both screenshots,
not just inspecting the code.

This is the same family of bug as the `-not $ExpiryRaw` coercion issue
in `Get-PasswordExpiryReport.ps1` -- PowerShell/.NET doing an implicit,
"helpful" conversion that changes the answer without raising any error
-- but harder to catch by reading the code, since `[DateTime]$string`
looks like it should just work.

**Fix:** Stopped storing (and re-parsing) an ISO string entirely.
State now stores Unix epoch seconds (`lastAlertUnixSeconds`, a plain
integer via `[DateTimeOffset]::ToUnixTimeSeconds()`), compared with
plain subtraction -- there is no timezone left to misinterpret. A
separate `lastAlertUtcDisplay` field keeps a human-readable ISO string
in the state file for anyone glancing at it directly, but the script
itself never reads that field back, so it can't reintroduce the bug.

**Reasoning for epoch over "parse it more carefully":** the correct fix
to the original code (`[DateTime]::Parse($string, $null,
[DateTimeStyles]::RoundtripKind)`) would have worked, but it relies on
every future reader of this file remembering that exact incantation.
Removing the string-parsing step removes the whole bug class rather
than patching one instance of it -- the same reasoning `New-BulkUsersFromCsv.ps1`
used for CSPRNG passwords over `Get-Random`: prefer a fix that makes
the mistake structurally unavailable over one that just corrects this
particular occurrence of it.

**Status:** Fixed and verified against the lab, 2026-09-28 14:51 --
forced alert fired and saved state correctly; a second run ~4 minutes
later correctly computed "4.1 of 60 min elapsed" and suppressed (0
alerts fired), confirming both the epoch-based math and the log message
itself are accurate, not just silent.


## 2026-09-29 -- Shared logging convention (Bash): TOOLKIT01 built, lib/logging.sh written

**Context:** First Bash work in the toolkit. Before any script logic,
needed (1) a real Linux target to test against and (2) the shared
logging piece the PowerShell side already has.

**Environment:** `TOOLKIT01` -- Ubuntu 26.04.1 LTS (arm64), VMware
Fusion, IP `192.168.45.130` (VMware's own NAT network -- separate from
UTM's `192.168.64.x` used by `homelab-ad-ds`; these are two unrelated
hypervisors on the same Mac). SSH confirmed reachable from the Mac's own
Terminal, password auth. Not domain-joined -- deliberately out of scope
for this toolkit; see the earlier decision to keep this separate from
the still-unbuilt hybrid-identity LNX01 project.

**Decision:** `bash/lib/write_log()` matches `Logging.psm1`'s
`Write-Log` shape exactly -- timestamped, leveled (INFO/WARN/ERROR),
console (color-coded) + append-only file -- so logs from both halves of
the toolkit read the same way despite being different languages.

**Two Bash-specific gotchas worth recording, since they're easy to get
wrong silently:**
- Bash function variables are global by default unless declared
  `local` -- the opposite of PowerShell, where a function's variables
  are already scoped to it. Every variable in `write_log` is explicitly
  `local` for this reason.
- Positional parameters (`$1 $2 $3`), not named ones -- Bash has no
  built-in equivalent to PowerShell's `-Level`/`-Message`/`-LogPath`
  parameter binding, so call-site order matters and isn't
  self-documenting the way the PowerShell side is. Documented directly
  in the file's usage comment to compensate.

**Status:** Accepted.


## 2026-09-29 -- rotate-logs.sh: two real bugs caught by actually running it

**Context:** First Bash script with real logic. Unlike every PowerShell
script in this repo, Bash can be executed directly in the sandbox this
gets built in -- so for the first time, testing happened *before*
anything was ever handed over, not only after.

**Design decisions:**
- **Copytruncate, not rename-then-recreate**, for the rotation
  mechanism -- a file descriptor points to an inode, not a path name,
  so renaming a log out from under a process that still has it open
  doesn't stop that process writing into the renamed file. Truncating
  the original in place keeps existing file descriptors valid.
- **Bash-native `KEY=VALUE` config** (`logrotate.conf.example` /
  `.local`), not JSON -- Bash has no built-in JSON parser, and pulling
  in `jq` as a dependency for a simple toolkit script isn't worth it.
  Different format from the PowerShell side's `config.example.json` on
  purpose: same override pattern, native idiom per language.
- **v1 scope is one target file, not a directory of many** -- keeps the
  first version simple; looping over multiple files is a natural
  extension if it's ever needed.

**Bug 1 -- empty files rotated forever.** The threshold check
(`size_bytes -lt max_bytes`) is correct in general, but with a test
override of `MAX_SIZE_MB=0` (the same "crank the threshold" trick used
for the PowerShell scripts), a freshly-truncated 0-byte file still
counted as "at or above threshold" on the very next run, rotating an
empty file into a useless empty archive, forever. **Fix:** an explicit
`size_bytes -eq 0` check that skips rotation regardless of threshold --
an empty file is never worth rotating, no matter how the config is set.

**Bug 2 -- retention pruning silently never ran on most days.** Every
"nothing to rotate" path (`exit 0`) sat *above* the pruning step in the
script, so pruning only ever executed on runs where a fresh rotation
also happened. On a real cron schedule, that means old archives would
almost never get cleaned up -- the exact opposite of what retention is
for. **Fix:** restructured so the rotation checks use if/else and fall
through, rather than exiting; pruning now runs unconditionally at the
end of every invocation, independent of what happened above it. Both
bugs were caught and fixed via direct execution against a real test
harness (an actual file, actual `gzip`, actual backdated mtimes via
`touch -d`) before this file was ever transferred to TOOLKIT01.

**A third apparent bug that wasn't one:** an early attempt to verify
pruning showed 0 files pruned when 1 was expected. Root cause was in
the *test harness*, not the script -- `touch -d "40 days ago" file`
followed immediately by `echo "old" > file` overwrites the file again,
which resets its mtime back to now. Fixed the test by writing content
first and backdating last. Worth recording because it's the same
"which side actually has the bug" discipline this whole project has
run on -- don't assume the newer, less-trusted code is at fault just
because something didn't work.

**Status:** Built and locally verified (rotation, empty-file skip,
retention pruning, and dry-run mode all tested against a real harness).
Pending a first real run against TOOLKIT01 itself.


## 2026-09-29 -- Shared Bash config module; backup.sh built and verified clean

**Context:** `backup.sh` needed the identical local-then-example config
pattern `rotate-logs.sh` already had inline -- the same threshold that
triggered extracting `Config.psm1` on the PowerShell side.

**Decision:** Extracted `bash/lib/config.sh` (`load_toolkit_config`),
refactored `rotate-logs.sh` to use it, re-ran its full regression suite
to confirm nothing broke (it didn't).

**backup.sh design decisions:**
- **Local destination only, one directory, archived whole (v1 scope).**
  Remote destinations (rsync/scp to a second host) are a natural
  extension, not built because there's no second machine in this lab
  to receive them yet -- same "don't build the distribution channel
  before you can test it" reasoning as the disk-alert script's deferred
  notification channel.
- **`tar -C <parent> <leaf>`, not an absolute path**, so the archive
  contains relative paths. An archive full of absolute paths fights you
  on restore -- extraction tries to write back to those exact original
  locations instead of wherever you actually want it that time.
- **Verification is a separate read-back pass** (`tar -tzf`), not trust
  in `tar -czf`'s own exit code. Confirmed this actually matters: a
  truncated archive (simulating an interrupted write) makes `tar -tzf`
  exit non-zero, which `pipefail` (in the `set -euo pipefail` header)
  correctly propagates through the `| wc -l` pipeline rather than
  hiding it behind `wc`'s own successful exit.

**Status:** Built and fully verified against a local test harness --
creation, verification, corruption detection, retention pruning, and
dry-run all tested clean, no bugs found. This is the first script in
either language that worked correctly on the first implementation,
plausibly because `rotate-logs.sh`'s "run maintenance unconditionally,
not behind an early exit" lesson got designed in from the start here
rather than discovered after the fact. Pending a first real run against
TOOLKIT01.

**Milestone:** all 5 scripts from the original project card now exist:
AD user creation, password expiry reporting, disk space alert, log
rotation, and backup -- the first four fully verified against real
environments, this one verified locally and awaiting the same.