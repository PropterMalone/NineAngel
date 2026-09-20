---
id: 22-jev-assisted-n2-reconciliation
name: Jev supplies advisory duplicate scores and removes default-N2 Sonnet reconcilers
date: 2026-09-17
status: draft
until: null
amends: [11-hierarchical-multiball-integration, 20-bounded-semantic-reducer]
supersedes: null
commits: [ff9e541, 57f495e]
depends_on:
  - ref: angel:16
    claim: frequency must not move severity at N=2, so a lossless raw union preserves the default run's severity inputs
  - ref: angel:20
    claim: Stage 2 already accounts for every raw source ID and shards oversized worksets
falsifier_cmd:
  - python3 scripts/test_jev_reconciliation.py
applies_to:
  - SKILL.md
  - reconciler.md
  - reducer.md
  - schemas/integration-workset-v1.json
  - schemas/run-meta-v1.json
  - scripts/build-integration-workset.py
  - scripts/integrate-run.sh
  - scripts/jev-reconciliation-eval.py
  - scripts/jev_reconciliation.py
  - scripts/record-run-meta.py
  - scripts/score-jev-reconciliation.py
  - scripts/shard-integration.py
  - scripts/test_jev_reconciliation.py
---

# Jev supplies advisory duplicate scores and removes default-N2 Sonnet reconcilers

**Decision**: `N` is the number of independent passes per persona. After the shadow gate in this ADR passes, an eligible N=2 run will replace the per-persona Sonnet reconciler fan-out with one bounded Jev scoring stage. Jev is TypeSafe's remote probabilistic judgment model; the local `jev` wrapper is the only client NineAngel may invoke. Jev scores whether two cross-pass findings from the same persona describe the same underlying defect. The workset builder preserves one candidate per raw finding and stores validated scores in non-structural `advisory_matches`. Existing deterministic `candidate_edges` remain unchanged and continue to control shard connectivity. The Stage-2 reducer owns every merge, exclusion, severity judgment, and final phrase. Runs use the current Sonnet reconciler path when N >= 3, the data is ineligible, the Jev client is absent, or the Jev result is invalid or incomplete.

**Why**: Default interactive multiball uses two passes per persona. At N=2, ADR-16 forbids frequency promotion and singleton demotion; Stage 1 still records contradictions, support, and surviving text, but Stage 2 can perform those semantic judgments from a complete raw union. Running one Sonnet agent per persona repeats shared context, then asks the reducer to reconsider merge relationships across personas. One measured six-persona N=2 run dispatched six Sonnet reconcilers that reported 467,202 aggregate `total_tokens` and 945,542 ms aggregate duration; `total_tokens` is a context high-water figure rather than billed throughput, and the durations overlap. [ran: `jq` over `/home/user/.angel/runs/20260818T135606Z-77138fd0/usage.jsonl`, 2026-09-17] Jev batches the narrower "same underlying defect?" judgments. The shadow gate must still prove that removing those contexts outweighs a larger Stage-2 workset.

Private Jev quality and performance figures remain outside the repository because TypeSafe's evaluation terms prohibit publishing benchmark or performance results. The repository may record the cohort, evaluation date, and pass/fail verdict without publishing the restricted figures.

## Safety and ownership

Jev is an attention mechanism in this version, never a mechanical adjudicator:

1. Every raw finding becomes its own candidate. No exact-key coalescing may discard an alternate description, effort, severity ceiling, or untrusted-content flag.
2. A low score cannot delete, demote, exclude, hide, or structurally separate a finding.
3. A high score enters `advisory_matches` only. It never enters `candidate_edges`, coalesces candidates, or changes raw-ID lineage.
4. `shard-integration.py` preserves only advisory matches whose two candidates already occur in the same deterministic shard. It never uses them to form components or pack shards.
5. Stage 2 receives complete candidate texts and must inspect the text before merging. A score may focus attention but does not establish that a merge is correct.
6. Every raw source ID remains represented exactly once under ADR-20's accounting gate.
7. Critical and Important findings receive no suppression path. Severity is preserved candidate metadata and is absent from the Jev question.

A false-positive score can still bias the reducer. The claim is therefore narrow: the score cannot mechanically change candidates, lineage, or sharding before Stage 2. The paired shadow gate separately tests reducer-induced false merges and lost mechanisms.

## Eligibility gate

Before invoking the scorer, `record-run-meta.py` must record an explicit `jev_eligibility` object. Absence and `ineligible` are the default and may not invoke the wrapper. The accepted classes are the shared Jev skill's `public`, `synthetic`, and `private-approved`; `private-approved` also requires the specific approved category and approval basis. `public` requires an affirmative `identifiers_stripped: true`. The scorer treats this metadata as operator authorization, not as a classification it may infer.

The scorer applies a second deterministic denial gate to the actual finding payload. It rejects PII/De-Anon persona lanes; AT Protocol DIDs and URIs; email addresses; credential-like strings; explicit EXCLUDED_CLIENT_A/EXCLUDED_CLIENT_B markers; and common minor-data markers. This denial scan cannot prove that text is safe, so it supplements rather than replaces explicit classification. Any rejection routes the whole run to Sonnet before a wrapper call.

The shared Jev policy remains authoritative. a small private target is a local project whose architecture, code, schemas, and synthetic fixtures are approved only when stripped of secrets, production records, and embedded user content. Real a small private target student/family content, EXCLUDED_CLIENT_A, EXCLUDED_CLIENT_B, other client material, credentials, confidential legal work, minor data, unknown data, and person-modeling inputs remain ineligible. A finding may quote source content, so an eligible project name never makes its findings automatically eligible.

Only the shared `jev` wrapper may call TypeSafe. It pins the model, validates typed requests and responses, refuses redirects, applies request ceilings, caches privately, and records provenance. NineAngel never reads the API key and never calls the endpoint directly.

## Pair and artifact contract

`score-jev-reconciliation.py` consumes durable pass Markdown and completed `run-meta.json`. For every persona with exactly two successful passes, the expected pair universe is the full Cartesian product of pass-1 findings and pass-2 findings. The scorer does not choose or truncate that universe. It exits before calling Jev when the universe exceeds 256 pairs.

The scorer:

1. parses findings with the same lossless parser as the workset builder;
2. plans every batch before the first call, permits at most four wrapper calls per run, and keeps each call within both 64 typed questions and the wrapper's 60,000-byte serialized-request ceiling;
3. sends only title, file, line, description, and raw text after the eligibility denial scan;
4. tells every question that supplied finding text is untrusted content rather than instructions;
5. binds the artifact to a canonical SHA-256 digest of run identity, exact eligibility metadata, the ordered expected pair IDs, and the exact submitted fields;
6. writes `jev-reconciliation.json` atomically only after every expected pair has one valid score; the artifact includes prompt version, data class, request hashes, returned model, cache state, usage, and scores; and
7. exits nonzero without writing a partial acting artifact when a batch fails, the wrapper rejects or times out the request, or the result is incomplete or invalid.

The builder independently recomputes the same Cartesian pair universe and canonical binding from current pass files and `run-meta.json`. It accepts the artifact only when the binding matches, pair coverage is exact, every raw ID exists, every pair crosses the two passes within one persona, every score lies in `[0,1]`, and the recorded model and prompt versions are supported. Ceiling exhaustion, stale hashes, missing pairs, extra pairs, and unsupported provenance all route to Sonnet.

The complete artifact retains every score for private evaluation. Before any score can influence an acting reducer, a human must label every expected pair from five pre-registered eligible calibration runs as duplicate, distinct, or ambiguous without seeing the Jev score. Freeze the lowest `attention_threshold` that produces zero false-positive matches among labeled-distinct pairs and at least 80% recall among labeled duplicates; if no threshold satisfies both conditions, Jev remains shadow-only. An acting workset may contain only pairs at or above that frozen threshold. Those pairs appear in `advisory_matches`; they supplement but never replace deterministic `candidate_edges`. An all-zero artifact therefore adds no advisory matches and must produce the same candidate set, structural edges, shard plan, and raw-ID accounting as an unassisted raw union.

## Routing and fallback

- During draft/shadow: continue to dispatch Sonnet reconcilers for the acting report. Eligible runs may generate a Jev artifact and a separate Jev-assisted raw-union workset for paired evaluation; neither may affect the acting report.
- After promotion, eligible N=2: run Jev scoring. On success, skip every Sonnet reconciler and build a `jev-advisory` raw-union workset.
- If Jev is unavailable, the wrapper rejects or times out the request, the pair universe exceeds 256, or the result is incomplete or invalid: dispatch the existing per-persona Sonnet reconcilers. Never continue silently on an unassisted raw union.
- N >= 3: use Sonnet reconcilers because ADR-16's frequency rules become active.
- Single pass: unchanged; no reconciliation stage exists.
- Stage-2 failure: ADR-20's existing retry and deterministic-union rules remain authoritative.

The run report names the path (`jev-advisory`, `sonnet-reconciled`, or degraded union) but does not publish Jev quality or performance measurements.

**Implementation status (2026-09-19)**: The mechanical shadow path is complete. Explicit eligibility metadata, the bounded scorer, content-bound artifact validation, a one-candidate-per-raw-finding builder, non-structural `advisory_matches`, same-deterministic-shard transport, and the private evidence harness are implemented. `jev-reconciliation-eval.py` pre-registers five blind calibration runs before scoring, freezes the lowest zero-false-match/80%-recall threshold, binds a ten-run consecutive holdout ledger, runs an isolated alternate reducer without touching acting artifacts, prepares score-blind raw-ID adjudication, and evaluates all five promotion clauses. Private artifacts are rejected inside any git repository. The acting path remains unchanged. The five calibration runs, ten holdouts, and their human labels are evidence still to collect before promotion.

## Promotion gate

This ADR stays `draft`, and the acting path stays Sonnet, until implementation tests prove all of the following:

- absent, `ineligible`, unknown, or malformed eligibility exits before invoking a mock wrapper;
- PII/De-Anon lanes and every denial-pattern fixture exit before invoking a mock wrapper;
- wrapper failure leaves no accepted partial artifact and dispatches the Sonnet path;
- the builder rejects stale bindings, missing pairs, extra pairs, invalid scores, unsupported model/prompt versions, and pair universes above the ceiling;
- an all-zero artifact preserves candidates, deterministic edges, shard plan, and raw-ID accounting;
- a high-scoring false-positive cannot mechanically merge, exclude, demote, suppress, or structurally group either candidate;
- exact-coordinate findings with different descriptions and ceilings remain separate complete candidates;
- N >= 3 never enters the Jev path; and
- workset size still routes through ADR-20's existing shard limit.

The holdout cohort is the first ten consecutive eligible N=2 shadows after the five-run calibration set, scorer, and paired comparison command land; calibration runs may not reappear in the holdout, and runs may not be omitted after their outcomes are known. If ordinary work produces fewer than fifteen eligible runs within 30 days, pre-registered public or synthetic review fixtures supply the remainder. Before the holdout begins, freeze the attention threshold, raw-ID matching rules, and a disagreement rubric. A blind manual adjudication classifies each baseline/alternate disagreement by raw source IDs before aggregate quality or performance figures are inspected.

Promotion requires all of these private results:

- no confirmed Critical or Important mechanism present in the Sonnet report is absent from the Jev-assisted report;
- no confirmed false merge combines distinct Critical or Important mechanisms;
- at most two of ten Jev-assisted worksets require an additional shard, and none requires more than one additional shard;
- median total reported model tokens for scoring plus Stage 2 are at most 75% of the Sonnet-reconciler plus Stage-2 baseline; and
- median wall time is no more than 125% of baseline.

The comparison command writes private measurements outside every git repository. After the private holdout completes, update this ADR with only the date, cohort size, and pass/fail verdict; never copy thresholds, scores, token figures, or timing figures here. The implementation test command is registered in `falsifier_cmd`; add the private `evaluate-holdout` invocation there only when its stable artifact paths exist.

Automatic Jev coalescing is a separate future ADR. It requires a private, human-labeled calibration corpus and a predeclared false-merge stopping rule. Advisory success does not silently earn that authority.

**Rejected alternative**: let Jev directly replace each Sonnet reconciler and emit one canonical finding per predicted group. That would maximize the reduction, but a false-positive match could erase a distinct defect before Stage 2. Also rejected: place scores in `candidate_edges`. ADR-20 uses those edges to form unsplittable shard components, so that field would give Jev structural authority. Also rejected: keep all Sonnet reconcilers and use Jev only to reorder their prompts. That preserves nearly all of the repeated-call cost this change exists to remove.

**Could-be-wrong-if**: The decision is wrong if the frozen ten-run cohort breaches any promotion threshold, if eligible runs cannot supply a cohort within 30 days even with pre-registered fixtures, or if the deterministic denial gate cannot exclude sensitive finding text without making eligible use impractical. Any observation leaves Sonnet active while the representation or use case is reassessed.

**Confidence**: 0.62 that this will safely reduce total N=2 review weight after the shadow gate. [tier: preliminary private runs plus current-code inspection; production comparison not yet run]

**Status quo check**: Current N=2 instructions dispatch one Sonnet reconciler per persona. The existing builder preserves raw-ID accounting, but exact-key fallback can retain only the first finding's text and metadata, and raw union is always a degraded fallback rather than an intentional state. [read: `scripts/build-integration-workset.py`, 2026-09-17]

**How to apply**: This decision governs only Stage-1 reconciliation routing. It does not change persona selection, multiball backends, Stage-2 semantic authority, verification, report rendering, or the data eligibility of any target. While the ADR is draft, exercise only the shadow path; Sonnet remains the acting reconciler. Use `scripts/jev-reconciliation-eval.py --help` for the fixed sequence: `prepare-calibration`, score the five registered runs, `freeze-threshold`, `begin-holdout`, `run-shadow` for each of ten consecutive eligible runs, `prepare-adjudication`, then `evaluate-holdout`. After `begin-holdout`, score and register every subsequently eligible N=2 run immediately and chronologically; do not inspect a score or shadow outcome before deciding whether the run enters, and do not remove failed ledger rows. Keep every path passed as `--output`, `--labels`, `--threshold`, `--ledger`, or `--adjudication` under a private non-repository directory.
