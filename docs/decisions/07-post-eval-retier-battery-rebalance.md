---
id: 07-post-eval-retier-battery-rebalance
name: Post-eval model retier + battery rebalance (eval legs 1–3)
date: 2026-07-08
status: active
commits: [fc1a14c, 0cd4363, 9e07cc6]
---

# Post-eval model retier + battery rebalance

**Decision**: Apply the frozen post-leg-3 batch. (1) Future-Me and Test promote to the top tier (`claude-fable-5[1m]`); Data-Integrity and Thousand-Foot stay there; Hypercritical deliberately stays Sonnet. (2) A **Fable-lapse ladder** is documented in SKILL.md §1: top lanes demote to `claude-opus-4-8[1m]` — except Test, which reverts to Sonnet — and multiball N=2 is kept on Opus lanes. (3) The tier-by-lane principle is reframed as **contract-tracing depth**. (4) Freshness demotes to `opt-in`; Test/Performance/User lose their near-universal gate signals (`package_json` / `runtime_code` / `readme`). (5) Sonnet personas pin explicit `claude-sonnet-5[1m]` instead of the tier alias. (6) Verdict becomes a strict 4-value enum. (7) Cross-file consistency claims get the run-it-first evidence bar in every severity-calibration block. (8) Per-run model verification (`requested=|ran=`) is standing methodology.

**Evidence base** — three eval legs, reports in `~/.claude/projects/-home-user-.claude-skills-angel/memory/`:
- **Leg 1** (retrospective, ~143 runs / 3,483 findings): data-int best acceptance-per-token (58%, 32k/accepted); fresh 4% acceptance at 354k/accepted; perf/naive/test/user cluster 23–26%; verdict vocabulary drift blocked outcome scoring; 12/143 runs had dispositions.
- **Leg 2** (seeded benchmark, 8 seeds + 6 baits, N=2): union recall 8/8 in one pass; the only FPs (2) were the same cross-file-consistency lure; fresh 0 strict catches + 1 anti-catch; adv the only reliable seeded-false-comment catcher.
- **Leg 3** (model swap, 16 pre-registered runs, all modelUsage-verified): recall tracks the model (Fable ~87–90%, Opus ~70% strict), not the persona. Demotion falsifier fired both branches for data-int/thousand. future cleared its pre-registered flip bar (5 absence-class catches/pass vs 2–3); test refuted "present-code lanes gain nothing" (3,5→7,7 with self-run repros); hyper's top-tier gain was one partial→full plus the leg's only FP. Opus-test ≈ sonnet-test at ~5× cost.

**Judgment calls that go beyond the reports** (deltas a re-scorer should challenge):
- **Naive stays unconditional** despite leg-1 rec 3 listing it: it is the only cheap (Haiku) cold-reader breadth pass left once fresh is gated, and leg-2 §2.5 showed union recall is carried by redundancy — thinning the battery shifts that load onto multiball. Cutting fresh *and* naive in one change conflates two effects.
- **Test is promoted AND gate-tightened**, not demoted: leg-1's 23% acceptance was measured on sonnet; leg-3 shows the Fable test persona is a different reviewer (self-run repros, 1.0 stability). The gate tightening (tests_dir_or_files only) handles the "add-a-test chores" noise on test-less projects; the promotion handles depth where a suite exists.
- **Sonnet 5 pins are eval-untested**: legs 2–3 benchmarked `claude-sonnet-4-6`. `claude-sonnet-5[1m]` was verified dispatchable (claude -p modelUsage, 2026-07-01, re-verified 2026-07-08) but its recall on the seeded benchmark is unmeasured. The seeded target (a private-project worktree + manifest) is retained for an optional sonnet-5 arm.

**Could-be-wrong-if** (falsifiers):
- future/test promotions: across the next ≥5 organic full runs with dispositions, the two promoted lanes fail to beat their leg-1 sonnet-era acceptance (36%/23%) or produce ≥2 rejected-wrong findings → revert to Sonnet 5 and record the benchmark-vs-wild gap.
- Gate tightening: any run where a demoted-by-signal persona (test/perf/user) would have caught a Critical/Important that the surviving battery missed and that the maintainer accepts → restore that persona's dropped signal. Concrete check: in post-run triage, grep the report's Coverage Gaps/Skipped line whenever an accepted finding's lane matches a skipped persona.
- Fresh demotion: fresh is named explicitly ≥3 times in a quarter and produces an accepted Important+ each time → re-promote with a narrowed CVE-table lane.
- Lapse ladder: on Fable lapse, if Opus-lane N=2 runs show pass-2 marginal recall ≈ 0 (subsample-analyzer, ≥8 measurable runs), the "N=2 earns its keep on Opus" claim from leg-3 stability data was wrong → revisit ADR-06 economics there.

**Rejected alternatives.**
- **Demote perf/naive/test/user to opt-in** (leg-1 rec 3 as written). Rejected: signal-gating machinery already exists; tightening gates preserves auto-inclusion where the lane is real. Opt-in demotion would have removed test from projects with suites — exactly where leg 3 shows it now excels.
- **Promote hyper to the top tier** (uniform "Fable everything"). Rejected: +1 seed headroom, the leg's only Fable FP, and it abandons the cost-anchored volume floor. Revisit only if adv is ever cut (B5-class comment-camouflage coverage).
- **Cut fresh outright** (delete the persona). Rejected: the lane (dependency rot/CVE) is real; the persona's *framing* is what loses triage. Opt-in preserves the tool while the CVE-table reshape is designed.
- **Retire multiball on the strength of leg 2** (pass 2 added 0 recall, +2 FPs). Rejected/deferred: leg 2 measured a *saturating full battery on Fable*; the standing N=2 rule protects the reduced-battery and Opus regimes where redundancy is thinner (leg-3 stability .78). Also a maintainer standing rule (never drop multiball unilaterally) — any change there is the maintainer's call on the ADR-06 falsifier data, not a side effect of this batch.
