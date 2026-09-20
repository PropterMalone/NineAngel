# NineAngel v2 — backend-portable battery

**Date**: 2026-08-18 · **Status**: DRAFT rev 2 — post-/angel revision (run `20260818T135606Z-77138fd0`, verdict CHANGES REQUIRED: 1C/21I applied — see `dispositions.json` there). SKILL.md is unchanged until this is accepted.
**Author**: Claude (Fable 5 driver session), directed by the user

> **Synthesis route amended by ADR-20 (2026-08-30).** The `synthesis-1m` vendor-first
> chains below are design history, not the reducer-era acting route. Integration now selects
> a qualified isolated structured-output runner by capability and context budget, with no
> agentic or inline fallback; deterministic union is the terminal route.
**Convention**: unqualified `§N` means this document's own sections; sections of the skill spec are always written `SKILL.md §N`.

**Terms** (for readers outside the project): *NineAngel* is a multi-persona code-review battery. A **persona** is a reviewer role with its own mandate file (22 exist: adversarial, hypercritical, data-integrity, …). A **battery** is the set of personas dispatched for one review run. A **leg** (or **pass**) is one subagent dispatch of one persona; **multiball** runs each persona N≥2 independent times because a single pass captures only ~40% of a persona's findings. **SKILL.md** is the orchestrator's instruction file — currently also the place where every persona's model assignment is hardcoded, which is the problem this design fixes.

## 1. Problem

Three forcing facts, one requirement.

1. **Model assignment is doctrine text.** Concrete model IDs are hardcoded in at least **eight** places — this list said "four" until ADR-19's retirement had to touch every one of them, which is itself the evidence for this fact: the SKILL.md §1 persona table, the depth-lane ladder (ADR-07, made standing by ADR-19), the integrator ladder (ADR-11, flattened by ADR-19, partially superseding docs/decisions/04), the standard-profile demotion note, **the reader dispatch (SKILL.md §3.5), the §5.7 verifier tier (ADR-08), and unattended.md's parallel persona table and integrator line** — the last of which is a second full copy of the first, kept in sync only by `validate-personas.py`. Allocation changes keep leaving scar tissue as scattered text rather than config edits: in SKILL.md itself, the 07-02 lapse ladder and the 07-21 driver-doctrine reframing bracket; outside it, the equivalent history lives in CLAUDE.md's model section and — for the newest change — in improvised run-dir markers (fact 2). Model history is recorded wherever there happened to be room, because no config file owns it.
2. **The cross-backend battery already happened — twice, unmeasured.** The 2026-08-16 and 08-17 a private target runs each wrote an improvised backend marker (`gpt-only` and `codex` respectively — two runs, two vocabularies) and ran every persona, reconciler, and verifier leg on `gpt-5.6-sol` via hand-rolled dispatch: 36 legs per run, all logged `total_tokens: null` `[ran: usage.jsonl in both run dirs]`. The findings pipeline — pass files, Stage-1 reconciliation, integrator, verification, report — worked end to end on a non-Claude backend. What's missing is not capability; it's specification (tier mapping, stagger policy, failure handling) and measurement (zero token capture on that path).
3. **The battery is the spend that matters.** 264 of 322 logged Fable *subagent dispatches* (82%) are angel legs `[ran: fable-tier-log.jsonl 2026-08-18]` — driver-mode Fable usage never enters that log, so this scopes the subagent share only; corroborate against the usage meter before treating it as total-spend share. Caveat per ADR-14: `usage.log` `total:` figures are peak-context high-water marks, not spend. Anthropic-side cost is cache-traffic-dominated (writes ~33% / reads ~41% / output ~25%), so optimization must target *dispatch structure and backend placement*, not just raw token counts.

**Requirement (the user, 2026-08-18):** (a) portable off Claude; (b) smarter about token use; (c) smarter about model choice; (d) **resilient to future subscription-allocation changes — generalizable to the extent possible.** Subscription states will keep changing. The design must absorb those changes in config, never in doctrine.

## 2. Design

### 2.1 Capability tiers, not model names — with a named escape hatch

Personas and pipeline roles stop naming models. They name **capability tiers**, which the tier principle (ADR-07) already defines conceptually:

| Tier | What it buys | Current occupants |
|---|---|---|
| `depth` | completed causal chains, contract-tracing | thousand, data-int, future, test, coach, blindspot, rigor, deanon, heir, recip |
| `volume` | high-stability bug-catching | adv, hyper, user, perf, rtfm, editor, install, penny, caritas |
| `breadth` | cheapest coverage | naive, fresh, pii |
| `synthesis-1m` | large-window load-bearing synthesis | integrator |
| `mechanical` | within-lane comparison, no discovery | reconcilers |
| `verify-deep` / `verify-cheap` | adversarial verification | verifiers (critical / other) |

SKILL.md's prose references tiers only; the SKILL.md §1 table's "Model" column becomes a "Tier" column. **Two existing rules are persona-specific, not tier-general, and the schema must express them rather than silently drop them**: (1) the lapse ladder demotes depth-tier personas to Opus *except `test`*, which goes to Sonnet (Opus-test ≈ sonnet-test at ~5× cost, eval leg 3); (2) the standard profile demotes *only* `future` and `test`. Both live in `persona_overrides` (§2.2). The lapse ladder, integrator ladder, and profile demotions otherwise become fallback chains in config.

**Two flag/tool consequences are in P1's scope, not left implicit:**
- `--model-override` currently takes literal model-family names. Under v2 it is redefined: the legacy values (`sonnet|opus|fable`; `haiku` was dropped by ADR-21) remain valid aliases resolving to the corresponding `claude-agent` model entries; the flag forces every persona's resolution to that entry, bypassing posture chains (integrator unaffected, as today). The P1 falsifier exercises this path explicitly.
- `validate-personas.py` detects the model table by its literal `Model` header and greps for model-family names — the rename silently disables it, and it is a **pre-commit gate** `[ran: verifier f9 — parse_rows() on a post-rename table returns zero rows, zero errors]`. P1's scope includes teaching it the tier vocabulary and cross-checking against `routing.toml`.

### 2.2 The routing config

One file, `routing.toml`, in the skill root. **The example below shows the P1 state — behavior-neutral, reproducing today's assignments exactly.** End-state postures for later phases follow it, clearly marked. Resolution rule: walk the tier's chain; first backend whose adapter is registered *and* available wins; **a chain entry naming an unregistered adapter is a loud resolution error, never a silent skip**. The posture resolved at `init-run.sh` is snapshotted into the run dir and **is authoritative for every dispatch of that run, including resume and retry** — re-resolution happens only at run init, so a mid-day posture edit affects the next run, and a resumed pass can never land on a different model family than its siblings (which would leak the cross-family multiball that §2.6 gates).

```toml
# --- backends: how to reach each execution surface ---
[backends.claude-agent]
adapter = "agent"            # in-session Agent tool (current path); orchestrator-inline —
                             # availability is attempt-then-fallback (ADR-04/11 pattern),
                             # unlike the shell adapters, which are probe-then-choose
models  = { depth = "claude-fable-5[1m]", volume = "claude-sonnet-5[1m]", breadth = "claude-sonnet-5[1m]", mechanical = "claude-sonnet-5[1m]", verify-deep = "claude-fable-5[1m]", verify-cheap = "claude-sonnet-5[1m]", synth-primary = "claude-fable-5[1m]", synth-fallback = "claude-opus-4-8[1m]" }
meter   = "agent-usage-block"
cache   = { prefix = true, ttl_s = 300 }   # drives Phase A/B stagger

[backends.codex]
adapter = "codex-exec"       # ~/.local/bin/codex exec, headless
models  = { depth = "gpt-5.6-luna", volume = "gpt-5.6-sol", breadth = "gpt-5.6-sol", mechanical = "gpt-5.6-sol", verify-deep = "gpt-5.6-luna", verify-cheap = "gpt-5.6-sol" }
meter   = "codex-exec-parse" # parse `tokens used` + session jsonl (§2.4)
cache   = { prefix = false } # unknown through exec; treat as cold until measured
sandbox = "none"             # semantic value; adapter maps to codex's danger-full-access
                             # (bwrap broken on the host — error-log 2026-08-18)
trust_hooks = false          # semantic value; adapter owns the CLI flag string
rails_ported = false         # posture activation MUST refuse any posture whose chains
                             # include this backend for persona/verifier tiers while false
                             # (guard hooks not yet ported — §3 P0 note)

[backends.agy]               # Gemini free tier ($0) — existing xreview backend
adapter = "agy"
model   = "gemini"           # single-model adapter: one model, no per-tier map (schema
cache   = { prefix = false } # allows scalar `model` for such backends)

[backends.ollama]            # local, $0 — schema completeness only: NO phase ships this
adapter = "ollama"           # adapter yet, and no posture below references it. It enters
model   = "local"            # a chain only when a phase builds and verifies it.

# --- persona_overrides: the two rules that are persona-specific, not tier-general ---
[persona_overrides]
lapse    = { test = "volume" }             # Fable lapse: test -> Sonnet, not Opus (leg 3)
standard = { future = "volume", test = "volume" }   # standard-profile demotion (SKILL.md §1)

# --- postures: named allocation states. THE ONLY THING THAT CHANGES when
# subscriptions change. Names are allocation-shaped (abundant/balanced/scarce),
# never vendor-shaped.
[postures.abundant]          # P1 POSTURE — behavior-neutral, reproduces today exactly
depth        = ["claude-agent"]
volume       = ["claude-agent"]
breadth      = ["claude-agent"]
synthesis-1m = ["claude-agent", "inline"]  # adapter implements ADR-11's size-dependent
                             # ladder over this backend's synth-primary/synth-fallback
                             # models (big bundle: fallback-first; small: primary-first),
                             # with "inline" as the terminal rung. The ladder ALGORITHM
                             # stays in the orchestrator; config names the models only.
mechanical   = ["claude-agent"]
verify-deep  = ["claude-agent"]            # same-family, as today (cross-family verify is
verify-cheap = ["claude-agent"]            # experiment-gated — §2.6, P4)

# --- END-STATE postures (P2+ targets, illustrative; NOT activatable until their
# backends' adapters exist AND rails_ported = true where required, and the
# cross-family entries stay claude-first until the §2.6/P4 gate passes) ---
[postures.balanced]          # e.g. an even two-vendor split
depth        = ["claude-agent", "codex"]
volume       = ["codex", "claude-agent"]
breadth      = ["agy", "codex"]
synthesis-1m = ["claude-agent", "codex", "inline"]  # codex rung pending open question 4
mechanical   = ["codex", "agy"]
verify-deep  = ["claude-agent", "codex"]
verify-cheap = ["claude-agent", "agy"]

[postures.scarce]            # crunch: push everything off-meter that can be moved
depth        = ["codex", "agy"]
volume       = ["codex", "agy"]
breadth      = ["agy", "codex"]
synthesis-1m = ["claude-agent", "codex", "inline"]  # claude-first even in crunch — decision 2 below
mechanical   = ["codex", "agy"]
verify-deep  = ["codex", "claude-agent"]
verify-cheap = ["agy", "codex"]

# --- active: which posture is live right now ---
[active]
posture = "abundant"
```

Properties this buys:

- **A subscription change is a one-line edit** (`active.posture`) or one new posture block. Zero SKILL.md edits. This is the generalized, permanent form of the Fable-lapse ladder — which handled exactly one allocation transition and hardcoded both ends of it.
- **A future third vendor is one `[backends.*]` block plus chain entries**, nothing else.
- **Run reproducibility and resume safety**: the init-time posture snapshot in the run dir is authoritative for the whole run (above), formalizing and hardening the improvised backend markers of 08-16/17.
- Profile modifiers apply after posture resolution via `persona_overrides` — note this *generalizes* what today is a single deliberately-narrow row note in SKILL.md §1, which is new (small) work, not reuse of an existing layer.

### 2.3 The adapter layer

One dispatch contract, N adapters — with one stated asymmetry: `claude-agent` is orchestrator-inline (the Agent tool isn't shell-scriptable) and availability-checked by attempt-then-fallback; shell adapters are out-of-process, backgroundable, and probe-then-choose. Retry/timeout semantics are per-adapter, not shared.

- **`agent`** — the current path: orchestrator fires the Agent tool; usage from the `<usage>` block, as today.
- **`codex-exec`** — `scripts/dispatch-leg.sh` wraps `~/.local/bin/codex exec -m <model>` plus the sandbox/trust flags the adapter owns (§2.2 semantic values), prompt via stdin, backgroundable, parallelizable. Exit code 0 is not success `[ran: 2026-08-18 — a fully failed sandboxed run exited 0]`; success = the pass file exists and parses. **`dispatch-leg.sh` performs no durable bookkeeping writes itself**: it emits the leg's output block and parsed usage, and every `usage.jsonl` / `passes/` / `findings/` write routes through `record-dispatch.sh` (with `--pass I` under multiball) — the ADR-12 single-writer chokepoint, its capture-time parse check, and its MULTIBALL enforcement apply to codex legs exactly as to Agent legs.
- **`agy`** / **`ollama`** — same wrapper shape; agy exists in xreview.py today and gets extracted, not rewritten. (ollama: no phase ships it yet — §2.2.)

The findings contract — `## [Persona] Review` + severity sections, pass files, `parse-findings.py` — is already model-agnostic and untouched. That contract is *why* the 08-16/17 improvisation worked at all; v2 treats it as the stable interface.

**Guard rails during the migration (the P0–P4 window):** codex legs run with hook trust bypassed and no ported guard hooks — instructions in the composed prompt only. That is weaker than the Claude side and CLAUDE.md's safety model ("judgment + hooks") says so. P0 therefore ships the **minimal codex-side guard set** alongside the meter: a repo-scoped `.codex/hooks.json` (the mechanism proven live 2026-08-18 — one deny-path exercised) carrying at minimum a secret-scan-equivalent PostToolUse hook and the leaf-reviewer marker-deny canary, and `rails_ported` stays `false` — keeping codex out of activatable persona postures — until that set is exercised. Anything beyond the minimal set lands with the Kodex hook-port work (out of scope here).

### 2.4 Metering per backend

- **codex**: `codex exec` printed a `tokens used` total on all three observed runs, including one fully-failed one `[ran: 6,388 / 4,420 / 35,558 on 2026-08-18 dispatches]`; the adapter parses it into `total_tokens`. Session rollout JSONLs under `~/.codex/sessions/` carry richer per-turn data — mine opportunistically, don't block on it.
- **Kind determination — RESOLVED 2026-08-18 (P0 falsifier, ADR-17).** codex's `tokens used` = **cumulative uncached tokens** (`total_token_usage.total_tokens − cached_input_tokens`), verified exact on two rollouts `[ran: 13,977−11,008=2,969; 227,814−192,256=35,558]`. Agent-tool totals are *peak single-turn context* (ADR-14). **The kinds differ** (on a 29-turn job: peak 148k vs uncached-cumulative 176k) and must never be compared or summed across meters. `by_backend` keeps sums separate; each `meter` value implies its kind (`agent-usage-block` → peak-context; `codex-exec-parse` → cumulative-uncached, the more billing-like measure).
- **Model identity, requested vs ran.** SKILL.md's `requested=|ran=` discipline exists because a silent model swap was *observed* (2026-07-01). Every adapter logs the requested model and the backend's own claimed model (codex session JSONL's model field; agy response metadata; Agent tool per current practice); mismatches get a note in the usage line. This lands **before eval leg 4**, whose calibration data is worthless if a provider silently downgraded mid-benchmark.
- **usage.jsonl schema**: add `"backend"` per line (ADR-12-compatible addition — the write still goes through `record-dispatch.sh`).
- **Cross-backend totals never sum — and the components that sum today are named**: `scripts/aggregate-usage.py` currently computes `total_tokens = sum(measured)` with no backend partitioning, and `append-usage-log.sh` prints that as the canonical `total:` `[ran: verifier f7 — synthetic 10k claude + 90k codex aggregated to 100000, and phase_record drops the backend key]`. P0's scope includes: backend-partitioned aggregation (`totals.by_backend`), per-entry `backend` preserved in `usage.json`, and — for mixed-backend runs — the usage.log line's `total:` carrying the Anthropic-side sum only plus a `backends:` bag key (`backends:codex=…,agy=…`); single-backend runs unchanged. `true-cost.py` grows per-backend weights on the same data.

### 2.5 Cache-awareness per backend

The Phase A/B multiball stagger and shared-prefix ordering exist to exploit Anthropic's ~5-min prompt cache. That logic becomes an adapter property (`cache.prefix`):

- `claude-agent`: stagger ON, as today.
- `codex-exec`: **stagger OFF until measured** — each exec is a fresh session and prefix-cache behavior through the CLI is unverified; staggering costs ~2× wall and buys nothing if the cache doesn't apply.
- `agy`/`ollama`: stagger OFF.

Reader/slicer stays retired per docs/decisions/01. One amendment to its *reopening clause*, not its verdict: decision 01's verdict rests on near-zero slicing gains (bundles ≈ inline size) — cache-invariant, so it holds on any backend. But a *re-implemented* slicer's payoff calculation changes on cache-less metered backends where every leg pays full input; that consideration attaches to ADR-01's existing could-be-wrong-if (this is our inference about its economics, not ADR-01's own stated basis).

### 2.6 Model diversity as a design axis (both openings experiment-gated)

Two openings. **Both** are gated behind eval leg 4 — neither ships as a default in any activatable posture until the gate passes:

1. **Cross-family multiball** (`--multiball-mix`): pass 1 and pass 2 of a persona on *different families*, reconciled as today. Rationale: cross-model catches are documented — 3 dispositioned real findings from the 07-19 run plus the 2026-06-27 De-Anon instance — and the structural blind-spot argument is SKILL.md §5.6 doctrine; the corpus evaluation is otherwise pending, so this is stated at that tier, not as "the corpus shows." **Gate**: ADR-07's stability data is per-model (Fable .95 pass-to-pass, Opus .78, gpt-5.6 **unknown**) and reconciliation semantics assume same-model resampling. Required first: seeded-benchmark leg 4 (gpt-5.6 tier recall + pass stability). The 08-16/17 a private target runs give preliminary in-the-wild data once their dispositions land.
2. **Cross-family verification**: verifiers are REFUTE-oriented; a different-family verifier shares fewer blind spots. Cheap to express as posture chains — but the `abundant` posture keeps same-family verification until the same leg-4 gate passes (the end-state postures show the intended direction).

`--cross` (SKILL.md §5.6) is unchanged for now. If cross-family multiball lands, `--cross`'s second-opinion axis partially folds into the battery; its refute-verdicts function is verifier-shaped and would migrate there. Decide at P4, on data.

### 2.7 Where the orchestrator lives

The orchestrator stays a Claude Code skill for now — the driver is the point of contact, the guard hooks live there, and the Agent tool is one of the adapters. After v2, everything backend-specific sits in `routing.toml` + adapter scripts, so the orchestrator becomes portable prompt-logic. A Kodex port is a P5 option, not part of this design — and its precondition is honestly stated: **a hook-parity mapping exists (16 hooks inventoried, one deny-path exercised live 2026-08-18; ports proposed, not exercised — see the matrix's own caveats)**, which is a survey, not a proven port. The design constraint honored throughout: **if the port makes one driver cheap and the other expensive, it is the wrong port** (kodex design principle).

### 2.8 What does NOT change

Persona specs and frontmatter; findings contracts and `parse-findings.py`; Stage-1 reconciler → integrator → verifier pipeline structure; run-dir schema (extended, never reshaped); profiles and the milestones-not-per-diff frequency doctrine; multiball N semantics (pending §2.6 evaluation); pii→deanon sequencing; caritas gating (ADR-15) and recip's artifact gate (SKILL.md §1, "Artifact gate for Recipient"); the reader retirement; every untrusted-content guard. (`validate-personas.py` DOES change — in P1's scope, §2.1.) The v2 surface is dispatch, routing, metering, and the two named tools.

## 3. Migration plan — each phase independently shippable, each with a runnable falsifier

Per ADR-14's amended rule: each falsifier command runs on its ship day with output pasted into the accepting ADR, **and is first run backward against the pre-change state to confirm the status quo doesn't already pass**.

- **P0 — meter and minimally guard the codex path.** `dispatch-leg.sh` (bookkeeping via `record-dispatch.sh`), `tokens used` parsing + `backend` field, backend-partitioned `aggregate-usage.py`, the token-kind determination (§2.4), requested-vs-ran capture, and the minimal codex-side guard set (§2.3). *Falsifier*: one codex leg dispatched; its usage.jsonl line (written by record-dispatch.sh) has non-null `total_tokens` + `backend:"codex"` + requested/ran fields; `usage.json` shows `totals.by_backend`; and the §2.4 kind determination is recorded with the comparison numbers pasted.
- **P1 — tier indirection, behavior-neutral.** `routing.toml` with the `abundant` posture + `persona_overrides`; SKILL.md model references → tier references; `validate-personas.py` taught the tier vocabulary; `--model-override` redefined (§2.1). Ships `scripts/resolve-routing.py --dump` (posture × profile → the resolved persona/role → backend.model map). *Falsifier*: `diff <(scripts/resolve-routing.py --posture abundant --profile full --dump | sort) tests/fixtures/expected-full-map.tsv` is empty — the fixture generated once from SKILL.md's current §1 table and hand-reviewed; repeat for `--profile standard` (exercises `persona_overrides`) and for `--model-override sonnet` (exercises the flag path). Deterministic, no battery runs commissioned.
- **P2 — formalize codex/agy adapters + the `balanced` posture, opt-in.** *Falsifier*: with `balanced` active on a scratch repo, a `--micro` run produces usage lines where every leg carries `backend` + model + non-null tokens, the resolved map matches the balanced fixture, and the codex canary hook denies its marker command (rails check).
- **P3 — eval leg 4**: seeded benchmark on gpt-5.6 tiers (recall, pass stability, false-positive lure resistance), on the requested-vs-ran instrumentation from P0. Sets the `balanced` chains on data instead of guesses. *Falsifier*: the leg-4 report exists with per-tier recall + stability tables and each benchmark leg's requested==ran verified.
- **P4 — diversity experiments**: `--multiball-mix` A/B vs same-model N=2; cross-family verify default; `--cross` fold-in decision. *Falsifier (pre-registered)*: adopt mixed-family defaults only if union recall ≥ same-model N=2 recall AND false-positive rate ≤ same-model + 2 points on the seeded benchmark.

## 4. Decisions of record (the user, 2026-08-18)

1. **Posture switching is manual + advisory.** One-line edit flips `active.posture`; every run prints its active posture; the orchestrator warns when the relevant quota window is low but never flips itself. Meter-driven auto-degrade is revisited only after the meter instrumentation has a reliability track record (per-run flapping + untrusted meter reads are the objections; the authoritative run snapshot already prevents mid-run yanks).
2. **Integrator stays claude-first in every posture, including `scarce`.** One load-bearing dispatch per run, worst historical failure mode (ADR-11 stalls); the codex rung is fallback only. Revisit at leg 4.
3. **Unattended (`claude -p`) runs follow `active` until leg 4 lands**, then flip to an off-Anthropic default with quality data in hand — not before (single-pass runs on an unmeasured backend compound unknowns, and the codex rails land in P0).
4. **Eval leg 4 runs this week, immediately after P0.** The Claude baselines re-run cheap on the abundant window, and the codex legs double as the OpenAI-tier load test feeding the subscription-split decision.

## 5. Claims register (quality.md discipline)

- **Claim**: tier indirection + postures + `persona_overrides` absorb any subscription change short of a new modality (a vendor without a CLI, a per-token-only vendor). Confidence 0.85 (raised from 0.8 after the review hardened the schema against the two known override cases). Could-be-wrong-if: a future allocation constrains *within*-backend model mix in ways the chain + override schema can't express — concrete signal: a posture edit that requires touching SKILL.md anyway.
- **Claim (revised after its falsifier fired)**: the original claim — codex totals "comparable in kind" to Agent-tool totals — was **falsified 2026-08-18**: the kinds differ (cumulative-uncached vs peak-context, ADR-17). Revised claim: per-backend totals are individually meaningful and the schema keeps them un-compared (`by_backend`, per-meter kind). Confidence 0.9, `[ran: two-rollout verification]`. Could-be-wrong-if: a future codex CLI changes what `tokens used` reports — concrete signal: the ADR-17 identity (printed figure = total − cached) failing on a fresh leg.
- **Claim**: the 08-16/17 codex batteries demonstrate pipeline compatibility, not quality parity. Confidence 0.85 (lowered from 0.9: the two runs' improvised vocabularies — `gpt-only` vs `codex` — show the path was less uniform than first read). Compatibility evidenced by reports + snapshots `[ran: usage.log, both run dirs]`; quality parity explicitly unmeasured until dispositions + leg 4.
