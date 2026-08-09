---
id: 13-inline-integration-field-parity
name: Inline integration owes the same fields, and inline verification writes its verdict files
date: 2026-07-28
status: active
amends: [08-adversarial-verify-stage, 09-run-profiles-invocation-policy]
supersedes: null
commits: [168ea89, b4cdc57]
---

# Inline integration owes the same *fields*, not just the same files

**Decision**: An inline integration must render the same report **fields** a dispatched integrator does — `integrator.md`'s header block verbatim (including `Files reviewed` and `Pre-flight`), a wall-clock **duration**, the verdict **enum**, and a derived `Effort` rollup — and when it verifies findings inline it must WRITE `$RUN_DIR/verification/{id}.json` per finding before invoking `apply-verification.py`.

**Why**: §5 steps B/C and `--micro` already said "emit every output the integrator owes." Every inline run read that as *files* — report, snapshot, registry block — and then re-invented the header, shedding whatever the prose didn't happen to include. Measured across three consecutive reports (07-21 self-review, 07-28 coach, 07-28 dogfood): `## Verification` absent from **all three**, `Files reviewed` and `Pre-flight` absent, wall reported as "~4 dispatch waves" (not a unit a reader can convert), and one report asserting "5 load-bearing singletons mechanically confirmed" while its own snapshot recorded **8** `CONFIRMED` — an artifact contradicting its own machine record, which is the failure the verify stage (ADR-08) exists to prevent. This is not a rare path: inline is `--micro`'s **default** (ADR-09) and step C's fallback.

The non-obvious half is the verification wiring. `apply-verification.py` reads **only** `$RUN_DIR/verification/*.json` and is a documented clean no-op with zero of them — verified 2026-07-28: `no verdicts to apply`, exit 0, no section emitted. So the obvious remedy, "just run the script on the inline path," is **inert**; shipping it would have closed the finding while fixing nothing. Writing the files first is what makes the `## Verification` section and the header's verification count come from one source, so they cannot diverge.

Found by `recip` (ADR-pending persona #21) on its first dogfood — the first review lane that reads NineAngel's own *output* rather than its source. No source-reading persona had looked at a rendered report in 20 personas' worth of coverage.

**Rejected alternative**: teach `apply-verification.py` to also read `verification` fields already present in the snapshot, so the inline path could keep hand-writing them. Rejected because it creates a **second input path to the same renderer** — a run could then populate the files, the snapshot fields, or both inconsistently, reintroducing precisely the count-vs-section divergence this decision exists to close. One input, one renderer.

**Could-be-wrong-if**: writing the files does not in fact produce a single source. Concretely — on the next **3** inline-integrated runs, check that (a) `grep -c '^## Verification' report.md` == 1, (b) the number of `verification/*.json` == the number of per-finding verdicts in that section, and (c) both equal any verification count asserted in the header. Any mismatch falsifies the single-source claim. Separately, if those same 3 runs still shed header fields, the fix is in the **wrong location** — prose in §5 is not binding, and the requirement belongs in `check-run-complete.py` as a mechanical gate instead.

**How to apply**: binds every integration that skips the integrator dispatch — `--micro` (inline by default, ADR-09), §5 step C's fallback after a stalled dispatch, and any orchestrator hand-integrating a small bundle. It does not change the dispatched-integrator path, which already renders from `integrator.md` directly. Two companion rules landed in `integrator.md` for both paths: the `Effort` rollup is counted from effort tags rather than improvised in prose, and finding locations must be paste-able paths (never elided for line width).
