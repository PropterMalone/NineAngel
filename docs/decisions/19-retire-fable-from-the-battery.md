---
id: 19-retire-fable-from-the-battery
name: Fable is retired from the battery — the lapse ladder becomes the standing table
date: 2026-08-26
status: active
until: null
amends: [07-post-eval-retier-battery-rebalance, 08-adversarial-verify-stage, 09-run-profiles-invocation-policy, 11-hierarchical-multiball-integration]
supersedes: null
commits: []
depends_on:
  - ref: angel:07
    claim: "leg 3's model-verified measurement (Fable 87-90% strict recall vs Opus ~70%, stability .95 vs .78) is the loss this retirement accepts, and its Fable-lapse ladder is what this ADR promotes to standing"
  - ref: angel:17
    claim: "`total_tokens` is peak single-turn context, not spend — the constraint that keeps the 14.7%-of-volume figure a share claim rather than a cost claim"
falsifier_cmd:
  - label: depth-lane-yield
    cmd: |
      out=$(python3 scripts/depth-lane-yield.py --json) || { echo "depth-lane-yield.py failed to run"; exit 2; }
      printf '%s' "$out" | python3 -c "
      import json,sys
      d=json.load(sys.stdin)
      n=d['arm']['n']; m=d['arm']['median']; t=d['threshold_r']; k=d['min_runs']
      print('arm_n=%d median_R=%.2f threshold=%s min_runs=%d' % (n,m,t,k))
      sys.exit(1 if (n>=k and m<t) else 0)"
---

# Fable is retired from the battery — the lapse ladder becomes the standing table

> **Integrator assignment amended by ADR-20 (2026-08-30).** Opus remains a persona/verifier
> tier, but reducer-era integration no longer dispatches an Opus agent or assumes a 1M agent
> window. It uses a qualified isolated runner with bounded structured output, or a visible
> deterministic union when that runner is unavailable.

**Decision**: Fable is no longer dispatched by default anywhere in `/angel`. The nine depth lanes — thousand, data-int, future, blindspot, coach, rigor, deanon, heir, **recip** — run `claude-opus-5[1m]`. **Test returns to `claude-sonnet-5[1m]`**, not Opus. The reader, the integrator ladder, and the §5.7 verifier's Critical tier all move to `claude-opus-5[1m]`. ADR-07's *Fable-lapse* ladder is promoted from conditional to **standing**: there is no availability check left to perform. `fable` remains a legal `--model-override` / `MODEL_OVERRIDE` value — this retires Fable as a default, not as a reachable choice.

**Why**: the user, 2026-08-24 — *"i think we gotta retire fable from the battery"*, and, on the driver doctrine the same day, Fable is *"not clearly better than Opus for most things anyway and it's incredibly pricy."* The proximate incident is the 08-24 a private target run, where **Fable hit its cap mid-battery**, killing `blindspot` p2 and `rigor` p2 outright and forcing Opus substitutions under the lapse ladder. That ladder worked — both killed passes re-dispatched and completed — which is the point: this change is mostly *promoting an existing fallback to the default*, not new machinery. Fable is **376 legs / 41.7M tokens / 14.7% of logged battery volume**, at 2× Opus list price. **That is a volume share, not a spend measurement, and the distinction is this repo's own**: `SKILL.md` and `docs/v2-backend-routing.md` both record that a `total_tokens` sum is *peak single-turn context*, not tokens billed, so multiplying it by list price does not yield a cost. `scripts/true-cost.py` is the instrument that prices a run properly and it was not run for this ADR. What the figure supports is that Fable was a large and expensive share of battery volume; what it does not support is a magnitude.

**This is a price decision and the ADR will not dress it as a quality upgrade.** ADR-07 leg 3 (16 pre-registered, modelUsage-verified runs) measured strict recall **Fable ~87–90% vs Opus ~70%** and pass-to-pass stability **.95 vs .78**. The battery accepts that. Two things bound the loss:

1. **The wild corpus does not reproduce the benchmark gap** — but it cannot currently refute it either. Depth-lane Important+ yield against the unmoved control lanes reads Fable 2.14 (n=21) vs Opus 1.09 (n=41) pooled, which looks decisive and is an artifact: the Opus arm's own by-month medians run 1.39 (May) → 1.04 (June) → 3.32 (July) → 2.97 (August), a 3× swing on an unchanged model. Restricted to the current era the Opus arm is **n=2** and supports no comparison at all. The pooled gap is calendar, not model.
2. **ADR-18 partly offsets the stability loss on interactive runs.** Pass 2 now goes to Codex, so cross-model diversity replaces some of what a second Fable pass bought. **The unattended path gets no such offset** — ADR-18's own carve-out makes it single-pass Claude, so it absorbs the full .95 → .78 stability drop.

Two named losses, so neither is discovered later as a surprise: **Test gives back 7/8 → 5/8** on the seeded benchmark (its top-tier promotion was Fable-specific — leg 3 also measured Opus-test ≈ sonnet-test at ~5× cost, so Opus is not the right destination), and **`recip` had no ladder entry at all**; ADR-07 never covered it, so this ADR assigns it rather than letting it inherit by accident.

**Rejected alternative**: keep Fable for the stakes tier (`--full`/`--all`) and move only standard/diff runs. It captures most of the savings and preserves depth where blast radius is highest, and ADR-09's existing rationing logic already establishes the principle. Rejected because it leaves the failure mode that prompted the change: the integrator is the one dispatch whose stall is catastrophic — it runs alone, last, and the run has no report without it — and a cap that exhausts mid-battery exhausts there too. A retirement that keeps three live Fable consumers is a demotion, not a retirement.

**Rejected alternative**: send Test to Opus with the other depth lanes, for uniformity. Rejected on leg-3's direct paired measurement (Opus-test ≈ sonnet-test at ~5× the cost). Uniformity is not worth 5× on a lane where the top tier buys nothing.

**Could-be-wrong-if**: across the first **≥10** post-retirement runs whose depth arm is model-verified on Opus and which clear the arm guards, the **median R falls below 1.69** — where R is a run's Important+ attributions per depth-arm persona divided by the same quantity for the control-arm personas this ADR does not move. That is the depth lanes losing ≥40% of their edge over the unmoved arm: **twice** the loss leg 3 measured and this ADR accepts.

The threshold is derived, not round. Baseline median is **2.82** (n=20); the accepted loss (recall 87→70, retain ≈0.80) predicts 2.26; the bar sits at retain-0.60, i.e. 2.82 × 0.60 = **1.69**.

**Sharpness is computed by the instrument, not asserted here.** `depth-lane-yield.py` carries `fire_probability()` — an exact binomial over the empirical baseline scaled by a retention factor, printed on every run — so these figures reproduce and move with the corpus instead of going stale in prose. At n=10 the falsifier fires **0.6% of the time at the loss this ADR accepts, 16.6% at retain-0.70, 37.7% at a doubled loss, and 99.0% at a halved edge.** **Do not read a `not met` as excluding a modest real loss** — at the accepted loss this test is very nearly blind. That is a property of a paired ratio with this much run-to-run spread, not a defect to argue away, and it is the honest reason this ADR's confidence sits at 0.6 rather than higher.

[The first cut of this clause registered 2.17/n=15 and a **1.30** bar, with hand-derived probabilities of ~3%/~46%/~94% and no reproducing code — in a document whose own test suite exists to forbid a constant the instrument cannot reproduce. Both were wrong: the baseline because the ballot counted Codex legs and the depth arm included Sonnet-demoted lanes, the sharpness because it was never computed at all. Corrected 2026-08-26, from this ADR's own review.]

Why *paired*, and why against these particular personas: the control arm reviews the identical diff, in the identical run, at the identical time, on models this ADR does not touch — so era, project difficulty and diff size divide out. That matters more here than usual, because era is this metric's dominant nuisance (the 3× within-arm swing above). `test` is in **neither** arm: it moves too, but to Sonnet on separate evidence, and folding it in would put two different bets under one threshold.

Three candidate metrics were measured and rejected on evidence, not taste: **pass-to-pass reproducibility** (the direct analogue of leg 3's .95/.78) is quantization-dead at N=2 — every arm's median is exactly 0.500, the Fable−Opus gap is 0.007, and the Opus arm is n=9; **evidence-tier depth** runs the wrong way (Opus 90.7% non-inference vs Fable 89.6%); **solo-Important+ share** also runs the wrong way, because it is a ratio that *rises* as a model files fewer findings.

**Evaluated by** `scripts/depth-lane-yield.py` — a script, not a heredoc, for ADR-16's stated reason: an instrument that costs a paste-and-edit to run is one that decays unobserved. Thresholds live in it as named constants so a silent edit shows up in `git diff` against this ADR.

```bash
scripts/depth-lane-yield.py              # forward — the post-retirement Opus arm
scripts/depth-lane-yield.py --backward   # backward — the pre-retirement Fable arm
scripts/depth-lane-yield.py --json       # machine
```

**Forward run, 2026-08-26** [ran], pasted verbatim:

```
ADR-19 falsifier — depth-lane Important+ yield vs the unmoved control arm
  FORWARD — Opus arm since 2026-08-26 (ADR-19)
  corpus: 324 dirs scanned, 324 accounted (balanced)
    measured 78  |  no snapshot 141  |  reduced-shape 4  |  unreadable 0
    guard-rejected  23  — control arm below MIN_CONTROL_IMPPLUS
    guard-rejected  26  — control arm below MIN_CONTROL_PERSONAS
    guard-rejected  52  — depth arm below MIN_DEPTH_PERSONAS
    !! 9 run(s) had no usable depth-tier model evidence (scorer fallback)
    !! 66 malformed field(s) quarantined: personas not a list on 'C1-RESIDUAL'
  arm census: fable=26, mixed=10, opus=42

  n = 1 runs across 1 projects
  median R = 2.42   (min 2.42, max 2.42)
  runs individually below 1.69: 0 of 1

  by month (era is this instrument's dominant nuisance — pooling hides it):
    2026-08   n= 1   median R = 2.42

  reference arms, all time — read the month columns, not the pooled medians:
    fable  n= 26  pooled median R=2.56   by month  2026-06:2.08  2026-07:2.54  2026-08:2.90
    opus   n= 42  pooled median R=1.51   by month  2026-05:1.85  2026-06:1.42  2026-07:3.32  2026-08:2.70
    mixed  n= 10  pooled median R=1.20   by month  2026-06:2.13  2026-07:1.22  2026-08:1.18
    (a 3x swing within one arm on an unchanged model is era, not model.)

  sharpness — P(fires at n=10) if the true effect retains:
    100% of baseline yield :   0.1%
    80% of baseline yield :   0.6%
    70% of baseline yield :  16.6%
    60% of baseline yield :  37.7%
    50% of baseline yield :  99.0%

  baseline (Fable arm, 2026-07-08 .. 2026-08-26): median 2.82 on n=20
  [ ] powered          n >= 10  (have 1)
  [ ] below threshold  median R < 1.69

pending (1/10 runs)
```

The arm holds exactly one run: the `/angel` review of this very commit, which is also the review that found the defect described below. Ten is roughly a month at the observed accrual rate for *eligible* runs — and that rate is now meaningful, which it was not when this ADR first shipped.

**Backward run, 2026-08-26** [ran], pasted verbatim — per ADR-14's rule, against the corpus that already exists:

```
ADR-19 falsifier — depth-lane Important+ yield vs the unmoved control arm
  BACKWARD — Fable arm, 2026-07-08 .. 2026-08-26 (exclusive)
  corpus: 324 dirs scanned, 324 accounted (balanced)
    measured 78  |  no snapshot 141  |  reduced-shape 4  |  unreadable 0
    guard-rejected  23  — control arm below MIN_CONTROL_IMPPLUS
    guard-rejected  26  — control arm below MIN_CONTROL_PERSONAS
    guard-rejected  52  — depth arm below MIN_DEPTH_PERSONAS
    !! 9 run(s) had no usable depth-tier model evidence (scorer fallback)
    !! 66 malformed field(s) quarantined: personas not a list on 'C1-RESIDUAL'
  arm census: fable=26, mixed=10, opus=42

  n = 20 runs across 10 projects
  median R = 2.82   (min 0.67, max 6.50)
  runs individually below 1.69: 3 of 20

  by month (era is this instrument's dominant nuisance — pooling hides it):
    2026-07   n= 8   median R = 2.54
    2026-08   n=12   median R = 2.90

  reference arms, all time — read the month columns, not the pooled medians:
    fable  n= 26  pooled median R=2.56   by month  2026-06:2.08  2026-07:2.54  2026-08:2.90
    opus   n= 42  pooled median R=1.51   by month  2026-05:1.85  2026-06:1.42  2026-07:3.32  2026-08:2.70
    mixed  n= 10  pooled median R=1.20   by month  2026-06:2.13  2026-07:1.22  2026-08:1.18
    (a 3x swing within one arm on an unchanged model is era, not model.)

  sharpness — P(fires at n=10) if the true effect retains:
    100% of baseline yield :   0.1%
    80% of baseline yield :   0.6%
    70% of baseline yield :  16.6%
    60% of baseline yield :  37.7%
    50% of baseline yield :  99.0%

  baseline (Fable arm, 2026-07-08 .. 2026-08-26): median 2.82 on n=20
  [x] powered          n >= 10  (have 20)
  [ ] below threshold  median R < 1.69

not met
```

**The forward arm could not populate at all as first shipped, and its own review caught it.** `attribute()` decided a run's arm by voting over every model id it found per persona. Under ADR-18 every persona carries a Codex leg logged under the same name, so each depth lane cast one Claude vote and one non-Claude vote, purity landed at exactly 0.50, the strict-majority test failed, and every heterogeneous run left both arms — **0 of 9 post-ADR-18 runs reached the Opus arm**, and `pending (0/10)` was the string it would have printed permanently. Two aggravations: an N=3 escalation did not help, because the model ids were accumulated in a *set* that collapsed the two identical Opus legs; and the residual selection was adverse, since a run tipped above 0.50 only when a Codex leg *failed*. The discriminator was already in the log — `usage.jsonl` carries `backend: codex` — and the instrument never read it. Fixed the same day: the ballot counts legs rather than distinct models, skips non-Claude backends and legs whose `note` records a mismatch or failure, and decides arm membership per run from the tier each lane actually ran (so a Sonnet-demoted `future` no longer enters the depth denominator). Re-deriving the baseline against the corrected ballot moved it from 2.17/n=15 to **2.82/n=20**, which is why the registered threshold moved with it. This is the ADR-15/ADR-16 defect class — a falsifier that cannot fire — reproduced by a new mechanism, in the commit that congratulated itself for avoiding it.

**Status quo check**: `not met` at 2.82 against a 1.69 bar — the status quo does not already pass, so the falsifier is not decorative. And the bar is reachable at the registered denominator, evidenced from the metric's own distribution *and* its null — the check ADR-16's tombstone records as never having been run for either prior range claim: **3 of the 20 baseline runs sit individually below 1.69**, and the Opus arm has held a sustained median of **1.09 across 41 runs**, four times the registered denominator. That second figure carries its own caveat and it is stated rather than buried: those 41 runs are mostly May–June, so the demonstration is partly era. The bar is reachable; the evidence that it is reachable is not clean.

**Known weakness, stated because it is the one that will bite**: era drift is only partly controlled. A post-retirement median of 1.3 could mean "Opus is worse" or "the prompt-improvement trend stopped." The 2026-07-08 floor bounds this; it does not remove it. The instrument prints a by-month breakdown on every run for exactly this reason, and a reading that ignores it is a misreading.

**Named successor — now unblocked (2026-08-26).** Codex provenance is recorded: `record-dispatch.sh` writes `backend=` into the pass marker, `assemble-wpr.py` joins it through the same `rid` match that already built `pass_support`, and every finding now carries `backend_support {persona: {backend: k}}`. R's numerator counts only Claude-sourced attributions (`claude_sourced()`), so a codex catch is review signal without being counted as Claude-tier yield — closing the contamination this ADR's own review filed as f2. Findings that predate the field fall through as Claude-sourced, which is correct rather than a guess: pre-ADR-18 runs had no codex pass. With that in place, the cross-model arm becomes strictly the better instrument — same persona, same diff, with a reference model held fixed across the retirement. Registering that now gives this falsifier a defined end-of-life instead of eleven days of unobserved decay.

---

**ADR-18 interaction — the trial window is partitioned at this date, not pooled.**

ADR-18 (heterogeneous multiball) was adopted 2026-08-22, time-boxed, revisit ~2026-09-22. This ADR lands four days into that box and changes what pass 1 *is*. Both of ADR-18's registered metrics move as a direct consequence, in opposite directions and for reasons that have nothing to do with heterogeneity: a weaker pass 1 mechanically **raises** Codex-only union share and **lowers** corroboration share. Runs before 2026-08-26 and runs after it are therefore **two segments and must be scored separately**. Pooling them would retire or vindicate heterogeneity on an artifact — and ADR-18 closes by warning against precisely that: *"a falsifier that measures one of a practice's two goods will retire the practice for failing a test it was never aimed at."*

**A defect found while writing this, and not inherited silently: ADR-18's falsifier is currently uncomputable.** The integrator collapses the codex pass into the base persona name, so `codex-` never appears in any finding's `personas` array. Measured across the corpus: **0 Codex-only Important+ findings are machine-detectable**, and of the runs with a codex leg, several carry no `findings` list at all. The attribution exists only in report prose. This is the ADR-14 failure mode — *"denominated in a log field the log did not carry"* — and it is the same one-field fix the named successor above needs. **Fix it before the 09-22 revisit, or that revisit has no instrument.**

---

**Retired falsifiers.** Four pre-registered clauses can no longer fire, because each is denominated in a Fable that is no longer dispatched. Kept rather than deleted: deleting a falsifier that lapsed is how a repo loses the ability to notice it lapsed (ADR-16's rule).

> **ADR-07, future/test promotions** — *"across the next ≥5 organic full runs with dispositions, the two promoted lanes fail to beat their leg-1 sonnet-era acceptance (36%/23%) … → revert to Sonnet 5."*
> **Resolved rather than retired, for `test`.** This ADR performs the reversion the clause prescribes, on cost grounds instead of on the acceptance evidence the clause asked for. `future` stays in the depth tier, so its half remains live — but re-denominated against Opus, not Fable.

> **ADR-07, lapse ladder** — *"on Fable lapse, if Opus-lane N=2 runs show pass-2 marginal recall ≈ 0 (subsample-analyzer, ≥8 measurable runs), the 'N=2 earns its keep on Opus' claim was wrong."*
> **Still live and now more urgent, not retired** — every depth lane is an Opus lane from today, so the population it needs stops being incidental. It is also newly confounded on interactive runs, where pass 2 is Codex rather than Opus; read it on the unattended path, or on `--model-override` runs.

> **ADR-09, Fable rationing** — *"future/test acceptance on standard runs drops materially below their leg-1 sonnet-era baselines (36%/23%) over ≥5 disposition-instrumented runs … → revert the demotion."*
> **Unfirable.** There is no Fable tier to be rationed *from*: `test` is now Sonnet at every profile, and the standard-profile exception it guarded is a no-op for that lane.

> **ADR-11, integrator ladder** — *"if measured Fable integrator stall rate is <10% over 10+ big runs, retire change 3."*
> **Unfirable, and change 3 is moot rather than wrong.** The stall mode it diagnosed was Fable-specific; with no Fable rung the ladder collapses to flat `opus → inline` at every bundle size. Its sibling clause — *"if Opus-first big integrations stall at a comparable rate, the Fable-specificity theory is wrong"* — **stays live and gets easier to evaluate**, since every integration is now Opus-first.

---

**How to apply**: this binds any change to model assignment or to the two arms the falsifier rests on.

1. **The two acting paths move together.** `SKILL.md` §1 and `unattended.md` Step 3 are twin tables and `scripts/validate-personas.py` fails the build on any per-persona tier mismatch. A model changed on one path has not shipped.
2. **Changing any control-arm persona's row voids the baseline.** The falsifier's denominator is twelve named personas (adv, hyper, user, perf, install, penny, rtfm, editor, orgpolicy, naive, fresh, pii). Promote or demote one and R's scale moves, making the pre/post comparison meaningless — **re-baseline before reading the falsifier again.**
3. **Verify the pin per run.** `claude-opus-5[1m]` was confirmed on 2026-08-26 via `claude -p --model 'claude-opus-5[1m]' --output-format json`, whose `modelUsage` block returned the key `claude-opus-5[1m]` with `contextWindow: 1000000` — i.e. `requested == ran`. **Agent-tool dispatches are a different surface and remain `ran=unverified`**: this ADR's own review run dispatched pass 1 on the tier aliases `opus`/`sonnet`, and its `usage.jsonl` records `requested=…|ran=unverified` for every one. The 2026-07-01 safety-classifier swap (`claude-fable-5[1m]` → Opus without `[1m]`) is why this is standing methodology and not a one-time check.
4. **ADR-04 is unchanged and was not superseded.** Its rule already authorized this: *"re-point them whenever the smartest no-meter [1m] model changes (a new top model, or a billing-status change to Fable)."* This ADR applied it. Do not record it as an integrator-policy change.
5. **Fable pricing stays in `scripts/true-cost.py`.** Historical transcripts still need it, and `UNKNOWN_MODEL_FALLBACK = "claude-sonnet-5"` would silently misprice the archive. Likewise `fable` stays in `validate-personas.py`'s `TIER_RE` — the override vocabulary needs it.
6. **Before the ADR-18 revisit (~2026-09-22)**, fix codex attribution in `personas` (see above) and score the trial in two segments split at 2026-08-26.

**Confidence 0.6** [tier: **inferred** — the backward instrument ran; the claim itself is unobserved] that retiring Fable costs the battery no material review quality. The tier is deliberately not `ran-and-saw-output`: nothing has yet observed the post-retirement battery. The backward figures below are `[ran]`; this forward-looking claim is not, and tagging it as though it were would collapse the one distinction `~/.claude/rules/quality.md` reserves as its strongest. Held low deliberately: the one benchmark that measured this directly says the top tier lost 17–20 points of strict recall, and the corpus evidence pointing the other way is a paired metric whose current-era Opus arm is n=2. What the number is *not* low about is the decision — the *direction* of the cost saving is near-certain and its *magnitude* is unmeasured (above), the quality loss is uncertain, and that trade is the user's to make and is made. The falsifier exists to convert this confidence into a measurement within a month.
