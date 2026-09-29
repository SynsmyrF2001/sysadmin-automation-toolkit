#!/usr/bin/env bash
#
# backup.sh
#
# Backs up a source directory to a timestamped, gzip-compressed tar
# archive, VERIFIES the archive afterward by actually reading it back
# (not just trusting tar's own exit code), and prunes backups older
# than a retention window.
#
# "Verify" means re-opening the archive and listing its contents
# (tar -tzf) as a separate pass after writing it. A backup that only
# checks "did the write command exit 0" is confirming the tool didn't
# crash, not that the file it produced is a valid, readable archive --
# those are different claims, and the second one is the one that
# matters the day someone actually needs to restore from this.
#
# v1 scope: local destination only, one source directory archived
# whole. Remote destinations (rsync/scp to another host) are a natural
# extension once there's a second machine in the lab to receive them --
# not built yet since there isn't one to test against.
#
# Usage: ./backup.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/config.sh"

LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/backup_$(date +%Y%m%d).log"

DRY_RUN=false
for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
        DRY_RUN=true
    fi
done

if [ "$DRY_RUN" = true ]; then
    write_log INFO "Starting backup (dry run)" "$RUN_LOG"
else
    write_log INFO "Starting backup" "$RUN_LOG"
fi

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

CONFIG_DIR="$REPO_ROOT/config"
if ! load_toolkit_config "$CONFIG_DIR" "backup"; then
    write_log ERROR "No config found at $CONFIG_DIR/backup.conf.local or .example" "$RUN_LOG"
    exit 1
fi

: "${BACKUP_SOURCE_DIR:?BACKUP_SOURCE_DIR not set in config}"
: "${BACKUP_DEST_DIR:?BACKUP_DEST_DIR not set in config}"
: "${RETENTION_DAYS:=30}"

write_log INFO "Source: $BACKUP_SOURCE_DIR; Destination: $BACKUP_DEST_DIR; Retention: ${RETENTION_DAYS} days" "$RUN_LOG"

if [ ! -d "$BACKUP_SOURCE_DIR" ]; then
    write_log ERROR "Source directory $BACKUP_SOURCE_DIR does not exist" "$RUN_LOG"
    exit 1
fi

mkdir -p "$BACKUP_DEST_DIR"

timestamp="$(date +%Y%m%d-%H%M%S)"
source_base="$(basename "$BACKUP_SOURCE_DIR")"
archive_path="$BACKUP_DEST_DIR/${source_base}_${timestamp}.tar.gz"

# ---------------------------------------------------------------------------
# Create the archive
# ---------------------------------------------------------------------------

if [ "$DRY_RUN" = true ]; then
    write_log INFO "[DRY RUN] Would archive $BACKUP_SOURCE_DIR to $archive_path" "$RUN_LOG"
else
    # -C into the parent directory and archive just the leaf name, so
    # the archive contains relative paths (toolkit-demo/file) instead
    # of absolute ones (/etc/toolkit-demo/file). An archive full of
    # absolute paths fights you on restore -- extracting it tries to
    # write back to those exact absolute locations instead of wherever
    # you actually want it this time.
    tar -czf "$archive_path" -C "$(dirname "$BACKUP_SOURCE_DIR")" "$source_base"
    write_log INFO "Archive created: $archive_path" "$RUN_LOG"
fi

# ---------------------------------------------------------------------------
# Verify -- read the archive back, don't just trust tar's exit code
# ---------------------------------------------------------------------------

if [ "$DRY_RUN" = true ]; then
    write_log INFO "[DRY RUN] Would verify $archive_path by listing its contents" "$RUN_LOG"
else
    if [ ! -s "$archive_path" ]; then
        write_log ERROR "Verification failed: $archive_path is missing or empty" "$RUN_LOG"
        exit 1
    fi

    # pipefail (part of `set -euo pipefail` above) is what makes this
    # actually catch a corrupted archive: without it, a pipeline's exit
    # status is just the LAST command's (wc -l, which succeeds
    # regardless of whether tar did), silently hiding a tar failure
    # behind a successful-looking word count.
    file_count=$(tar -tzf "$archive_path" | wc -l)

    if [ "$file_count" -eq 0 ]; then
        write_log ERROR "Verification failed: $archive_path contains no files" "$RUN_LOG"
        exit 1
    fi

    write_log INFO "Verified: $archive_path readable, $file_count entries" "$RUN_LOG"
fi

# ---------------------------------------------------------------------------
# Prune backups older than the retention window
# ---------------------------------------------------------------------------

pruned_count=0
if [ -d "$BACKUP_DEST_DIR" ]; then
    while IFS= read -r -d '' old_backup; do
        if [ "$DRY_RUN" = true ]; then
            write_log INFO "[DRY RUN] Would delete old backup: $old_backup" "$RUN_LOG"
        else
            rm -f "$old_backup"
            write_log INFO "Deleted old backup: $old_backup" "$RUN_LOG"
        fi
        pruned_count=$((pruned_count + 1))
    done < <(find "$BACKUP_DEST_DIR" -maxdepth 1 -name "${source_base}_*.tar.gz" -mtime "+${RETENTION_DAYS}" -print0)
fi

write_log INFO "Backup complete -- $pruned_count old backup(s) pruned" "$RUN_LOG"
