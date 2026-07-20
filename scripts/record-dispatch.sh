#!/usr/bin/env bash
# pattern: imperative shell
# Mechanize the two per-dispatch side effects of a /angel run — the SKILL.md
# §3.4 usage.jsonl append and the §4 findings/{name}.md write. These are the
# writes LLM orchestrators have historically dropped (ADR-03: prose-mandated
# per-dispatch bookkeeping silently skipped under context pressure), so one
# script call replaces both hand-formatted writes.
#
# Usage:
#   record-dispatch.sh [--reader-pack] [--findings] \
#     <RUN_DIR> <phase> <name> <model> <total_tokens|null> <tool_uses|null> <duration_ms|null> [note]
#
#   --reader-pack : sets reader_pack:true on the JSONL line (default false)
#   --findings    : read the persona's verbatim findings block from STDIN and
#                   write it to $RUN_DIR/findings/<name>.md (explicit flag, not
#                   tty-sniffing — unambiguous and testable)
#   phase         : reader | persona | reconciler | integrator | verifier (§3.4 schema)
#   name          : [a-z0-9_-]+ only — it becomes a filename component; anything
#                   else is rejected (review finding f34: path traversal /
#                   surprise filenames via persona name)
#   note          : optional 8th arg, e.g. "unmeasured" when tokens are null
#
# started_at/ended_at are stamped here (ADR-11): ended_at = call time (the
# script runs right as the dispatch returns), started_at = ended_at - duration_ms
# when duration is numeric, else null. Before 2026-07-19 both were hard nulls,
# which made every aggregate wall time 0s and integrator stall rates unmeasurable.
# Echoes the appended JSONL line on success.
set -euo pipefail

READER_PACK=false
FINDINGS=false
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --reader-pack) READER_PACK=true; shift ;;
    --findings)    FINDINGS=true; shift ;;
    *) echo "error: unknown flag '$1'" >&2; exit 1 ;;
  esac
done

if [[ $# -lt 7 || $# -gt 8 ]]; then
  echo "usage: record-dispatch.sh [--reader-pack] [--findings] <RUN_DIR> <phase> <name> <model> <total_tokens|null> <tool_uses|null> <duration_ms|null> [note]" >&2
  exit 1
fi

RUN_DIR="$1"; PHASE="$2"; NAME="$3"; MODEL="$4"; TT="$5"; TU="$6"; DM="$7"; NOTE="${8:-}"

[[ -d "$RUN_DIR" ]] || { echo "error: run dir not found: $RUN_DIR" >&2; exit 1; }
case "$PHASE" in reader|persona|reconciler|integrator|verifier) ;; *)
  echo "error: phase must be reader|persona|reconciler|integrator|verifier (got '$PHASE')" >&2; exit 1 ;;
esac
[[ "$NAME" =~ ^[a-z0-9_-]+$ ]] || { echo "error: name must match [a-z0-9_-]+ (got '$NAME')" >&2; exit 1; }
for v in "$TT" "$TU" "$DM"; do
  [[ "$v" =~ ^(null|[0-9]+)$ ]] || { echo "error: total_tokens/tool_uses/duration_ms must be a non-negative integer or 'null' (got '$v')" >&2; exit 1; }
done

# Timestamp the dispatch (ADR-11): the script is invoked right as the dispatch
# returns, so now = ended_at; started_at is derived from duration_ms when known.
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

if $FINDINGS; then
  mkdir -p "$RUN_DIR/findings"
  cat > "$RUN_DIR/findings/$NAME.md"
fi

printf '%s\n' "$line"
