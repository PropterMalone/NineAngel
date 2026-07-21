#!/usr/bin/env bash
# pattern: imperative shell
# Pre-commit guard: run both drift detectors and fail fast on the first error.
# Install as a git hook:
#   ln -s ../../scripts/pre-commit.sh .git/hooks/pre-commit
#
# The tracked script (not the untracked hook symlink) is the deliverable —
# any contributor can install it without a separate doc step.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== pre-commit: validate-personas =="
python3 "$DIR/validate-personas.py"

echo "== pre-commit: test_scripts.sh =="
bash "$DIR/test_scripts.sh"

echo "pre-commit: all guards passed"
