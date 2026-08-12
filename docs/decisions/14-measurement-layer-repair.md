# ADR-14 — Measurement-layer repair, and a rule about falsifiers

**Date**: 2026-08-09
**Status**: accepted
**Supersedes**: nothing. **Amends**: ADR-08 (adds `severity_opinion` to the verdict schema), ADR-12 (adds `scale` to `usage.json`).

## Context

An overnight exploration ran eight independent analyses of NineAngel (four topics × Fable/Opus, identical briefs, `~/.angel/exploration/2026-08-09/`). The comparison is in `COMPARISON.md` there. Several findings converged across both models and survived first-party verification; this ADR records the batch shipped in response, and one rule that generalizes beyond this project.

Three things were settled empirically before any change was made:

1. **`usage.log`'s `total:` field is a context high-water mark, not spend.** Verified 8/8 against subagent transcripts: the recorded figure matches each pass's *peak single-turn context* to within 0.2%, against cumulative flows 18.8×–43.5× larger, with the ratio growing with turn count. Every per-token figure in ADR-01, ADR-06, and the Thousand demotion is a peak-context delta presented as a cost delta. **[Direction correct, magnitude overstated — corrected to a median 10.6× below.]**
2. **Cost is dominated by cache traffic, not output.** Measured on a comparable 8-agent batch: cache writes 46% of cost from 8% of tokens, cache reads 40%, output 14%, uncached input 0.3%. **[Superseded — the real split is writes 33%, reads 41%, output 25%. See below.]**
3. **ADR-08's rubber-stamp falsifier is at 93.3%** (163 CONFIRMED / 5 PLAUSIBLE / 12 REFUTED across 180 verdicts in 31 run dirs) — above its own ≥90% threshold. See "the falsifier rule" below for why it still did not fire.

## Decision

Six changes, all mechanical, all shipped with tests.

1. **`mine-runs.py` scores each false positive once, against a denominator it is in.** Two stacked defects: no `elif`, so a finding both human `rejected-wrong` and machine `REFUTED` counted twice; and machine REFUTED incremented the numerator without the denominator, so `fp_rate` could exceed 1.0. Precedence is now human-over-machine. Measured effect on the real corpus: 8 personas change, 11 of 35 reported false positives were double-counts, corpus fp 2.54% → 1.74%, `pii` 100% → 67%.
2. **`severity_opinion: agree|too-high|too-low` is required on every verdict.** SKILL.md §9 has promised "severity accuracy" since the outcomes format was written and no schema field for it existed, while `verifier.md` already mandated the judgment and sent it to free-text `note`. Zero marginal runtime cost.
3. **The pre-commit hook is installed, and works when installed.** It was absent from `.git/hooks/`, and installing it failed immediately because it resolved sibling scripts through the hook symlink's directory. The documented install line had never been exercised.
4. **`validate-personas.py` runs at §3 pre-flight.** It ran only at pre-commit and publish — never on the run path, the one place a malformed registry costs a battery, since §1 selects from that frontmatter.
5. **`scale: {files, diff_lines}` is recorded per run**, derived from `filelist.txt` / `src-only.diff`, which already exist in every run dir. Without it, "yield per token fell 3×" cannot be separated from "batteries got pointed at bigger targets" — the two overnight T1 analyses reached opposite verdicts on that exact trend.
6. **Window-aware batching is removed from §4.** It ordered batches of 3-4 at `N ≥ 9` on an orchestrator output budget that the pass-file contract has since eliminated. Measured median parallelism was 2.5×, with recent large runs at 0.9× — effectively serial. DESIGN.md:149's concurrency claim, aspirational since batching was introduced, is now true and carries a note to change both together.

### The falsifier rule

**Every falsifier in a NineAngel ADR must name the command that evaluates it, and that command must be run on the day the ADR ships with its "not yet met" output pasted in.**

This is the generalizable finding. The overnight audit framed the project's unadjudicated triggers as a discipline failure — things fired, nobody decided. The evidence supports something worse: at least three could not have been settled by someone who wanted to.

- **ADR-06** compares recall against an N-pass union that grows with N. At ~50% per-pass reproducibility, k=2-of-3 recovering ~71% is near the expectation of pure resampling, so the rule cannot distinguish "N=3 finds more real defects" from "N=3 samples more noise."
- **ADR-08** is an AND. The first clause is computable and met (93.3%). The second — "no REFUTED verdict ever prevented a would-be-accepted finding" — requires dispositions on refuted findings; 4 of 12 have `no-record` and one run has no `dispositions.json` at all. **It cannot fire as written**, which is why this ADR does not demote the verify stage on the computable half alone.
- **ADR-09**'s falsifiers are denominated in a run profile the §8 log line does not carry, so "zero micro runs" conflates *unused* with *unlogged*.

A watch mechanism that checks whether a threshold is crossed does not fix any of these. Writing the evaluating command first does. The rule is also added to `~/.claude/templates/adr-template.md`, since nothing about it is specific to this project.

## Consequences

- Precision figures move. Any analysis citing per-persona `fp%` from before 2026-08-09 is reading inflated numbers; the direction is always down.
- Severity accuracy becomes computable from the first verdict written after this ADR. The report section stays silent until verdicts carrying the field accrue, so it will read as absent rather than as zero.
- `usage.log` lines gain `files:` / `difflines:` where the artifacts exist. Historical lines do not, and cannot be backfilled for runs whose dirs were pruned.
- Removing batching is the one change here with real behavioral blast radius, and it is **unvalidated** — see below.

## Could-be-wrong-if

**(a) Batching was load-bearing for reasons the output-budget rationale did not state.** The next `--full` run on **a private target** is the test, compared against the paired pre-change a private target `--full` (`20260807T142427Z-1dd77385`: 73 passes, **4.41×**, **127 min**). Thresholds, on comparable pass count (±25%):

- **Parallelism ≥ 6.6×** (1.5× the paired baseline), **or span ≤ 85 min** (⅔ the baseline) → batching was a real constraint and its removal helped.
- **Neither moves** → batching was not the binding constraint; the cause is elsewhere (orchestrator turn latency, or an Agent-tool concurrency cap), and §4's rationale should say so rather than claiming a win it did not produce.
- **Orchestrator context exhaustion or dropped returns appear** → batching was doing real work and should return, with DESIGN.md:149 and `unattended.md` Step 3 corrected in the same commit.

Do **not** commission a run to satisfy this. Every run writes the inputs as a byproduct; a dedicated `--full` costs roughly $500 at list (the paired baseline moved 496M tokens) to buy data that arrives free with the next organic review.

**Evaluated by**: per-run `usage.jsonl` span-vs-sum arithmetic —
```
python3 - <<'PY'
import json,glob,os,datetime
t=lambda s: datetime.datetime.fromisoformat(s.replace("Z","+00:00"))
for p in sorted(glob.glob(os.path.expanduser("~/.angel/runs/*/usage.jsonl"))):
    ls=[json.loads(l) for l in open(p) if l.strip()]
    ls=[x for x in ls if x.get("started_at") and x.get("ended_at") and x.get("duration_ms")]
    if len(ls)<16: continue
    span=(max(t(x["ended_at"]) for x in ls)-min(t(x["started_at"]) for x in ls)).total_seconds()
    if span<=0: continue
    print(f"{os.path.basename(os.path.dirname(p)):17} {len(ls):3} passes "
          f"{span/60:7.1f} min {sum(x['duration_ms'] for x in ls)/1000/span:6.2f}x")
PY
```
→ Ran 2026-08-09 against the pre-change corpus: **14 runs** with ≥16 passes, parallelism min 0.04× / median 2.21× / max 7.56×, span median 84 min. Not yet evaluable for the change itself — zero `--full` runs since.

> **Amended 2026-08-09, hours after shipping, on the strength of that backward run.** The original threshold was absolute: "median parallelism must exceed 4.0×, median span below 60 min." Running the evaluating command against the **existing** corpus shows why that could not discriminate — **5 of 14 pre-change runs already clear 4.0×, and 6 of 14 already clear 60 minutes**, batching fully in force. The 4.41× paired baseline is itself above the bar. A post-change run scoring 4.5× would have landed inside the pre-change distribution and proved nothing, while reading as a pass.
>
> The threshold had been set from the two runs in front of me when I wrote it (a 4.4× full and a 0.9× diff) rather than from the distribution, which spans 0.04× to 7.56× — variance dominated by target size, integrator stalls, and at least one wedged-dispatch incident. Batching is one term in a noisy sum; the original test treated it as the only one. Pairing against the same project controls for the largest confound.
>
> **Third instance of the same lesson, and the sharpest.** ADR-14's own rule says to name the evaluating command and run it at ship time. I did — but only *forward*, against a population that did not exist yet, which returns "not yet met" for a well-posed and an ill-posed threshold alike. **The rule needs its other half: run the command against the existing corpus too, and check that the threshold is not already satisfied by the status quo.** A falsifier the current state would pass is not a falsifier. That check is cheap, it is mechanical, and it would have caught this one in one command.

**(b) `severity_opinion` is a permanent tax that buys nothing.** If, across the next 50 **CONFIRMED-or-PLAUSIBLE** verdicts carrying the field, ≥90% return `agree` (fewer than 5 disagreements), severity self-assessment is accurate and the field should be demoted to an occasional audit rather than a per-verdict requirement. If `too-high` exceeds `too-low` by ≥2:1, the battery systematically inflates severity and the report's ranking is wrong in a knowable direction.

**Evaluated by**: `python3 scripts/mine-runs.py | sed -n '/## Severity accuracy/,/^$/p'` → currently prints nothing, because zero verdicts carry the field. That silence is the correct pre-data state, not a failure.

> **Amended 2026-08-09, same day, after a `coach` review of this ADR's own commit range.** The denominator originally read "the next 50 verdicts carrying the field," and the schema originally required the field on REFUTED verdicts too. Both were wrong, and in the same place: all three enum values presuppose a mechanism that fires, so a REFUTED verdict has no consequence to weigh the filed tier against. Verifiers would have split between a counterfactual reading (`agree` — the tier fits the claim as filed) and a literal one (`too-high` — the actual consequence is nil). REFUTED is **12 of 184 verdicts (6.5%)** `[ran: tally over ~/.angel/runs/*/verification/*.json]`, so at this threshold ~3 of 50 would have been inconsistently-judged noise — enough to move both the 90%-agree test and the 2:1 skew test on a subpopulation where the measurement is meaningless by construction. REFUTED now carries no opinion (`verifier.md`), `mine-runs.py` filters it regardless of what a verdict file claims, and this denominator says which verdicts it counts.
>
> Worth recording as a second instance of the same lesson this ADR introduced: **the fragile part of a falsifier is its denominator**, and running the evaluating command at ship time would not have caught this one — the severity section prints nothing until data accrues, so the denominator was never exercised. The rule as written ("run the command, paste the not-yet-met output") is necessary but not sufficient for falsifiers whose population does not exist yet. For those, state the population's *inclusion rule* explicitly rather than relying on the command to reveal it.

**(c) The fp precedence rule is backwards.** Human-over-machine assumes the human ruling is better informed. If findings that were machine-`REFUTED` but human-`accepted` turn out to be dominated by cases where the verifier was right and the human fixed a non-bug, precedence should invert.

**Evaluated by**: cross-join of `verification/*.json` against `dispositions.json` over `~/.angel/runs/*/`, filtering `verdict == REFUTED and disposition.startswith("accepted")` → **returns 1 finding** (run `20260801T143040Z-bb75d4d9`, `f3`). Threshold: not evaluable at n=1 — re-run when the population reaches ≥8; invert precedence if ≥⅔ favour the machine.

> **This falsifier is the rule's first catch, and it caught this ADR.** The paragraph above originally read "currently 7 findings," taken from the overnight analysis. Running the command returned 1. The 7 was a different set — `rejected-wrong ∩ REFUTED`, the overlap driving the double-count in change (1) — and I had carried it across to `REFUTED ∩ accepted` without checking. A falsifier whose command is written and run at ship time cannot inherit that kind of error; one whose command is merely described can, and this one did.

## Amended 2026-08-09, same day — the meter itself was double-counting

**The cache-write anomaly this ADR left open was an artifact of the tool this ADR shipped.** It is closed, and two of the three empirical claims above move.

`true-cost.py` summed `usage` over every transcript **line**. But the harness writes one transcript record per **content block** of an assistant message, and every one of those records repeats the same `usage` object. A single billed API call therefore appears 2–4 times. Over all 2285 transcripts — 82,732 usage records against **35,496 distinct `requestId`s, mean 2.33 records per request** — summing per line inflates:

| class | inflation |
|---|---:|
| cache **write** | **2.74×** |
| cache **read** | 2.19× |
| uncached input | 2.98× |
| **output** | **1.05×** |

**That asymmetry is the whole anomaly.** Non-terminal duplicate records carry ~2 output tokens while the cache counters repeat at full value. So the numerator of "writes vs. genuinely new content" was inflated ~2.7× and the denominator — which was mostly output — was not. The gap was manufactured by the measurement.

Collapsing to one record per request (`requestId`, falling back to `message.id`):

- **Write amplification is 0.94× fleet-wide, 0.92× on the a private target `--full` run.** Contexts grow monotonically, so a healthy incremental cache writes each token once and `sum(writes) ≈ sum(peak context)`. It does. There is no anomaly to explain.
- The 08-07 run's cache writes are **9.33M, not 25.5M**, and decompose: **22.3% first-turn dispatch prefix**, **11.0% re-write**, **66.7% genuinely-new content**. The 6.22M of new content against the "~3.6M of tool results + output" the anomaly was posed with is the rest of the gap: that estimate excluded the dispatch prefix by construction.

  **The prefix figure needs care, and the first reading of it was wrong.** The 2.08M over 82 agents is ~25.3k each, and that was reconciled here as "consistent with the ~33.5k prefix measured separately, lower because a third of the roster is Haiku." Every clause of that is false, and the arithmetic it implies is impossible — it requires a *negative* Haiku prefix. Measured: mean first-turn **write 25,324**, mean first-turn **read 25,055**, mean **total first-turn prefix 50,378**; Haiku is **9 of 82 agents (11%)**, not a third, and its measured prefix equals Sonnet's. The mechanism is that concurrent siblings **share a prefix**: the first agent writes it and the rest read it, so `first-turn prefix` counts only the *written half*. It therefore **understates** true prefix cost by roughly 2× — the opposite of the reassuring gloss originally attached to it. *(Corrected 2026-08-12; `rigor` caught it on both passes.)*
- **Run cost: $509.66 → $234.92.** Tokens 496.3M → 214.7M. Understatement 56.5× → 24.4×.
- **Fleet-wide: $7,568.64 → $3,543.43** over the same corpus, a **2.14×** overstatement of every figure the meter has printed.

Corrected cost structure, measured over all 35,496 requests rather than one 8-agent batch:

| class | share of tokens | share of cost |
|---|---:|---:|
| cache **read** | 92.8% | **40.7%** |
| cache **write** | 6.0% | **33.3%** |
| **output** | 1.0% | **25.1%** |
| uncached input | 0.2% | 0.9% |

"Cost is cache traffic, not output" survives — 74% of cost is cache — but **output is 25% of the bill, not 14%**, which is nearly double and changes what a leaf-dispatch context diet is worth relative to shortening pass write-ups.

Corrected understatement of `usage.log`'s `total:`, over the 1792 transcripts with ≥5 requests: **median 10.6×** (p10 5.0×, p90 28.9×). The 18.8×–43.5× range was 8 agents measured on the inflated basis. Claim 1's direction is unchanged and still an order of magnitude.

**A second, smaller defect surfaced in the same pass:** the meter priced a whole transcript at the *first* model it saw. 138 of 2288 transcripts (6.0%, as of 2026-08-09) carry more than one. A **minority** — 63, or 46% — are only a trailing `<synthetic>` abort placeholder, which is skipped; the other **75 (54%) are genuine mid-pass switches**, one running **26 requests on Fable and 11 on Opus**. Requests are now priced at the model that served them.

**Validation.** The collapse is not an assumption. `requestId` and `message.id` agree; one or the other is present on 100% of records; the cache counters are identical across a request's records in 99.98% of cases (the 8 exceptions are trailing all-zero aborts, so the selector takes max output rather than the last record). Independently: deduped, request N's `cache_read` matches request N−1's total context with **median ratio 1.0000** (93.1% within 2%, 97.9% within 10%). Per line it is 0.9893 with **18.3% of pairs outside 10%** — an incoherent conversation. The collapsed sequence is the real one. Pinned by `scripts/test_true_cost.py` (45 assertions), wired into `test_scripts.sh`.

> **Corrected 2026-08-12 after `/angel` on this commit** (run `20260809T151654Z-e9872ab0`, CHANGES REQUIRED, 12 Important). The paragraph above originally read "one pass ran **52** requests on Fable and **25** on Opus," and described `<synthetic>` as the majority case. Both were wrong, and the first was wrong in the way this ADR exists to warn about: **52/25 is the per-LINE record count. Per request it is 26/11** — the exact double-count the change corrects, committed in the sentence explaining the correction, at the same ~2× ratio. `rigor` caught it on both passes.
>
> **Every absolute count in this document is now dated**, because the corpus grows monotonically: the same sweep read 2,285 transcripts on 2026-08-09 and **2,521 on 2026-08-12**. That drift is why "2285" and "2288" both appear here meaning the same population. Ratios are stable; counts are snapshots.

**Evaluated by**: `scripts/true-cost.py <run_dir> --breakdown`, new in this amendment. Ran 2026-08-09 on `20260807T142427Z-1dd77385`:
```
  cache-write budget:
    amplification  : 0.92x  (sum writes / sum peak context; ~1.0 = each token written once)
    first-turn prefix (written half only)     2,076,533   22.3%
    re-write (cache lost between turns)       1,026,629   11.0%
    genuinely-new content                     6,224,510   66.7%
    re-write turns : 60/2013 (3.0%)  [turns = 2095 requests - 82 transcripts; a first request has no preceding turn]
    re-write tokens by inter-turn gap: <60s 34%  60-300s 66%  300-600s 0%  >=600s 0%  unknown 0%
    (13 turn(s) where context shrank; their vanished content is NOT counted as re-write)
```
*(Re-generated 2026-08-12 after the re-write formula was corrected. The block originally pasted here read `re-write 1,900,395 / 20.4%`, `new 5,350,744 / 57.4%`, `<60s 19% 60-300s 81%`. See the correction below.)*

### What is actually left, and why the first falsification missed it

> **Rewritten 2026-08-12.** Everything in this section was computed with a re-write formula that booked context *shrink* as re-write. The corrected figures follow; the superseded ones are named inline so the delta is legible rather than quietly swapped.

Re-writes — content already paid for, not served from cache on a later turn — are **11.0% of writes on the 08-07 run and 16.4% fleet-wide** (as of 2026-08-12), so roughly **5% of spend**, against the ~32–46% the anomaly was thought to be worth. They are concentrated: 3.0% of turns produce all of it. *(Superseded: 20.4% / 23.9% / "7–8% of spend", inflated by the shrink defect — 300 of 33,350 turns fleet-wide carried 64% of the reported mass, and the decomposition drove `new` negative in 16 transcripts.)*

**The gap distribution no longer supports a clean TTL story.** On the 08-07 run the mass splits **`<60s` 34% / 60–300s 66%**; fleet-wide **`<60s` 25% / 60–300s 36% / 300–600s 19% / ≥600s 20%**. *(Superseded: "81% follows a 60–300s gap", and — flatly false — "on this run *no* turn had a gap above 300s"; there are **three**, at 314s, 320s and 333s. They carry zero re-write, i.e. they were counter-evidence to the TTL account, dropped rather than reported.)*

The original diagnosis of the first falsification still stands and is worth keeping: the overnight analysis tested the right hypothesis and reported it falsified because only 2 of 5,050 turns followed a **≥300s** gap — a threshold taken from the nominal 5-minute TTL, with the mass sitting just under it. Note also that the gap is measured response-timestamp to response-timestamp, which is *not* the write-to-next-request elapsed the TTL runs on: the cache entry for turn N is created when turn N starts generating, so true elapsed ≈ gap + turn N's generation time. **That caveat cuts both ways and was applied only one way here** — it was invoked to explain why a 60–300s gap might really exceed the TTL, and never to note that it equally inflates short gaps.

This is the same failure mode as this ADR's own falsifier rule, one level down: **a threshold set from a nominal figure rather than from the measured distribution.** The rule said to run the evaluating command; it did not say to check that the cut point falls where the data is.

**Could-be-wrong-if (residual re-writes are not TTL):** if they were TTL expiry, re-write mass should fall monotonically as inter-turn gap shrinks. It does not.

**Evaluated by**: `scripts/true-cost.py <run_dir> --breakdown`, gap histogram. Threshold: if the `<60s` bucket holds **≥30%** of re-write mass on a majority of runs, TTL is not the dominant mechanism and the residual needs the harness-side view, not more transcript analysis.

> **THIS FALSIFIER HAS FIRED.** Run backward against the existing corpus on 2026-08-12: **34%** on the ADR's own reference run, and a spread of 0%–100% across ten further run dirs that were already on disk (one at 51% on a 227K-token base). Fleet-wide the `<60s` bucket holds **25%**, and it is not a monotone decay — the ≥600s bucket holds 20%. TTL expiry is **not** the dominant mechanism for the residual. The next step is the harness-side view (breakpoint rotation, prefix mutation), which transcripts cannot show.
>
> It shipped on 2026-08-09 recording "`<60s` at 19%, below the bar — not yet met, and not evaluable at n=1." Both halves were wrong. The 19% came from the shrink-inflated formula; the "not evaluable" came from **not running the command backward against a corpus that already held the answer**, which is the precise discipline this ADR was written to introduce and restates twice in the lines above. `rtfm` extended n from 1 to 5 in under a minute, then to 11, commissioning nothing.

Do **not** commission runs for this. At ~5% of spend the residual is worth a note, not a budget — and it is now a *characterised* note rather than an open question.

## Deliberately not done

- **ADR-08 not demoted.** Its falsifier cannot fire (above), and the strongest counter-evidence is that the verifier executes repros on 71% of verdicts (`method: ran` 127/180) with similar refute rates across `ran` (6.3%) and `traced` (8.9%) — not the signature of a rubber stamp. The right next step is a **negative control** (plant 2 fabricated findings per 10 verified runs), not a demotion.
- **Multiball N unchanged.** Both overnight analyses argued for keeping N=3, but both computed their recall curves from `within_persona_runs` records written before 2026-08-02 — which ADR-12's own standing caveat disavows as LLM-transcribed. The conclusion rests on data the project has already declared unsupported. Re-run the curve once enough post-08-02 multiball snapshots exist.
- **Fable→Sonnet retier, leaf-dispatch context diet, execute-axis persona.** All need live runs and real token spend; queued for a session with cost sign-off.
