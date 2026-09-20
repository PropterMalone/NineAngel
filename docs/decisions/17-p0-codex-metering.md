---
id: 17-p0-codex-metering
name: P0 — codex leg dispatcher, backend-partitioned metering, token-kind determination
date: 2026-08-18
status: accepted
amends: ADR-12 (usage.jsonl gains an optional `backend` field, still single-writer)
supersedes: null
commits: []
---

# ADR-17 — P0 of the v2 backend-portable battery

> **Amended by ADR-20 (2026-08-30).** Reducer usage is recorded in the backward-compatible
> `integrator` phase with typed initial/peak-context and runner fields when measured. Those
> context measurements are not cumulative spend tokens and remain distinct from persona-leg
> backend accounting.

**Decision**: Ship P0 of `docs/v2-backend-routing.md`: `scripts/dispatch-leg.sh` (headless codex leg adapter, all durable writes through `record-dispatch.sh`), an optional `--backend` field on the usage line, backend-partitioned aggregation (`totals.by_backend`), requested-vs-ran model capture, and the token-kind determination. Implementation by Codex (gpt-5.6) against the rev-2 spec; review, hardening, and falsifier runs by Claude.

**Why**: the 08-16/17 improvised codex batteries ran 36 legs each with zero token capture. P0 makes the codex path metered, attributable, and honest about what its numbers mean before any routing decision leans on them.

## Falsifier runs (ADR-14 rule: commands run on ship day, output pasted)

**Backward run (status quo)**: both 08-16/17 run dirs' usage.jsonl: all `total_tokens: null`, no `backend` field — the status quo does not already pass.

**Live leg** (scratch run dir, `--experiment` tombstoned):

```
printf '<structured-review prompt>' | scripts/dispatch-leg.sh --run-dir "$RUN_DIR" \
  --phase persona --name adv --model gpt-5.6-sol --pass 1 --findings --note "P0 falsifier leg"
```

produced (verbatim):

```json
{"phase":"persona","name":"adv","model":"gpt-5.6-sol","total_tokens":2969,"tool_uses":null,"duration_ms":5937,"started_at":"2026-08-18T19:14:51Z","ended_at":"2026-08-18T19:14:56Z","reader_pack":false,"note":"P0 falsifier leg; requested=gpt-5.6-sol|ran=gpt-5.6-sol","backend":"codex"}
```

Non-null tokens ✓, `backend:"codex"` ✓, requested=ran verified against the rollout ✓, model-stamped pass file written by the chokepoint ✓.

**Kind determination** (the load-bearing falsifier — the v2 doc's claim 2 predicted "comparable in kind"; it was **falsified**):

```
falsifier leg rollout:  total_tokens=13,977  cached_input=11,008  → 13,977−11,008 = 2,969  (printed: 2,969)
hook-parity rollout:    total_tokens=227,814 cached_input=192,256 → 227,814−192,256 = 35,558 (printed: 35,558)
29-turn comparison job: cumulative-uncached 176,182 vs peak single-turn context 148,386 — kinds diverge
```

**Finding**: codex's `tokens used` = **cumulative uncached tokens** (total − cached input across all turns). Agent-tool totals are **peak single-turn context** (ADR-14). The two are different kinds and are never summed or compared across meters; `totals.by_backend` keeps them separate and each backend's `meter` implies its kind.

## Hardening applied post-implementation

1. **`CODEX_BIN` pin.** The implementation resolved `codex` via PATH; on the host, `~/.local/bin` is absent from non-login shells (Claude Code bash, cron), so bare resolution finds nothing — and a stale `/usr/bin/codex` has burned a plan before (kodex memory, 0.118). `dispatch-leg.sh` now pins `${CODEX_BIN:-$HOME/.local/bin/codex}` with an executability check; tests shim via `CODEX_BIN`, not PATH.
2. **Stdin discipline.** `codex exec` appends piped stdin to its prompt and will wait forever on an open fd — a background dispatch wedged 93 minutes pre-flight this way (error-log 2026-08-18, second entry). `dispatch-leg.sh` reads its prompt to EOF first and invokes codex with `</dev/null`.

## Deliberately out of this ADR

- The **minimal codex-side guard set** (v2 doc §2.3): requires either editing the global `~/.codex/hooks.json` (touches the user's interactive Kodex sessions) or an ephemeral-CODEX_HOME scheme — surfaced to the user as its own decision rather than shipped silently. `rails_ported` stays `false`; no codex-inclusive posture is activatable.
- P1 (tier indirection, resolver, validate-personas tier vocabulary).

## Falsifier for this ADR's own claim

The token-kind identity (printed `tokens used` == `total_tokens − cached_input_tokens` in the leg's rollout) is re-checkable on any leg: `dispatch-leg.sh` records the printed figure; the rollout holds the components. If a future codex CLI breaks the identity by >1 token, this ADR's kind classification is stale and `codex-exec-parse`'s kind must be re-determined before any cross-backend report is trusted.
