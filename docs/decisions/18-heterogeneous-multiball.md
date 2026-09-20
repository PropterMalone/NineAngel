# ADR-18 — Heterogeneous multiball: pass 1 Claude, pass 2 Codex

**Status:** Adopted as the default for interactive runs, 2026-08-22 (the user). Time-boxed —
revisit ~2026-09-22.

> **Amended by ADR-19's review, 2026-08-26 — this ADR's falsifier was uncomputable and now is not.**
> Both registered metrics (Codex-only union share, and corroboration share) are denominated in
> per-finding backend provenance, and no such field existed: the integrator credits a codex pass to
> the base persona name, so **0 of 8,689 persona attributions across the whole corpus carried codex
> provenance.** The trial was running with no numerator — the ADR-14 failure mode ("denominated in a
> log field the log did not carry"), inside the trial it was meant to score. Fixed at the writer
> (`record-dispatch.sh` emits `backend=` in the pass marker), the assembler (`assemble-wpr.py` emits
> per-finding `backend_support`), and the consumer. **First real datapoint, run
> `20260826T153123Z-ca7d099c`: 18 Important+, union share 16.7% (3 Codex-only), corroboration 33.3%
> (6 found by both).** Union sits just above this ADR's ~15% failure bar on a single run — one run
> decides nothing, but the metric is live. Note the trial window is partitioned at 2026-08-26 per
> ADR-19: runs before it have no usable provenance and cannot be scored on either axis.

**Supersedes for the default case:** the homogeneous N=2 multiball of ADR-06. ADR-06's N
selection is unchanged; what changes is *which model runs each pass*.

## Decision

For interactive `/angel` runs, multiball's two passes come from **different model
families**: pass 1 on the persona's table-assigned Claude tier, pass 2 through ADR-17's
codex leg (`dispatch-leg.sh`).
the user, 2026-08-22: *"multiball 1: claude, multiball 2: codex … that should be generally how
Angel runs for the next month."*

## Why

ADR-06 justified N=2 on the marginal-value prior: a second independent pass catches the
first pass's stochastic misses. That is true, but it buys the *weakest* kind of
independence — two Claude passes resample one model's judgment and share its blind spots
exactly. The skill already concedes this in §5.6: *"model-independence is the one axis the
same-model battery (personas + multiball all share Claude's blind spots) structurally
cannot cover."*

The insight is that multiball and the cross leg were solving overlapping problems with
separate budgets. Making pass 2 a different model collapses them: the same N=2 cost now
buys cross-model diversity *inside every persona lane*, rather than one bolted-on cross
pass over the integrated report at the end.

Secondary, and the reason it is affordable now: Codex capacity is separately metered from
the Claude subscription (ADR-17), so pass 2 spends a budget that would otherwise idle.

## What this does NOT change

- **N stays 2** (3 on `--full`/`--all`, per ADR-06). If N=3, pass 3 is Claude again.
- **Persona independence is untouched.** Heterogeneity applies only to within-persona
  resamples, where independence was never claimed anyway.
- **The §5.6 cross leg still runs.** It reviews the *integrated report*, which is a
  different object from a persona pass. Do not drop it as redundant — that was considered
  and rejected: refuting Angel's synthesis is not the same act as independently finding
  what Angel's lane missed.
- **Unattended (`claude -p`) stays single-pass Claude.** Shelling to another CLI from a
  cron path is a new unattended failure mode for no measured gain.

## Mechanics — use `dispatch-leg.sh`, the mechanism already exists

**ADR-17 (2026-08-18) already built this**: a headless codex-backend leg adapter, backend
-partitioned metering, and token-kind determination. This ADR adds only the POLICY of
making that leg multiball's second pass by default. It does not invent a mechanism, and a
hand-rolled `codex exec < prompt` is the wrong way to do it — it bypasses the ADR-12
single-writer chokepoint and loses pass-file writing, backend partitioning, the
requested/ran model record, and the garbage-output failure path.

Compose the persona prompt ONCE (the §4 shared-prefix template, persona-by-path), write it
to `$RUN_DIR/prompt-{persona}.md`, then:

```
~/.claude/skills/angel/scripts/dispatch-leg.sh \
  --run-dir "$RUN_DIR" --phase persona --name {persona} --model gpt-5.6-sol --pass 2 \
  < "$RUN_DIR/prompt-{persona}.md"
```

`--model` takes a **model id**, not a backend name — `dispatch-leg.sh:85` passes it
straight to `codex exec -m`, and `:171` compares it against the model the rollout reports
actually ran. This ADR shipped saying `--model codex`, which is neither: it was copied
literally at least once, and that leg sits in the run record as `"model":"codex"` against
126 legs correctly recorded as `gpt-5.6-sol`. Use the id configured in `~/.codex/config.toml`
(`gpt-5.6-sol` today; `gpt-5.6-terra` also appears in the record). Say "the codex backend"
in prose, never in the flag.

The prompt filename is per-persona for the same reason: a full battery fires ~13 personas
against one `$RUN_DIR`, so a shared `$RUN_DIR/prompt.md` is a write race in which the last
writer decides what every leg reviews. Flat file, no subdirectory — `dispatch-leg.sh`
creates `$RUN_DIR/tmp` itself, so the orchestrator cannot assume a directory exists ahead
of it.

It delegates all durable bookkeeping to `record-dispatch.sh`, so pass files, the
`usage.jsonl` line (with `backend: codex`), and the failure stub all land on contract
without special-casing. Codex has filesystem access, so dispatch-by-path works: it reads
its own persona file and the diff.

Consequence for reconciliation: the Stage-1 reconciler now merges ACROSS MODELS. **A
finding present in only one pass is no longer just a stochastic singleton — it may be a
model-specific catch, which is the entire point.** Reconcilers should surface which model
found what rather than treating 1-of-2 as weak corroboration. This is the one place ADR-16's
reconciliation thresholds may need re-tuning under heterogeneity; leaving them as-is for the
trial and watching whether Codex-only findings get suppressed as low-consensus.

## The Phase-A/Phase-B stagger does not apply

ADR-06's cache-priming stagger exists so passes 2..N read a warm Claude prompt cache. A
Codex pass shares no cache with a Claude pass, so **dispatch both concurrently** — the
serialization would cost wall-clock and buy nothing.

## Falsifier — SCORE BOTH GOODS, not just union

The obvious bet is that cross-model passes produce more *union* findings (things pass 1
missed) than same-model passes at equal N. That was this ADR's original and only falsifier:
Codex-only share of Important+ under ~15% means it is buying noise.

**The first run's result says that metric alone would retire the practice wrongly.**

Run `20260822T190008Z-006ea55b` (data-int on a new Reverb adapter, 2026-08-22):

| | Critical | Important | Codex-only Important+ |
|---|---|---|---|
| Claude (Fable, pass 1) | 1 | 5 | — |
| Codex (pass 2) | 1 | 3 | **0** |

Union was 6 Important+; Claude found all 6, Codex found 4, and **every Codex finding was
also a Claude finding**. On the union metric that is 0% — a clean failure.

But union was the wrong good to measure alone. What the Codex pass actually delivered:

- **Independent cross-model corroboration of the Critical.** Two models, different training,
  each probing the live API separately, converging on the same defect and the same fix. §5.7
  exists because corroboration-vs-causation is what makes a finding actionable; a
  cross-model CONFIRMED Critical is materially stronger evidence than a Claude-only one, and
  it arrived without spending the verification stage.
- **Distinct evidence for shared findings.** Codex sampled 74 listings and quantified the
  population (52 offers-enabled, 23 carrier-calculated); Claude probed fewer listings but
  traced further into consumers. Same findings, complementary support.

So the revised falsifier scores TWO metrics over the trial month, and heterogeneity has to
fail BOTH to revert:

1. **Union** — Codex-only share of Important+ findings. Under ~15% is a failure on this axis.
2. **Corroboration** — share of Claude's Critical/Important findings that the Codex pass
   independently reproduces. If this stays HIGH (say >50%), the second pass is buying
   confirmation even when it buys no new findings, and that is worth the seat. If it is
   *also* low, the passes are neither agreeing nor complementing, and heterogeneity is
   simply noise — revert to ADR-06.

Recording the reasoning error explicitly because it is the more reusable lesson: a falsifier
that measures one of a practice's two goods will retire the practice for failing a test it
was never aimed at.

The format-drift counter-risk stands and is so far unrealized: the first Codex pass returned
a fully format-conformant block needing no manual extraction. Keep tracking how often a
`.raw` needs hand-massaging.
