#!/usr/bin/env bash
# pattern: imperative shell
# One mechanical end-of-run gate — SKILL.md §8a-c in a single call, so a run
# record cannot be left half-written by orchestrator drift (ADR-03 reboot
# condition 4: run-record completeness enforced, not disciplined).
#
# Stage order is ADR-12's edit map, and the order is load-bearing:
#   1. assemble-wpr.py             passes/*.md -> within_persona_runs (SCRIPT, not LLM)
#   2. aggregate-usage.py          usage.jsonl -> usage.json (§8a; reads counts, must follow 1)
#   3. check-run-complete.py       completeness + provenance GATE (§8c)
#   4. append-usage-log.sh         canonical usage.log line (§8b) — ONLY IF THE GATE PASSED
#   5. emit-dispositions-skeleton  dispositions.json skeleton — every finding starts
#                                  "no-record", so non-triage is recorded, not inferred
#
# Why 4 is after 3 (fixed 2026-08-02, six weeks late): appending BEFORE the gate meant a
# gate failure did not stop the log line, it produced a DUPLICATE one once the orchestrator
# remediated and re-finalized. 14 runs back to 2026-06-01 were logged twice, 9 of them with a
# premature 0C/0I/0M/0N first line, so the cross-run miner read them as having found nothing.
# The gate's alert had become a silent data-corruption channel. Do not move the append back
# above the gate.
#
# Why 1 exists at all: ADR-12 shipped the provenance CHECK without the PRODUCER. Nothing
# called assemble-wpr.py in production, so the integrator kept hand-writing
# within_persona_runs, the gate correctly found LLM-written != recompute, and every multiball
# run failed. Stage 1 is the mechanism the gate was always enforcing against.
#
# Gate-fail is alert + NO append (an incomplete run must not enter the calibration index;
# the run dir on disk plus this alert are the recovery path — see resume-run.sh).
#
# Usage: finalize-run.sh <RUN_DIR> [RUN_TAG]
set -euo pipefail

RUN_DIR="${1:?usage: finalize-run.sh <RUN_DIR> [RUN_TAG]}"
RUN_TAG="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

stage() { # $1=stage name, rest=command
  local name="$1"; shift
  if ! "$@"; then
    echo "finalize-run: stage failed: $name" >&2
    exit 1
  fi
}

stage "assemble-wpr.py" python3 "$SCRIPT_DIR/assemble-wpr.py" "$RUN_DIR"
stage "aggregate-usage.py" python3 "$SCRIPT_DIR/aggregate-usage.py" "$RUN_DIR"

# The gate. On failure: alert loudly, do NOT append, exit nonzero.
if ! python3 "$SCRIPT_DIR/check-run-complete.py" --pre-append "$RUN_DIR"; then
  cat >&2 <<EOF
finalize-run: stage failed: check-run-complete.py
finalize-run: run is INCOMPLETE — usage.log line NOT written (ADR-12).
finalize-run:   run dir: $RUN_DIR
finalize-run:   Fix the missing artifacts and re-run finalize-run.sh; the append is
finalize-run:   idempotent on the run: pointer, so re-finalizing corrects the record
finalize-run:   rather than duplicating it. See scripts/resume-run.sh for the phase map.
EOF
  exit 1
fi

if [[ -n "$RUN_TAG" ]]; then
  stage "append-usage-log.sh" "$SCRIPT_DIR/append-usage-log.sh" "$RUN_DIR" "$RUN_TAG"
else
  stage "append-usage-log.sh" "$SCRIPT_DIR/append-usage-log.sh" "$RUN_DIR"
fi
stage "emit-dispositions-skeleton.py" python3 "$SCRIPT_DIR/emit-dispositions-skeleton.py" "$RUN_DIR"
