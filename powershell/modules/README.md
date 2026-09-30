# modules/

Shared PowerShell helper functions used by more than one script in this
repo.

- `Logging.psm1` -- `Write-Log`: timestamped, leveled (INFO/WARN/ERROR)
  logging to console + an append-only file under `logs/`. See
  docs/DECISIONS.md (2026-09-11, "Shared logging convention") for why it
  is shaped this way.
- `Config.psm1` -- `Get-ToolkitConfig`: the local-then-example-then-
  hardcoded-default fallback chain, shared once a second script needed
  it. See docs/DECISIONS.md (2026-09-25, "Test-DiskSpaceAlert.ps1:
  state, cooldown, and shared config") for why it was extracted then and
  not sooner.
- `PasswordExpiry.psm1` -- `Get-PasswordExpiryCategory`: the pure
  categorization logic extracted from `Get-PasswordExpiryReport.ps1`
  specifically so it could be unit tested without live AD access. See
  `powershell/tests/Get-PasswordExpiryCategory.Tests.ps1`.
