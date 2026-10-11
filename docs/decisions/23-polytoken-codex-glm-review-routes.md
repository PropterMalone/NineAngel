# ADR-23 — Polytoken review routes: ChatGPT/Codex + Z.ai/GLM

**Status:** Adopted for the Polytoken Angel port, 2026-09-24. The canonical Claude Code orchestrator's Codex persona and reducer roles also moved to GPT-6 Sol; its Claude/Codex family topology, historical run artifacts, and ADR-18 semantics are not rewritten retroactively.

## Allocation amendment — 2026-10-09

the user selected Codex-first default reviews after reporting Z.ai subscription limits and returning OpenAI to $200/month. ADR-24 amends only this port's default allocation: Codex for every selected persona, GLM only for explicitly selected checks. The paired topology below remains available through an explicit cross-family request; it is no longer the default. The canonical Claude Code orchestrator is unchanged. See `24-codex-first-polytoken-allocation.md` and the separately installed external adapter's `references/run-protocol.md` resource. That adapter resource is not a local file shipped in this canonical repository.

## Decision (paired topology; allocation amended above)

Explicitly paired Polytoken-driven Angel reviews dispatch selected personas through two separate blind, read-only subagents:

1. `angel-codex-reviewer` pinned to `codex/gpt-6-sol(high)` through the ChatGPT-authenticated Codex provider;
2. `angel-glm-reviewer` pinned to `zai/glm-5.3(high)` through the Z.ai provider.

The two definitions are separate. They are not candidates in one model group and neither has a fallback model. This guarantees that successful two-leg coverage represents two provider families rather than two successful invocations after failover onto one provider.

## Why

Anthropic capacity is scarce and Opus 5.5 is reserved for writing and artifact editing. Fable is off-menu. The existing OpenAI and Z.ai subscriptions provide separately routed review capacity, while the model-family split preserves the independent-blind-review purpose of heterogeneous Angel.

## Guardrails

- Both routes must use existing subscription entitlements: ChatGPT device authentication for Codex and the Z.ai Coding Plan for GLM. Metered API spend and API-credit purchases are forbidden; a route that cannot prove subscription-backed access fails closed.
- Each leaf receives only its persona path, target or bounded diff, constraints, and necessary authority paths. It never receives the parent conversation or another pass's output.
- Each leaf exposes only `file_read`, `glob`, and `grep`; it cannot edit, execute shell commands, message, commit, publish, or spawn another subagent.
- Every pass records persona, provider family, requested model, observed model when exposed, and target. An unobserved actual model remains `unobserved`, not inferred from the requested route.
- A failed leg is recorded and never replaced by the surviving family or a fallback model.
- A review whose target is under `~/private/legal/` remains Codex-only. Omit the GLM leg for that directory by policy and label that review single-family.
- Integration begins only after both blind passes finish and preserves provider-specific catches and disagreements.

## Compatibility boundary

This decision governs the Polytoken port at `~/.agents/skills/angel/` and the user-wide subagents under `~/.config/polytoken/subagents/`. The canonical Claude Code implementation still has a Codex-specific durable adapter and historical Claude/Codex telemetry. Its ordinary persona leg and semantic reducer now pin GPT-6 Sol; the reducer remains fingerprint- and qualification-bound to GPT-6 Sol plus Codex CLI 0.155.1. This deliberately starts a new calibration era rather than preserving GPT-5.6 Sol continuity. The live admission probe and reducer suite are required after the model change. Migrating the legacy implementation's second family from Claude to GLM still requires extending its adapter and provenance contracts; documentation must not pretend those code changes have already shipped.

## Validation

Before use:

1. run `polytoken config validate`;
2. run `polytoken validate subagent` on both definitions;
3. run the canonical persona registry validator;
4. smoke-test one tiny blind read-only prompt through each exact pinned model route without running a full Angel battery.
