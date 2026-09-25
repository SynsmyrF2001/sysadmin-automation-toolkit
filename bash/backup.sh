#!/usr/bin/env bash
#
# backup.sh
#
# STATUS: Scaffold only -- not yet implemented.
#
# Planned behavior: back up a configured set of paths/databases to a
# destination (local, remote, or object storage -- TBD, see
# docs/DECISIONS.md), verify the backup after writing it (not just "the
# copy command exited 0"), and prune backups beyond a retention policy.
# Must support --dry-run.
#
# Design decisions for this script are logged in docs/DECISIONS.md as
# they are made.

set -euo pipefail

# TODO: argument parsing, backup logic, verification, retention pruning
