#!/usr/bin/env python3
# pattern: functional core + imperative shell
"""True-cost meter — what a run actually cost, as opposed to what usage.log records.

WHY THIS EXISTS
---------------
`usage.json`/`usage.log` `total_tokens` per pass is the size of that pass's
LAST assistant message -- a context-window high-water mark, not spend. Verified
2026-08-09 against subagent transcripts: the recorded figure matched each pass's
peak single-turn context to within 0.2% across 8/8 agents, against cumulative
flows 18.8x-43.5x larger. The ratio grows with turn count, so the metric is not
even a consistent proxy: it flatters long agentic passes and penalises short
ones with fat contexts.

This script reads the real numbers out of the subagent transcripts the harness
writes, sums the four billable token classes, and prices them.

ATTRIBUTION
-----------
Per-pass attribution needs a join between usage.jsonl records and transcripts,
and the only available key -- (tool_uses, last-turn context) -- collides. So
this script does NOT attribute per persona. It scopes by the run's time window
and reports the total plus a per-model breakdown, which is the number every
cost decision in the ADRs actually needs. It reports how many transcripts it
matched so a low-confidence result is visible rather than silent.

USAGE
-----
  true-cost.py <run_dir> [--json] [--write]

  --write   merge `cost` into the run's usage.json (does not touch usage.log)

Prices are Anthropic list, USD per million tokens, as of 2026-08-09. Cache
writes bill at 1.25x input (5-minute TTL, which is what the transcripts show);
cache reads at 0.1x. On a Max plan the marginal cash cost is zero and the true
currency is quota -- these figures are for RELATIVE comparison between runs and
stages, and should not be quoted as spend.
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# --- functional core -------------------------------------------------------

PRICES = {  # (input, output) USD per 1M tokens
    "claude-fable-5": (10.0, 50.0),
    "claude-mythos-5": (10.0, 50.0),
    "claude-opus-5": (5.0, 25.0),
    "claude-opus-4-8": (5.0, 25.0),
    "claude-opus-4-7": (5.0, 25.0),
    "claude-opus-4-6": (5.0, 25.0),
    "claude-sonnet-5": (3.0, 15.0),
    "claude-sonnet-4-6": (3.0, 15.0),
    "claude-haiku-4-5": (1.0, 5.0),
}
CACHE_WRITE_MULT = 1.25   # 5-minute TTL
CACHE_READ_MULT = 0.10
UNKNOWN_MODEL_FALLBACK = "claude-sonnet-5"


def price_for(model):
    """Longest-prefix match so dated snapshots (…-20251001) resolve."""
    if not model:
        return PRICES[UNKNOWN_MODEL_FALLBACK], True
    best = None
    for k in PRICES:
        if model.startswith(k) and (best is None or len(k) > len(best)):
            best = k
    if best:
        return PRICES[best], False
    return PRICES[UNKNOWN_MODEL_FALLBACK], True


def cost_of(counts, model):
    """counts: dict with input/output/cache_write/cache_read. -> USD float."""
    (pin, pout), guessed = price_for(model)
    usd = (counts["input"] * pin
           + counts["output"] * pout
           + counts["cache_write"] * pin * CACHE_WRITE_MULT
           + counts["cache_read"] * pin * CACHE_READ_MULT) / 1_000_000
    return usd, guessed


def tally_transcript(lines):
    """Sum billable token classes over one agent transcript's assistant messages.

    Returns (model, counts, turns). Model is the first one seen; a transcript
    is one agent, so it does not switch models mid-run.
    """
    c = {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0}
    model, turns = None, 0
    for line in lines:
        try:
            d = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            continue
        m = d.get("message")
        if not isinstance(m, dict):
            continue
        u = m.get("usage")
        if not isinstance(u, dict):
            continue
        turns += 1
        model = model or m.get("model")
        c["input"] += u.get("input_tokens", 0) or 0
        c["output"] += u.get("output_tokens", 0) or 0
        c["cache_write"] += u.get("cache_creation_input_tokens", 0) or 0
        c["cache_read"] += u.get("cache_read_input_tokens", 0) or 0
    return model, c, turns


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).astimezone(timezone.utc)
    except (ValueError, TypeError):
        return None


# --- imperative shell ------------------------------------------------------

def find_transcripts(run_dir, started, ended, projects_root=None):
    """Agent transcripts whose mtime falls in the run window.

    mtime is the completion time, so a pass that started before the window but
    finished inside it is included -- which is what we want for a run total.
    """
    root = Path(projects_root or (Path.home() / ".claude" / "projects"))
    if not root.is_dir():
        return []
    out = []
    for p in root.glob("*/*/subagents/agent-*.jsonl"):
        try:
            mt = datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc)
        except OSError:
            continue
        if started and mt < started:
            continue
        if ended and mt > ended:
            continue
        out.append(p)
    return sorted(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--write", action="store_true",
                    help="merge `cost` into the run's usage.json")
    ap.add_argument("--projects-root", default=None)
    ap.add_argument("--slack-seconds", type=int, default=900,
                    help="widen the window each side; transcripts flush after the pass ends")
    args = ap.parse_args()

    run = Path(args.run_dir)
    uj = run / "usage.json"
    if not uj.is_file():
        print(f"ERROR: no usage.json in {run}", file=sys.stderr)
        return 2
    usage = json.loads(uj.read_text())

    started = parse_ts(usage.get("started_at"))
    ended = parse_ts(usage.get("ended_at"))
    if started:
        started = started.fromtimestamp(started.timestamp() - args.slack_seconds, tz=timezone.utc)
    if ended:
        ended = ended.fromtimestamp(ended.timestamp() + args.slack_seconds, tz=timezone.utc)

    files = find_transcripts(run, started, ended, args.projects_root)
    by_model, total = {}, {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0}
    usd_total, guessed_models, turns_total = 0.0, set(), 0

    for f in files:
        try:
            model, c, turns = tally_transcript(f.read_text(errors="replace").splitlines())
        except OSError:
            continue
        if turns == 0:
            continue
        usd, guessed = cost_of(c, model)
        if guessed and model:
            guessed_models.add(model)
        key = model or "unknown"
        slot = by_model.setdefault(key, {"agents": 0, "turns": 0, "usd": 0.0,
                                         **{k: 0 for k in total}})
        slot["agents"] += 1
        slot["turns"] += turns
        slot["usd"] += usd
        for k in total:
            slot[k] += c[k]
            total[k] += c[k]
        usd_total += usd
        turns_total += turns

    # The time window is a scope, not an attribution: concurrent work from other
    # sessions lands inside it. Compare against the run's own dispatch count so a
    # divergence is visible instead of silently inflating the total.
    dispatched = 0
    ujl = run / "usage.jsonl"
    if ujl.is_file():
        dispatched = sum(1 for ln in ujl.read_text(errors="replace").splitlines() if ln.strip())

    recorded = (usage.get("totals") or {}).get("total_tokens")
    cum = sum(total.values())
    payload = {
        "usd_total": round(usd_total, 2),
        "tokens_cumulative": cum,
        "tokens_recorded_peak": recorded,
        "understatement_x": round(cum / recorded, 1) if recorded else None,
        "agents_matched": sum(v["agents"] for v in by_model.values()),
        "dispatches_logged": dispatched or None,
        "turns": turns_total,
        "by_class": total,
        "by_model": {k: {**v, "usd": round(v["usd"], 2)} for k, v in by_model.items()},
        "unpriced_models": sorted(guessed_models),
        "method": "time-window scope over subagent transcripts; no per-persona attribution",
    }

    if args.write:
        usage["cost"] = payload
        uj.write_text(json.dumps(usage, indent=2) + "\n")

    if args.json:
        print(json.dumps(payload, indent=2))
        return 0

    if not payload["agents_matched"]:
        print(f"no subagent transcripts found in the run window for {run.name}")
        print("  (transcripts may be pruned, or the run predates per-agent transcript retention)")
        return 0

    print(f"run {run.name}")
    print(f"  agents matched : {payload['agents_matched']}  ({turns_total} metered turns)")
    if dispatched and payload["agents_matched"] != dispatched:
        d = payload["agents_matched"] - dispatched
        print(f"  ! window caught {abs(d)} {'more' if d > 0 else 'fewer'} transcripts than the "
              f"{dispatched} dispatches this run logged -- the window is a scope, not an "
              f"attribution. Treat the total as +/-{abs(d)/dispatched*100:.0f}%.")
    print(f"  recorded total : {recorded:,}  <- usage.log `total:` (peak context)"
          if recorded else "  recorded total : n/a")
    print(f"  actual flow    : {cum:,}"
          + (f"  ({payload['understatement_x']}x)" if payload["understatement_x"] else ""))
    print(f"  cost (list)    : ${usd_total:,.2f}")
    print("  by class       : " + "  ".join(
        f"{k}={v:,}" for k, v in total.items()))
    print("  by model:")
    for k, v in sorted(by_model.items(), key=lambda kv: -kv[1]["usd"]):
        print(f"    {k:24} {v['agents']:3} agents  {v['turns']:5} turns  ${v['usd']:8,.2f}")
    if guessed_models:
        print(f"  ! unpriced models fell back to {UNKNOWN_MODEL_FALLBACK}: "
              + ", ".join(sorted(guessed_models)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
