---
id: 10-cross-leg-auto-attach-on-full
name: Auto-attach the cross-model leg on --full/--all + enrich its log for precision
date: 2026-07-15
status: superseded-in-part
supersedes: null
superseded_note: "2026-07-18 the user extended cross-default-on to every interactive run (not just --full/--all) per SKILL.md §5.6 decision note. The measurability enhancements (had_angel_report, fid, xreview-dispositions.py) remain active. The --full/--all-only trigger is the superseded part."
commits: [1211ba6]
---

# Cross-model leg: auto-attach on --full, and make the trial measurable

**Decision**: The `--cross` leg (§5.6, `xreview.py`) now runs automatically on `--full`/`--all` runs (suppress with `--no-cross`); it stays opt-in on diff/micro and unattended. Its self-log (`xreview-runs.jsonl`) gains `had_angel_report` and a per-finding stable `fid`; a companion `xreview-disposition.py` records real-vs-noise per finding into `xreview-dispositions.jsonl`.

**Why.** The 2026-07-15 evaluation of the leg (task due 07-07) could not reach a keep/drop verdict — and the reason was measurement, not the tool:

1. **The corpus was unrepresentative and non-evaluable.** 5 runs, all on the 2026-06-23 setup day, `backend=agy` only (codex never exercised). 3 were tiny synthetic smoke-tests; only 2 reviewed real code (xreview.py's own dev diffs).
2. **The headline metric was a false negative.** `refutes=0` across all 5 looked damning, but **no run was fed an Angel report** — a report-less run structurally *cannot* refute Angel or find "what Angel missed." You cannot read "no refute value" off runs incapable of producing a refutation. Nothing in the old log distinguished paired (evaluable) runs from cold ones.
3. **The one real signal was positive.** On the 2 runs against real code, the cross model surfaced ≥4 concrete bugs (ARG_MAX, non-UTF-8 crash, unlogged failures, ValueError on non-numeric confidence) that were all fixed before xreview's first commit — verified against the shipped code. Model-independence delivered on the only real code it saw.
4. **It went dormant because it was pure opt-in** — 0 runs in the ~3 weeks after setup. The value can't accrue if nobody remembers the flag.

Auto-attaching on `--full`/`--all` puts the leg where its one extra call is most worth it (pre-ship, high-leverage, larger input) AND makes it generate the paired Angel+cross corpus the next evaluation needs. `had_angel_report` + `fid` + the disposition sidecar convert the next evaluation from finding-**count** (which rewards noise) to **precision** (real vs noise on paired runs).

**Expected effect**: paired, disposition-labeled runs accrue on every `--full`; the keep/drop decision becomes answerable with data instead of hitting the same wall.

**Could-be-wrong-if** (falsifiers, the concrete re-evaluation bar):
- Over the next ≥5 **paired** runs (`had_angel_report:true`), the cross leg surfaces **zero** findings dispositioned `real`/`accepted` that Angel missed **and** zero correct refutes of Angel → drop the leg. That is the clean negative the 2026-06 trial couldn't produce.
- Auto-attach makes `--full` runs materially slower/costlier without payoff (cross findings all `noise`/`dup` over ≥5 runs) → revert to opt-in.
- The codex backend, once exercised on GSD `--full` runs, proves unreliable (timeouts/parse-fail rate > agy) → pin backend or restrict auto-attach to agy.

**Rejected alternatives.**
- **Decide keep/drop now on the 5-run corpus.** Rejected: the corpus can't answer the question (see 1–2). Deciding on it would be vibes, not data — the exact thing the task forbade.
- **Drop the leg for dormancy.** Rejected: dormancy was an opt-in artifact, and the one real-code signal was positive. Killing a demonstrated-useful capability over a measurement gap is the wrong lesson.
- **Auto-attach on standard runs too.** Rejected: standard runs are frequent (milestone cadence); a backend call per standard run reintroduces the cost pressure ADR-09 just relieved. `--full` is the leverage tier that justifies it.
