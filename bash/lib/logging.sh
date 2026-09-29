#!/usr/bin/env bash
#
# lib/logging.sh
#
# Shared logging function for this repo's Bash scripts -- the same shape
# as powershell/modules/Logging.psm1's Write-Log: timestamped, leveled
# (INFO/WARN/ERROR), console (color-coded) + an append-only log file.
# The file is what matters most in practice: a cron job has no one
# watching the console, so the file is the only record a run happened.
#
# Usage: source this file, then call:
#   write_log INFO  "message" "/path/to/file.log"
#   write_log WARN  "message" "/path/to/file.log"
#   write_log ERROR "message" "/path/to/file.log"
#
# The log directory itself is the CALLER's responsibility to create
# (mkdir -p) before the first call -- same split of responsibility as
# the PowerShell side.

write_log() {
    # "local" is not optional here the way it might look. Bash function
    # variables are GLOBAL by default unless explicitly declared local
    # -- the opposite of most languages, and the opposite of PowerShell,
    # where a function's variables are already scoped to it. Skipping
    # "local" here would let this function silently clobber a variable
    # of the same name in whatever script sources it.
    local level="$1"
    local message="$2"
    local log_path="$3"

    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local line="[$timestamp] [$level] $message"

    # Color-code by level so problems are visually obvious in an
    # interactive run. \033[0m resets afterward so the color doesn't
    # bleed into whatever prints next in the terminal.
    case "$level" in
        ERROR) echo -e "\033[0;31m${line}\033[0m" ;;
        WARN)  echo -e "\033[0;33m${line}\033[0m" ;;
        *)     echo "$line" ;;
    esac

    # Append, not overwrite -- each run adds to the history instead of
    # erasing the last run's record. This IS the audit trail.
    echo "$line" >> "$log_path"
}
