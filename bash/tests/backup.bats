#!/usr/bin/env bats
#
# Tests for backup.sh. Run with: bats bash/tests/backup.bats

setup() {
    TEST_DIR="$(mktemp -d)"
    REPO_DIR="$TEST_DIR/repo"
    mkdir -p "$REPO_DIR/bash/lib" "$REPO_DIR/config"
    mkdir -p "$TEST_DIR/source/subdir" "$TEST_DIR/dest"

    cp "$BATS_TEST_DIRNAME/../backup.sh" "$REPO_DIR/bash/"
    cp "$BATS_TEST_DIRNAME/../lib/logging.sh" "$REPO_DIR/bash/lib/"
    cp "$BATS_TEST_DIRNAME/../lib/config.sh" "$REPO_DIR/bash/lib/"
    chmod +x "$REPO_DIR/bash/backup.sh"

    SCRIPT="$REPO_DIR/bash/backup.sh"

    echo "file one" > "$TEST_DIR/source/file1.txt"
    echo "file two" > "$TEST_DIR/source/subdir/file2.txt"

    cat > "$REPO_DIR/config/backup.conf.local" << EOF
BACKUP_SOURCE_DIR="$TEST_DIR/source"
BACKUP_DEST_DIR="$TEST_DIR/dest"
RETENTION_DAYS=30
EOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "dry run creates no archive" {
    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN] Would archive"* ]]
    [ "$(find "$TEST_DIR/dest" -name '*.tar.gz' | wc -l)" -eq 0 ]
}

@test "creates a verified archive using relative, not absolute, paths" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Verified:"* ]]
    archive="$(find "$TEST_DIR/dest" -name '*.tar.gz')"
    [ -n "$archive" ]
    listing="$(tar -tzf "$archive")"
    [[ "$listing" == *"source/file1.txt"* ]]
    # The absolute source path must NOT appear in the archive -- that's
    # the whole point of the -C flag in the script.
    [[ "$listing" != *"$TEST_DIR/source/file1.txt"* ]]
}

@test "the archive actually contains the real file content" {
    "$SCRIPT"
    archive="$(find "$TEST_DIR/dest" -name '*.tar.gz')"
    extract_dir="$(mktemp -d)"
    tar -xzf "$archive" -C "$extract_dir"
    [ "$(cat "$extract_dir/source/file1.txt")" = "file one" ]
    [ "$(cat "$extract_dir/source/subdir/file2.txt")" = "file two" ]
    rm -rf "$extract_dir"
}

@test "fails loudly rather than reporting success when the destination can't be created" {
    # A regular file sitting where the destination directory should be
    # -- mkdir -p genuinely cannot succeed here. Deliberately NOT using
    # chmod for this: bats commonly runs as root in CI, and root ignores
    # permission bits, which would make a permissions-based test pass
    # for the wrong reason (or not at all).
    rm -rf "$TEST_DIR/dest"
    touch "$TEST_DIR/dest"
    run "$SCRIPT"
    [ "$status" -ne 0 ]
}

@test "a missing source directory fails loudly" {
    rm -rf "$TEST_DIR/source"
    run "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "retention prunes old backups but keeps recent ones" {
    "$SCRIPT"   # creates today's real backup

    echo "old" > "$TEST_DIR/dest/source_20200101-000000.tar.gz"
    touch -d "40 days ago" "$TEST_DIR/dest/source_20200101-000000.tar.gz"
    echo "recent" > "$TEST_DIR/dest/source_20260924-000000.tar.gz"
    touch -d "5 days ago" "$TEST_DIR/dest/source_20260924-000000.tar.gz"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_DIR/dest/source_20200101-000000.tar.gz" ]
    [ -f "$TEST_DIR/dest/source_20260924-000000.tar.gz" ]
}
