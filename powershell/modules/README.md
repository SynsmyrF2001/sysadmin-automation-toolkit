# modules/

Shared PowerShell helper functions used by more than one script in this
repo.

- `Logging.psm1` -- `Write-Log`: timestamped, leveled (INFO/WARN/ERROR)
  logging to console + an append-only file under `logs/`. See
  docs/DECISIONS.md (2026-09-11, "Shared logging convention") for why it
  is shaped this way.
