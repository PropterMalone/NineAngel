#!/usr/bin/env bash
# pattern: imperative shell
# The single mechanical chokepoint for durable per-dispatch bookkeeping records
# (ADR-12 invariant): usage.jsonl, findings/{name}.md, passes/{persona}-p{i}.md, and
# verification/{id}.json. These are the writes LLM orchestrators historically dropped
# under context pressure (ADR-03) — one script call replaces each hand-formatted write.
#
# Usage:
#   record-dispatch.sh [--reader-pack] [--findings] [--pass I] [--failed] [--verdict] \
#     <RUN_DIR> <phase> <name> <model> <total_tokens|null> <tool_uses|null> <duration_ms|null> [note]
#
#   --reader-pack : sets reader_pack:true on the JSONL line (default false)
#   --findings    : read the persona's verbatim block from STDIN -> findings/<name>.md
#                   (only composes with --pass 1: pass-1's block IS the findings/ record)
#   --pass I      : read the pass block from STDIN -> passes/<name>-pI.md, with an
#                   `<!-- angel-pass persona=.. pass=I model=.. -->` header (ADR-12 D1/D3
#                   model stamp), after a CAPTURE-TIME parse check (a block with no
#                   recognizable finding structure is REJECTED to <file>.rejected + exit 2,
#                   so a malformed pass fails loud now instead of at finalize).
#   --failed      : write a failure stub passes/<name>-pI.md (no STDIN parse) that the
#                   completeness gate treats as an excused pass. Requires --pass I.
#   --verdict     : read a JSON verdict from STDIN -> verification/<name>.json (folds the
#                   §5.7 verifier hand-write into the chokepoint; <name> is the finding id).
#   phase         : reader | persona | reconciler | integrator | verifier
#   name          : [A-Za-z0-9_-]+ (filename component; blocks path traversal; allows the
#                   mixed-case finding ids used by --verdict, e.g. C1/f2)
#   note          : optional 8th arg, e.g. "unmeasured" when tokens are null
#
# Multiball capture is mechanical, not prose-mandated: a `persona`-phase call under an
# active MULTIBALL marker MUST pass --pass I (or --failed) or the script refuses — the
# fix for the ADR-03 dropped-pass-write class.
#
# started_at/ended_at stamped here (ADR-11). Echoes the appended JSONL line on success.
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

READER_PACK=false
FINDINGS=false
PASS_I=""
FAILED=false
VERDICT=false
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --reader-pack) READER_PACK=true; shift ;;
    --findings)    FINDINGS=true; shift ;;
    --pass)        PASS_I="${2:-}"; shift 2 ;;
    --failed)      FAILED=true; shift ;;
    --verdict)     VERDICT=true; shift ;;
    *) echo "error: unknown flag '$1'" >&2; exit 1 ;;
  esac
done

if [[ $# -lt 7 || $# -gt 8 ]]; then
  echo "usage: record-dispatch.sh [--reader-pack] [--findings] [--pass I] [--failed] [--verdict] <RUN_DIR> <phase> <name> <model> <total_tokens|null> <tool_uses|null> <duration_ms|null> [note]" >&2
  exit 1
fi

RUN_DIR="$1"; PHASE="$2"; NAME="$3"; MODEL="$4"; TT="$5"; TU="$6"; DM="$7"; NOTE="${8:-}"

[[ -d "$RUN_DIR" ]] || { echo "error: run dir not found: $RUN_DIR" >&2; exit 1; }
case "$PHASE" in reader|persona|reconciler|integrator|verifier) ;; *)
  echo "error: phase must be reader|persona|reconciler|integrator|verifier (got '$PHASE')" >&2; exit 1 ;;
esac
[[ "$NAME" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "error: name must match [A-Za-z0-9_-]+ (got '$NAME')" >&2; exit 1; }
for v in "$TT" "$TU" "$DM"; do
  [[ "$v" =~ ^(null|[0-9]+)$ ]] || { echo "error: total_tokens/tool_uses/duration_ms must be a non-negative integer or 'null' (got '$v')" >&2; exit 1; }
done
if [[ -n "$PASS_I" ]]; then
  [[ "$PASS_I" =~ ^[0-9]+$ && "$PASS_I" -ge 1 ]] || { echo "error: --pass I must be a positive integer (got '$PASS_I')" >&2; exit 1; }
fi
$FAILED && [[ -z "$PASS_I" ]] && { echo "error: --failed requires --pass I" >&2; exit 1; }
if $FINDINGS && [[ -n "$PASS_I" && "$PASS_I" != "1" ]]; then
  echo "error: --findings only composes with --pass 1 (pass-1's block is the findings/ record)" >&2; exit 1
fi
# Mechanical multiball capture: a persona dispatch under an active MULTIBALL marker must
# write its pass file (or a failure stub). This is the ADR-12 enforcement of D1.
if [[ "$PHASE" == "persona" && -f "$RUN_DIR/MULTIBALL" && -z "$PASS_I" ]]; then
  echo "error: persona dispatch under multiball must pass --pass I (mechanical capture, ADR-12 D1)" >&2; exit 1
fi

# Capture STDIN once for whichever consumer needs it.
BLOCK=""; VERDICT_JSON=""
if $VERDICT; then
  VERDICT_JSON="$(cat)"
elif { [[ -n "$PASS_I" ]] && ! $FAILED; } || $FINDINGS; then
  BLOCK="$(cat)"
fi

# Timestamp the dispatch (ADR-11).
ENDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ "$DM" != "null" ]]; then
  STARTED_AT="$(date -u -d "@$(( $(date -u -d "$ENDED_AT" +%s) - DM / 1000 ))" +%Y-%m-%dT%H:%M:%SZ)"
else
  STARTED_AT=""
fi

line="$(jq -cn \
  --arg phase "$PHASE" --arg name "$NAME" --arg model "$MODEL" --arg note "$NOTE" \
  --arg sa "$STARTED_AT" --arg ea "$ENDED_AT" \
  --argjson tt "$TT" --argjson tu "$TU" --argjson dm "$DM" --argjson rp "$READER_PACK" '
  {phase:$phase, name:$name, model:$model, total_tokens:$tt, tool_uses:$tu,
   duration_ms:$dm, started_at:(if $sa == "" then null else $sa end),
   ended_at:$ea, reader_pack:$rp}
  + (if $note != "" then {note:$note} else {} end)')"

printf '%s\n' "$line" >> "$RUN_DIR/usage.jsonl"

# --pass: write the pass file (mechanical D1), with capture-time parse validation.
if [[ -n "$PASS_I" ]]; then
  mkdir -p "$RUN_DIR/passes"
  PASS_FILE="$RUN_DIR/passes/${NAME}-p${PASS_I}.md"
  if $FAILED; then
    printf '<!-- angel-pass persona=%s pass=%s model=%s failed -->\n(pass failed: %s)\n' \
      "$NAME" "$PASS_I" "$MODEL" "$NOTE" > "$PASS_FILE"
  else
    status="$(printf '%s' "$BLOCK" | python3 "$SCRIPT_DIR/parse-findings.py" 2>/dev/null || true)"
    if [[ "$status" == "no-structure" ]]; then
      printf '%s' "$BLOCK" > "$PASS_FILE.rejected"
      echo "error: pass block for $NAME p$PASS_I has no recognizable finding structure — not written (see ${PASS_FILE}.rejected); re-dispatch" >&2
      exit 2
    fi
    printf '<!-- angel-pass persona=%s pass=%s model=%s -->\n%s\n' "$NAME" "$PASS_I" "$MODEL" "$BLOCK" > "$PASS_FILE"
  fi
fi

# --findings: write the per-persona human record (pass-1's block under multiball).
if $FINDINGS; then
  mkdir -p "$RUN_DIR/findings"
  printf '%s' "$BLOCK" > "$RUN_DIR/findings/$NAME.md"
fi

# --verdict: fold the verifier verdict write into the chokepoint.
if $VERDICT; then
  printf '%s' "$VERDICT_JSON" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 \
    || { echo "error: --verdict payload for $NAME is not valid JSON" >&2; exit 1; }
  mkdir -p "$RUN_DIR/verification"
  printf '%s' "$VERDICT_JSON" > "$RUN_DIR/verification/$NAME.json"
fi

printf '%s\n' "$line"
