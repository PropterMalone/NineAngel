#!/usr/bin/env python3
# pattern: imperative shell (I/O: read passes + snapshot, write snapshot); pure assembly core
"""assemble-wpr.py — mechanically build within_persona_runs from passes/*.md (ADR-12).

The single post-integrator assembly step. No LLM writes within_persona_runs; this
script does, deterministically, from the durable per-pass markdown. It:

  1. discovers passes/{persona}-p{i}.md (tolerant of legacy _p/_pass; skips junk),
     parses each with parse-findings.py, groups by canonical persona + pass index;
  2. builds within_persona_runs = {persona: [[{severity,title,file,line,rid,model}], ...]};
  3. stamps each pass finding's `rid` = the reconciled finding it maps into
     (constrained: persona ∈ F.personas; same-file + closest-line, else title overlap;
     null-file by title) — inherits the integrator's semantic identity;
  4. computes pass_support {finding_id: {persona:[k,N]}} (k floored at 1 for a persona
     the integrator attributed — its membership in F.personas is authoritative);
  5. records a severity_drift audit (D5-audit): where the LLM's severity disagrees with
     what the k/N rule would give — advisory, never a failure (rule-22 override is legit);
  6. injects within_persona_runs + per-finding pass_support + severity_drift into the
     snapshot (default), or --check compares against the stored field (the provenance gate).

Single-pass / no passes/ dir → within_persona_runs: null, exit 0 (unattended/--single).

Since ADR-12 defers D5, rid/pass_support are analytics-tier (the shipped verdict still
uses the reconciler's (k/N) tags), so best-effort matching is acceptable.

Usage: assemble-wpr.py <run_dir> [--check] [--json] [--threshold 0.5] [--line-window 10]
"""
import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

_D = Path(__file__).resolve().parent
sys.path.insert(0, str(_D))
from finding_match import normalize_finding, file_match, title_overlap, SEV_RANK  # noqa: E402
from persona_aliases import build_persona_aliases, canon_persona  # noqa: E402

_spec = importlib.util.spec_from_file_location("parse_findings", _D / "parse-findings.py")
parse_findings_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(parse_findings_mod)
parse_findings = parse_findings_mod.parse_findings

# passes/{persona}-p{i}.md, tolerating legacy {persona}_p{i} / {persona}_pass{i};
# rejects CONSOLIDATED.md, {persona}{i}-summary.md (no p<digit> segment).
_PASS_RE = re.compile(r"^(?P<persona>.+?)[-_](?:p|pass)(?P<i>\d+)\.md$", re.IGNORECASE)
_MODEL_RE = re.compile(r"<!--\s*angel-pass[^>]*\bmodel=(\S+)[^>]*-->")
_FAILED_RE = re.compile(r"<!--\s*angel-pass[^>]*\bfailed\b[^>]*-->")


# ============================ FUNCTIONAL CORE ============================
# Pure: given parsed passes + reconciled findings, compute the artifacts. No I/O.

def _norm_reconciled(findings, amap):
    """Reconciled findings[] -> matcher-ready records with id + canon persona set."""
    out = []
    for f in findings or []:
        if not isinstance(f, dict) or not f.get("id"):
            continue
        nf = normalize_finding(f)  # nfile/title/toks/sev/line — tolerant of missing file/line
        out.append({
            "id": f["id"],
            "severity": (f.get("severity") or "noted").lower(),
            "personas": {canon_persona(p, amap) for p in (f.get("personas") or [])},
            "nfile": nf["nfile"], "toks": nf["toks"], "line": nf["line"],
        })
    return out


def best_rid(pf, candidates, threshold):
    """Best reconciled id for a pass finding among candidates (already filtered to
    persona ∈ F.personas). Same-file + closest-line wins; else title overlap; else None."""
    if not candidates:
        return None
    if pf["nfile"]:
        same = [c for c in candidates if c["nfile"] and file_match(pf["nfile"], c["nfile"])]
        if same:
            if pf["line"] is not None:
                lined = [(abs(pf["line"] - c["line"]), c["id"]) for c in same if c["line"] is not None]
                if lined:
                    lined.sort(key=lambda t: (t[0], t[1]))  # closest line, id tiebreak
                    return lined[0][1]
            t = _best_title(pf, same, threshold)
            return t if t else sorted(c["id"] for c in same)[0]
    return _best_title(pf, candidates, threshold)


def _best_title(pf, cands, threshold):
    best, best_ov = None, threshold
    for c in cands:
        ov = title_overlap(pf["toks"], c["toks"])
        if ov >= best_ov:
            best_ov, best = ov, c["id"]
    return best


def assemble_core(passes_by_persona, reconciled, threshold):
    """passes_by_persona: {persona: [ {i, model, findings:[{severity,title,file,line}]} ]}
    reconciled: output of _norm_reconciled. Returns (within_persona_runs, pass_support, drift)."""
    # within_persona_runs + rid stamping
    wpr = {}
    for persona in sorted(passes_by_persona):
        cands = [c for c in reconciled if persona in c["personas"]]
        passes = sorted(passes_by_persona[persona], key=lambda p: p["i"])
        sub = []
        for p in passes:
            block = []
            for raw in p["findings"]:
                nf = normalize_finding(raw)
                rid = best_rid(nf, cands, threshold)
                block.append({
                    "severity": raw.get("severity"), "title": raw.get("title"),
                    "file": raw.get("file"), "line": raw.get("line"),
                    "rid": rid, "model": p["model"],
                })
            sub.append(block)
        wpr[persona] = sub

    # pass_support {id: {persona:[k,N]}} — k floored at 1 for attributed personas
    pass_support = {}
    for c in reconciled:
        entry = {}
        for persona in sorted(c["personas"]):
            passes = wpr.get(persona)
            if not passes:
                continue  # persona ran but produced no parseable passes; skip
            N = len(passes)
            k = sum(1 for blk in passes if any(fi["rid"] == c["id"] for fi in blk))
            entry[persona] = [max(1, k), N]
        if entry:
            pass_support[c["id"]] = entry

    # severity_drift audit (advisory)
    drift = []
    for c in reconciled:
        ps = pass_support.get(c["id"])
        if not ps:
            continue
        vals = list(ps.values())  # [[k,N], ...]
        multiball = any(N >= 2 for _, N in vals)
        if not multiball:
            continue
        single_pass_singleton = len(vals) == 1 and vals[0][0] == 1 and vals[0][1] >= 2
        all_unanimous = all(k == N for k, N in vals)
        sev = c["severity"]
        if single_pass_singleton and SEV_RANK.get(sev, 0) >= 2:  # important/critical
            drift.append({"finding_id": c["id"], "severity": sev,
                          "drift": "singleton-high", "pass_support": ps})
        elif all_unanimous and SEV_RANK.get(sev, 0) <= 1:  # minor/noted
            drift.append({"finding_id": c["id"], "severity": sev,
                          "drift": "unanimous-low", "pass_support": ps})
    return wpr, pass_support, drift


# ============================ IMPERATIVE SHELL ============================

def _read_passes(run_dir, amap):
    """Discover + parse passes/*.md. Returns (passes_by_persona, notes).
    A --failed stub contributes no findings sub-array (excused from N)."""
    pdir = Path(run_dir) / "passes"
    by = {}
    notes = []
    if not pdir.is_dir():
        return by, notes
    for f in sorted(pdir.glob("*.md")):
        m = _PASS_RE.match(f.name)
        if not m:
            notes.append(f"skipped non-pass file: {f.name}")
            continue
        persona = canon_persona(m.group("persona"), amap)
        i = int(m.group("i"))
        text = f.read_text(encoding="utf-8", errors="replace")
        model_m = _MODEL_RE.search(text)
        model = model_m.group(1) if model_m else None
        if _FAILED_RE.search(text):
            notes.append(f"failed pass excused: {f.name}")
            continue
        parsed = parse_findings(text)
        if parsed["status"] == "no-structure":
            notes.append(f"UNPARSEABLE (no severity structure): {f.name}")
        by.setdefault(persona, []).append({"i": i, "model": model, "findings": parsed["findings"]})
    return by, notes


def assemble(run_dir, threshold=0.5):
    """Read passes + snapshot, compute artifacts. Does NOT write. Returns a dict."""
    run_dir = Path(run_dir)
    amap = build_persona_aliases(_D.parent)
    passes_by_persona, notes = _read_passes(run_dir, amap)

    snap_path = run_dir / "findings-snapshot.json"
    snap = None
    if snap_path.is_file():
        try:
            snap = json.loads(snap_path.read_text())
        except Exception:
            snap = None
    reconciled = _norm_reconciled((snap or {}).get("findings"), amap)

    if not passes_by_persona:
        # single-pass / no passes/ dir -> null field, no support
        return {"within_persona_runs": None, "pass_support": {}, "severity_drift": [],
                "notes": notes, "snapshot": snap, "snap_path": snap_path, "single_pass": True}

    wpr, pass_support, drift = assemble_core(passes_by_persona, reconciled, threshold)
    return {"within_persona_runs": wpr, "pass_support": pass_support, "severity_drift": drift,
            "notes": notes, "snapshot": snap, "snap_path": snap_path, "single_pass": False}


def _canon(obj):
    return json.dumps(obj, sort_keys=True, ensure_ascii=False)


def check(run_dir, threshold=0.5):
    """Provenance check: does the snapshot's stored within_persona_runs equal a fresh
    recompute? Returns (ok, reason). Single-pass (null) is vacuously ok."""
    a = assemble(run_dir, threshold)
    snap = a["snapshot"]
    if snap is None:
        return False, "no findings-snapshot.json to check"
    if a["single_pass"]:
        stored = snap.get("within_persona_runs")
        return (stored in (None, {}, [])), ("single-pass ok" if stored in (None, {}, []) else
                                            "single-pass run but snapshot has a non-null within_persona_runs")
    stored = snap.get("within_persona_runs")
    if _canon(stored) == _canon(a["within_persona_runs"]):
        return True, "provenance ok"
    return False, "within_persona_runs != assemble-wpr recompute (tampered/stale/LLM-written)"


def _write(a, threshold):
    snap = a["snapshot"]
    if snap is None:
        return "no snapshot to write"
    snap["within_persona_runs"] = a["within_persona_runs"]
    snap["severity_drift"] = a["severity_drift"]
    if not a["single_pass"]:
        for f in snap.get("findings") or []:
            if isinstance(f, dict) and f.get("id") in a["pass_support"]:
                f["pass_support"] = a["pass_support"][f["id"]]
    a["snap_path"].write_text(json.dumps(snap, indent=2, ensure_ascii=False))
    return f"wrote within_persona_runs ({0 if a['single_pass'] else len(a['within_persona_runs'])} personas), " \
           f"pass_support ({len(a['pass_support'])}), severity_drift ({len(a['severity_drift'])})"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir")
    ap.add_argument("--check", action="store_true", help="provenance check vs stored field; exit 0/1")
    ap.add_argument("--json", action="store_true", help="print computed artifacts, do not write")
    ap.add_argument("--threshold", type=float, default=0.5)
    args = ap.parse_args()

    if args.check:
        ok, reason = check(args.run_dir, args.threshold)
        print(reason, file=sys.stderr if not ok else sys.stdout)
        sys.exit(0 if ok else 1)

    a = assemble(args.run_dir, args.threshold)
    if args.json:
        print(json.dumps({k: a[k] for k in ("within_persona_runs", "pass_support", "severity_drift", "notes")},
                         indent=2, ensure_ascii=False))
        return
    msg = _write(a, args.threshold)
    for n in a["notes"]:
        print(f"note: {n}", file=sys.stderr)
    print(msg)


if __name__ == "__main__":
    main()
