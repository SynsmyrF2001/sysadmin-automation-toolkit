# tests/ (Bash)

bats tests for the scripts in `bash/`. Both suites are fully verified
-- run and passing, not just written.

- `rotate-logs.bats` -- 7 tests, including permanent regression tests
  for both real bugs found and fixed 2026-09-29 (docs/DECISIONS.md): an
  empty file being rotated forever under a low threshold, and retention
  pruning silently never running on days without a fresh rotation.
- `backup.bats` -- 6 tests, including archive content verification and
  a permission-independent failure test (a file, not a permissions
  restriction, sits where the destination directory should be -- root,
  which bats commonly runs as, ignores permission bits, so a
  chmod-based test would pass for the wrong reason).

Install bats if it's not already present:

```bash
sudo apt-get install -y bats
```

Run with:

```bash
bats bash/tests/rotate-logs.bats
bats bash/tests/backup.bats
```
