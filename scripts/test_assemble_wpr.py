#!/usr/bin/env python3
# pattern: imperative shell (test harness)
"""Unit tests for assemble-wpr.py — rid matching, pass_support, severity_drift, provenance.

Run: scripts/test_assemble_wpr.py   (exit 0 = all pass)
"""
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(DIR))
from finding_match import normalize_finding  # noqa: E402

spec = importlib.util.spec_from_file_location("assemble_wpr", DIR / "assemble-wpr.py")
aw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aw)

PASS = 0
FAIL = 0


def ok(name):
    global PASS
    PASS += 1
    print(f"ok   - {name}")


def bad(name, detail=""):
    global FAIL
    FAIL += 1
    print(f"FAIL - {name}\n     {detail}")


def check(cond, name, detail=""):
    ok(name) if cond else bad(name, detail)


RECON = [
    {"id": "C1", "severity": "critical", "title": "sql injection in a", "personas": ["adv", "hyper"], "file": "a.py", "line": "10"},
    {"id": "S1", "severity": "critical", "title": "race in writer c", "personas": ["naive"], "file": "c.py", "line": "5"},
    {"id": "U1", "severity": "minor", "title": "style nit d", "personas": ["test"], "file": "d.py", "line": "7"},
]
PASSES = {
    "adv": [
        {"i": 1, "model": "m", "findings": [{"severity": "critical", "title": "sql injection in a", "file": "a.py", "line": "10"}]},
        {"i": 2, "model": "m", "findings": [{"severity": "critical", "title": "sql injection a", "file": "a.py", "line": "11"}]},
    ],
    "hyper": [
        {"i": 1, "model": "m", "findings": [{"severity": "critical", "title": "sql inject a", "file": "a.py", "line": "10"}]},
        {"i": 2, "model": "m", "findings": []},
    ],
    "naive": [
        {"i": 1, "model": "m", "findings": [{"severity": "critical", "title": "race in writer c", "file": "c.py", "line": "5"}]},
        {"i": 2, "model": "m", "findings": []},
    ],
    "test": [
        {"i": 1, "model": "m", "findings": [{"severity": "minor", "title": "style nit d", "file": "d.py", "line": "7"}]},
        {"i": 2, "model": "m", "findings": [{"severity": "minor", "title": "style nit d", "file": "d.py", "line": "7"}]},
    ],
}


def test_best_rid():
    recon = aw._norm_reconciled(RECON, {})
    c1 = [c for c in recon if c["id"] == "C1"]
    pf = normalize_finding({"file": "a.py", "line": "11", "title": "sql injection a"})
    check(aw.best_rid(pf, c1, 0.5) == "C1", "best_rid: same file, closest line -> C1")
    # null-file title match
    nf = normalize_finding({"file": None, "title": "sql injection in a"})
    check(aw.best_rid(nf, c1, 0.5) == "C1", "best_rid: null-file title overlap -> C1")
    check(aw.best_rid(normalize_finding({"file": None, "title": "totally unrelated xyz"}), c1, 0.5) is None,
          "best_rid: unrelated -> None")


def test_assemble_core():
    recon = aw._norm_reconciled(RECON, {})
    wpr, ps, drift = aw.assemble_core(PASSES, recon, 0.5)
    # rid stamping
    check(wpr["adv"][0][0]["rid"] == "C1" and wpr["adv"][1][0]["rid"] == "C1", "core: adv both passes rid=C1")
    check(wpr["hyper"][0][0]["rid"] == "C1" and wpr["hyper"][1] == [], "core: hyper p1 rid=C1, p2 empty")
    check(wpr["adv"][0][0]["model"] == "m", "core: model carried onto pass findings")
    # pass_support {persona:[k,N]}
    check(ps["C1"] == {"adv": [2, 2], "hyper": [1, 2]}, "core: pass_support C1 adv[2,2] hyper[1,2]", str(ps.get("C1")))
    check(ps["S1"] == {"naive": [1, 2]}, "core: pass_support S1 naive[1,2] (k=1, floored ok)", str(ps.get("S1")))
    check(ps["U1"] == {"test": [2, 2]}, "core: pass_support U1 test[2,2]", str(ps.get("U1")))
    # severity_drift both directions
    dmap = {d["finding_id"]: d["drift"] for d in drift}
    check(dmap.get("S1") == "singleton-high", "drift: S1 critical singleton -> singleton-high", str(dmap))
    check(dmap.get("U1") == "unanimous-low", "drift: U1 minor unanimous -> unanimous-low", str(dmap))
    check("C1" not in dmap, "drift: C1 (2 personas, not unanimous) -> no drift")


def test_missing_attribution_floor():
    # a persona attributed to a finding but whose passes never matched -> k floored to 1
    recon = aw._norm_reconciled(
        [{"id": "X1", "severity": "important", "title": "ghost", "personas": ["adv"], "file": "z.py", "line": "1"}], {})
    passes = {"adv": [{"i": 1, "model": None, "findings": [{"severity": "minor", "title": "other", "file": "q.py", "line": "9"}]},
                      {"i": 2, "model": None, "findings": []}]}
    _, ps, _ = aw.assemble_core(passes, recon, 0.5)
    check(ps.get("X1") == {"adv": [1, 2]}, "floor: attributed-but-unmatched persona -> k=1 (not 0)", str(ps.get("X1")))


def _write_run(tmp, passes_files, snapshot):
    rd = Path(tmp)
    (rd / "passes").mkdir(exist_ok=True)
    for name, text in passes_files.items():
        (rd / "passes" / name).write_text(text)
    (rd / "findings-snapshot.json").write_text(json.dumps(snapshot))
    return rd


def test_single_pass_null():
    with tempfile.TemporaryDirectory() as tmp:
        rd = Path(tmp)
        (rd / "findings-snapshot.json").write_text(json.dumps({"findings": [], "within_persona_runs": None}))
        a = aw.assemble(str(rd))
        check(a["within_persona_runs"] is None and a["single_pass"], "single-pass: no passes/ -> null")
        okc, _ = aw.check(str(rd))
        check(okc, "single-pass: provenance check ok (null == null)")


def test_provenance_roundtrip():
    snap = {"findings": [dict(f) for f in RECON], "within_persona_runs": None}
    with tempfile.TemporaryDirectory() as tmp:
        files = {
            "adv-p1.md": "#### Critical (blocks ship)\n- **sql injection in a** `[moderate]` — `a.py:10` — x\n",
            "adv-p2.md": "#### Critical (blocks ship)\n- **sql injection a** `[moderate]` — `a.py:11` — x\n",
            "CONSOLIDATED.md": "junk, should be skipped\n",
        }
        rd = _write_run(tmp, files, snap)
        a = aw.assemble(str(rd))
        aw._write(a, 0.5)
        okc, reason = aw.check(str(rd))
        check(okc, "provenance: write then check == ok", reason)
        # tamper the stored field -> check must fail
        s = json.loads((rd / "findings-snapshot.json").read_text())
        s["within_persona_runs"]["adv"][0][0]["rid"] = "TAMPERED"
        (rd / "findings-snapshot.json").write_text(json.dumps(s))
        okc2, _ = aw.check(str(rd))
        check(not okc2, "provenance: tampered field -> check fails")
        # the junk file was skipped, noted
        check(any("CONSOLIDATED" in n for n in a["notes"]), "provenance: non-pass junk file skipped + noted")


test_best_rid()
test_assemble_core()
test_missing_attribution_floor()
test_single_pass_null()
test_provenance_roundtrip()
print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
