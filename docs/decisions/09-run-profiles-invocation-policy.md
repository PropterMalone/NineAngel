---
id: 09-run-profiles-invocation-policy
name: Run profiles (micro/standard/full) + milestone invocation policy
date: 2026-07-08
status: active
supersedes: null
commits: []
---

# Run profiles + invocation policy

**Decision**: Three named run profiles — **micro** (`--micro`: adv + hyper, + data-int when signaled; N=2; inline integration), **standard** (default: auto-detected battery, N=2, integrator dispatch, **future/test demoted to Sonnet 5**), **full** (`--full`/`--all`: whole battery, N=3, full Fable complement) — plus a **milestone invocation policy**: standard/full runs happen at pre-merge / pre-ship / public-artifact milestones over accumulated commits; mid-development checks use micro. Profile choice is the maintainer's ex-ante call, never the orchestrator's per-run judgment.

**Why.** Token constraints are the binding pressure (maintainer, 2026-07-08), and the empirical menu resolved cleanly the same day:

1. **The alternatives to a light 9A profile are not light.** /code-review at high AND medium effort measured ~4.1–4.6M all-bucket / ~$17-equivalent on the seeded benchmark — a zero-maintenance *equivalent* to the full battery, not an economy tier (`_scoring-notes-cr-arm.md`). A micro profile (~0.4–0.6M) is the only sub-1M review that exists.
2. **The micro battery is the demonstrated core**: adv+hyper+data-int unioned 8/8 on the seeded benchmark in each pass independently, and holds the best acceptance-per-token in the wild (leg 1). Inline integration is safe at this scale (≤4 personas' output fits the orchestrator window) and saves a full Fable dispatch.
3. **Frequency dominates weight**: recent cadence re-reviewed the same project on consecutive days; findings persist on lightly-changed code (recurrence pilot), so per-diff runs re-buy the same findings. Milestone batching cuts run count without touching any run's rigor.
4. **Fable rationing (standard demotes future/test to Sonnet 5)**: leg 3 shows their sonnet floors are serviceable (future union 4/8, test 5/8 vs Fable 7/8 each); the Fable gain is completed causal chains — reserved for the stakes tier that pays for depth. data-int and thousand are NOT rationed at any tier (leg-3 Q1: demotion falsifier fired both branches).
5. **The profile mechanism is the multiball lesson generalized**: cost-vs-recall tradeoffs are the maintainer's to make ex ante, not the orchestrator's to optimize silently per run. Named profiles remove the discretion that produced the recurring single-pass drop. N is untouched — the multiball guard hook stands; micro runs N=2 like everything else. Any future N change goes through the ADR-06 falsifier data (singleton-vs-consensus acceptance, measurable since the 2026-07-08 instrumentation), not through a profile.

**Expected effect**: routine spend drops ~75–80% (lighter runs × fewer runs); full-tier rigor unchanged by construction.

**Could-be-wrong-if** (falsifiers):
- **Micro too thin**: a milestone standard/full run over code that only micro reviewed surfaces ≥2 accepted Critical/Important findings *in micro-lane territory* (security, code-quality, data-flow — findings adv/hyper/data-int should catch) across ~5 milestone runs → widen micro (first candidate: + future on Sonnet 5).
- **Fable rationing costs real findings**: future/test acceptance on standard runs drops materially below their leg-1 sonnet-era baselines (36%/23%) over ≥5 disposition-instrumented runs, or an accepted absence-class Critical arrives that the Fable version demonstrably catches and the Sonnet version missed on re-run → revert the demotion.
- **Milestone batching produces monster runs**: standard runs consistently exceed ~2M tokens because too much accumulates between milestones → shorten the milestone interval rather than thinning the battery.
- **Micro becomes the de-facto everything-tier** (the cost-aversion failure mode wearing a new coat): if standard/full runs stop appearing in usage.log for weeks while micro runs on ship-bound artifacts, the policy is being abused in exactly the direction the multiball hook exists to prevent — that's a maintainer conversation, not a silent drift to accept.

**Rejected alternatives.**
- **Micro at N=1**: halves micro again but requires amending the maintainer's standing multiball rule, and the singleton-acceptance data that would justify it doesn't exist yet (~2 weeks out). Revisit on that data; the §5.7 verification stage was built partly to make an N=1 profile *possible* to argue for (causal credibility replacing corroboration).
- **Routine tier on /code-review**: measured cost parity kills the economy argument; it remains the zero-maintenance alternative and a candidate `--cross`-style second harness on full runs.
- **Orchestrator picks the profile from diff size/signals**: rejected on the multiball lesson — per-run cost discretion is exactly what drifts. Detection picks the *battery within* standard; the human picks the profile.
