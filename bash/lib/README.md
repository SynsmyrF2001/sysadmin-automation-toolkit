# lib/

Shared shell functions used by more than one script in `bash/`.

- `logging.sh` -- `write_log`: timestamped, leveled (INFO/WARN/ERROR)
  logging to console (color-coded) + an append-only file, matching
  `powershell/modules/Logging.psm1`'s shape. Source it, then call
  `write_log LEVEL "message" "/path/to/file.log"`.
- `config.sh` -- `load_toolkit_config`: the local-then-example fallback
  chain, matching `powershell/modules/Config.psm1`. Source it, then
  call `load_toolkit_config "/path/to/config/dir" "basename"`.
