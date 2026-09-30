#!/usr/bin/env bats
#
# Tests for rotate-logs.sh. Run with: bats bash/tests/rotate-logs.bats
#
# These encode the exact scenarios verified manually during development
# -- including the two real bugs found and fixed on 2026-09-29 (see
# docs/DECISIONS.md) -- as permanent regression tests, so neither can
# silently come back if this file gets touched again later.

setup() {
    TEST_DIR="$(mktemp -d)"
    REPO_DIR="$TEST_DIR/repo"
    mkdir -p "$REPO_DIR/bash/lib" "$REPO_DIR/config" "$TEST_DIR/target"

    # BATS_TEST_DIRNAME is bats' own variable for the directory
    # containing this .bats file -- used to find the real script under
    # test relative to wherever the suite itself is invoked from.
    cp "$BATS_TEST_DIRNAME/../rotate-logs.sh" "$REPO_DIR/bash/"
    cp "$BATS_TEST_DIRNAME/../lib/logging.sh" "$REPO_DIR/bash/lib/"
    cp "$BATS_TEST_DIRNAME/../lib/config.sh" "$REPO_DIR/bash/lib/"
    chmod +x "$REPO_DIR/bash/rotate-logs.sh"

    SCRIPT="$REPO_DIR/bash/rotate-logs.sh"
    TARGET="$TEST_DIR/target/app.log"

    cat > "$REPO_DIR/config/logrotate.conf.local" << EOF
LOG_TARGET_FILE="$TARGET"
MAX_SIZE_MB=0
RETENTION_DAYS=30
EOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "dry run does not modify the target file or create an archive" {
    printf 'line one\nline two\n' > "$TARGET"
    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN] Would copy"* ]]
    [ "$(stat -c%s "$TARGET")" -gt 0 ]
    [ "$(find "$TEST_DIR/target" -name '*.gz' | wc -l)" -eq 0 ]
}

@test "rotates and truncates when the file exceeds threshold" {
    printf 'line one\nline two\nline three\n' > "$TARGET"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated to"* ]]
    [ "$(stat -c%s "$TARGET")" -eq 0 ]
    [ "$(find "$TEST_DIR/target" -name '*.gz' | wc -l)" -eq 1 ]
}

@test "the archive actually contains the original content" {
    printf 'line one\nline two\nline three\n' > "$TARGET"
    "$SCRIPT"
    archive="$(find "$TEST_DIR/target" -name '*.gz')"
    result="$(zcat "$archive")"
    [ "$result" = "$(printf 'line one\nline two\nline three')" ]
}

@test "regression: an empty file is not rotated again (bug fixed 2026-09-29)" {
    printf 'content\n' > "$TARGET"
    "$SCRIPT"       # first run rotates and empties the file
    run "$SCRIPT"   # second run, against the now-empty file
    [ "$status" -eq 0 ]
    [[ "$output" == *"empty, nothing to rotate"* ]]
    # Still exactly one archive -- the original bug produced a second,
    # useless empty one here.
    [ "$(find "$TEST_DIR/target" -name '*.gz' | wc -l)" -eq 1 ]
}

@test "regression: retention pruning runs even when nothing was rotated (bug fixed 2026-09-29)" {
    printf 'content\n' > "$TARGET"
    "$SCRIPT"   # rotate once; file is now empty

    echo "old" > "$TEST_DIR/target/app.log.20200101-000000.gz"
    touch -d "40 days ago" "$TEST_DIR/target/app.log.20200101-000000.gz"

    # File stays empty this run -- nothing to rotate -- but pruning must
    # still execute. Before the fix, every early exit skipped it.
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"empty, nothing to rotate"* ]]
    [[ "$output" == *"Deleted old archive"* ]]
    [ ! -f "$TEST_DIR/target/app.log.20200101-000000.gz" ]
}

@test "retention keeps archives within the window" {
    printf 'content\n' > "$TARGET"
    "$SCRIPT"

    echo "recent" > "$TEST_DIR/target/app.log.20260924-000000.gz"
    touch -d "5 days ago" "$TEST_DIR/target/app.log.20260924-000000.gz"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/target/app.log.20260924-000000.gz" ]
}

@test "a missing target file logs a warning without erroring" {
    rm -f "$TARGET"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"does not exist"* ]]
}
