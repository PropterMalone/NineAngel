#!/usr/bin/env python3
# pattern: functional core
"""Deterministic parser: a persona's markdown finding block -> structured findings.

The single md->struct transcription in the ADR-12 capture pipeline (no LLM assembles
within_persona_runs). Built against the REAL passes/*.md corpus, not the spec — which
shows >=3 formats:
  A canonical:  `#### Critical (blocks ship)` then `- **title** `[effort]` — `file:line` — desc`
  B compact:    `#### Important` (bare) then `- prose bullet`, file:line in parens, no title
  C bare-label: `CRITICAL:` / `IMPORTANT:` (no #, all-caps or Title-case, trailing colon),
                sometimes with run-on text on the same line (`NOTED: foo; bar`).
Plus `None.` / `No findings.` markers, preambles, and `### Cap overflow`/`Contradictions`/
`Reconciler notes` sections.

LOUDNESS (ADR-12 "loud, not silent-empty"). The real corpus is too prose-variant for
line-level strict-consume (it would error on nearly every pass). The guard that actually
matters is at the STRUCTURE level: a file with real content but NO recognizable severity
section returns status="no-structure" — the caller treats that as a parse failure
(capture-time rejection / gate INCOMPLETE) instead of a silent empty array. Findings that
ARE under a recognized section but lack a structured title/file (formats B/C) are returned
best-effort (title = first clause, file/line = first `path.ext:line` in the bullet, else
null) — the data is real, just less structured; dropping it silently is the bug.

Pure: no I/O. parse_findings(text) -> {"findings": [{severity,title,file,line}], "status"}.
"""
import re

SEVERITIES = ("critical", "important", "minor", "noted")

# Severity header line: optional leading #'s, the severity word, optional "(label)" and/or
# trailing ":". Matches "#### Critical (blocks ship)", "#### Important", "CRITICAL:", "Critical:".
_SEV_HDR = re.compile(
    r"^\s*#{0,4}\s*(critical|important|minor|noted)\b\s*(?:\([^)]*\))?\s*:?\s*$",
    re.IGNORECASE,
)
# Bare label with run-on text on the same line: "NOTED: foo; bar".
_SEV_INLINE = re.compile(
    r"^\s*#{0,4}\s*(critical|important|minor|noted)\s*(?:\([^)]*\))?\s*:\s+(\S.*)$",
    re.IGNORECASE,
)
_BULLET = re.compile(r"^\s*[-*]\s+(.*\S)\s*$")
_BOLD_TITLE = re.compile(r"\*\*(.+?)\*\*")
_NONE = re.compile(r"^\s*(none\.?|no findings\.?)\s*$", re.IGNORECASE)
# file:line — require a dot-extension so ratios/times/`N:M` don't match. Range tail ok.
_FILELINE = re.compile(r"([\w./-]+\.[A-Za-z0-9]+):(\d+(?:-\d+)?)")
# Section headers that are NOT severity sections — skipped, not errored.
_SKIP_HDR = re.compile(
    r"^\s*#{1,4}\s*(findings|cap overflow|contradictions|reconciler notes|"
    r"structural|verification|per-file|summary|preamble)\b",
    re.IGNORECASE,
)
_PERSONA_HDR = re.compile(r"^\s*#{1,3}\s*\[?[^\]]+\]?\s*(review|pass)\b", re.IGNORECASE)


def _title_from(text):
    """Best-effort finding title. Prefer a bold span; else the first clause up to an
    em/en-dash or sentence end; capped so a run-on prose bullet doesn't become the title."""
    m = _BOLD_TITLE.search(text)
    if m:
        return m.group(1).strip()
    # split on em/en-dash (the canonical title/desc separator) or first sentence
    head = re.split(r"\s[—–-]\s", text, 1)[0]
    head = re.split(r"(?<=[.;])\s", head, 1)[0]
    head = head.strip().strip("`").strip()
    return (head[:117] + "...") if len(head) > 120 else head


def _fileline_from(text):
    """First `path.ext:line` in the bullet -> (file, line) or (None, None). Skips a
    leading effort tag like `[moderate]` (no colon-digit, so it won't match anyway)."""
    m = _FILELINE.search(text)
    if not m:
        return None, None
    return m.group(1), m.group(2)


def _finish(cur, findings):
    if cur is None:
        return
    text = " ".join(cur["lines"]).strip()
    if not text:
        return
    f, ln = _fileline_from(text)
    findings.append({
        "severity": cur["severity"],
        "title": _title_from(text),
        "file": f,
        "line": ln,
    })


def parse_findings(text):
    """Parse a persona markdown finding block into structured findings.

    Returns {"findings": [...], "status": "ok"|"empty"|"no-structure"}.
      ok           — >=1 severity section recognized and >=1 finding parsed.
      empty        — severity sections recognized but all None./No findings.
      no-structure — real content but no severity section recognized (the loud
                     silent-empty guard: caller treats as a parse failure).
    """
    findings = []
    cur = None                 # {"severity", "lines": [...]} — the open bullet
    current_severity = None
    saw_severity_header = False
    saw_content = False

    for raw in (text or "").splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue

        mi = _SEV_INLINE.match(line)
        if mi:
            _finish(cur, findings); cur = None
            current_severity = mi.group(1).lower()
            saw_severity_header = True
            # run-on text after the colon is itself finding content
            cur = {"severity": current_severity, "lines": [mi.group(2).strip()]}
            continue

        mh = _SEV_HDR.match(line)
        if mh:
            _finish(cur, findings); cur = None
            current_severity = mh.group(1).lower()
            saw_severity_header = True
            continue

        if _NONE.match(line):
            _finish(cur, findings); cur = None
            continue

        if _PERSONA_HDR.match(line) or _SKIP_HDR.match(line):
            _finish(cur, findings); cur = None
            continue

        mb = _BULLET.match(line)
        if mb and current_severity:
            _finish(cur, findings)
            cur = {"severity": current_severity, "lines": [mb.group(1)]}
            saw_content = True
            continue

        # continuation of an open bullet (multi-line description)
        if cur is not None:
            cur["lines"].append(line.strip())
            continue

        # non-blank content outside any section (preamble prose etc.)
        saw_content = True

    _finish(cur, findings)

    if findings:
        status = "ok"
    elif saw_severity_header:
        status = "empty"          # sections present, all None. — a valid all-clean pass
    elif saw_content:
        status = "no-structure"   # content but nothing recognized -> loud failure
    else:
        status = "empty"          # genuinely blank
    return {"findings": findings, "status": status}


# CLI: capture-time validation for record-dispatch.sh --pass. Reads a pass block
# from a file arg or stdin, prints the status, exits 2 on no-structure (reject).
if __name__ == "__main__":
    import sys
    _text = open(sys.argv[1], encoding="utf-8", errors="replace").read() if len(sys.argv) > 1 else sys.stdin.read()
    _r = parse_findings(_text)
    print(_r["status"])
    sys.exit(2 if _r["status"] == "no-structure" else 0)
