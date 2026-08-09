#!/usr/bin/env bash
# pattern: imperative shell
# Pre-commit guard: run both drift detectors and fail fast on the first error.
# Install as a git hook:
#   ln -s ../../scripts/pre-commit.sh .git/hooks/pre-commit
#
# The tracked script (not the untracked hook symlink) is the deliverable —
# any contributor can install it without a separate doc step.
set -euo pipefail

# Resolve through the hook symlink. When installed as .git/hooks/pre-commit,
# BASH_SOURCE points at the symlink, so a plain dirname yields .git/hooks and
# every script path below misses. The install line in the header has been in
# CONTRIBUTING.md since it was written and was never actually exercised —
# the hook was found uninstalled on 2026-08-09, and installing it failed
# immediately for this reason.
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  TARGET="$(readlink "$SELF")"
  case "$TARGET" in
    /*) SELF="$TARGET" ;;
    *)  SELF="$(cd "$(dirname "$SELF")" && pwd)/$TARGET" ;;
  esac
done
DIR="$(cd "$(dirname "$SELF")" && pwd)"

echo "== pre-commit: validate-personas =="
python3 "$DIR/validate-personas.py"

echo "== pre-commit: test_scripts.sh =="
bash "$DIR/test_scripts.sh"

echo "pre-commit: all guards passed"
