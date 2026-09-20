---
id: 16-reconciliation-thresholds
name: Reconciliation thresholds are N-aware — frequency stops moving severity below N=5
date: 2026-08-13
status: active
amends: [06-multiball-n2-default-n3-escalation, 11-hierarchical-multiball-integration, 12-per-pass-capture-integrity]
supersedes: null
commits: []
---

# Reconciliation thresholds are N-aware — frequency stops moving severity below N=5

**Decision**: Split the two frequency rules and give each its own floor. **Promotion** applies at **N ≥ 3** and requires a **true majority** (`≥⌈(N+1)/2⌉`: 2 of 3, 3 of 5) rather than `≥⌈N/2⌉`. **Demotion of singletons** applies at **N ≥ 5** only. Both values in operative use — N = 2 (the interactive default, ADR-06) and N = 3 (the `--full`/`--all` escalation) — therefore carry **no frequency-based demotion at all**, and N = 2 carries no frequency-based promotion either: the reconciler and integrator record the `(k/N)` tag and rank on merit. Separately, the `[unanchored]`-Critical test's pass-count threshold becomes a flat **≥2 passes** at every N.

**Why the old thresholds broke**: `⌈N/2⌉ = 1` at N = 2. Every rule keyed on that expression degenerates at the default, in two operative places, each with an observed consequence:

| Site | Rule as written | What it does at N=2 | Observed |
|---|---|---|---|
| `reconciler.md:20-21`, `integrator.md:51-52` | promote at `≥⌈N/2⌉`; demote at exactly 1 | Both fire on the same singleton — a direct contradiction. Which one an LLM applies is arbitrary. | Run `20260813T132632Z-a638626d`: `future` lost all four Importants and `rtfm`'s Critical was demoted (demote branch), while `editor` promoted three line-edits to Important on 2/2 agreement (promote branch). Both in one run. |
| `integrator.md:94` | Critical is anchored if it appears in `≥⌈N/2⌉` passes | Satisfied by any finding that exists. The anchoring test passes unconditionally. | The `[unanchored]` mechanism — added to stop verdict whipsaw from ~50% Critical test-retest reproducibility — has been inert on every interactive run since N=2 became the default. |

The contradiction was half-noticed once before: `integrator.md:103`'s parenthetical records that an earlier "fewer than `⌈N/2⌉`" phrasing "selected nothing at N=2," and that site was fixed in isolation. `ADR-12:139` noticed the tie explicitly and resolved it — "at N=2, k=1 demotes (demote wins the `⌈N/2⌉` tie)" — but that resolution sits inside ADR-12's **deferred D5** design, which neither `reconciler.md` nor `integrator.md` reads, so the operative prompts never carried it. This ADR supersedes that tiebreak: demote is the wrong winner.

**Why demotion is wrong below N = 5 — not just at N = 2.** It contradicts multiball's own premise. The extra passes exist because per-pass exhaustion is incomplete; the recurrence pilot (2026-06-07) measured per-pass exhaustion at **~40%**. Run that number forward and a singleton is the *modal* outcome for a **true** finding at both operative N:

| N | P(true finding is a singleton, given it was found at all) — at p = 0.4 | at p = 0.3 |
|---|---|---|
| 2 | 75% | 82% |
| 3 | **55%** | 67% |
| 4 | 40% | **54%** |
| 5 | 28% | 43% |

At N = 3 a singleton is still the *majority* outcome for a true finding, so the same argument that kills demotion at N = 2 kills it at N = 3 — and N = 3 is not a hypothetical, it is what every `--full` and `--all` run uses. Keeping the rule there while striking it at N = 2 would have been an unprincipled line: the arithmetic changes continuously in N.

The floor is N ≥ 5 rather than N ≥ 4 for margin. The crossing below 50% happens between N = 3 and N = 4 at the measured p = 0.4, but 40% is a single-pilot point estimate (recurrence-pilot, one run, one corpus); at p = 0.3 the N = 4 row flips back to 54% while N = 5 stays at 43%. N ≥ 5 is the smallest floor that holds across that range. The clause is **dormant by design** — nothing in operative use reaches it (ADR-06 caps at N = 3) — and it is written down so a future N is governed by a rule rather than by a re-derivation. Restoring it at N = 4 is a reasonable move once p is measured a second time.

The corpus agrees, weakly but in the right direction, and the trade is what settles it: across 335 dispositioned Important+ multiball findings, **singletons are ruled `rejected-wrong` 5.0% of the time against 2.8% for corroborated findings** (numbers and command under *Status quo check*). Demotion applied a blanket one-tier penalty to a stratum that is 95% correct in order to catch a ~2-point excess of wrong ones. That is a bad exchange rate at any N where singletons are the majority of true findings.

**Why the converse also had to be written down.** Nothing previously forbade promotion on agreement, and `reconciler.md:22`'s "quality-ranked synthesis, not majority vote" was a caveat rather than a rule. Two passes share a model, a prompt, and a blind spot, so their agreement is weak evidence of importance — it correlates with a finding being *easy to notice*, which is close to the opposite of important. Now stated as a prohibition at N = 2, and raised to a true majority at N ≥ 3.

**Rejected alternative**: keep demotion at N = 3 and strike it only at N = 2, since at N = 3 the promote and demote branches are disjoint and no longer contradict. Rejected because the contradiction was never the whole case against the rule — the exhaustion arithmetic is, and at 55% it indicts N = 3 too. Retaining it would also have left the interaction below unfixed: at N ≥ 3 a demoted Important is a Minor by the time the integrator selects the verification queue, and `verify_queue` rule 2 only sees Importants, so demotion silently removes findings from the one stage that adjudicates them on evidence.

**Rejected alternative**: retain demotion on a likelihood-ratio argument — a singleton is less likely under "true" (55%) than under "false" (near 100% if false findings never reproduce), so it *is* evidence. Rejected because `P(singleton | false)` is unmeasured: no instrument in this repo estimates the reproducibility of findings that turned out wrong. Trading a measured base rate for an assumed likelihood is the move this ADR's own review flagged elsewhere.

**Rejected alternative**: exempt design/architecture lanes (`future`, `blindspot`, `thousand`) from demotion and keep it elsewhere. Rejected because the lane is not what makes the rule wrong — N is. The same singleton-heavy distribution holds for `adv` and `rtfm`; `rtfm`'s demoted Critical in the motivating run was not a design finding. A lane carve-out would also need maintaining per persona and would silently mis-apply to every new one.

**Rejected alternative**: raise the interactive default to N = 3 so `⌈N/2⌉` stops degenerating. Rejected as out of scope and expensive — ADR-06 set N = 2 on cost grounds after N = 5 proved unaffordable — and, given the row above, it would not have fixed demotion anyway.

**What replaces demotion. Nothing, and §5.7 verification does not cover the gap.** As first shipped this ADR claimed "the §5.7 verification stage already does this job properly." That was false, and its own motivating run says so:

- **The queue cap binds.** `integrator.md:108` caps the queue at 8, priority Criticals → consistency-shaped → singleton Importants, so singleton Importants are the first thing dropped. Run `20260813T132632Z-a638626d` Integration Notes: `unverified (queue cap): f14, f16, f17 (singleton Importants at code-site, 1-of-2-pass support)` — three of the exact findings the claim said were covered, in the run the claim was written from.
- **The queue never sees Minors**, so once demotion has fired at N ≥ 3 the finding is out of reach regardless of the cap.
- **`cited-spec` singletons are excluded** by rule 2 by construction.
- **`base_severity` does not exist.** The shipped text leaned on "the ADR-12 note that `verify_queue` keys on `base_severity`" — but that note lives in ADR-12's Appendix A, the **deferred** D5 design. No prompt and no script implements the field. Citing a deferred design as an operative guarantee is precisely the failure this ADR opens by describing in ADR-12; it should not have been repeated three paragraphs later.

So the honest statement is: demotion is removed and nothing takes its place. Verification remains valuable and still catches part of this population, but it is a partial, capped, severity-gated overlap, not a replacement. What justifies removing the rule anyway is the exchange rate measured above, not a substitute mechanism.

**Could-be-wrong-if** — *re-derived 2026-08-25 against a denser signal; the original `rejected-wrong` clause is kept below as a tombstone because its decay is the evidence for the swap*: pass count turns out to carry real signal about severity being **over-filed**. Concretely — among multiball findings where a verifier actually rendered a severity judgment, the over-filed rate for `pass_support` singletons (k = 1 in every persona that caught it) reaches **≥ 25%** *and* **≥ 2×** the k ≥ 2 rate, on **n ≥ 100** singletons and **n ≥ 75** corroborated, *and* the Critical stratum does not contradict it (ratio ≥ 1.0×). That would mean demotion was discarding genuinely over-filed findings and should be restored — first at N = 3, and at N = 2 only if the effect survives there.

**Over-filed** = the verifier `REFUTED` the finding, **or** kept it and recorded `severity_opinion: too-high`. REFUTED is the limiting case of too-high — the severity should have been nothing at all — so the union is one coherent quantity: *the filed severity was wrong in the direction demotion moves it*. That is the operation this ADR removed, which is why the union replaces the `rejected-wrong` proxy rather than sitting beside it. The old clause asked whether singletons are more often **wrong**; this one asks whether they are more often **over-filed**, and the decision under test is a severity operation, so the second question is the one that was always meant.

**Why the swap, in events.** `rejected-wrong` is 13 events across 420 dispositions (3.1%) — the absolute clause sat >3× above anything the corpus had produced. Over-filed is **29 events across 209 judgments (13.9%)**, a 4.5× denser positive class. The consequence is the whole point: **both n clauses are already satisfied** (122 singletons, 87 corroborated), so this falsifier can fire *today* on the data already on disk if the effect exists. The old one could not have fired on any timescale we care about.

**Why not `severity_opinion` alone**, which is what `backlog.md` queued. The field is **omitted on REFUTED by contract** (`verifier.md:40`), so on its own it measures calibration only among findings whose mechanism survived verification — blind to exactly the stratum most associated with being wrong. Taken alone it reads k = 1 13/119 = 10.9% vs k ≥ 2 9/83 = 10.8% `too-high` (1.01×); folding REFUTED back in is what makes the denominator the full set of severity judgments rather than the survivors.

**The admission confound, and why stratifying answers it.** The original clause sampled human dispositions specifically to dodge `verify_queue` rule 2, which admits Importants only at `k ≤ ⌊N/2⌋` (`integrator.md:105`), leaving the k ≥ 2 Important stratum reachable only through rule 3 — consistency-shaped claims, which `integrator.md:106` names as the source of every false positive in the eval record. That confound is real and it survives the swap, since over-filed is measured on verification output.

What partly defuses it is that **rule 1 admits every Critical to the queue regardless of k**. As first written this ADR went one step further and said the Critical stratum "carries no k-based selection at all." **That is false, and the correction matters more than the original claim did.** Rule 1 governs *admission*; it does not govern *survival*. `integrator.md:108` caps the queue at 8 and Phase 3 ranks by severity × consensus × effort, so on any run that overflows the cap the Criticals reaching a verdict are corroboration-selected. Measured 2026-08-25: **63 of 86 in-scope Criticals carry a verdict**, with 7 runs leaving some unverified (`20260823T202901Z-67af1a61` at 16 Criticals / 8 verified; `20260824T210716Z-51e48e8e` at 17 / 9). In `67af1a61` the verified Criticals average **4.75 attributing personas against 1.625** for the unverified — the truncation tracks corroboration directly. So the Critical stratum is **less** confounded than the Importants, not unconfounded, and the clause below is a weaker-confound sanity check rather than a clean read.

The instrument therefore reports pooled, per-severity *and* per-N, and the falsifier requires the less-confounded stratum not to contradict the pooled one. The confound's direction is toward *not* firing (it enriches k ≥ 2 with the worst class), so a fired result stays trustworthy. That direction claim was itself challenged on the grounds that rule 2's own evidence-tier gate — it admits singleton Importants only below `cited-spec` — enriches the k = 1 stratum in the opposite direction, leaving the net sign undetermined. **Measured, it does not**: rule 3 backfills cited-spec singletons through the consistency-shaped path, and the two strata's evidence-tier compositions come out statistically indistinguishable (cited-spec share 14/82 = 17.1% at k = 1 vs 14/69 = 20.3% at k ≥ 2, p = 0.61 — and the point estimate runs *opposite* the objection). Evidence tier does not predict over-filing in this corpus either (14.3% vs 18.7%, p = 0.58). The one-sidedness in the prose was real; the skew it predicted is not there.

Three measurement caveats:

1. `pass_support` k is floored at 1 for any persona the integrator attributed but whose passes failed to `rid`-match (`assemble-wpr.py`'s `best_rid` join, `:87`), so k is a lower bound. Corroborated findings leak into the k = 1 stratum and dilute the gap. Biases **against** firing.
2. Historical severities are **post-demotion** for runs before 2026-08-13, so surviving singletons are ones the reconciler declined to demote — selected for strength. Biases **against** firing. Decays as post-ADR-16 runs accumulate.
3. The k ≥ 2 stratum is 79 findings at k = 2 and 8 at k = 3; **no run in the corpus uses N ≥ 5**. This instrument therefore says nothing about the N ≥ 5 demotion floor, which remains what it always was — a dormant clause resting on the singleton-probability arithmetic above, not on this comparison.

**Evaluated by** `scripts/pass-support-accuracy.py` — a script rather than an inline heredoc, deliberately. The failure this re-derivation corrects is not only that the old bar was unreachable; it is that nobody re-read the instrument for eleven days, and an instrument that costs a paste-and-edit to run is one that decays unobserved. Thresholds live in the script as named constants so a silent edit shows up in `git diff` against this ADR.

```bash
scripts/pass-support-accuracy.py          # human-readable, with per-severity strata
scripts/pass-support-accuracy.py --json   # machine
```

**Backward run, 2026-08-25** [ran]. Per ADR-14's amended rule, evaluated against the corpus that already exists before being adopted — the discipline that ADR-14's TTL falsifier shipped without and was wrong for:

```
  runs scanned 178, in scope 34
  !! 4 unreadable snapshot(s) — corpus is incomplete
  !! 1 malformed finding(s) excluded:
       F7: severity outside the enum: 'refuted'

  k=1  singleton    : over-filed 16/122 =  13.1%
  k>=2 corroborated : over-filed 13/87  =  14.9%
  ratio             : 0.88x
  two-sided p       : 0.706 (diagnostic; never gated on)

  by severity (Criticals are less k-selected than Importants — not unselected):
    critical  k=1 3/30 =  10.0%   k>=2 4/32 =  12.5%   ratio 0.80x
    important k=1 13/83 =  15.7%   k>=2 8/50 =  16.0%   ratio 0.98x

  by multiball N (the restoration rule is N-specific; pooling hides sign flips):
    N=2        k=1 15/113 =  13.3%   k>=2 10/72 =  13.9%   ratio 0.96x
    N=3        k=1 1/9   =  11.1%   k>=2 3/15  =  20.0%   ratio 0.56x

  per-run crossings of 25.0% (runs with >= 4 judged singletons):
    observed 3 of 15, expected by chance 3.24, P(>= observed) 0.67, max 42.9%

  [x] powered        n1>=100 and n2>=75  (have 122, 87)
  [ ] absolute       k=1 rate >= 25.0%
  [ ] ratio          k=1/k>=2 >= 2.0x
  [ ] uncontradicted Critical stratum ratio >= 1.0x

not met
```

Two of those lines are the instrument reporting on itself and should not be read past. The **malformed finding** is a snapshot row carrying `severity: "refuted"` — a clobbered value, not a severity — which the first cut of this script folded into the pooled denominator because it never validated the enum. Excluding it is what moves the headline from 16/106 to 15/105 on the same corpus. The **unreadable snapshots** were previously dropped in silence, so a corrupted corpus would have produced a legitimate-looking `not met` on a denominator nobody had audited. The remaining growth to 122/87 is corpus accumulation: this run's scope now includes the review of this ADR and the 20 verdicts it produced.

The status quo does not already pass, so the bar is non-decorative. **The reachability argument first offered for the 25% clause was wrong, and it was wrong in the same way the clause it replaced was wrong.** It read: *4 of the 15 runs with ≥ 4 judged singletons post a k = 1 over-filed rate ≥ 25%, max 42.9% — so a sustained 25% is a value this instrument has produced.* Those crossings are what noise produces. Per-run denominators here are 4–7, which quantize so coarsely that a 15% population throws 25%+ readings routinely: at the pooled base rate the **expected** number of crossings across those runs is **3.24 against 3 observed, P(≥ observed) = 0.67**. The observation is indistinguishable from chance, so it is evidence about quantization, not about reachability at the registered denominator of n ≥ 100. The instrument now prints that expectation beside the observation on every run, which is the only reason this cannot be misread a third time. **The 25% threshold is retained but is now explicitly a judgment call, not an empirically demonstrated value** — a rate the corpus has never sustained at any honest denominator.

The 2× ratio is likewise not what the first cut claimed. It cited **71% power at α = .05 two-sided, and 95% at 2.5×**. Those figures are arithmetically correct — simulation reproduces 71.8% / 95.6% — but they describe a **two-proportion z-test that the firing rule never applies**. `p_value` is computed and printed; `fired` is a conjunction of point-estimate thresholds and never reads it. Simulating the *actual* rule at the registered denominators against a true 2× effect gives a fire probability of **~49%**, not 71% (~0.79 at 2.5×, which the original figure happened to match). A reader discounting a `not met` by "71% power" therefore overweights the null by roughly 22 points. The z-test power is retained above only as a diagnostic; the number that governs how much a `not met` is worth is ~49%.

**What the not-met now means, and this is the change that matters.** The old instrument's "not yet met" was uninformative — absence of evidence from a starved positive class. This one is a **null with real power behind it**: 209 judgments, 29 positive events, p = 0.71, and every stratum at or below parity (pooled 0.88×, Important 0.98×, Critical 0.80×, N = 2 0.96×). Of the two readings the 08-24 re-read could not distinguish, **reading 1 is now the supported one**: in the k = 1 vs k ≥ 2 range at N = 2–3, pass count does not predict that a severity was over-filed, and demoting on it would be sorting on noise. That *strengthens* the decision this ADR made rather than threatening it.

Two honest qualifications on "powered". First, ~49% is the fire probability at a true 2×, not 71% — so this null excludes a 2× effect with materially less confidence than the original text implied. Second, **the one stratum that runs the other way is N = 3** (0.56×, k = 1 1/9 vs k ≥ 2 3/15), and the restoration clause below is explicitly N = 3-first. That inversion is 4 positive events across 3 run-dirs, Fisher exact p = 1.0 — noise, and it is reported rather than acted on. But it is reported at all only because the instrument now stratifies by N: pooled across N the two strata cancel to 0.88× and the sign flip is invisible, while **~87% of the eligible corpus is N = 2** (166 of 190 at the time of measurement). A pooled `FIRED` would be an N = 2 result answering an N = 3 question.

Confidence **0.65** [tier: ran-and-saw-output], revised down from 0.75 on 2026-08-25. Held there because the two supporting reads are each weak where the other is strong, and the second is weaker than first stated: the pooled comparison carries the rule-2 confound, and the Critical stratum — the intended answer to it — is only *less* selected, not unselected (63 of 86 Criticals reach a verdict, and the cap that drops the rest tracks corroboration), while resting on 7 events. The fire probability at a true 2× is ~49%, so a `not met` is weaker evidence against the effect than a "71% power" reading suggests. Could-be-wrong-if: the Critical stratum at n ≥ 150 (roughly 5× current, ~20 more full runs) shows k = 1 over-filed at ≥ 2× the k ≥ 2 rate, which would mean the pooled null was the confound talking after all — and note that this successor read must come from runs where the verify queue did **not** overflow, or it inherits the same selection it is meant to rule out.

**Not changed on the strength of this.** The N ≥ 5 floor stays at 5. A powered null over k = 1 vs k = 2–3 is not evidence about N = 5, which no run in the corpus has ever used (caveat 3 above); and the floor's justification was never this comparison. If the null holds as post-ADR-16 runs accumulate, retiring the dormant clause outright is a candidate for a successor ADR — not a thing to fold into the ADR whose premise it undercuts.

---

**Superseded falsifier (pre-registered 2026-08-13, retired 2026-08-25).** Kept because the decay history is the evidence that justified replacing it, and because deleting a falsifier that failed is how a repo loses the ability to notice it failed.

> Among Important+ multiball findings carrying a **human** disposition, the `rejected-wrong` rate for k = 1 singletons reaches **≥10%** *and* **≥3×** the k ≥ 2 rate, on **n ≥ 50** dispositioned singletons.
>
> | read | k=1 | k≥2 | ratio | verdict |
> |---|---|---|---|---|
> | 2026-08-13 (backward) | 6/120 = 5.0% | 6/215 = 2.8% | 1.79× | not yet met |
> | 2026-08-24 (re-read) | 6/172 = 3.5% | 7/248 = 2.8% | 1.24× | not yet met |
>
> Eighty-five new dispositioned findings produced exactly **one** new `rejected-wrong`. Both denominators grew while the numerators did not, so the ratio decayed *toward* the null — and corpus-wide `rejected-wrong` is 13/420 = **3.1%**, putting the absolute clause more than 3× above anything the corpus has ever produced. **A falsifier whose positive class is that rare cannot fire on any timescale we care about, which makes it unfalsifiable in practice** — the failure mode ADR-15 exists to catch, reproduced inside the acceptance criteria of its successor. The evaluating command is preserved at `git show 94d95fc:docs/decisions/16-reconciliation-thresholds.md`.

The `rejected-wrong` instrument is not *wrong*, only starved; it remains a legitimate secondary read on the correctness question, and `mine-runs.py` still reports the dispositions it needs. What it cannot do is carry an acceptance criterion.

> **Status quo check as written 2026-08-13, and where it went wrong.** It correctly established that the status quo did not already pass — 5.0% vs 2.8% on n = 120, with both clauses outside that. Then it claimed the bar was "inside the metric's demonstrated range rather than off the end of it," citing ADR-15's per-persona `fp%` of 7% (`recip`, n = 15) as evidence that a 10% stratum rate was nearly reachable. **That citation is the defect.** Per-persona false-positive rate and per-k-stratum `rejected-wrong` rate are different metrics over different denominators; the range of one says nothing about the reachability of the other. The check that would have caught it — *what is the highest value this metric has actually produced?* — was never run, and the answer was ~5%. A range claim must be evidenced from the metric's own distribution — and **the replacement above committed a version of the same error on its first pass**, which is why this tombstone now carries two names. It cited per-run k = 1 over-filed rates (4 of 15 runs ≥ 25%, max 42.9%) as evidence that 25% was reachable, and did so twice over: the figure was attributed to "the same script that evaluates the clause," but that script populated `per_run_k1` and never read it, so the number came from somewhere unrecorded; and the per-run denominators were 4–7, where crossings at that rate are what chance produces (expected 3.24, observed 3). Both defects are now closed — the script emits the per-run breakdown *and*, beside it, the crossings chance alone predicts. The rule the 08-13 check needed is one clause longer than it looked: a range claim needs the metric's own distribution **and** its null.

**Status quo check** [ran 2026-08-25]: see the backward run above — `not met`, with the absolute and ratio clauses both unsatisfied, so the bar is non-decorative. Choosing a ratio clause alongside the absolute one is the template's paired-comparison preference: the absolute rate moves with corpus-wide finding quality, the k=1-vs-k≥2 ratio does not.

**How to apply**: this binds any change to within-persona reconciliation — `reconciler.md`'s reconciliation rules, `integrator.md` Phase 1 (and its Phase 3 anchoring test), and any script that re-derives what the k/N rule "would have" assigned (`assemble-wpr.py`'s `severity_drift` audit). Three concrete triggers: (1) changing the multiball default N in ADR-06 or SKILL.md §4 — re-read the singleton table above before assuming the rules carry over; (2) adding a rule keyed on a pass count anywhere — write it against a stated floor, never against `⌈N/2⌉`, which is 1 at the default; (3) writing a new severity heuristic into a script — gate it on the N where a frequency rule actually exists, or it will fire on the normal shape of every run. A fourth trigger is on the falsifier rather than the decision: **re-run `scripts/pass-support-accuracy.py` at each retro** — it costs one command, both n clauses are already met so its verdict is live rather than pending, and the eleven-day gap in which the previous instrument decayed unobserved is the reason it is named here instead of left to memory. The prompts are the operative artifacts: a threshold changed here and not in `reconciler.md` and `integrator.md` has not shipped, which is the whole lesson of ADR-12's D5 tiebreak.
