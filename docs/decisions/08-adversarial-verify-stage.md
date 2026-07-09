---
id: 08-adversarial-verify-stage
name: Adversarial verification stage — causal credibility for uncorroborated findings
date: 2026-07-08
status: active
supersedes: null
commits: []
---

# Adversarial verification stage (§5.7)

**Decision**: Add a default-ON verification stage after the integrator. The integrator (Phase 3.5) queues up to 8 findings — every Critical, singleton sub-`cited-spec` Importants, and all consistency-shaped C/I claims — and the orchestrator dispatches one **verifier** subagent per entry (`verifier.md`: refute-first mandate, run-it-preferred, read-only). Verdicts (`CONFIRMED`/`PLAUSIBLE`/`REFUTED`) are applied mechanically (`scripts/apply-verification.py`): CONFIRMED anchors a Critical regardless of corroboration; REFUTED findings stay in the snapshot as calibration data but are excluded from fix batches and surfaced first in a `## Verification` report section. `--no-verify` skips.

**Why.** Three converging lines of evidence, all from 2026-07-08 and the leg 1–3 evals:

1. **Every false positive in the eval record (3/3) was an unverified cross-file consistency claim** — the N1 lure took sonnet twice and Fable once with the same wrong story. A single `node -e` check kills the class. The severity-calibration rule shipped this morning asks finders to self-verify; a dedicated adversarial pass is the mechanized version (this project's history: discipline decays, mechanism survives).
2. **/code-review's internal verify stage demonstrated the design working** on our own seeded benchmark, twice (2026-07-08 arms: 8/8 catches with empirical repros AND correct handling of the N1 lure at both effort levels — `_scoring-notes-cr-arm.md`). This stage is the deliberate steal-back of that architecture.
3. **It is the causal substitute for corroboration where corroboration is absent.** Multiball buys credibility statistically at ~2× whole-battery output; verification buys it causally at ~30–60k tokens per finding, targeted exactly at the findings with no independent support (singletons). This is what could make a single-pass micro profile safe — the "N=1 + verify vs N=2 without" comparison is now runnable, and the pass_support/dispositions instrumentation (shipped same day) measures it.

**Targeting rationale**: corroborated findings carry statistical support; `cited-spec` findings carry a quote. The queue covers precisely the remainder — plus all Criticals (they drive the verdict; CONFIRMED converts `[unanchored]` to anchored, closing the loop with the anchored-verdict rule) and all consistency-shaped claims (consensus does not clear that class: two sonnets converged on the identical false N1 story independently).

**Cost envelope**: ≤8 dispatches ≈ 100–400k tokens/run; near-zero on clean runs (empty queue skips). Verifier tiers: Fable[1m] on Criticals, Sonnet 5[1m] otherwise.

**Could-be-wrong-if** (falsifiers — evaluated after ~5 verified runs with dispositions):
- **Rubber-stamp failure**: ≥90% of verdicts are CONFIRMED/PLAUSIBLE and no REFUTED verdict ever prevents a would-be-accepted finding from reaching triage → the stage is paying tokens for stamps; demote to Criticals-only (drop queue rules 2–3).
- **No acceptance lift**: CONFIRMED singletons are accepted at no better rate than the historical unverified-singleton baseline (computable from pass_support × dispositions once ≥8 measurable runs accrue) → the causal-credibility premise fails in triage practice; demote as above.
- **False refutation**: any REFUTED finding later proves real (fix applied elsewhere, bug ships) → tighten verifier.md's refutation bar (require `method: ran` for REFUTED) before trusting exclusions again.
- **Cost creep**: verifier phase exceeds ~30% of run total on ≥3 consecutive standard runs → cap tighter or gate to Criticals.

**Rejected alternatives.**
- **Re-run /code-review on the same diff as the verifier**: $17-equiv / ~4M all-bucket per run to adjudicate 3–8 findings (measured, both effort arms), verifies by incidental re-finding rather than attacking the claim, and can't be pointed at a findings list. Kept instead as a possible cross-harness arm on `full`-profile runs (the §5.6 `--cross` concept).
- **Ad-hoc in-session verification** (orchestrator "remembers" to check C/Is): free, and decays exactly like every disciplined-hope in this repo's history (metering, dispositions, multiball recording — all drifted until mechanized). Rejected on operational record, not principle.
- **Verify everything** (all severities, no cap): unbounded cost on Minor/Noted findings that triage ignores at 17%/2% anyway (leg 1 §4). The cap concentrates spend where dispositions show action happens.
- **Verifier inside the integrator** (one dispatch does both): the integrator is a single bounded synthesis pass and cannot spawn subagents (leaf guard); folding verification in would serialize ≤8 independent checks inside one context and lose the run-it-first tool isolation.
