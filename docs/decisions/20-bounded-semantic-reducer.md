# ADR-20 — NineAngel integration as a bounded semantic reducer

**Date:** 2026-08-30
**Status:** active
**Decision:** ADR-20
**Extends:** ADR-11 (hierarchical integration), ADR-12 (mechanical per-pass capture), ADR-13 (output parity)
**Partially supersedes:** ADR-04's agent-integrator route; ADR-09's micro inline-integration rule; ADR-11/19's inline terminal fallback and 1M-window assumption; ADR-13's prose-only inline parity mechanism

## Decision

Move integration into a measured-low-context, capability-restricted semantic reducer process that does not inherit the NineAngel driver conversation, project instructions, project memory, or project source. The Codex CLI may still supply its own fixed runtime instructions; qualification therefore measures the completed turn's cumulative input instead of claiming an empty initial context. The reducer consumes a mechanically derived finding workset and emits only validated semantic decisions; scripts own provenance, counts, verdict calculation, verification selection, report rendering, and snapshot assembly.

The LLM remains responsible for the part that is actually semantic: deciding which findings describe the same defect, choosing the sharpest source wording, applying judgment-based calibration, ranking the final findings, and expressing causal claims. It stops being the parser, bookkeeper, renderer, and recovery orchestrator.

**Implementation record (2026-08-30; amended 2026-09-20):** the reducer-era acting path, schemas, strict lineage validator, deterministic renderer, bounded two-level sharder, visible union fallback, qualified runner probe, resume/retry/clone recovery, and completeness integration are implemented. Both frozen worksets replay mechanically with the final schema: Fixture B is ~20.1k estimated tokens; Fixture A is ~35.0k and packs into three ≤16k-target shards (~14.4k/~15.0k/~5.4k). The active runner uses the exact supported Codex CLI release with saved **Sign in with ChatGPT** authentication and the subscription allowance. The child receives only an explicit auth/TLS/proxy environment allowlist; runs ephemerally with strict configuration, user/project configuration and rules ignored; and disables hosted web search plus local command/filesystem/browser/MCP/plugin/delegation hosts before inference. The semantic mandate is a developer instruction, while nonce-delimited, delimiter-escaped workset JSON is separate untrusted user data. Emitted item events are checked afterward as a detection guard: an attempted Code Mode call produces one recognized fail-closed error because its host is disabled; it is counted separately, while any executable tool event rejects the result. Qualification is bound to the trusted-code fingerprint and the Codex binary's trusted path, exact version, file identity, and SHA-256 content digest. Signal masking closes the child-handle race during process creation; hosts without that primitive are unqualified. The live hostile probe completed at 12,081 cumulative input tokens with zero executable tool events. A clone replay of `20260907T175648Z-90142242` reduced 40 candidates to 27 validated findings plus 5 exclusions, selected 8 verification targets, and reduced report bytes 20,768→9,123 while passing completeness. A real oversized clone replay of `20260915T234628Z-d56caa75` exercised two shards plus final reconciliation: 95 candidates became 60 validated findings plus 7 exclusions, with 8 verification targets and report bytes reduced 49,784→19,814. Its three first-attempt ChatGPT-authenticated turns used 112,165 tokens over 650 seconds, emitted zero executable tool events, and recorded three recognized blocked Code Mode attempts; completeness passed and the source run was unchanged. JSON-native reviewer outputs remain a separate architecture change.

## Why this is needed now

The integration leg is near its context limit even when the review corpus itself is modest.

The 2026-08-29 `a private target` run (`20260829T000259Z-49c4c1ae`) is the cleanest measured example:

- The Opus integrator's **first request created 100,675 tokens of context before it read a finding**. That was harness, project, skill-catalog, and other inherited context.
- It peaked at **188,855 tokens**, used 23 tools, and took 582.7 seconds.
- Stage 1 had been skipped, so the prompt told Stage 2 to read and reconcile 14 raw pass files itself.
- The raw pass files contained 44,855 bytes (about 44 KiB; the earlier 72 KiB figure was block-allocated disk usage). The semantic workload was not intrinsically a 189k-token problem.

The 2026-08-30 `a private target` run (`20260830T143153Z-46bea721`) shows the useful reduction already available:

- 109 findings reported by the legacy parser (113 structural records in the lossless walk)
- 41 findings after per-persona reconciliation
- 23 final cross-persona findings

The legacy parser's 109 count includes 50 mechanically identifiable non-findings: 26 bulleted empty markers plus 24 bullets under `### File summaries` across the two Naive passes. It also omits four bare empty markers. A separate lossless raw-section walk therefore observes 113 structural records, records 30 canonical empty markers plus 24 file-summary bullets as 54 explicit discards, and retains 59 finding records before reconciliation. Fixture A similarly changes from 102 legacy rows to 117 structural records, 18 discards, and 99 retained findings. These figures were re-derived from the immutable fixture pass files during implementation. The design does not depend on “41 candidates”; it depends on removing harness scaffolding, recording rather than hiding mechanical discards, and sharding any remaining oversized workset.

There is also live contract drift:

- `integrator.md` Phase 1 says **do not** assemble or write `within_persona_runs`; `assemble-wpr.py` owns it.
- The snapshot rules later say to emit it.
- `SKILL.md` still tells the hierarchical integrator to read `*-passes.json` fragments and assemble the field.

The script overwrites that work at finalize. The model is being instructed to spend context producing a representation whose canonical producer is already mechanical.

## Goals

1. Keep reducer input mechanically bounded: target ≤16k estimated workset tokens and enforce a 24k workset hard cap, a ≤20k cumulative-turn-input admission check on the tiny probe, and explicit accepted-output ceilings. The original **60k** target and **80k** peak ceiling remain planning targets; current Codex telemetry does not expose direct peak context, so the implementation does not fabricate that measurement.
2. Keep the model input independent of NineAngel's driver conversation, project instructions, project memory, and project source. Codex's own runtime instructions and the host's cached ChatGPT authentication are explicitly outside that claim.
3. Account for every raw structural record: retain it through candidate lineage or record its mechanical discard—with source ID, section, rule, and verbatim text—before semantic integration.
4. Produce `report.md` and `findings-snapshot.json` from one canonical decision record so their counts, verdict, IDs, effort totals, and verification queue cannot diverge.
5. Keep Markdown persona outputs as the durable source of truth, per ADR-12. Structured integration input is derived mechanically; reviewers do not hand-transcribe a second JSON representation.
6. Retain NineAngel's semantic behavior: cross-persona dedup, severity ceilings, tier-divergence treatment, contradiction preservation, loop annotations, verification claims, and registry updates.
7. Fail usefully. A dead semantic reducer may reduce integration quality, but must not consume the driver context, lose raw findings, or prevent a readable report.

## Non-goals

- Changing persona selection, multiball N, heterogeneous pass routing, or reviewer prompts.
- Re-reviewing project source during integration. The prohibition is enforced by removing model-callable filesystem and command tools, using an isolated temporary workspace containing only the schema/output target, and ignoring user/project rules and configuration—not by prompt convention.
- Making fuzzy matching authoritative for correctness. Candidate edges are suggestions to the reducer, never automatic merge decisions.
- Replacing ADR-12's durable Markdown capture with an LLM-authored JSON tail.
- Moving verification into integration. Verifiers remain separate and adversarial.
- Optimizing reviewer-leg context. This design is specifically for reconciliation and integration.

## Invariants

These are implementation gates, not prose preferences.

1. **Stage 2 never reads raw pass files.** It reads one derived workset.
2. **The Stage-2 model never reads project source or credentials.** The trusted Codex host process may read its cached ChatGPT login, but hosted web search and local tool hosts are disabled before inference and executable tool events are rejected. Its cwd is an isolated temporary workspace containing only the schema/output target; the workset is supplied as untrusted user data under a separately privileged mandate. The only accepted tool-related event is the exact fail-closed Code Mode-host-disabled error.
3. **No integration call inherits NineAngel harness context.** Every reducer starts as a fresh ephemeral process with user configuration and project rules ignored; runner admission proves ≤20k cumulative input tokens on the tiny probe. Codex's fixed runtime instructions are included in that measurement. A fresh sidechain alone does not satisfy this invariant.
4. **The reducer never writes the report or snapshot.** It writes `integration-decisions.json` only.
5. **Every candidate is accounted for exactly once as a primary source:** included in one final finding's `source_candidate_ids`, or placed in `excluded_candidates` with an allowed reason and explanation. Contradiction/tier-divergence records may non-exclusively cite candidates through `derived_from_candidate_ids`.
6. **No LLM writes `within_persona_runs`, `pass_support`, or `backend_support`.** `assemble-wpr.py` remains their producer, consuming reducer-era raw lineage from the workset rather than re-enumerating Markdown in a second ordinal space.
7. **The renderer owns all derived fields:** IDs, counts, effort rollup, verdict, Top-5 shape, queue cap/order, resource table, and report/snapshot parity.
8. **No inline semantic fallback in the driver.** Two isolated reducer attempts may fail; the terminal fallback is a deterministic union report marked `integration_degraded`.
9. **The workset has a hard size budget.** Oversized worksets shard before dispatch; the reducer cannot elect to “try the big prompt anyway.”

## Proposed pipeline

```text
durable reviewer Markdown
        │
        ├─ multiball ─→ per-persona Reconcilers ─→ reconciled/*.md
        │                         │
        │                         └─ missing/failed view → mechanical union fallback
        │
        └─ single pass ───────────────────────────→ findings/*.md
                                  │
                                  ▼
                    build-integration-workset.py
                    parse · normalize · candidate edges
                                  │
                         integration-workset.json
                                  │
                                  ▼
                 fresh bounded semantic reducer process
                 merge · calibrate · rank · phrase claims
                                  │
                      integration-decisions.json
                                  │
                                  ▼
                       render-integration.py
                  validate lineage · derive · render
                         │                    │
                         ▼                    ▼
                     report.md     findings-snapshot.json
                                              │
                                              ▼
                    finalize-run.sh / assemble-wpr.py
                    pass support · backend support · WPR
```

## Stage 1: reconciliation becomes mandatory input reduction

ADR-11 already defines per-persona reconciliation as the normal multiball path. The remaining raw-pass escape hatch defeats its main benefit.

### Normal path

For every selected persona in a multiball run, Stage 1 must produce `reconciled/{persona}.md`. Stage 2 starts only when every persona is in one of three explicit states:

- `reconciled`: the view exists and parses;
- `failed-pass-degraded`: one or more pass failures were mechanically recorded and the surviving passes were reconciled;
- `union-fallback`: the reconciler failed twice, so the workset builder mechanically preserved the union of that persona's parseable raw findings.

### Mechanical union fallback

The terminal response to a failed reconciler is not “give all raw passes to Stage 2.” `build-integration-workset.py` parses only that persona's pass files and creates one candidate per raw finding, conservatively coalescing only exact normalized file + line + title matches.

- Severity stays at the highest raw severity among exact matches.
- No singleton demotion occurs.
- Frequency promotion may occur only for an exact match at **N ≥ 3** with a true majority, `k ≥ ceil((N+1)/2)`; N=2 never promotes. Singleton demotion remains disabled unless `N ≥ 5`. These are ADR-16's reconciliation thresholds; the separate flat `k ≥ 2` rule is for Critical anchoring, not promotion.
- Ambiguous near-duplicates remain separate candidates for Stage 2.
- The workset records `reconciliation_status: union-fallback` and the report surfaces it in Integration Notes.

This can increase Stage-2 candidate count for one persona, but it cannot silently discard signal and it bounds failure to that persona.

### Single-pass runs

Single-pass and unattended runs skip the reconciler as today. The workset builder reads `findings/*.md` and emits the same candidate schema, with `pass_support: null` until finalization.

## Stage 2 input: `integration-workset.json`

`build-integration-workset.py` is deterministic. It requires `run-meta.json`, selected reconciliation views, `usage.jsonl`, and multiball pass files. `init-run.sh` creates `run-meta.json` with the reducer-era discriminator and immutable project/date/mode fields; `record-run-meta.py` atomically adds preflight, reader mode, selected/dropped/failed personas, files reviewed, codebase size, pass denominators, and loop metadata before integration. Missing required metadata is loud. Historical replay alone may use an explicit adapter that writes `unknown` values and records their provenance; acting runs may not infer them from the pipeline's own snapshot.

In multiball mode the builder ignores `findings/*.md` so pass 1 is not counted twice. It performs the sole reducer-era raw Markdown enumeration, assigns raw IDs before any discard, and associates retained raw records to reconciled candidates using a strict matcher. The matcher requires a bounded line distance and title-overlap floor, has no alphabetical/same-file force-bind, and returns `unmatched` when confidence is insufficient. `assemble-wpr.py` later consumes this persisted mapping; it does not repeat the match. It emits:

```json
{
  "version": 1,
  "run": {
    "integration_pipeline": "semantic-reducer-v1",
    "run_dir": "/abs/path",
    "project": "example",
    "date": "2026-08-30",
    "mode": "diff",
    "reader_mode": "off",
    "files_reviewed": 12,
    "preflight": {"test": "pass", "build": "pass", "lint": "skipped"},
    "multiball": 2,
    "pass_denominators": {"adv": 2, "test": 2},
    "personas_run": ["adv", "test"],
    "personas_dropped": [],
    "personas_failed": [],
    "codebase": {"files": 12, "lines": 1800}
  },
  "candidates": [
    {
      "id": "c_adv_001",
      "persona": "adv",
      "severity": "important",
      "title": "Timeout does not stop the underlying operation",
      "effort": "moderate",
      "file": "src/example.ts",
      "line": "42-47",
      "description": "Full preserved finding description.",
      "raw_text": "The original reconciled Markdown bullet.",
      "raw_source_ids": ["adv-p1:r2"],
      "support_passes": ["adv-p1"],
      "support_tag": [1, 2],
      "support_drift": null,
      "severity_ceiling": {"state": "none", "value": null, "policy": null},
      "reconciliation_status": "reconciled"
    }
  ],
  "candidate_edges": [
    {
      "left": "c_adv_001",
      "right": "c_test_003",
      "reasons": ["same-file", "line-distance<=2", "title-overlap=0.71"]
    }
  ],
  "noise_floor_discards": [
    {
      "raw_source_id": "adv-p1:r1",
      "source_file": "adv-p1.md",
      "ordinal": 1,
      "section": "Critical",
      "rule": "canonical-empty-marker",
      "raw_text": "- None."
    }
  ],
  "previous_cycle": null
}
```

In loop mode, the builder receives `--previous-run-dir <dir>` explicitly. `previous_cycle` is a compact projection of that run's snapshot (`id`, severity, title, file, line, summary), not the previous Markdown report and never its `within_persona_runs`.

### Parser extension

The existing `parse_findings()` API remains byte-for-byte stable because it is already on the capture and completeness gates. A new additive `parse_findings_lossless()` performs its own raw-Markdown section walk and grows the fields needed by integration:

- `raw_text`
- `description`
- `effort`
- `(k/N)` support tag when reading a reconciled view
- raw section path and record ordinal
- severity-ceiling state (`none|detected|unparsed`), value, and policy source

Golden tests over both replay corpora pin every legacy `parse_findings()` record before and after this addition. A second checked-in golden pins the intentional legacy→lossless difference, so changing the noise floor cannot masquerade as parser cleanup. The lossless parser still does not invent `evidence`; evidence classification remains semantic.

The raw-section walk assigns `raw_source_id = <exact-file-stem>:r<structural-record-ordinal>` **before** disposition. It then applies only two non-overlapping mechanical rules:

1. A bullet whose complete payload, after Markdown emphasis removal, is exactly `None.` or `No findings.` is `canonical-empty-marker` even when it appears under a severity heading.
2. A bullet whose nearest active section is an explicitly recognized non-severity section (including `File summaries`, `Per-file summary`, `Verification`, `Cap overflow`, `Contradictions`, or `Reconciler notes`) is `non-finding-section`. Entering such a section clears the active severity; no file/path/title heuristic is allowed.

Every such record goes to `noise_floor_discards`; nothing vanishes. All other bullets under a severity heading are retained, including coordinate-less Noted observations. A discard carrying a parsed `file:line` is a validation error. Fixture B's checked-in golden contains exactly its re-derived 54 discards. A non-empty file with no recognizable severity structure records a per-persona builder diagnostic; an unparseable reconciled view routes that persona to union fallback over its parse-gated pass files rather than aborting the run.

Retained records keep those pre-disposition IDs, preventing both canonical-persona alias collisions and legacy/lossless ordinal drift. `raw_source_ids` are the sole support provenance. `support_passes` is the set of pass stems derived from those IDs; `support_tag` is displayed provenance only and is never authoritative for thresholds. If the reconciler's `(k/N)` tag disagrees with the raw-ID set, the workset carries both plus a `support_drift` note. `reducer.md` explicitly says every threshold uses the raw-ID recompute. Final snapshot `pass_support` and `backend_support` remain owned and re-injected by `assemble-wpr.py`, which joins raw ID → candidate ID → final finding ID from persisted reducer-era artifacts.

Any parseable raw finding that matches no reconciled candidate is not dropped. The builder adds a candidate with `reconciliation_status: recovered-unmatched`. A false-negative match may therefore create a duplicate for Stage 2 to merge, but cannot erase the raw signal. The workset validator requires every raw source ID to belong to exactly one candidate or exactly one `noise_floor_discards` row; no ID may occur in both.

### Candidate IDs

Candidate IDs are deterministic within a run: canonical persona plus zero-padded ordinal in the parsed reconciled view. They are lineage identifiers, not cross-run finding IDs. The renderer assigns final `f1`, `f2`, … IDs after integration.

### Candidate edges

The builder proposes possible-duplicate edges using the existing `finding_match.py` primitives plus line distance:

1. Same normalized file and line distance ≤2.
2. Same normalized file and title overlap above the configured threshold.
3. Coordinate-less findings with high title overlap.

An edge means “compare these together,” not “merge these.” False-positive edges cost reducer attention but cannot corrupt the report automatically. False-negative edges are mitigated because the reducer receives the whole budget-qualified workset, and the sharded path includes a final compact cross-shard pass. This is an attention assumption to measure, not a guarantee from context fit; replay compares known merge groups.

### Untrusted finding text

Candidate titles, descriptions, and raw text descend from project content and remain untrusted data. The builder flags spans matching a versioned, tested set of imperative/prompt-override forms but does not delete plausible finding content. `reducer.md` carries the existing Phase-0 rule in compact form. The qualification workset includes instruction-shaped content, while the runner disables local/remote tool hosts, records the recognized fail-closed Code Mode refusal, and rejects any executable tool event before accepting output.

## Stage 2 output: `integration-decisions.json`

The reducer writes only semantic decisions:

```json
{
  "version": 1,
  "producer": "reducer",
  "degraded_reason": null,
  "findings": [
    {
      "decision_id": "d1",
      "source_candidate_ids": ["c_adv_001", "c_test_003"],
      "canonical_source_id": "c_test_003",
      "title": "Timeout does not stop the underlying operation",
      "summary": "The deadline rejects the waiter while the operation continues mutating state.",
      "severity": "important",
      "severity_reason": "highest source severity; no calibration override",
      "effort": "moderate",
      "evidence": "code-site",
      "priority_rank": 1,
      "loop_status": null,
      "previous_finding_id": null,
      "consistency_shaped": false,
      "causal_claim": "The timed-out operation continues after the caller advances.",
      "repro_hint": "Observe whether the operation performs work after the timeout result is returned."
    }
  ],
  "excluded_candidates": [],
  "derived_records": [
    {
      "kind": "tier-divergence",
      "derived_from_candidate_ids": ["c_adv_001"],
      "title": "Severity disagreement: timeout behavior",
      "summary": "A source assessed this at a lower tier."
    }
  ],
  "integration_notes": [],
  "registry_updates": [
    {
      "field": "session_token",
      "kind": "direct-identifier",
      "why": "Reusable identifier pattern",
      "source": "pii",
      "severity": "high",
      "status": "candidate",
      "source_candidate_ids": ["c_adv_001"]
    }
  ]
}
```

`producer` is the enum `reducer|deterministic-union`; `degraded_reason` is null for reducer output and a fixed failure-reason enum for union output. Snapshot degradation fields are mechanically derived from those values, and `decision_schema_version` must equal this file's `version`. The reducer may choose the sharpest source and rewrite the final summary, but it may not add a finding with no source candidate.

Allowed exclusion reasons are deliberately narrow:

- `instruction-shaped-content-redacted`
- `malformed-nonfinding`
- `non-defect-observation`
- `explicitly-withdrawn-by-reconciler`

“Duplicate” is not an exclusion: duplicate candidates belong together in one final finding's `source_candidate_ids`. Severity demotion is not exclusion either; the finding remains present at its calibrated tier.

Every exclusion is retained in snapshot `excluded_candidates`. Non-trivial exclusions (`instruction-shaped-content-redacted` and `malformed-nonfinding`) are also listed by candidate ID/title/reason above the fold in a `**Coverage exclusions**` report banner; ordinary non-defect observations may be summarized by count in Integration Notes.

## Semantic versus mechanical ownership

| Concern | Owner | Reason |
|---|---|---|
| Markdown parsing | script | Deterministic transcription already exists |
| Stage-1 fallback union | script | Signal-preserving recovery, no judgment needed for exact matches |
| Candidate-edge generation | script | Suggestion only; cheap and reproducible |
| Same-defect decision | reducer | “Same class of problem” is semantic |
| Sharpest source wording | reducer | Quality judgment |
| Severity ceiling/calibration | machine policy + reducer decision + renderer validation | Candidate policy is explicit; judgment says whether a conditional policy applies; renderer rejects invalid upward moves |
| Evidence class | reducer | Requires interpreting the support |
| Final summary and causal claim | reducer | Semantic compression |
| Priority order | reducer | Current tier-divergence rule makes a purely numeric score incomplete |
| Personas, consensus, effort rollup | renderer | Directly derived from sources |
| Anchoring and verdict | renderer | Derived from persisted `decision_support` |
| Consistency-shaped classification | reducer | Semantic class used by verification policy |
| Verification eligibility/cap/order | renderer | Mechanical after reducer supplies `consistency_shaped` and claim text |
| Finding IDs and counts | renderer | Prevents report/snapshot drift |
| Resource table and wall duration | renderer | Derived from `usage.jsonl` |
| Markdown report | renderer | Pure presentation |
| Base snapshot | renderer | One canonical serialization |
| WPR/pass/backend support | `assemble-wpr.py` | ADR-12/18 canonical producer |
| Verification application | `apply-verification.py` | Existing canonical producer |

## Deterministic renderer

`render-integration.py` validates the workset and decisions before writing anything final.

### Lineage gate

- Every `source_candidate_id` must exist.
- No candidate may appear in two final findings' `source_candidate_ids`; `derived_from_candidate_ids` is non-exclusive and cannot satisfy primary accounting.
- Every candidate must be included once or explicitly excluded once.
- `canonical_source_id` must belong to the finding's source set.
- A final finding may not lack sources.
- Every raw source ID in the workset must belong to exactly one candidate or one noise-floor discard, so candidate-level completeness rests on raw-pass completeness rather than reconciler discipline.

### Field validation

- Verdict and severity values are enums.
- Effort is the most generous source estimate unless the reducer supplies a reasoned override; upward understatement is rejected.
- Every candidate carries a three-state ceiling result. `unparsed` is a validation failure, not an alias for “no ceiling.” Conditional persona policies are machine-readable; the reducer decides whether the condition applies. The merged ceiling is the strictest applicable ceiling across **all** sources, including non-canonical sources, and the renderer enforces it.
- File and line default to the canonical source and may only be replaced with another source's location.
- Evidence is one of `cited-spec|code-site|inference`.
- Priority ranks are unique. Missing or duplicate ranks fail rendering rather than being guessed.
- `repro_hint` remains descriptive and rejects command-shaped text using the same guard as the verifier path.
- Every finding that could enter the verification queue must carry a causal claim. Eligibility is computed by set-unioning source candidates' raw-ID-derived `support_passes` per persona, with N from `run.pass_denominators`; the reconciler's `support_tag` and a reducer-authored support value are never inputs.
- Every `previous_finding_id` resolves in `previous_cycle`, every derived record cites existing candidates, and registry updates conform to the fixed schema above. The renderer assigns registry `finding_id` only after final IDs exist.

### Derived output

The renderer assigns final finding IDs, computes persona attribution, counts effort tags, derives anchored Criticals and the verdict, selects and caps the verification queue, derives wall-clock duration from usage timestamps, and writes both final artifacts from the same in-memory object. For anchoring and queue eligibility it set-unions each final finding's candidates' `support_passes` by persona and persists `{persona: [k,N]}` as `decision_support`, the explicit verdict basis. This is exact because pass identity is retained until after union. Finalization independently projects the same persisted raw-ID lineage into canonical `pass_support` and `backend_support`; it performs no fuzzy rematch. The two support fields have distinct purposes and their equality is gate-checked where their domains overlap.

Finalization follows the lineage rather than fuzzy-matching raw text directly to final findings: raw source ID → candidate ID → final finding ID. Fuzzy matching remains confined to the builder's per-persona raw→reconciled association, where an unmatched raw finding becomes a recovered candidate rather than disappearing.

The reducer-era snapshot is **version 3** and `run-meta.json.integration_pipeline == "semantic-reducer-v1"` is the acting-era discriminator. Its schema is the existing v2 field set from `integrator.md` plus top-level `integration_degraded`, typed `integration_degraded_reason`, `excluded_candidates`, `noise_floor_discards`, and `decision_schema_version`; each finding adds `source_candidate_ids`, optional `derived_from_candidate_ids`, and `decision_support`. `personas_run` and `codebase` come from the required workset run block. The snapshot initially carries `within_persona_runs: null` and per-finding `pass_support: null`; `assemble-wpr.py` overwrites only its owned fields. A v3 snapshot or reducer-era run metadata without the retained workset and decisions is **INCOMPLETE**, never interpreted as legacy.

`registry-updates.json` is rendered from the reducer's validated registry decisions when `pii` or `deanon` ran. It remains absent otherwise. On deterministic union, the file is an empty array and both the snapshot and first-screen banner say `registry_updates: not produced (degraded)`; the learning-loop loss is never a silent absent-write.

## Fresh-context runner and context budget

The architectural requirement is a **qualified isolated runner**, not a particular vendor.

### Isolation contract

NineAngel supplies the reducer process only:

- the contents of `reducer.md` as a developer instruction containing semantic rules only;
- nonce-delimited, delimiter-escaped `integration-workset.json` contents as untrusted user data;
- a strict output schema and a temporary decision-output target.

`dispatch-integration.sh` launches a fresh `codex exec` process authenticated with the CLI's saved ChatGPT login. The wrapper accepts only the exact supported CLI release from a trusted user/system root and incorporates the binary's path, version, file identity, and SHA-256 digest into the qualified identity. The command pins `gpt-5.6-sol`, uses `--ephemeral` and `--strict-config`, ignores user configuration and project rules, selects the read-only sandbox, explicitly disables hosted web search and all command/filesystem/browser/MCP/plugin/delegation features, requests strict schema output, and runs from an isolated temporary workspace containing only the schema and output target. The model receives no project path and no local tool capable of opening one.

The wrapper—not the model—reads `reducer.md`, `integration-workset.json`, and the decision schema. It validates that one logical Codex turn completed and rejects every item type except reasoning, the final agent message, and the exact fail-closed Code Mode-host-disabled error. This post-turn audit is detection, not the primary boundary: the primary boundary is the pinned CLI plus pre-inference feature/configuration controls. A malicious finding can influence decision text, but the admitted configuration gives it no local execution, file-read, MCP, delegation, or browser-egress tool. Timeouts and termination signals kill the entire Codex process group before a retry can begin; signals are blocked across process creation until the child handle is installed, and a host unable to provide that atomic handoff is unqualified.

The runner requires `codex login status` to report `Logged in using ChatGPT`. Rather than denylisting known secrets, it constructs a minimal child environment containing only home/auth discovery, TLS/proxy plumbing, a fixed system `PATH`, and deterministic locale controls. Ambient API/cloud credentials therefore do not reach the child and cannot silently switch the job to usage-based billing. The trusted Codex host may read its cached ChatGPT credential; because the model has no callable local tools, that credential cannot enter model context through shell or file output. A host signed in with an API key is unqualified and degrades to deterministic union.

`scripts/probe-integration-runner.sh` is the admission gate. It verifies ChatGPT auth, one completed logical turn, zero executable tool events, separately counted blocked attempts, bounded cumulative turn input, credential-marker non-persistence, and a non-vacuous four-candidate result: one required two-source merge plus explicit exclusion of a non-defect and an instruction-shaped candidate. Independent unit tests assert the exact feature-disable set and environment allowlist. The qualification record is bound to a SHA-256 fingerprint of the trusted runner surface plus the full Codex binary identity; changing code, schema, CLI version, or binary content invalidates admission until the probe runs again. Missing ChatGPT auth, unexpected tool activity, unknown turn input, stale runner identity, credential-boundary failure, or bad lineage makes the semantic route unavailable and produces the explicit degraded union.

### Runner qualification

Before a runner is admitted to the synthesis route, the tiny qualification workset must show **≤20k cumulative input tokens for its single completed turn**. Unknown turn input is not qualifying. This is an admission regression bound, not a claim that the CLI exposes or has an empty initial context.

Context measurements are separate from spend meters. Codex reports completed-turn input/output usage, not independently measured initial or peak context. Reducer usage therefore records truthful `input_tokens`, `output_tokens`, and `turn_count`; legacy `initial_context_tokens` and `peak_context_tokens` remain `null` instead of relabeling cumulative counters (ADR-17).

The current Claude Agent path is not qualified by the 08-29 measurement: despite being a fresh sidechain with no parent cache read, harness scaffolding created 100,675 tokens before finding input. An ordinary interactive `codex exec` is likewise not qualified because its shell can read local credentials even under a read-only filesystem sandbox. The admitted adapter is narrower: the exact supported `codex exec` binary with those tool features and hosted web search disabled at command construction, strict config, user/project configuration ignored, an isolated temporary workspace, schema-constrained output, and event-stream rejection if a tool item nevertheless appears. Admission remains empirical and vendor-neutral. This moves the acting integrator off unconditional Claude/Opus routing; ADR-17/19 and the backend-routing spec must be amended at cutover.

This deliberately revisits the old “integrator stays Claude-first” decision. That decision optimized one large, load-bearing synthesis call. This design removes the large call; runner isolation and bounded input become more important than preserving its historical dispatch surface.

### Workset budget

`build-integration-workset.py` records UTF-8 bytes and a conservative token estimate. One reducer call may receive at most **24k estimated reducer-input tokens**; ordinary packing targets ≤16k. The original 60k fixture target budgeted a typical ≤16k workset, ≤4k mandate, an anticipated ≤20k runner-instruction contribution, and ≤16k output reserve. That remains sizing arithmetic, not a measured decomposition: Codex reports cumulative turn input/output and no direct peak-context field. The implementation records those counters under their truthful names and enforces the workset and accepted-output bounds directly.

If the workset exceeds that:

1. Build connected components from `candidate_edges`; never split a component.
2. Pack components into shards targeting ≤16k estimated tokens.
3. Dispatch each shard in a fresh reducer process.
4. Mechanically combine shard decisions into a compact second workset.
5. Run one fresh final reducer over the compact results to catch missed cross-shard duplicates, set global priority, and phrase verification claims.

If one connected component alone exceeds 16k, split it deterministically by persona groups while copying a compact anchor (`id`, file, line, title) for every cut edge into both shards; the final reducer must adjudicate those cut edges. If the compact final workset itself exceeds 24k, recursively apply the same procedure. A hard maximum of two sharding levels prevents unbounded fan-out; exceeding it produces a visible degraded union report rather than an oversized prompt.

No reducer conversation is resumed across shards. Files, not conversation history, carry state.

## Failure and recovery

### Reducer failure

1. Validate output existence and schema, not exit code alone.
2. On invalid lineage/schema, write the validator diagnostics and retry once in a new isolated context, optionally on the next qualified runner.
3. If both fail—or no runner qualifies—write a schema-valid `integration-decisions.json` with `producer: deterministic-union` and render it normally:
   - one final finding per candidate;
   - no semantic dedup;
   - source severity/effort preserved;
   - deterministic order: severity (`critical`, `important`, `minor`, `noted`), then persona, file, numeric line, candidate ID;
   - `evidence: inference` for every finding, the conservative class that cannot anchor by itself;
   - verdict derived from the same persisted `decision_support` rules;
   - no invented causal claim; findings without one are ineligible for verification;
   - `integration_degraded: true` plus typed reason (`reducer-failed-twice|no-qualified-runner|runner-cleanup-failed|shard-depth-exceeded`) in the snapshot; historical sandbox reasons remain schema-readable only for old artifacts and are not emitted by the acting runner;
   - a first-screen `DEGRADED INTEGRATION` banner naming the reason, candidate/finding counts, missing semantic operations, registry-update status, and an actually runnable retry command;
   - bounded Markdown: preliminary Top 5 plus counts, while the required `findings-snapshot.json` retains every union candidate for retry and audit.

The driver never absorbs the work as an inline fallback.

### Builder failure

An absent or unparseable reconciled view is a per-persona state, not a run-level dead end: the builder writes a diagnostic and constructs that persona's union fallback from its capture-gated pass files. If a pass file itself is missing or unparseable, the builder records the persona under `personas_failed`, emits candidates from surviving inputs, and produces a visibly degraded report. Only an invalid/missing `run-meta.json` or a raw-ID accounting violation stops before rendering; `integrate-run.sh --resume` names the exact missing field/ID and `record-run-meta.py` is the repair command.

### Renderer failure

Rendering is deterministic and testable. A renderer-internal failure preserves the workset and decisions, writes `integration-error.json`, and stops before finalization. Decision validation failure follows the reducer retry/union path above, so it cannot dead-end without a report. `integrate-run.sh --resume` reports and re-enters the exact stage.

Ordinary rendering is permitted only before verification/finalization. If `verification/`, non-null snapshot `verification`, or assembled WPR/support is present, ordinary re-render refuses and instructs the operator to start a new run; it never overwrites enriched artifacts or reassigns IDs under existing verdict files. Within the pre-finalize window, final IDs are stable because decisions are sorted by their deterministic primary source set before IDs are assigned; `priority_rank` controls display order, not identity.

`integrate-run.sh <RUN_DIR> --retry-reducer` is the one narrow exception. It is allowed only when the current snapshot says `integration_degraded: true`, every verification is null, `verification/` is absent, and every disposition remains `no-record`. It atomically copies the old report/snapshot/decisions to `retry-history/<timestamp>/`, reruns only dispatch→validate→render, reruns `assemble-wpr.py` from the unchanged raw lineage, and re-finalizes idempotently. If verification or a human disposition exists, `--retry-reducer` refuses and prints `integrate-run.sh <RUN_DIR> --clone-retry`, which creates a new run dir referencing the preserved workset. The degraded banner selects and prints the form valid for its current state.

### Partial files

Write workset, decisions, report, and snapshot through temporary files followed by atomic rename. The delivery signal remains a valid `findings-snapshot.json`, but a partial report can no longer exist under its final filename.

`scripts/integrate-run.sh <RUN_DIR>` is the single composed entry point and state owner. It calls builder → dispatcher/validator → renderer → finalizer and supports `--resume`, `--retry-reducer`, and `--clone-retry`. The dispatcher owns `integration-runner.pid` and atomically updates `integration-heartbeat.json` at least every 60 seconds while the child PID is alive; it enforces a 10-minute wall cap. The watchdog checks those named artifacts rather than expecting the reducer to write PROGRESS.

The PROGRESS trail becomes script-owned:

- `workset-built`
- `reducer-dispatched`
- `decisions-validated`
- `report-rendered`
- `snapshot-rendered`
- `finalized`

Owner mapping: builder writes `workset-built`; dispatcher writes `reducer-dispatched` and heartbeats; validator writes `decisions-validated`; renderer writes both render markers; finalizer writes `finalized`. `resume-run.sh` remains read-only and diagnostic; it prints the exact `integrate-run.sh <RUN_DIR> --resume` command without executing it.

## Contract cleanup

The implementation deletes, rather than amends around, the obsolete instructions:

- Remove `integrator.md`'s later instruction to emit `within_persona_runs`.
- Remove SKILL.md's instruction to read or assemble `reconciled/*-passes.json`.
- Retire `reconciler.md` output #2 (`{persona}-passes.json`), completing ADR-12's deferred cleanup.
- Remove the legacy raw-pass Stage-2 mode.
- Remove micro's inline-integration default.
- Remove inline integration as the terminal stall fallback.
- Replace the 337-line `integrator.md` acting mandate with concise `reducer.md` semantic rules plus `docs/report-format.md` and versioned JSON schemas owned beside the renderer. Inline ADR-16 reconciliation thresholds, the distinct Critical-anchoring rule, the cross-persona severity-ceiling clamp, verification ordering, and the descriptive-only `repro_hint` guard from SKILL.md §5.7 so retiring the mandate does not orphan them.

The historical file may remain as documentation during migration, but no acting path may concatenate or dispatch it once cutover occurs.

## Migration plan

Each phase is independently testable. Production behavior does not flip until Phase 4 and the targeted `/angel` re-review has no unresolved Critical. Estimated implementation size: roughly 1,500–2,500 lines across scripts, schemas, fixtures, and docs; expect 2–4 focused days including replay and one real shadow run. That estimate is a planning range, not a cutover promise.

### Phase 0 — contract repair and measurement

- Remove the three `within_persona_runs` contradictions.
- Extend `test_adr_consistency.py` with a Phase-0 predicate that only checks WPR ownership; keep the raw/inline-path predicate disabled until Phase 4.
- Add `run-meta.json` creation/recording and its reducer-era completeness discriminator without changing the acting integrator.
- Add typed context/workset measurements to integrator usage where measurable. When a backend exposes only cumulative turn counters, record them as `input_tokens`/`output_tokens` and leave legacy initial/peak fields unknown.
- Add a script that extracts the two replay fixtures' current artifacts and expected headline outcomes.
- Do not change the acting integrator yet.

**Gate:** `python3 scripts/test_adr_consistency.py --phase wpr-ownership && bash scripts/test_scripts.sh`; status quo is both replay fixtures passing `python3 scripts/check-run-complete.py <run>`. The phase fails if either changes, an acting instruction still assigns WPR assembly to an LLM, or `usage.json` drops any typed context measurement written to `usage.jsonl`.

### Phase 1 — workset builder and lossless parser

- Add the lossless wrapper without changing legacy `parse_findings()` output.
- Build `build-integration-workset.py` and its schema validator.
- Implement the Stage-1 union fallback.
- Run it side-by-side after existing integrations; do not consume its output yet.

**Gate:** `python3 scripts/test_integration_workset.py --fixtures <A> <B>` must prove legacy parser golden parity; an exact checked-in legacy→lossless difference; Fixture B's 54 auditable discard records; no discard with a parsed location; raw-ID total accounting across retained + discarded records; strict-match `unmatched` behavior; exact support-pass set union; unparseable-reconciled→union fallback; and byte-identical builder output across two runs. Reducer-era `assemble-wpr.py` must consume the workset mapping and its projected support must match renderer `decision_support`; historical `assemble-wpr.py --check` remains green.

### Phase 2 — decisions schema and renderer

- Build `validate-integration-decisions.py` and `render-integration.py`.
- Hand-author fixture decisions from the accepted existing snapshots.
- Render reports/snapshots in a temporary fixture directory and run the ordinary finalize/completeness path.

**Gate:** `python3 scripts/test_render_integration.py` must reject missing/duplicated/invented IDs, preserve derived contradiction records, persist exclusions/decision support, refuse post-verification overwrite, and produce exact verdict/count/effort/queue parity. `bash scripts/test_integration_replay.sh --mechanical-only` finalizes both fixtures without an LLM.

### Phase 3 — isolated reducer shadow run

- Add `reducer.md`.
- Add qualified-runner dispatch with workset budgeting and sharding.
- Replay the two frozen runs without touching their original artifacts.
- Compare outputs with the accepted reports and dispositions.

**Gate:** `bash scripts/test_integration_replay.sh --runner codex` must emit `integration-replay-comparison.json` with `verdict: pass|review|fail` and `hard_failures: []`. Hard failure means >80k measured peak, loss of any source behind a final Critical/Important in the accepted snapshot (regardless of later human disposition), source-less addition, unexplained anchored-verdict change, or incomplete run.

### Phase 4 — acting-path cutover

- Switch interactive, micro, and unattended integration to the reducer pipeline.
- Delete legacy raw and inline acting paths.
- Update resume/failure docs and changelog.
- Keep the old integrator available only as a replay oracle for one release interval, then remove it.

**Gate:** the hostile, mixed-reconciliation, double-reducer-failure, ordinary-oversized-sharding, single-oversized-component, shard-depth-exceeded, zero-finding, registry, failed-pass, ceiling-policy, N=2-no-promotion/N=3-majority-promotion, and loop fixtures all pass, followed by one real multiball shadow run. `test_adr_consistency.py --phase cutover` additionally rejects all acting raw/inline Stage-2 paths. Cutover fails if Stage 2 sees a raw pass path, a runner inherits harness context, model-tool egress succeeds, degradation is absent above the fold, or report/snapshot disagree.

## Replay acceptance suite

### Fixture A — raw-fallback stress

`/home/user/.angel/runs/20260829T000259Z-49c4c1ae`

Why: Stage 1 was skipped, the integrator performed both reconciliation levels, and peak context reached 188,855.

Required:

- Peak context ≤80k; target ≤60k.
- Same verdict.
- Every source behind a final Critical/Important finding in the accepted snapshot remains represented, regardless of later `dispositions.json` status.
- No raw pass is read by the semantic reducer.
- Union fallback status is visible if Stage 1 is not reconstructed for the replay.
- The noise floor is applied before lineage; the measured retained candidate count is recorded rather than assumed to be 41.

### Fixture B — normal hierarchical run

`/home/user/.angel/runs/20260830T143153Z-46bea721`

Why: complete current-shape run with 109 legacy-parser rows / 113 structural records → 41 reconciled → 23 final findings and eight verification targets.

Required:

- New reducer peak context ≤80k; target ≤60k. This fixture's current Codex integrator peak was unmeasured, so it is an absolute gate, not a paired old/new claim; Fixture A supplies the paired context comparison.
- Same verdict and verification queue size.
- All retained reconciled candidates accounted for exactly once as primary sources, with any recovered-unmatched candidates listed separately.
- Same final Critical/Important source coverage; changed merge boundaries require explicit diff output for review.

### Additional fixtures before cutover

Generated fixtures live under `fixtures/integration-v1/<case>/`; `scripts/generate-integration-fixtures.py` creates deterministic raw/reconciled/run-meta inputs and checked-in expected lineage. Live outputs stay in temporary run dirs.

- One all-clean/zero-finding run.
- One `pii`/`deanon` run with registry updates.
- One run with a failed persona pass.
- One mixed run where one persona reconciles and another uses union fallback.
- One hostile/instruction-shaped finding with an out-of-mount canary.
- One double-reducer-failure run that must still pass completeness with a degraded banner.
- One `--loop` cycle-2 run with persisted/regressed annotations.
- One oversized synthetic workset that must shard.
- One oversized single connected component that must exercise anchor duplication.
- One shard-depth-exceeded workset that must degrade visibly.
- One conditional severity-ceiling case.
- One N=2 no-promotion and N=3 true-majority-promotion pair.
- `oversized-known-merges`: hand-labelled duplicate groups planted across shard cuts; the gate fails if any planted pair remains separate in at least two of three reducer runs. This synthetic ground truth replaces the impossible requirement for a current-integrator baseline on a corpus it never saw.

## Comparison report

The replay harness writes `integration-replay-comparison.json` containing:

- old/new peak context and wall time;
- candidate count, final count, and merge-group membership;
- verdict/count/effort parity;
- Critical/Important title-match and persona-attribution deltas;
- verification queue delta;
- excluded-candidate reasons;
- noise-floor discard and recovered-unmatched counts/deltas;
- complete-run gate result.
- `verdict: pass|review|fail` and `hard_failures: []`.

Semantic deltas are review material, not automatically failures below Important. Loss of a source behind any final Critical/Important fixture finding, source-less additions, lineage failure, context-budget failure, isolation failure, and completeness failure are hard failures.

## Exhaustive edit map

| File | Planned change |
|---|---|
| `SKILL.md` | Replace Stage-2 prompt construction with workset/reducer/renderer flow; make reconciled views mandatory or union-fallback; delete raw/inline paths; replace the PROGRESS-mtime watchdog with `integration-runner.pid` + `integration-heartbeat.json`; document context budget and degraded union report; cite ADR-20. |
| `unattended.md` | Mirror the same file pipeline; no verbatim persona blocks in the reducer prompt; use deterministic terminal fallback. |
| `integrator.md` | Retire as acting mandate; remove contradictory WPR rules during Phase 0; retain temporarily as replay oracle. |
| `reducer.md` | **New:** concise semantic-only mandate and decision schema rules. |
| `docs/report-format.md` | **New:** canonical report sections, degraded first-screen banner, verdict/anchoring/verification rules, and inline ADR-16 thresholds. |
| `schemas/run-meta-v1.json`, `schemas/integration-workset-v1.json`, `schemas/integration-decisions-v1.json`, `schemas/findings-snapshot-v3.json` | **New:** versioned contracts consumed by validators and parity tests. |
| `reconciler.md` | Remove `*-passes.json`; clarify that failed reconciliation degrades to script-built union, never Stage-2 raw mode. |
| `scripts/parse-findings.py` | Add lossless raw text, description, effort, support-tag, and ceiling fields without breaking existing callers. |
| `scripts/init-run.sh`, `scripts/record-run-meta.py` | Create and atomically complete required `run-meta.json`; persist the reducer-era discriminator before integration. |
| `scripts/finding_match.py` | Add strict bounded integration matching with explicit unmatched results; preserve the legacy analytics matcher for historical consumers. |
| `scripts/build-integration-workset.py` | **New:** normalize inputs, union fallback, candidate IDs/edges, resource metadata, budget estimate, atomic write. |
| `scripts/validate-integration-decisions.py` | **New:** schema, lineage, enum, source, priority, ceiling, and command-shaped-hint validation. |
| `scripts/render-integration.py` | **New:** derive final IDs/personas/counts/effort/verdict/queue/resources and atomically write report/snapshot/registry. |
| `scripts/dispatch-integration.sh`, `scripts/run-reducer-sandbox.py` | **New/amended:** qualified ChatGPT-authenticated Codex runner, fixed model/schema, disabled tools, API-key scrubbing, retry, sharding, usage/progress capture, and process-group cleanup. No agent-shell or parent-context fallback. |
| `scripts/integrate-run.sh` | **New:** one composed build/dispatch/validate/render/finalize entry point with `--resume`, qualified in-place `--retry-reducer`, and state-preserving `--clone-retry`. |
| `scripts/probe-integration-runner.sh` | **New/amended:** exact Codex identity, ChatGPT auth, API-key scrubbing, one-turn/no-tools, context, instruction-shaped input, and four-candidate lineage qualification. |
| `scripts/dispatch-leg.sh` | No reducer route: retain for agentic persona legs; add a regression assertion that integration never calls it. |
| `scripts/record-dispatch.sh` | Record reducer activity under the backward-compatible `integrator` usage slot plus typed runner/context metadata. |
| `scripts/assemble-wpr.py` | Continue owning WPR/pass/backend support; expose its support-matching core for the workset builder; use raw→candidate→final lineage when reducer-era artifacts exist; tolerate renderer's base snapshot and preserve decision lineage fields. |
| `scripts/finalize-run.sh` | Add decisions/render validation before existing assembly/usage/completeness stages; final PROGRESS marker. |
| `scripts/check-run-complete.py` | Require workset + decisions + lineage-valid rendered artifacts for reducer-era runs; retain legacy checks for history. |
| `scripts/resume-run.sh` | Remain read-only; report phases independently and print the exact `integrate-run.sh --resume` recovery command. |
| `scripts/aggregate-usage.py` | Preserve isolated reducer context measurements and degraded status. |
| `scripts/test_parse_findings.py` | Lossless-field fixtures across observed Markdown variants. |
| `scripts/test_assemble_wpr.py`, `scripts/test_dispatch_leg.sh`, `scripts/test_reducer_sandbox.py` | Pin reducer-era raw-lineage projection, forbid reducer routing through the agentic leg, and test ChatGPT-only auth, no-tools command construction, event rejection, API-key scrubbing, and timeout cleanup. |
| `scripts/generate-integration-fixtures.py`, `fixtures/integration-v1/` | **New:** deterministic synthetic cutover cases plus expected lineage/merge groups. |
| `scripts/test_integration_workset.py` | **New:** deterministic candidates, fallback union, edges, budget/sharding fixtures. |
| `scripts/test_render_integration.py` | **New:** lineage failures, derivations, parity, zero/registry/loop/degraded cases. |
| `scripts/test_integration_replay.sh` | **New:** mechanical replay gate plus optional live reducer comparison; writes explicit verdict/hard failures. |
| `scripts/test_scripts.sh` | Wire deterministic builder/validator/renderer/completeness fixtures only; never invoke a live LLM. |
| `scripts/test_adr_consistency.py` | Assert no acting path assigns WPR/report bookkeeping to the reducer or retains raw/inline Stage-2 paths. |
| `docs/decisions/09-*` | Mark micro inline integration superseded if cutover is accepted. |
| `docs/decisions/04-*` | Supersede the inline terminal rung with deterministic union and qualified retry. |
| `docs/decisions/11-*` | Amend Stage 2, retry, incremental-write, inline-fallback, and watchdog portions; retain history while replacing the old PROGRESS-mtime tripwire with PID + named heartbeat. |
| `docs/decisions/12-*` | Close the deferred `*-passes.json` cleanup; record that renderer writes only the base snapshot and script still injects WPR. |
| `docs/decisions/13-*` | Mark output parity structurally enforced by one renderer. |
| `docs/decisions/16-*` | Record `decision_support` as the renderer's verdict basis and finalized `pass_support` as the provenance/calibration field; inline the promotion/demotion thresholds in report-format docs. |
| `docs/decisions/17-*` | Add typed initial/peak context measurements without conflating them with cumulative spend tokens. |
| `docs/decisions/19-*` | Amend integrator model assignment: qualified isolated runner replaces unconditional Opus-first dispatch. |
| `docs/v2-backend-routing.md` | Change synthesis routing from vendor-first/1M-first to qualified-runner chain with context capability. |
| `scripts/mine-runs.py`, `scripts/subsample-analyzer.py`, `scripts/persona-overlap.py`, `scripts/depth-lane-yield.py`, `scripts/recurrence-pilot.py`, `scripts/finalize-calibration.py`, `scripts/emit-dispositions-skeleton.py`, `scripts/pass-support-accuracy.py` | Assert v3 compatibility and distinguish `decision_support` from finalized `pass_support`; preserve zero-finding participants. |
| `README.md`, `DESIGN.md`, `CHANGELOG.md`, `backlog.md` | Document qualified subscription-backed isolation, runner probe, architecture, recovery entry point, migration, and completed backlog item. |

## Risks and controls

### Candidate graph misses a duplicate

Control: edges are aids, not the only comparison surface on budget-qualified runs; oversized runs get a final compact cross-shard pass with cut-edge anchors. Replay compares known merge groups and persona attribution. This remains an empirical attention risk, not a formal guarantee.

### Structured decisions become another fragile LLM transcription

Control: the reducer is not transcribing raw findings. It emits semantic relationships over script-assigned IDs. The validator requires total candidate accounting and rejects invented IDs. Raw content remains recoverable in the workset.

### Deterministic rendering flattens useful editorial judgment

Control: title, summary, evidence, priority, causal claim, calibration reason, contradiction handling, and notes remain reducer outputs. The renderer owns only specified derivations and presentation.

### Fresh runner changes integration quality

Control: model/backend admission is replay-gated. Source coverage and accepted C/I preservation are measured before routing changes. A runner that is lean but semantically worse does not qualify.

### Deterministic union fallback produces a noisy report

Control: it is terminal and visibly degraded above the fold, uses stable severity/persona/location ordering, preserves signal, emits schema-valid deterministic decisions, and passes the ordinary completeness gate. The banner carries the exact retry command.

### Versioned schemas create maintenance cost

Control: schemas are versioned next to validators; run metadata and decisions are durable audit inputs, the workset remains retained for the run's lineage/retry lifetime, and the snapshot remains the public run record. Each has one producer and one purpose.

## Claims register

- **Claim:** most integration context is scaffolding and redundant representations, not irreducible semantic work. Confidence: high, based on the measured 100,675-token pre-finding context and 188,855 peak in run `20260829T000259Z-49c4c1ae`. Evaluating command: `bash scripts/test_integration_replay.sh --runner codex`; falsified by any replay whose measured peak exceeds 80k, regardless of source preservation.
- **Claim:** rendering both artifacts from one validated in-memory object prevents report/snapshot divergence. Confidence: high. Evaluating command: `python3 scripts/test_render_integration.py`; falsified by any successful invocation whose report and snapshot disagree on IDs/verdict/counts.
- **Claim:** removing raw-pass and inline fallbacks bounds driver-context growth without sacrificing recoverability. Confidence: medium-high. Evaluating command: `bash scripts/test_integration_replay.sh --case double-reducer-failure`; falsified if the workset cannot yield a complete, source-preserving degraded run.
- **Claim:** candidate-edge sharding retains cross-persona dedup quality. Confidence: provisional. Evaluating command: `bash scripts/test_integration_replay.sh --case oversized-known-merges --repeat 3`; falsified if any hand-labelled cross-shard duplicate pair remains separate in at least two runs.

## Review record

- Initial `/angel`: `20260830T175526Z-6ba81036` — seven personas, 68 findings; its verified mechanisms were dispositioned into the first revision.
- Targeted `/angel`: `20260830T183354Z-b5d839de` — five personas, 48 integrated findings and eight unique Critical mechanisms. Claude hit its session cap during the verifier fan-out after the report was written; the review findings themselves were complete.
- Fresh focused verification: `/tmp/angel-reducer-critical-verification.json` checked the revised document and resolved f1–f6 and f8; it left only credential exposure through a model-callable shell.
- Fresh f7 verification: `/tmp/angel-reducer-f7-verification.json` checked the tool-free API-client revision and returned `resolved: true`, `unresolved_critical_count: 0`.

The implementation gate is therefore **8/8 Critical mechanisms resolved, zero unresolved**. The 60k context target remains aspirational for shadow operation; a measured peak above 80k, isolation/probe failure, source loss, or incomplete artifact blocks acting-path cutover. Semantic output deltas without a hard failure require human review rather than automatic acceptance.
