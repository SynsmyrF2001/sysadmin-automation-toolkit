# lib/

Shared shell functions used by more than one script in `bash/`.

- `logging.sh` -- `write_log`: timestamped, leveled (INFO/WARN/ERROR)
  logging to console (color-coded) + an append-only file, matching
  `powershell/modules/Logging.psm1`'s shape. Source it, then call
  `write_log LEVEL "message" "/path/to/file.log"`.
