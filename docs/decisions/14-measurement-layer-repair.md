# ADR-14 — Measurement-layer repair, and a rule about falsifiers

**Date**: 2026-08-09
**Status**: accepted
**Supersedes**: nothing. **Amends**: ADR-08 (adds `severity_opinion` to the verdict schema), ADR-12 (adds `scale` to `usage.json`).

## Context

An overnight exploration ran eight independent analyses of NineAngel (four topics × Fable/Opus, identical briefs, `~/.angel/exploration/2026-08-09/`). The comparison is in `COMPARISON.md` there. Several findings converged across both models and survived first-party verification; this ADR records the batch shipped in response, and one rule that generalizes beyond this project.

Three things were settled empirically before any change was made:

1. **`usage.log`'s `total:` field is a context high-water mark, not spend.** Verified 8/8 against subagent transcripts: the recorded figure matches each pass's *peak single-turn context* to within 0.2%, against cumulative flows 18.8×–43.5× larger, with the ratio growing with turn count. Every per-token figure in ADR-01, ADR-06, and the Thousand demotion is a peak-context delta presented as a cost delta.
2. **Cost is dominated by cache traffic, not output.** Measured on a comparable 8-agent batch: cache writes 46% of cost from 8% of tokens, cache reads 40%, output 14%, uncached input 0.3%.
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

## Deliberately not done

- **ADR-08 not demoted.** Its falsifier cannot fire (above), and the strongest counter-evidence is that the verifier executes repros on 71% of verdicts (`method: ran` 127/180) with similar refute rates across `ran` (6.3%) and `traced` (8.9%) — not the signature of a rubber stamp. The right next step is a **negative control** (plant 2 fabricated findings per 10 verified runs), not a demotion.
- **Multiball N unchanged.** Both overnight analyses argued for keeping N=3, but both computed their recall curves from `within_persona_runs` records written before 2026-08-02 — which ADR-12's own standing caveat disavows as LLM-transcribed. The conclusion rests on data the project has already declared unsupported. Re-run the curve once enough post-08-02 multiball snapshots exist.
- **Fable→Sonnet retier, leaf-dispatch context diet, execute-axis persona.** All need live runs and real token spend; queued for a session with cost sign-off.
