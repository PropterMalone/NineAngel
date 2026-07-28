# ADR-12 — Per-pass capture integrity: mechanical capture, scripted assembly, provenance gate

Status: **proposed (v3)** — rewritten 2026-07-22 after two `/angel` reviews (draft + v2, the latter N=2). Supersedes the draft and v2. Extends ADR-06 (completeness gate), ADR-11 (hierarchical file-contract). This version resolves the v2 review's blocking findings: it removes the circular dependency (by **deferring D5** — see the boxed decision), defines the degraded-run contract, scopes the invariant honestly, names every writer, and builds the parser against the real pass corpus rather than the spec.

## Problem

Multiball runs persist a per-pass record — the snapshot's `within_persona_runs` — that the reproducibility/overlap/optimization tooling depends on. `[ran:]` shape scan of 32 multiball snapshots: **23 valid structured**, 9 unanalyzable (3 id-ref, 2 prose, 4 other-broken). `subsample-analyzer.py` **crashed** on the id-ref shape (`AttributeError`), taking the whole `--runs-dir` scan down — now shape-guarded to skip them (commit `d28b961`).

Failure partition (correcting v2's loose "correlates with inline"): of the 5 id-ref/prose failures, **3 are inline-integration runs** (1 id-ref + 2 prose) and **2 are hierarchical runs that had `passes/` on disk yet still wrote id-refs.** So the diagnosis is not "inline mode" but the stronger **LLM assembly is a failure locus** — the integrator (inline) or the reconciler→integrator transcription (hierarchical) reconstructs the per-pass record from memory and shortcuts it. The consolidation below addresses that regardless of mode.

Not systemic (23/32 fine), so we preserve existing good data — but the bug silently corrupts `within_persona_runs` on any run whose LLM assembly shortcuts, so it is worth fixing on its own.

## Root cause: three representations transcribed by LLMs

```
persona pass (markdown)
  └─(orchestrator hand-writes, prose-mandated)→ passes/{persona}-p{i}.md    [SKIPPED in broken runs]
       └─(reconciler parses md→JSON)→ reconciled/{persona}-passes.json
            └─(integrator assembles)→ within_persona_runs (snapshot field)
                 └─(integrator self-re-derives from memory if malformed)  ← integrator.md:44, the bug path
```

Three representations of the same per-pass data, each step LLM-mediated. Inline mode skips the reconciler entirely and reconstructs from memory.

## The consolidation

The persona output is already captured on stdin by `record-dispatch.sh` (for `findings/`), so the md→struct step can be a **deterministic script**, and everything downstream assembled mechanically:

```
persona pass (markdown)
  └─(record-dispatch.sh --pass i, MECHANICAL)→ passes/{persona}-p{i}.md   [durable when the call is made; gate-enforced]
reconciler (LLM synthesis) → reconciled/{persona}.md                       [human view + (k/N) tags — KEPT unchanged]
integrator (LLM) → findings[] + personas[] + ids + verdict                 [semantic dedup + severity — KEPT unchanged]
assemble-wpr.py (SCRIPT, post-integrator) reads passes/*.md + findings[]:
  • parse each pass md → structured [{severity,title,file,line}]  (parse-findings.py)
  • stamp each pass finding with rid = reconciled finding it maps into (P ∈ F.personas + file/line)
  • compute pass_support per reconciled finding (distinct passes carrying its rid)
  • join model per (persona, pass) — stamped at capture, see D3
  • INJECT within_persona_runs (+ pass_support) into findings-snapshot.json; emit a provenance record
check-run-complete.py: recompute assemble-wpr, require the injected field to equal it  [PROVENANCE]
```

**One transcription (md→struct), deterministic, from a durable source, post-integrator.** No circular dependency: the script consumes the integrator's output and nothing feeds back. The reconciler's JSON output, the integrator's wpr assembly, and the self-re-derive fallback are retired.

**Stated invariant (scoped per the v2 review).** *Every durable per-dispatch **bookkeeping record** — `usage.jsonl`, `findings/{name}.md`, `passes/{persona}-p{i}.md`, and (D-verifier) `verification/{id}.json` — is written by `record-dispatch.sh`, never hand-mandated to the LLM.* This does NOT cover synthesis artifacts the LLM legitimately authors (`report.md`, `findings-snapshot.json`, `reconciled/{persona}.md`) — those are named, single, per-*run*/per-*phase* writes, not per-dispatch bookkeeping, and the provenance gate (not the invariant) guards the one field inside the snapshot that must be mechanical.

> ## Boxed decision — severity-by-corroboration: **DEFER the move, ADD an audit** (decided 2026-07-22, the user)
> the user asked to fold in "edit 1" (move the reconciler's k/N severity promote/demote into the script). The v2 `/angel` review showed that move (**D5**) is the sole source of the circular dependency (severity-to-script means the integrator must consume the script's output, but the script must consume the integrator's for rid), and it separately breaks the singleton-Critical verdict path, deletes rule 22's promote-veto, and strips the reconciler of pass-count context. The determinism it buys is also partly illusory: severity would become a function of the brittle rid-matcher's precision (a mis-match flips k=1↔k=2 = a tier), degrading reliability exactly where it ships.
>
> **Decision: do NOT move the decision (keep severity with the reconciler/integrator, as today), but MEASURE it — D5-audit below.** Assembly stays single-phase and post-integrator. The two-phase move is specified in **Appendix A** and revisited only if the audit shows the LLM drifting from the mechanical rule meaningfully.

## Decisions (D5 deferred)

### D1 — Mechanical single-source capture
- **`passes/{persona}-p{i}.md` becomes a mechanical write**: `record-dispatch.sh --pass i` writes the block (already on stdin) to `passes/{name}-p{i}.md`. `--findings` composes only with `--pass 1` (pass-1's block is also the `findings/{name}.md` record; passes 2..N use `--pass i` alone and never touch `findings/`). Mode-independent — fires on inline/`--micro` runs too.
- **Mechanical enforcement (honest durability).** The write is durable only when the call is made — `record-dispatch.sh` is orchestrator-invoked, so a skipped call is still a skipped call (the ADR-03 class, narrowed to one call). To convert discipline back to mechanism: `record-dispatch.sh` **refuses a `persona`-phase call that lacks `--pass` when the `MULTIBALL` marker is present** (the marker is on disk at run start, `check-run-complete.py:38`). A missed pass is unrecoverable (the block lived only in the returned subagent message) — the gate **detects** it (INCOMPLETE), it cannot recover it; do not claim otherwise.
- **`within_persona_runs` is assembled by `assemble-wpr.py`** (deterministic, post-integrator), which parses `passes/*.md` via a shared `parse-findings.py` core and injects the field into the snapshot. No LLM writes it.
- **Retire**: the reconciler's `reconciled/{persona}-passes.json`; the integrator's `within_persona_runs` assembly (both modes) + self-re-derive fallback (`integrator.md:44`) + inline hand-parse (`~60,280`). The reconciler keeps `reconciled/{persona}.md` (unchanged, still `(k/N)`-tagged); the integrator keeps `findings[]`/severity/verdict (unchanged — D5 deferred).
- Rejected: personas emit a structured-JSON tail. Not because the markdown is "already enforced" (it is NOT — the parser handles real variance, see C-parser) but because a tail is a **second LLM-transcribed representation** — the exact root-cause class. A script parsing durable markdown is recoverable on failure; a corrupted tail is not.

### D2 — Provenance gate (honestly scoped)
`assemble-wpr.py` writes the field; `check-run-complete.py` recomputes `assemble-wpr` from `passes/*.md` and requires the snapshot field to **equal** it. **What this proves**: no LLM wrote the field (D1 guarantees that directly), and the field wasn't tampered/staled after assembly. It does **not** prove `assemble-wpr` is correct — the script is the new single point of failure, so it is **unit-tested against hand-labeled `passes/*.md` fixtures before it is load-bearing** (R-parser). Also:
- **Degraded-run contract** (v2 C3). A pass that errors/times out is a supported state. `record-dispatch.sh --pass i --failed` writes a mechanical failure stub + usage note. The gate consults it: a persona with a `--failed` pass is **excused** from the all-N-present requirement; `within_persona_runs[persona]` carries one sub-array per *successful* pass; `pass_support` denominators use successful-pass counts. **A bannered failure never blocks the usage.log line** — the gate marks the run degraded, not INCOMPLETE, when every gap has a failure stub.
- **Single-pass / unattended contract** (v2 I6). No `passes/` dir → `assemble-wpr` emits `within_persona_runs: null` and exits 0; the gate skips the provenance check for N=1 (null is valid). `finalize-run.sh` runs on every run, so this must be a no-op, not an error.
- Require all `{persona}-p[0-9]*.md` (glob the numbered pattern, **not** `*.md` — real dirs contain `CONSOLIDATED.md`, `pass2-summary.md`) present for every non-failed multiball persona.
- **Content-floor** `findings/*.md` AND `passes/*.md`: each must parse to ≥1 finding or be a `No findings.`/`None.`-only stub (which maps to an empty array, not a parse error).
- **Element-level structure check, version-independent** (v2 fixture-vs-backcompat contradiction): reject a `within_persona_runs` whose pass elements are not `{severity,title,file}` objects — applied to v<3 too, so the 3 broken id-ref snapshots are rejected by `--all` audits (they currently pass the shape check). Ship them as gate fixtures.
- **Gate robustness**: `check-run-complete.py` now imports `parse-findings` and can raise on malformed content; catch it and emit a distinct `provenance-uncomputable` failure (naming the parser) so a parser bug never aborts finalize and silently drops a valid run from the usage.log index.

### C-parser — `parse-findings.py` built against the real corpus (v2 C2)
The persona output format is **not** rigid in the wild `[ran: passes/*.md across ~29 runs]`: canonical `#### Critical`; bare `CRITICAL:`/`Important:` labels; `## [X] pass i` headers (not `Review`); prose paraphrases with no bold titles/effort; en-dash ranges; parenthetical secondary coords. So:
- The parser handles the **observed** formats (severity keyed on the `#### {sev}` prefix OR a bare `{SEV}:`/`{Sev}:` line-start, never the parenthetical label which is mode-dependent).
- **Strict-consume**: any non-blank line not consumed by a recognized finding/section is an error — so a nonconforming pass fails **loud**, never silently to an empty array (the silent-empty hole).
- **Capture-time validation**: `record-dispatch.sh --pass` runs the parser and **rejects the write on a strict-consume failure**, so a bad pass fails immediately (cheap single re-dispatch) instead of failing the whole run at finalize hours later. This also makes the format contract mechanically enforced for the first time.
- **Pre-cutover gate** (deliverable, not just a falsifier): parser must hit **≥95% field accuracy against a hand-labeled sample of the existing corpus** before capture-time rejection is enabled. Ship the corpus as golden fixtures. A test pins the SKILL.md/persona output-format spec to the parser so the next prompt tweak can't silently break assembly.

### D3 — rid, pass_support, model (post-integrator, single-phase)
- **rid**: match each pass finding of persona P to the reconciled `F` where `P ∈ F.personas` and file/line proximity holds (constrained by the integrator's own attribution → inherits its semantic identity). **Closest-line tiebreaker** when two same-persona findings map to one `F`; **absence findings (file=null)** match by title-token similarity (same threshold `finding_match` uses, stated, not left to R2). A pass finding matching no `F` (reconciler-dropped) gets `rid=null` and contributes 0 to pass_support — `pass_support` counts support among *surviving* findings.
- **pass_support**: per reconciled finding, distinct passes carrying its rid. Computed here (currently null on every finding while it drives Critical anchoring). Since D5 is deferred, the integrator's verdict still uses the reconciler's `(k/N)` tags as today; `pass_support` in the snapshot is now *also* mechanically correct for downstream tooling.
- **model**: **stamped into the pass file at capture** — `record-dispatch.sh --pass` already receives `<model>` as an argument, so it writes a `model:` header into `passes/{persona}-p{i}.md`. This **deletes** v2's fragile name-keyed join to `usage.json.totals.personas[]` (ambiguous under the lapse-ladder when a persona's passes ran on different models; empty on some runs).

### D4 — High-N calibration cadence
Scripted N≥5 run on a **frozen external target** (fixed repo + commit) for recall-curve + overlap estimation. Needs an explicit `--calibration` carve-out permitting multiball + the assembly path unattended (standing policy is single-pass; `unattended.md` currently hard-fails on `--multiball` — **this file is in the edit map**, D4 is unimplementable without it). Cost `~7–8M tokens/data point` `[recalled — derive before scheduling]` (>$50, surfaced per cost-consciousness). Lowest priority; the 23 existing snapshots already yield N=2 data.

### D5-audit — severity-by-corroboration: measure, don't move (the boxed decision)
The k/N severity decision stays with the LLM (reconciler/integrator), unchanged. But `assemble-wpr.py` already computes `pass_support` mechanically (D3), so for near-zero cost it **also computes the severity the k/N rule *would* assign and records a drift note** whenever the reconciler's actual severity disagrees. Output: a per-run `severity_drift` list in the assembled record (`{finding_id, reconciler_severity, rule_severity, k, N}`) — **advisory, never a gate failure** (the LLM's rule-22 judgment legitimately overrides the mechanical rule; disagreement is data, not error). This gives a determinism *check* — how often, and in which direction, the LLM deviates from the rule — with none of D5's cost. If the audit accrues evidence that the drift is large or biased, that is the trigger to promote D5 (Appendix A) with data instead of a hunch. `mine-runs.py` reads the drift list at retro.

## File-by-file edit map (exhaustive — v2 flagged omissions)

| File | Change |
|---|---|
| `scripts/parse-findings.py` | **NEW** — pure md→`[{severity,title,file,line}]`; strict-consume; handles observed formats; reuses `finding_match.norm_file`/`extract_line`. |
| `scripts/assemble-wpr.py` | **NEW** — post-integrator: parse `passes/*.md`, stamp rid, compute pass_support, inject `within_persona_runs`+`pass_support` into the snapshot, emit provenance record + `severity_drift` audit list (D5-audit). Single-pass → `null`, exit 0. |
| `scripts/record-dispatch.sh` | Add `--pass i` (writes `passes/{name}-p{i}.md`, runs capture-time parser, refuses `persona`-phase without `--pass` when MULTIBALL marker present); `--failed` (failure stub); `--verdict` (writes `verification/{id}.json`, folding the verifier hand-write into the chokepoint); `model:` header in the pass file. `--findings` only with `--pass 1`. |
| `scripts/check-run-complete.py` | `within_persona_runs_ok` → provenance check (== assemble-wpr output) + element-level dict check (version-independent) + all-`{persona}-p[i]` present (excusing `--failed`) + content-floor + `provenance-uncomputable` catch. |
| `scripts/finalize-run.sh` | **Reorder**: `assemble-wpr` (inject field) → `aggregate-usage` (reads counts, must follow) → `check-run-complete` (gate) → `append-usage-log` (now AFTER the gate, so a fail blocks it) → `emit-dispositions-skeleton`. Distinguish gate-fail (alert + no append) from degraded (append, note). |
| `integrator.md` | Delete Phase-1 `within_persona_runs` persistence (both modes), the hierarchical `{persona}-passes.json` read (line ~44 step 2, not just the fallback), the inline hand-parse (~60,280). Bump snapshot `version` 2→3. Severity/verdict/`(k/N)`-tag logic UNCHANGED (D5 deferred). |
| `reconciler.md` | Delete output #2 (`reconciled/{persona}-passes.json`) only. Rules 20–22, 25, and the `(k/N)` output template (line 37) UNCHANGED (D5 deferred). |
| `SKILL.md` | §4: pass writes via `record-dispatch.sh --pass` (mechanical, mode-independent). §5 `reconciled_views` block (line ~580): strike `+ one {persona}-passes.json …`; the integrator reads only `reconciled/{persona}.md`; assembly is scripted post-integrator. §5.7 step 3: verifier verdict write via `record-dispatch.sh --verdict`. §7.8/§8c: gate is provenance; artifact list drops `reconciled/{persona}-passes.json`. |
| `unattended.md` | Single-pass contract for `assemble-wpr` (null, no-op); the `--calibration` carve-out (D4) if adopted; remove `--multiball` from "Unsupported" only under `--calibration`. |
| `scripts/resume-run.sh` | Drop `reconciled/{persona}-passes.json` from the artifact list; add the assembled-field/provenance phase. |
| `scripts/aggregate-usage.py`, `scripts/mine-runs.py` | Version 2→3 awareness (consume the new snapshot; no behavior change required beyond tolerating v3). |
| `docs/decisions/12-*-DRAFT.md`, `…-v2` | Already removed / this file supersedes. |

## What's retired (net simplification)
Reconciler JSON output; integrator wpr assembly (both modes); integrator self-re-derive fallback; v2's fragile model join (replaced by capture-time stamp); v2's systemic-identical alarm (subsumed by provenance). Net: **two LLM transcription steps and one fallback removed**, one deterministic post-integrator script added, no circular dependency, severity/verdict path untouched.

## Backward compatibility
3 broken snapshots stay on disk, skipped by the shape-guard (shipped) and rejected by the version-independent element check as gate fixtures. The 23 valid snapshots remain analyzable (shape-checked; provenance applies to v3 going forward). Snapshot `version` 2→3; the gate applies strict provenance equality only when versions match, else shape+element check with a `provenance-era mismatch` note — so a future `parse-findings` change doesn't retroactively flip old v3 runs to INCOMPLETE (v2 parser-version-skew finding).

## Confidence / falsifiers (observable this time)
- Claim: single-phase post-integrator assembly removes the circular dependency. Tier: read-the-code. Confidence 0.9. Falsifier: a step in the flow that requires the integrator to consume `assemble-wpr` output — there is none once D5 is deferred.
- Claim: capture-time strict-consume parsing prevents silent-empty corruption. Tier: read-the-code. Confidence 0.85. Could-be-wrong-if the parser accuracy on the corpus is <95% (measured, pre-cutover). Falsifier: a hand-labeled corpus finding the parser drops or misclassifies above the threshold.
- Claim: the provenance gate + D1 together guarantee no LLM-authored `within_persona_runs`. Tier: read-the-code. Confidence 0.9. Falsifier: a gate-passing v3 snapshot whose field omits a finding present verbatim in `passes/*.md` (would mean the script, not an LLM, is wrong — the unit-test target).

## Appendix A — the D5 two-phase design (only if you choose to keep D5)
Split `assemble-wpr.py`: **Phase A** (post-reconciler, pre-integrator; new SKILL.md §5 step): parse passes, within-persona k/N match, apply promote/demote from a *per-finding base severity + a reconciler-emitted `promote_ok` quality flag* (preserving rule 22's promote-veto as data), compute per-persona pass_support; hand the integrator adjusted severity + pass_support. **Phase B** (post-integrator, as in D3): rid, cross-persona pass_support, provenance. Findings carry `base_severity` and `severity`; the §5.7 verify_queue and CONFIRMED→`CHANGES REQUIRED` upgrade key on `base_severity` so a mechanically-demoted singleton Critical still gets verified and can still flip the verdict. Per-persona-adjust-then-merge-max; at N=2, k=1 demotes (demote wins the ⌈N/2⌉ tie). This is more moving parts than the deferred design — hence the recommendation to defer.
