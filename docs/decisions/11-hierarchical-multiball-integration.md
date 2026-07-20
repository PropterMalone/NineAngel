# ADR-11: Hierarchical multiball integration + integrator stall mitigation

Date: 2026-07-19
Status: accepted (the user + Claude, designed live during the --full run)
Supersedes: ADR-04's model ladder *for big-bundle integrations only* (the bounded-dispatch rule itself stands and is strengthened here)

## Problem

The integrator stalls on big runs — repeatedly. Documented instances: 2026-06-09 meta run (7860s wall), 2026-06-10 diff run, 2026-07-19 --full (29 min mid-turn wedge, killed). the user's felt rate: "a majority of big integrator runs." Historical usage.log shows six runs with 50min–2.8h walls, consistent with stall-then-recover. The stall could not be *measured* because record-dispatch.sh wrote `started_at:null`/`ended_at:null`, so every finalize emitted `wall:0s`.

Root cause (2026-07-19 controlled comparison): the stall is **Fable-specific and turn-shape-specific**. Persona dispatches almost never stall (23/24 clean the same day) — they run short turns with ~2-3k-token outputs. The integrator is the opposite shape: one agent ingesting 20+ raw pass files (~80k tokens), long thinking turns, then monolithic 20-60k-token Write generations. Long turns maximize exposure to the Fable mid-turn API stall; the 07-19 instance died on a thinking turn with zero output after 4 minutes of healthy work. Same job re-dispatched on Opus delivered report.md in 155 seconds.

Compounding failure: the orchestrator's §5 "10-minute bound" was prose, not mechanism — the 07-19 stall ran 29 minutes because the orchestrator waited on a completion notification that never came (the CLAUDE.md "delivery-stall blind spot", verbatim).

## Decision

Five changes, the first being the structural one (the user's design):

### 1. Hierarchical integration (stage 1 → stage 2) under multiball

- **Stage 1 — per-persona reconcilers** (only when multiball N≥2): one small agent per persona, reading ONLY that persona's N pass files. `naive1 + naive2 + naive3 → naive′`. Runs integrator.md's Phase-1 rules (majority-promote / singleton-demote / contradictions / `(k/N)` tags), preserving **verbatim finding text** for surviving findings — union-with-attribution, not summary. Writes `reconciled/{persona}.md` + `reconciled/{persona}-passes.json` (that persona's structured `within_persona_runs` fragment). All reconcilers dispatch in parallel; model **Sonnet** (mechanical within-lane comparison — no discovery). Mandate: `reconciler.md`.
- **Stage 2 — cross-persona integrator**: consumes the ~10 compact reconciled views instead of 20+ raw passes. Phase 1 collapses to fragment assembly + structural validation; Phases 0/2/3/3.5 unchanged. Input drops ~60%; the giant-turn shape mostly disappears.
- Independence is preserved: stage 1 never crosses persona lanes (reconciliation happens only where independence was never claimed — within one persona's resamples); stage 2 remains the only place lanes meet.
- Failure isolation: a stage-1 stall costs one ~2-min retry; a stage-2 restart is cheap because stage-1 artifacts persist on disk.
- Single-pass (no-multiball) runs skip stage 1 entirely — unchanged.

### 2. Mechanical watchdog on stage 2 (and any lone load-bearing dispatch)

Dispatch-time, not prose: immediately after dispatching the integrator, arm a background `until [ -f "$RUN_DIR/report.md" ] || timeout` loop. Liveness tripwire: the integrator touches `$RUN_DIR/PROGRESS` per phase; PROGRESS mtime stale >5 min = wedged (kill + advance ladder) even inside the wall cap. Never rely on completion notifications alone. (07-19 validation: the watchdog fired seconds after the Opus retry delivered.)

### 3. Big-bundle integrations go Opus-first

For full-profile / --all runs or ≥20 multiball passes: stage-2 integrator dispatches on `claude-opus-4-8[1m]` FIRST (ladder: opus → inline). Fable stays rung 1 only for small diff-run integrations (≤8 passes), where its synthesis premium is cheap to retry. Rationale: at an observed majority stall rate on big Fable integrations, expected wall = bound + Opus-anyway; paying the Opus rung directly deletes the 10-30-min discovery cost. Revisit if stall telemetry (change 5) shows Fable clean for a month.

### 4. Resume-friendly retries

A killed integrator attempt's confirmed adjudications, PROGRESS state, and any partial artifacts get injected into the retry prompt as verified context so the retry doesn't re-read/re-probe the world. (07-19: this cut the Opus retry to ~6 min total.)

### 5. Fix the wall/stall telemetry

record-dispatch.sh now stamps `ended_at` (call time) and `started_at` (ended_at − duration_ms) instead of nulls, so aggregate wall times and stall rates become measurable. Stalled dispatches are logged with a `STALLED`/`KILLED` note (07-19 precedent) so `grep` can count them.

## Also changed

- `record-dispatch.sh` accepts phase `reconciler`; §3.4 schema enum extended.
- integrator.md: incremental-writes rule (report.md and findings-snapshot.json written in section-sized appends, never one monolithic generation) + PROGRESS touches. Applies in BOTH hierarchical and legacy modes.

## Falsifiers / revisit triggers

- If stage-1 reconciliation measurably degrades cross-persona dedup (stage-2 misses merges the flat integrator made — check via snapshot `personas` attribution regressions across runs), restore raw-pass input for stage 2 alongside reconciled views.
- If Opus-first big integrations stall at a comparable rate, the Fable-specificity theory is wrong — the fix is then turn-shape only (incremental writes + smaller inputs), and model choice reverts to ADR-04's quality ladder.
- If measured Fable integrator stall rate (change 5 makes it countable) is <10% over 10+ big runs, retire change 3.
