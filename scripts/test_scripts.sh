#!/usr/bin/env bash
# pattern: imperative shell
# Smoke tests pinning the angel script contracts. Exercises every script against
# fixtures and asserts behavior — so the usage.json schema and the finding-id
# contract (shared by append-usage-log.sh, mine-runs.py, record-disposition.py,
# check-run-complete.py) can't silently drift. Run: scripts/test_scripts.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
export ANGEL_RUNS_ROOT="$TMP/runs"
export ANGEL_USAGE_LOG="$TMP/usage.log"
mkdir -p "$ANGEL_RUNS_ROOT"
PASS=0; FAIL=0
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL - %s\n     %s\n' "$1" "${2:-}"; }
has()  { case "$2" in *"$1"*) ok "$3";; *) bad "$3" "missing '$1' in: $2";; esac; }
hasnt(){ case "$2" in *"$1"*) bad "$3" "unexpected '$1' in: $2";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3" || bad "$3" "rc=$1 expected $2"; }

mk_usage() { # $1=rundir $2=total_tokens(null|int) ; writes a full-schema usage.json
  local rd="$1" tok="$2"
  mkdir -p "$rd/findings"
  cat > "$rd/usage.json" <<JSON
{"run_dir":"$rd","project":"demo","mode":"full","reader_enabled":true,
 "started_at":"2026-05-31T12:00:00Z","ended_at":"2026-05-31T12:05:00Z",
 "totals":{"total_tokens":$tok,"wall_seconds":300,
   "reader":{"total_tokens":40000,"duration_ms":22000,"tool_uses":9},
   "personas":[{"name":"rtfm","model":"claude-sonnet-4-6","total_tokens":50000,"reader_pack":true},
               {"name":"adv","model":"claude-sonnet-4-6","total_tokens":60000,"reader_pack":true}]},
 "unmeasured":[],"verdict":"CHANGES REQUIRED","findings":{"critical":1,"important":2,"minor":0,"noted":1}}
JSON
}
mk_snapshot() { # $1=rundir : snapshot with ids + evidence + a shared finding
  cat > "$1/findings-snapshot.json" <<'JSON'
{"version":1,"project":"demo","date":"2026-05-31","mode":"full","verdict":"CHANGES REQUIRED",
 "personas_run":["rtfm","adv"],
 "findings":[
  {"id":"f1","severity":"critical","title":"Spec | violated `here`","personas":["rtfm"],"evidence":"cited-spec"},
  {"id":"f2","severity":"important","title":"Path traversal","personas":["adv"],"evidence":"code-site"},
  {"id":"f3","severity":"important","title":"Both caught this","personas":["rtfm","adv"],"evidence":"code-site"},
  {"id":"f4","severity":"minor","title":"Vague","personas":["rtfm"],"evidence":"inference"}
 ]}
JSON
}

echo "== validate-personas =="
rc=0; out="$("$DIR/validate-personas.py" 2>&1)" || rc=$?; rc_is $rc 0 "validate-personas exits 0 (registry clean)"
has "clean" "$out" "validate-personas reports clean"
# Synthetic-drift fixtures: prove the detector actually fires (not just clean-on-live).
vp_fixture() { # $1=dir $2=SKILL rows $3=unattended rows (data rows only)
  rm -rf "$1"; mkdir -p "$1/personas"
  printf '# fixture\n\n| Short | Full | Model |\n|---|---|---|\n%s\n' "$2" > "$1/SKILL.md"
  printf '# fixture\n\n| Short | Persona file | Model |\n|---|---|---|\n%s\n' "$3" > "$1/unattended.md"
}
mk_persona() { # $1=path ; writes a contract-conformant persona file (DESIGN.md frontmatter contract)
  cat > "$1" <<'PERSONA'
---
name: adversarial
default: yes
modes: [diff, full]
experimental: false
requires:
  any_of: [any]
context:
  digest: yes
  project_claude_md: yes
  full_bundle: no
  lane: |
    fixture lane
---
fixture body
PERSONA
}
VP="$TMP/vp"
vp_fixture "$VP" '| adv | Adversarial | Sonnet 4.6 |' '| adv | `adversarial.md` | `claude-sonnet-4-6` |'
mk_persona "$VP/personas/adversarial.md"
rc=0; vout="$("$DIR/validate-personas.py" --skill-dir "$VP" 2>&1)" || rc=$?
rc_is $rc 0 "drift fixture baseline is clean"
vp_fixture "$VP" $'| adv | Adversarial | Sonnet 4.6 |\n| ghost | Ghost | Sonnet 4.6 |' \
  $'| adv | `adversarial.md` | `claude-sonnet-4-6` |\n| ghost | `ghost.md` | `claude-sonnet-4-6` |'
rc=0; vout="$("$DIR/validate-personas.py" --skill-dir "$VP" 2>&1)" || rc=$?
rc_is $rc 1 "orphan table row (no persona file) exits nonzero"
has "orphan row" "$vout" "orphan row named in output"
vp_fixture "$VP" '| adv | Adversarial | Sonnet 4.6 |' '| adv | `adversarial.md` | `claude-haiku-4-5` |'
rc=0; vout="$("$DIR/validate-personas.py" --skill-dir "$VP" 2>&1)" || rc=$?
rc_is $rc 1 "tier mismatch between SKILL and unattended exits nonzero"
has "tier drift" "$vout" "tier drift named in output"
vp_fixture "$VP" '| adv | Adversarial | GPT-9000 |' '| adv | `adversarial.md` | `gpt-9000` |'
rc=0; vout="$("$DIR/validate-personas.py" --skill-dir "$VP" 2>&1)" || rc=$?
rc_is $rc 1 "unrecognized model string exits nonzero (TIER_RE blind spot)"
has "unrecognized model" "$vout" "unrecognized model named, not silently dropped"
# Frontmatter-contract fixtures: dead key and missing context key both fire.
vp_fixture "$VP" '| adv | Adversarial | Sonnet 4.6 |' '| adv | `adversarial.md` | `claude-sonnet-4-6` |'
mk_persona "$VP/personas/adversarial.md"
sed -i '/^experimental:/a prefers: []' "$VP/personas/adversarial.md"
rc=0; vout="$("$DIR/validate-personas.py" --skill-dir "$VP" 2>&1)" || rc=$?
rc_is $rc 1 "dead prefers: frontmatter key exits nonzero"
has "prefers" "$vout" "prefers: violation named in output"
vp_fixture "$VP" '| adv | Adversarial | Sonnet 4.6 |' '| adv | `adversarial.md` | `claude-sonnet-4-6` |'
mk_persona "$VP/personas/adversarial.md"
sed -i '/^  full_bundle:/d' "$VP/personas/adversarial.md"
rc=0; vout="$("$DIR/validate-personas.py" --skill-dir "$VP" 2>&1)" || rc=$?
rc_is $rc 1 "missing context key exits nonzero"
has "full_bundle" "$vout" "missing context key named in output"

echo "== append-usage-log.sh =="
RD="$ANGEL_RUNS_ROOT/r_full"; mk_usage "$RD" 110000
line="$("$DIR/append-usage-log.sh" "$RD")"
has "total:110000" "$line" "normal run emits total:<int>"
has "run:$RD" "$line" "line carries run: pointer"
has "reader_total:40000" "$line" "reader_total present when reader block exists"
RDN="$ANGEL_RUNS_ROOT/r_null"; mk_usage "$RDN" null
lineN="$("$DIR/append-usage-log.sh" "$RDN")"
has "total:null" "$lineN" "null tokens emit total:null (not total:0)"
hasnt "total:0 " "$lineN" "null tokens do NOT masquerade as total:0"
RDC="$ANGEL_RUNS_ROOT/r_cal"; mk_usage "$RDC" 5000
lineC="$("$DIR/append-usage-log.sh" "$RDC" baseline)"
has "cal:baseline" "$lineC" "calibration tag becomes cal:<tag>"
RDM="$ANGEL_RUNS_ROOT/r_missing"; mkdir -p "$RDM/findings"
lineM="$("$DIR/append-usage-log.sh" "$RDM" 2>/dev/null)" || true
has "usage.json-missing" "$lineM" "missing usage.json -> fallback line"
has "run:$RDM" "$lineM" "fallback line still carries run: pointer"
RDX="$ANGEL_RUNS_ROOT/r_bad"; mkdir -p "$RDX/findings"; echo '{bad json' > "$RDX/usage.json"
lineX="$("$DIR/append-usage-log.sh" "$RDX" 2>/dev/null)" || true
has "usage.json-malformed" "$lineX" "malformed usage.json -> fallback line"
# f10: a `|` in project/mode/persona must not shift the pipe-delimited columns
RDP="$ANGEL_RUNS_ROOT/r_pipe"; mkdir -p "$RDP/findings"
cat > "$RDP/usage.json" <<JSON
{"run_dir":"$RDP","project":"we|ird","mode":"fu|ll","reader_enabled":false,
 "started_at":"2026-05-31T12:00:00Z","ended_at":"2026-05-31T12:05:00Z",
 "totals":{"total_tokens":1000,"wall_seconds":10,
   "personas":[{"name":"rt|fm","model":"claude-sonnet-4-6","total_tokens":1000,"reader_pack":false}]},
 "unmeasured":[],"verdict":"OK","findings":{"critical":0,"important":0,"minor":0,"noted":0}}
JSON
lineP="$("$DIR/append-usage-log.sh" "$RDP")"
nf="$(printf '%s' "$lineP" | awk -F'|' '{print NF}')"
[ "$nf" = 7 ] && ok "pipe in project/mode/persona keeps 7 fields" || bad "pipe in project/mode/persona keeps 7 fields" "got $nf fields: $lineP"
has "we ird" "$lineP" "pipe in project replaced with space"
has "rt fm" "$lineP" "pipe in persona name replaced with space"

echo "== record-disposition.py =="
rc=0; "$DIR/record-disposition.py" "$RD" f1 accepted >/dev/null || rc=$?; rc_is $rc 0 "record accepted ok"
rc=0; "$DIR/record-disposition.py" "$RD" f4 rejected-wrong not a real bug at all >/dev/null || rc=$?; rc_is $rc 0 "record rejected-wrong ok"
note="$(python3 -c "import json;print(json.load(open('$RD/dispositions.json'))['f4']['note'])")"
[ "$note" = "not a real bug at all" ] && ok "note joins unquoted words" || bad "note joins unquoted words" "got: $note"
rc=0; "$DIR/record-disposition.py" "$RD" f9 bogus-disp 2>/dev/null || rc=$?; rc_is $rc 1 "invalid disposition rejected"
rc=0; "$DIR/record-disposition.py" /etc f1 accepted 2>/dev/null || rc=$?; rc_is $rc 1 "write outside runs-root rejected"

echo "== mine-runs.py (evidence + precision + overlap) =="
mk_snapshot "$RD"; echo "stub" > "$RD/findings/rtfm.md"
mout="$("$DIR/mine-runs.py" --runs-dir "$ANGEL_RUNS_ROOT" --since 2026-05-31)"
has "cited%" "$mout" "value table has cited% column"
has "fp% (n)" "$mout" "value table has fp% column"
has "Persona overlap" "$mout" "overlap section emitted"
has "adv + rtfm" "$mout" "overlap lists the shared-Important+ pair"
mjson="$("$DIR/mine-runs.py" --runs-dir "$ANGEL_RUNS_ROOT" --since 2026-05-31 --json)"
rc=0; python3 - "$mjson" <<'PY' || rc=$?
import json,sys
d=json.loads(sys.argv[1])
rt=d["personas"]["rtfm"]
assert rt["disposed"]==2, rt           # f1 + f4 dispositioned
assert rt["false_positives"]==1, rt    # f4 rejected-wrong
assert rt["cited"]>=1, rt              # f1 cited-spec
assert any(o["pair"]==["adv","rtfm"] for o in d["portfolio"]["overlap_important_plus"]), d["portfolio"]["overlap_important_plus"]
print("json-asserts-ok")
PY
rc_is $rc 0 "mine-runs --json: disposed/fp/cited/overlap correct"

echo "== check-run-complete.py =="
"$DIR/append-usage-log.sh" "$RD" >/dev/null   # ensures a run: line in $ANGEL_USAGE_LOG
rc=0; "$DIR/check-run-complete.py" "$RD" >/dev/null 2>&1 || rc=$?; rc_is $rc 0 "complete run passes"
rc=0; "$DIR/check-run-complete.py" "$RDN" >/dev/null 2>&1 || rc=$?; rc_is $rc 1 "incomplete run fails (no findings/snapshot)"
rc=0; "$DIR/check-run-complete.py" --all >/dev/null 2>&1 || rc=$?; rc_is $rc 1 "--all exits nonzero when any run incomplete"

# multiball completeness: a run with multiball N>=2 must persist within_persona_runs
RMB="$ANGEL_RUNS_ROOT/r_mball"; mk_usage "$RMB" 90000; echo "stub" > "$RMB/findings/adv_ball1.md"
"$DIR/append-usage-log.sh" "$RMB" >/dev/null
cat > "$RMB/findings-snapshot.json" <<'JSON'
{"version":2,"project":"demo","mode":"diff","multiball":2,"personas_run":["adv"],
 "findings":[{"id":"f1","severity":"important","title":"x","personas":["adv"]}],
 "within_persona_runs":null}
JSON
rc=0; "$DIR/check-run-complete.py" "$RMB" >/dev/null 2>&1 || rc=$?; rc_is $rc 1 "multiball run with null within_persona_runs fails"
ferr="$("$DIR/check-run-complete.py" "$RMB" 2>&1 || true)"; has "within_persona_runs" "$ferr" "failure names the missing per-pass record"
# now with a well-formed per-pass record it passes
cat > "$RMB/findings-snapshot.json" <<'JSON'
{"version":2,"project":"demo","mode":"diff","multiball":2,"personas_run":["adv"],
 "findings":[{"id":"f1","severity":"important","title":"x","personas":["adv"]}],
 "within_persona_runs":{"adv":[[{"severity":"important","title":"x","file":"a.ts"}],[{"severity":"important","title":"x","file":"a.ts"}]]}}
JSON
rc=0; "$DIR/check-run-complete.py" "$RMB" >/dev/null 2>&1 || rc=$?; rc_is $rc 0 "multiball run with valid within_persona_runs passes"
# prose-string record (the 2026-06-19 failure shape) must NOT pass as structured
cat > "$RMB/findings-snapshot.json" <<'JSON'
{"version":2,"project":"demo","mode":"diff","multiball":2,"personas_run":["adv"],
 "findings":[{"id":"f1","severity":"important","title":"x","personas":["adv"]}],
 "within_persona_runs":{"adv":["near-universal across all balls","adv balls 1 & 2"]}}
JSON
rc=0; "$DIR/check-run-complete.py" "$RMB" >/dev/null 2>&1 || rc=$?; rc_is $rc 1 "multiball run with prose-string within_persona_runs fails (not structured per-pass)"
# all-clean multiball run (both passes empty) is a VALID record — must pass
cat > "$RMB/findings-snapshot.json" <<'JSON'
{"version":2,"project":"demo","mode":"diff","multiball":2,"personas_run":["adv"],
 "findings":[],"within_persona_runs":{"adv":[[],[]]}}
JSON
rc=0; "$DIR/check-run-complete.py" "$RMB" >/dev/null 2>&1 || rc=$?; rc_is $rc 0 "multiball run with empty-but-structured passes ([[],[]]) passes (legit all-clean run)"
# empty within_persona_runs dict must fail
cat > "$RMB/findings-snapshot.json" <<'JSON'
{"version":2,"project":"demo","mode":"diff","multiball":2,"personas_run":["adv"],
 "findings":[],"within_persona_runs":{}}
JSON
rc=0; "$DIR/check-run-complete.py" "$RMB" >/dev/null 2>&1 || rc=$?; rc_is $rc 1 "multiball run with empty within_persona_runs dict fails"
# ball-file fallback: multiball inferred from *_ball*.md even if snapshot lacks the field, single-pass unaffected
cat > "$RMB/findings-snapshot.json" <<'JSON'
{"version":2,"project":"demo","mode":"diff","personas_run":["adv"],
 "findings":[{"id":"f1","severity":"important","title":"x","personas":["adv"]}],"within_persona_runs":null}
JSON
echo "stub" > "$RMB/findings/adv_ball2.md"
rc=0; "$DIR/check-run-complete.py" "$RMB" >/dev/null 2>&1 || rc=$?; rc_is $rc 1 "multiball inferred from ball files (no multiball field) still requires the record"
# bool multiball:true falls through to ball-file inference (not treated as N>=2 directly)
cat > "$RMB/findings-snapshot.json" <<'JSON'
{"version":2,"project":"demo","mode":"diff","multiball":true,"personas_run":["adv"],
 "findings":[],"within_persona_runs":{"adv":[[],[]]}}
JSON
rc=0; "$DIR/check-run-complete.py" "$RMB" >/dev/null 2>&1 || rc=$?; rc_is $rc 0 "multiball:true (bool) with valid record passes; bool not miscounted as N"

echo "== record-dispatch =="
RRD="$ANGEL_RUNS_ROOT/r_rd"; mkdir -p "$RRD"
rdl="$(printf '## Findings\n- one\n' | "$DIR/record-dispatch.sh" --findings "$RRD" persona rtfm claude-sonnet-4-6 50000 10 60000)"
rc=0; python3 - "$RRD" "$rdl" <<'PY' || rc=$?
import json, sys
rd, line = sys.argv[1], sys.argv[2]
j = json.loads(line)
assert j == {"phase": "persona", "name": "rtfm", "model": "claude-sonnet-4-6",
             "total_tokens": 50000, "tool_uses": 10, "duration_ms": 60000,
             "started_at": None, "ended_at": None, "reader_pack": False}, j
last = open(rd + "/usage.jsonl").read().strip().splitlines()[-1]
assert json.loads(last) == j, last
print("rd-asserts-ok")
PY
rc_is $rc 0 "record-dispatch appends a schema-correct JSONL line"
grep -q '^- one$' "$RRD/findings/rtfm.md" && ok "findings file written from stdin (--findings)" || bad "findings file written from stdin (--findings)"
rdn="$("$DIR/record-dispatch.sh" "$RRD" persona adv claude-sonnet-4-6 null null null unmeasured </dev/null)"
has '"total_tokens":null' "$rdn" "null tokens stay null in the JSONL line"
has '"note":"unmeasured"' "$rdn" "optional note arg lands on the line"
rdr="$("$DIR/record-dispatch.sh" --reader-pack "$RRD" persona hyper claude-sonnet-4-6 100 1 100 </dev/null)"
has '"reader_pack":true' "$rdr" "--reader-pack sets reader_pack:true"
rc=0; "$DIR/record-dispatch.sh" "$RRD" persona '../evil' m null null null </dev/null >/dev/null 2>&1 || rc=$?
rc_is $rc 1 "path-traversal persona name rejected (f34)"
rc=0; "$DIR/record-dispatch.sh" "$RRD" persona 'Bad Name' m null null null </dev/null >/dev/null 2>&1 || rc=$?
rc_is $rc 1 "non-[a-z0-9_-] persona name rejected"
rc=0; "$DIR/record-dispatch.sh" "$RRD" bogus rtfm m null null null </dev/null >/dev/null 2>&1 || rc=$?
rc_is $rc 1 "unknown phase rejected"
rdv="$("$DIR/record-dispatch.sh" "$RRD" verifier f3 claude-sonnet-4-6 7000 3 30000 </dev/null)"
has '"phase":"verifier"' "$rdv" "verifier phase accepted (verification stage)"
rc=0; "$DIR/record-dispatch.sh" "$RRD" persona rtfm m 12x3 null null </dev/null >/dev/null 2>&1 || rc=$?
rc_is $rc 1 "non-integer token count rejected"

echo "== init-run.sh =="
SYNTH_PROJ="$TMP/proj"; mkdir -p "$SYNTH_PROJ"
rc=0; iout="$(HOME="$TMP/home" "$DIR/init-run.sh" "$SYNTH_PROJ")" || rc=$?
rc_is $rc 0 "init-run exits 0"
[ "$(printf '%s\n' "$iout" | wc -l)" -eq 3 ] && ok "init-run emits exactly 3 stdout lines" || bad "init-run emits exactly 3 stdout lines" "got: $iout"
RUN_DIR=""; ENCODED_CWD=""; HANDOFF_DIR=""
eval "$iout"
[ -d "$RUN_DIR/findings" ] && ok "RUN_DIR/findings created" || bad "RUN_DIR/findings created" "RUN_DIR=$RUN_DIR"
[ -f "$RUN_DIR/usage.jsonl" ] && [ ! -s "$RUN_DIR/usage.jsonl" ] && ok "usage.jsonl created empty" || bad "usage.jsonl created empty"
case "$RUN_DIR" in "$ANGEL_RUNS_ROOT"/*) ok "RUN_DIR under ANGEL_RUNS_ROOT";; *) bad "RUN_DIR under ANGEL_RUNS_ROOT" "RUN_DIR=$RUN_DIR";; esac
[ "$ENCODED_CWD" = "${SYNTH_PROJ//\//-}" ] && ok "ENCODED_CWD encodes project dir" || bad "ENCODED_CWD encodes project dir" "got: $ENCODED_CWD"
[ -d "$HANDOFF_DIR" ] && ok "HANDOFF_DIR exists" || bad "HANDOFF_DIR exists" "got: $HANDOFF_DIR"
case "$HANDOFF_DIR" in "$TMP/home"/*) ok "HANDOFF_DIR honors HOME override (nothing outside temp)";; *) bad "HANDOFF_DIR honors HOME override" "got: $HANDOFF_DIR";; esac
[ ! -e "$RUN_DIR/EXPERIMENT" ] && ok "no EXPERIMENT marker without --experiment" || bad "no EXPERIMENT marker without --experiment"
rc=0; iexp="$(HOME="$TMP/home" "$DIR/init-run.sh" "$SYNTH_PROJ" --experiment "roster swap trial")" || rc=$?
rc_is $rc 0 "init-run --experiment exits 0"
[ "$(printf '%s\n' "$iexp" | wc -l)" -eq 3 ] && ok "--experiment keeps exactly 3 stdout lines (eval contract)" || bad "--experiment keeps exactly 3 stdout lines (eval contract)" "got: $iexp"
RUN_DIR=""; eval "$iexp"; EXP_RUN_DIR="$RUN_DIR"
[ -f "$EXP_RUN_DIR/EXPERIMENT" ] && ok "--experiment writes EXPERIMENT marker" || bad "--experiment writes EXPERIMENT marker"
[ "$(wc -l < "$EXP_RUN_DIR/EXPERIMENT")" -eq 1 ] && ok "EXPERIMENT marker is a single line" || bad "EXPERIMENT marker is a single line"
mline="$(cat "$EXP_RUN_DIR/EXPERIMENT")"
case "$mline" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z" roster swap trial") ok "marker line is ISO date + reason";;
  *) bad "marker line is ISO date + reason" "got: $mline";;
esac

echo "== aggregate-usage.py =="
RAG="$ANGEL_RUNS_ROOT/20260601T120000Z-fixture1"
mkdir -p "$RAG/findings"; echo "stub" > "$RAG/findings/rtfm.md"
cat > "$RAG/usage.jsonl" <<'JSONL'
{"phase":"persona","name":"rtfm","model":"claude-sonnet-4-6","total_tokens":50000,"tool_uses":10,"duration_ms":60000,"started_at":"2026-06-01T12:05:00Z","ended_at":"2026-06-01T12:06:00Z","reader_pack":false}
{"phase":"persona","name":"adv","model":"claude-sonnet-4-6","total_tokens":null,"tool_uses":null,"duration_ms":null,"reader_pack":false,"note":"unmeasured"}
{"phase":"integrator","name":"integrator","model":"claude-fable-5[1m]","total_tokens":20000,"tool_uses":0,"duration_ms":120000,"started_at":"2026-06-01T12:10:00Z","ended_at":"2026-06-01T12:12:00Z","reader_pack":false}
JSONL
mk_snapshot "$RAG"
rc=0; python3 "$DIR/aggregate-usage.py" "$RAG" >/dev/null 2>&1 || rc=$?; rc_is $rc 0 "aggregate-usage exits 0"
rc=0; python3 - "$RAG" <<'PY' || rc=$?
import json, sys
rd = sys.argv[1]
u = json.load(open(rd + "/usage.json"))
assert u["totals"]["total_tokens"] == 70000, u["totals"]["total_tokens"]   # null-safe sum
assert u["unmeasured"] == ["persona:adv"], u["unmeasured"]
assert u["totals"]["integrator"]["total_tokens"] == 20000, u["totals"]["integrator"]
assert u["totals"]["reader"] is None and u["reader_enabled"] is False, u
assert u["verdict"] == "CHANGES REQUIRED", u["verdict"]
assert u["findings"] == {"critical": 1, "important": 2, "minor": 1, "noted": 0}, u["findings"]
assert u["started_at"] == "2026-06-01T12:00:00Z", u["started_at"]          # from run-dir basename
assert u["totals"]["wall_seconds"] == 720, u["totals"]["wall_seconds"]
assert len(u["totals"]["personas"]) == 2, u["totals"]["personas"]
print("aggregate-asserts-ok")
PY
rc_is $rc 0 "aggregate-usage: totals/unmeasured/integrator/verdict/findings correct"
grep -q "persona:adv" "$RAG/UNMEASURED.md" && ok "UNMEASURED.md written with unmeasured entry" || bad "UNMEASURED.md written with unmeasured entry"

echo "== finalize-run.sh =="
rc=0; "$DIR/finalize-run.sh" "$RAG" >/dev/null 2>&1 || rc=$?; rc_is $rc 0 "finalize-run exits 0 on complete fixture"
grep -q "run:$RAG" "$ANGEL_USAGE_LOG" && ok "finalize-run appended usage.log line" || bad "finalize-run appended usage.log line"
rc=0; python3 -c "
import json
d = json.load(open('$RAG/dispositions.json'))
assert sorted(d) == ['f1','f2','f3','f4'], d
assert all(v['disposition'] == 'no-record' for v in d.values()), d
" || rc=$?
rc_is $rc 0 "finalize-run stage 4 emitted dispositions skeleton"
RBAD="$ANGEL_RUNS_ROOT/20260601T130000Z-fixture2"   # no findings-snapshot.json -> completeness gate fails
mkdir -p "$RBAD/findings"; echo "stub" > "$RBAD/findings/rtfm.md"; : > "$RBAD/usage.jsonl"
rc=0; ferr="$("$DIR/finalize-run.sh" "$RBAD" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -ne 0 ] && ok "finalize-run exits nonzero on incomplete fixture" || bad "finalize-run exits nonzero on incomplete fixture"
has "check-run-complete" "$ferr" "finalize-run stderr names the failing stage"

echo "== emit-dispositions-skeleton.py =="
SKROOT="$TMP/skelruns"; mkdir -p "$SKROOT"
SK="$SKROOT/r_skel"; mkdir -p "$SK/findings"; mk_snapshot "$SK"
rc=0; sout="$(ANGEL_RUNS_ROOT="$SKROOT" "$DIR/emit-dispositions-skeleton.py" "$SK")" || rc=$?
rc_is $rc 0 "skeleton emit exits 0"
rc=0; python3 - "$SK" <<'PY' || rc=$?
import json, sys
d = json.load(open(sys.argv[1] + "/dispositions.json"))
assert sorted(d) == ["f1", "f2", "f3", "f4"], d
assert all(v == {"disposition": "no-record", "note": "", "recorded_at": None}
           for v in d.values()), d
print("skel-asserts-ok")
PY
rc_is $rc 0 "skeleton has every snapshot id at no-record (record-disposition entry schema)"
hasnt "experiment" "$(cat "$SK/dispositions.json")" "no experiment key without EXPERIMENT marker"
# idempotency: a recorded disposition survives a re-emit byte-for-byte
ANGEL_RUNS_ROOT="$SKROOT" "$DIR/record-disposition.py" "$SK" f1 accepted >/dev/null
cp "$SK/dispositions.json" "$TMP/disp.before"
rc=0; sout2="$(ANGEL_RUNS_ROOT="$SKROOT" "$DIR/emit-dispositions-skeleton.py" "$SK")" || rc=$?
rc_is $rc 0 "re-emit over existing dispositions.json exits 0"
has "already exists" "$sout2" "re-emit reports the no-op"
cmp -s "$TMP/disp.before" "$SK/dispositions.json" && ok "existing dispositions.json untouched (idempotent)" || bad "existing dispositions.json untouched (idempotent)"
rc=0; ANGEL_RUNS_ROOT="$SKROOT" "$DIR/emit-dispositions-skeleton.py" /etc >/dev/null 2>&1 || rc=$?
rc_is $rc 1 "write outside runs-root rejected"
# EXPERIMENT marker -> top-level experiment:true, preserved by record-disposition
SKE="$SKROOT/r_skel_exp"; mkdir -p "$SKE/findings"; mk_snapshot "$SKE"
printf '2026-07-08T00:00:00Z eval leg 2\n' > "$SKE/EXPERIMENT"
ANGEL_RUNS_ROOT="$SKROOT" "$DIR/emit-dispositions-skeleton.py" "$SKE" >/dev/null
rc=0; python3 -c "
import json
d = json.load(open('$SKE/dispositions.json'))
assert d.get('experiment') is True, d
assert d['f1']['disposition'] == 'no-record', d
" || rc=$?
rc_is $rc 0 "EXPERIMENT marker -> top-level experiment:true in skeleton"
ANGEL_RUNS_ROOT="$SKROOT" "$DIR/record-disposition.py" "$SKE" f1 accepted >/dev/null
rc=0; python3 -c "
import json
d = json.load(open('$SKE/dispositions.json'))
assert d.get('experiment') is True, d
assert d['f1']['disposition'] == 'accepted', d
" || rc=$?
rc_is $rc 0 "record-disposition preserves experiment:true on upsert"
rc=0; ANGEL_RUNS_ROOT="$SKROOT" "$DIR/record-disposition.py" "$SKE" experiment accepted 2>/dev/null || rc=$?
rc_is $rc 1 "finding id 'experiment' rejected (reserved marker key)"
# init-run --experiment marker propagates through the skeleton
mk_snapshot "$EXP_RUN_DIR"
"$DIR/emit-dispositions-skeleton.py" "$EXP_RUN_DIR" >/dev/null
rc=0; python3 -c "
import json
d = json.load(open('$EXP_RUN_DIR/dispositions.json'))
assert d.get('experiment') is True, d
" || rc=$?
rc_is $rc 0 "init-run --experiment marker propagates to skeleton experiment:true"
# mine-runs: no-record placeholders are untriaged, not disposed
SKN="$SKROOT/r_skel_untriaged"; mkdir -p "$SKN/findings"; mk_snapshot "$SKN"
ANGEL_RUNS_ROOT="$SKROOT" "$DIR/emit-dispositions-skeleton.py" "$SKN" >/dev/null
mjson2="$("$DIR/mine-runs.py" --runs-dir "$SKROOT" --since 2026-05-31 --json)"
rc=0; python3 - "$mjson2" <<'PY' || rc=$?
import json, sys
d = json.loads(sys.argv[1])
rt = d["personas"]["rtfm"]
assert rt["disposed"] == 2, rt        # f1 accepted in r_skel + r_skel_exp; no-record excluded
assert rt["false_positives"] == 0, rt
assert d["coverage"]["with_dispositions"] == 2, d["coverage"]  # skeleton-only run not counted
print("norecord-asserts-ok")
PY
rc_is $rc 0 "mine-runs: no-record excluded from disposed; skeleton-only run not with-dispositions"

echo "== finalize-calibration =="
FC_HOME="$TMP/fchome"; mkdir -p "$FC_HOME"
FCLOG="$TMP/fc-usage.log"
FCB="$ANGEL_RUNS_ROOT/fc_base"; FCR="$ANGEL_RUNS_ROOT/fc_read"
mk_usage "$FCB" 100000; mk_snapshot "$FCB"
mk_usage "$FCR" 120000; mk_snapshot "$FCR"
cat > "$FCLOG" <<EOF
2026-05-31 | fcproj | full | 1C/2I/0M/1N | total:100000 | cal:baseline | run:$FCB
2026-05-31 | fcproj | full | 1C/2I/0M/1N | total:120000 | cal:reader | run:$FCR
EOF
FCROOT="$TMP/fcroot"; mkdir -p "$FCROOT/fcproj"
rc=0; fout="$(HOME="$FC_HOME" ANGEL_USAGE_LOG="$FCLOG" "$DIR/finalize-calibration.py" 2>&1)" || rc=$?
rc_is $rc 0 "finalize-calibration dry-run exits 0 on fixture log"
has "tok=+20.0%" "$fout" "dry-run pairs baseline+reader and computes token delta"
rc=0; fskip="$(HOME="$FC_HOME" ANGEL_USAGE_LOG="$FCLOG" "$DIR/finalize-calibration.py" --write 2>&1)" || rc=$?
has "no dir under $FC_HOME/Projects" "$fskip" "marker-skip message names the searched root"
rc=0; HOME="$FC_HOME" ANGEL_USAGE_LOG="$FCLOG" "$DIR/finalize-calibration.py" --write --projects-root "$FCROOT" >/dev/null 2>&1 || rc=$?
rc_is $rc 0 "--projects-root override accepted"
FC_ENC="${FCROOT//\//-}-fcproj"
FC_MARK="$FC_HOME/.claude/projects/$FC_ENC/memory/reader-calibration.json"
[ -f "$FC_MARK" ] && ok "marker written for project under overridden root" || bad "marker written for project under overridden root" "missing $FC_MARK"
rm -rf "$FC_HOME/.claude/projects"
HOME="$FC_HOME" ANGEL_USAGE_LOG="$FCLOG" ANGEL_PROJECTS_ROOT="$FCROOT" "$DIR/finalize-calibration.py" --write >/dev/null 2>&1 || true
[ -f "$FC_MARK" ] && ok "ANGEL_PROJECTS_ROOT env override honored" || bad "ANGEL_PROJECTS_ROOT env override honored" "missing $FC_MARK"
# f8: two DIFFERENT same-file findings with NO line numbers must not collapse into
# one match (line defaults to 0; 0==0 used to satisfy the file-line branch).
F8B="$ANGEL_RUNS_ROOT/f8_base"; F8R="$ANGEL_RUNS_ROOT/f8_read"
mk_usage "$F8B" 100000; mk_usage "$F8R" 100000
cat > "$F8B/findings-snapshot.json" <<'JSON'
{"version":1,"findings":[
 {"id":"a","severity":"critical","title":"unchecked deserialization of payload","file":"src/app.py","personas":["adv"]},
 {"id":"b","severity":"critical","title":"missing auth on admin route","file":"src/app.py","personas":["rtfm"]}
]}
JSON
cat > "$F8R/findings-snapshot.json" <<'JSON'
{"version":1,"findings":[
 {"id":"a","severity":"critical","title":"unchecked deserialization of payload","file":"src/app.py","personas":["adv"]}
]}
JSON
F8LOG="$TMP/f8-usage.log"
cat > "$F8LOG" <<EOF
2026-05-31 | f8proj | full | 2C/0I/0M/0N | total:100000 | cal:baseline | run:$F8B
2026-05-31 | f8proj | full | 1C/0I/0M/0N | total:100000 | cal:reader | run:$F8R
EOF
rc=0; f8out="$(HOME="$FC_HOME" ANGEL_USAGE_LOG="$F8LOG" "$DIR/finalize-calibration.py" 2>&1)" || rc=$?
rc_is $rc 0 "f8 fixture dry-run exits 0"
has "lostC=1" "$f8out" "distinct same-file no-line findings do NOT collapse (dropped critical counts as lost)"
has "gainC=0" "$f8out" "same-file same-title no-line finding still matches (not gained)"

echo "== apply-verification.py =="
AV="$ANGEL_RUNS_ROOT/20260601T140000Z-verify1"
mk_usage "$AV" 80000; echo "stub" > "$AV/findings/adv.md"
cat > "$AV/findings-snapshot.json" <<'JSON'
{"version":2,"project":"demo","mode":"full","verdict":"CHANGES REQUIRED",
 "personas_run":["adv","rtfm"],"verify_queue":["f1","f2"],
 "findings":[
  {"id":"f1","severity":"critical","title":"Crit one","personas":["adv"],"verification":null},
  {"id":"f2","severity":"important","title":"Imp two","personas":["rtfm"],"verification":null},
  {"id":"f3","severity":"minor","title":"Min three","personas":["rtfm"],"verification":null}
 ]}
JSON
printf '# Code Review — CHANGES REQUIRED\n\n## Critical\n\n- stuff\n\n---\n\n*Review by NineAngel — 2026-06-01*\n' > "$AV/report.md"
cp "$AV/findings-snapshot.json" "$TMP/snap.orig"
# zero verdict files (missing dir, then empty dir) -> no-op exit 0, nothing written
rc=0; nout="$("$DIR/apply-verification.py" "$AV")" || rc=$?
rc_is $rc 0 "no verification dir -> exit 0"
has "no verdicts to apply" "$nout" "missing-dir no-op message emitted"
mkdir -p "$AV/verification"
rc=0; nout="$("$DIR/apply-verification.py" "$AV")" || rc=$?
rc_is $rc 0 "empty verification dir -> exit 0"
has "no verdicts to apply" "$nout" "empty-dir no-op message emitted"
cmp -s "$TMP/snap.orig" "$AV/findings-snapshot.json" && ok "no-op leaves snapshot untouched" || bad "no-op leaves snapshot untouched"
[ ! -e "$AV/verification-summary.md" ] && ok "no-op writes no summary" || bad "no-op writes no summary"
# happy path: REFUTED + CONFIRMED + unknown-id verdict
cat > "$AV/verification/f1.json" <<'JSON'
{"id":"f1","verdict":"REFUTED","method":"ran","evidence":"repro script shows the guard already covers this","note":"n"}
JSON
cat > "$AV/verification/f2.json" <<'JSON'
{"id":"f2","verdict":"CONFIRMED","method":"traced","evidence":"traced call path to unsanitized sink"}
JSON
cat > "$AV/verification/f9.json" <<'JSON'
{"id":"f9","verdict":"CONFIRMED","method":"ran","evidence":"ghost finding"}
JSON
rc=0; averr="$("$DIR/apply-verification.py" "$AV" 2>&1 >/dev/null)" || rc=$?
rc_is $rc 0 "apply exits 0 despite unknown verdict id"
has "f9" "$averr" "unknown finding id warned to stderr"
rc=0; python3 - "$AV" <<'PY' || rc=$?
import json, sys
s = json.load(open(sys.argv[1] + "/findings-snapshot.json"))
by = {f["id"]: f for f in s["findings"]}
assert by["f1"]["verification"] == {"verdict": "REFUTED", "method": "ran",
    "evidence": "repro script shows the guard already covers this"}, by["f1"]  # note NOT copied
assert by["f2"]["verification"]["verdict"] == "CONFIRMED", by["f2"]
assert by["f3"]["verification"] is None, by["f3"]           # no verdict -> stays null
assert s["verify_queue"] == ["f1", "f2"], s["verify_queue"] # queue untouched
print("av-asserts-ok")
PY
rc_is $rc 0 "verdicts patched into snapshot; verdict-less finding stays null"
sm="$(cat "$AV/verification-summary.md")"
has "## Verification" "$sm" "summary has section heading"
has "REFUTED:**" "$sm" "bold warning line above REFUTED items"
has "- **CONFIRMED** f2 (important) — Imp two — traced call path to unsanitized sink" "$sm" "verdict line format: - **verdict** id (severity) — title — evidence"
lr="$(grep -nF '**REFUTED** f1' "$AV/verification-summary.md" | cut -d: -f1)"
lc="$(grep -nF '**CONFIRMED** f2' "$AV/verification-summary.md" | cut -d: -f1)"
[ -n "$lr" ] && [ -n "$lc" ] && [ "$lr" -lt "$lc" ] && ok "REFUTED listed before CONFIRMED" || bad "REFUTED listed before CONFIRMED" "refuted@$lr confirmed@$lc"
has "All verified Criticals were REFUTED" "$sm" "all-criticals-refuted warning fires (only Critical refuted)"
[ "$(grep -c '^## Verification$' "$AV/report.md")" = 1 ] && ok "report.md gained one ## Verification section" || bad "report.md gained one ## Verification section"
has "All verified Criticals were REFUTED" "$(cat "$AV/report.md")" "report section carries the summary content"
# idempotent double-run: snapshot + summary + report all byte-identical
cp "$AV/findings-snapshot.json" "$TMP/snap.after1"; cp "$AV/verification-summary.md" "$TMP/sum.after1"; cp "$AV/report.md" "$TMP/rep.after1"
rc=0; "$DIR/apply-verification.py" "$AV" >/dev/null 2>/dev/null || rc=$?
rc_is $rc 0 "second run exits 0"
cmp -s "$TMP/snap.after1" "$AV/findings-snapshot.json" && ok "snapshot byte-identical after second run" || bad "snapshot byte-identical after second run"
cmp -s "$TMP/sum.after1" "$AV/verification-summary.md" && ok "summary byte-identical after second run" || bad "summary byte-identical after second run"
cmp -s "$TMP/rep.after1" "$AV/report.md" && ok "report.md byte-identical after second run (no duplicate section)" || bad "report.md byte-identical after second run"
# changed verdict -> report section replaced in place, never duplicated
cat > "$AV/verification/f2.json" <<'JSON'
{"id":"f2","verdict":"PLAUSIBLE","method":"traced","evidence":"sink reachable but input already validated upstream"}
JSON
"$DIR/apply-verification.py" "$AV" >/dev/null 2>/dev/null
[ "$(grep -c '^## Verification$' "$AV/report.md")" = 1 ] && ok "re-run replaces report section (still exactly one)" || bad "re-run replaces report section (still exactly one)" "$(grep -c '^## Verification$' "$AV/report.md") sections"
has "PLAUSIBLE" "$(cat "$AV/report.md")" "replaced section carries the new verdict"
hasnt "CONFIRMED" "$(cat "$AV/report.md")" "stale verdict gone from report after replace"
# new schema keys must not break the completeness gate (verification NOT gated in v1)
"$DIR/append-usage-log.sh" "$AV" >/dev/null
rc=0; "$DIR/check-run-complete.py" "$AV" >/dev/null 2>&1 || rc=$?
rc_is $rc 0 "check-run-complete passes with verify_queue/verification keys"
# all-criticals-refuted gating: an unverified Critical blocks the warning
AV2="$ANGEL_RUNS_ROOT/20260601T150000Z-verify2"
mkdir -p "$AV2/verification" "$AV2/findings"
cat > "$AV2/findings-snapshot.json" <<'JSON'
{"version":2,"verify_queue":["f1","f2"],"findings":[
 {"id":"f1","severity":"critical","title":"C1","personas":["adv"],"verification":null},
 {"id":"f2","severity":"critical","title":"C2","personas":["adv"],"verification":null}
]}
JSON
cat > "$AV2/verification/f1.json" <<'JSON'
{"id":"f1","verdict":"REFUTED","method":"traced","evidence":"code path not reachable"}
JSON
"$DIR/apply-verification.py" "$AV2" >/dev/null 2>/dev/null
hasnt "All verified Criticals" "$(cat "$AV2/verification-summary.md")" "unverified Critical blocks the all-refuted warning"
cat > "$AV2/verification/f2.json" <<'JSON'
{"id":"f2","verdict":"REFUTED","method":"ran","evidence":"the failing test passes on main"}
JSON
"$DIR/apply-verification.py" "$AV2" >/dev/null 2>/dev/null
has "All verified Criticals were REFUTED" "$(cat "$AV2/verification-summary.md")" "warning fires once every Critical is refuted"

echo "== aggregate-usage.py (verifier phase) =="
RAV="$ANGEL_RUNS_ROOT/20260601T160000Z-verify3"
mkdir -p "$RAV/findings"; echo "stub" > "$RAV/findings/adv.md"
cat > "$RAV/usage.jsonl" <<'JSONL'
{"phase":"persona","name":"adv","model":"claude-sonnet-4-6","total_tokens":50000,"tool_uses":10,"duration_ms":60000,"started_at":"2026-06-01T16:05:00Z","ended_at":"2026-06-01T16:06:00Z","reader_pack":false}
{"phase":"verifier","name":"f1","model":"claude-sonnet-4-6","total_tokens":7000,"tool_uses":3,"duration_ms":30000,"started_at":null,"ended_at":null,"reader_pack":false}
{"phase":"verifier","name":"f2","model":"claude-sonnet-4-6","total_tokens":null,"tool_uses":null,"duration_ms":null,"started_at":null,"ended_at":null,"reader_pack":false,"note":"unmeasured"}
JSONL
rc=0; python3 "$DIR/aggregate-usage.py" "$RAV" >/dev/null 2>&1 || rc=$?
rc_is $rc 0 "aggregate-usage exits 0 with verifier-phase lines"
rc=0; python3 - "$RAV" <<'PY' || rc=$?
import json, sys
u = json.load(open(sys.argv[1] + "/usage.json"))
assert u["totals"]["total_tokens"] == 57000, u["totals"]["total_tokens"]  # verifier tokens counted
assert u["unmeasured"] == ["verifier:f2"], u["unmeasured"]                # null verifier surfaces
assert len(u["totals"]["personas"]) == 1, u["totals"]["personas"]         # not misfiled as personas
assert u["totals"]["integrator"] is None, u["totals"]["integrator"]      # nor as integrator
print("rav-asserts-ok")
PY
rc_is $rc 0 "verifier lines aggregate into totals; not misfiled per-phase"

echo
echo "--- subsample-analyzer + shared matcher suite (test_subsample.py) ---"
rc=0; python3 "$DIR/test_subsample.py" || rc=$?
rc_is $rc 0 "subsample-analyzer + finding_match suite passes"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
