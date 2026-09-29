#!/usr/bin/env bash
#
# rotate-logs.sh
#
# Rotates a log file once it exceeds a size threshold: copies its
# contents to a timestamped, gzip-compressed archive, then truncates
# the ORIGINAL file in place (does not rename or delete it). Also
# prunes archives older than a retention window.
#
# Copytruncate, not rename-then-recreate: a Unix file descriptor points
# to an inode, not a path name. Renaming app.log to app.log.1 does not
# stop a process that already has app.log open from continuing to write
# into that same (now-renamed) inode -- the data keeps growing
# somewhere no one's watching under the original name. Truncating the
# original file in place means a process's existing file descriptor
# stays valid and its next write lands at offset 0 of the same file.
# The real cost: a small window between copying the content out and
# truncating it, where a line written in that gap could end up
# duplicated in both the archive and the fresh file. Accepted tradeoff
# for a generic script with no way to know which process to signal to
# reopen its handle -- the alternative (create+signal, what logrotate
# does for known services like nginx) needs service-specific
# coordination this script doesn't have.
#
# Usage: ./rotate-logs.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/config.sh"

LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/rotate-logs_$(date +%Y%m%d).log"

DRY_RUN=false
for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
        DRY_RUN=true
    fi
done

if [ "$DRY_RUN" = true ]; then
    write_log INFO "Starting log rotation (dry run)" "$RUN_LOG"
else
    write_log INFO "Starting log rotation" "$RUN_LOG"
fi

# ---------------------------------------------------------------------------
# Config -- plain KEY=VALUE, sourced directly. logrotate.conf.local
# (gitignored) overrides logrotate.conf.example, same override pattern
# as the PowerShell side, different file format since Bash has no
# built-in JSON parser (see the file header notes above for why).
# ---------------------------------------------------------------------------

CONFIG_DIR="$REPO_ROOT/config"
if ! load_toolkit_config "$CONFIG_DIR" "logrotate"; then
    write_log ERROR "No config found at $CONFIG_DIR/logrotate.conf.local or .example" "$RUN_LOG"
    exit 1
fi

# ${VAR:?msg} errors out with msg if VAR is unset or empty -- fails
# loudly on a missing required value instead of silently proceeding
# with an empty path. ${VAR:=default} assigns a default only if VAR is
# unset, so the config file can leave these out and still get a
# sane value.
: "${LOG_TARGET_FILE:?LOG_TARGET_FILE not set in config}"
: "${MAX_SIZE_MB:=10}"
: "${RETENTION_DAYS:=30}"

write_log INFO "Target: $LOG_TARGET_FILE; max size: ${MAX_SIZE_MB}MB; retention: ${RETENTION_DAYS} days" "$RUN_LOG"

# ---------------------------------------------------------------------------
# Check size and rotate if needed. Each "nothing to do" case here logs
# and falls through to pruning below, rather than exiting -- retention
# cleanup is an independent maintenance task that should run every time,
# not only on runs where a rotation also happened to occur.
# ---------------------------------------------------------------------------

if [ ! -f "$LOG_TARGET_FILE" ]; then
    write_log WARN "Target file $LOG_TARGET_FILE does not exist, nothing to rotate" "$RUN_LOG"
else
    # GNU stat (-c%s), not BSD stat -- this targets Linux, where it'll
    # actually run, not macOS.
    size_bytes=$(stat -c%s "$LOG_TARGET_FILE")
    max_bytes=$((MAX_SIZE_MB * 1024 * 1024))

    write_log INFO "Current size: $size_bytes bytes (threshold: $max_bytes bytes)" "$RUN_LOG"

    if [ "$size_bytes" -eq 0 ]; then
        # An empty file has nothing worth rotating, regardless of how
        # low the threshold is configured. Without this check, a
        # threshold of 0 (or a file already rotated down to empty)
        # would rotate a 0-byte file forever, producing a useless empty
        # .gz every single run.
        write_log INFO "Target file is empty, nothing to rotate" "$RUN_LOG"
    elif [ "$size_bytes" -lt "$max_bytes" ]; then
        write_log INFO "Below threshold, no rotation needed" "$RUN_LOG"
    else
        timestamp="$(date +%Y%m%d-%H%M%S)"
        archive_path="${LOG_TARGET_FILE}.${timestamp}.gz"

        if [ "$DRY_RUN" = true ]; then
            write_log INFO "[DRY RUN] Would copy $LOG_TARGET_FILE to $archive_path (gzip) and truncate the original" "$RUN_LOG"
        else
            # Compress to the archive FIRST, truncate the original only
            # after that succeeds -- with set -e, a failure during gzip
            # stops the script before truncation, leaving the original
            # log intact rather than empty with no successful archive
            # to show for it.
            gzip -c "$LOG_TARGET_FILE" > "$archive_path"
            : > "$LOG_TARGET_FILE"
            write_log INFO "Rotated to $archive_path, truncated original in place" "$RUN_LOG"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Prune archives older than the retention window -- always runs, per
# the note above.
# ---------------------------------------------------------------------------

log_target_dir="$(dirname "$LOG_TARGET_FILE")"
log_target_base="$(basename "$LOG_TARGET_FILE")"

pruned_count=0
if [ -d "$log_target_dir" ]; then
    # NUL-delimited find output + read -d '' handles filenames with
    # spaces or other special characters safely -- a plain
    # newline-split loop would break on those.
    while IFS= read -r -d '' old_archive; do
        if [ "$DRY_RUN" = true ]; then
            write_log INFO "[DRY RUN] Would delete old archive: $old_archive" "$RUN_LOG"
        else
            rm -f "$old_archive"
            write_log INFO "Deleted old archive: $old_archive" "$RUN_LOG"
        fi
        pruned_count=$((pruned_count + 1))
    done < <(find "$log_target_dir" -maxdepth 1 -name "${log_target_base}.*.gz" -mtime "+${RETENTION_DAYS}" -print0)
else
    write_log WARN "Target directory $log_target_dir does not exist, skipping prune" "$RUN_LOG"
fi

write_log INFO "Rotation complete -- $pruned_count old archive(s) pruned" "$RUN_LOG"
