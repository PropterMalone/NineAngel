---
id: 24-codex-first-polytoken-allocation
name: Codex-first allocation for Polytoken Angel
date: 2026-10-09
status: draft
until: null
amends: 23-polytoken-codex-glm-review-routes
supersedes: null
commits: []
depends_on: []
falsifier_cmd:
  - label: Allocation and existing record-boundary regressions
    cmd: if [ -z "${EXTERNAL_ANGEL_ADAPTER:-}" ] || [ ! -f "${EXTERNAL_ANGEL_ADAPTER}/scripts/test_subscription_policy.py" ]; then printf '%s\n' 'Validation unavailable; separately installed external adapter required' >&2; exit 2; fi; python3 -m unittest discover -s "${EXTERNAL_ANGEL_ADAPTER}/scripts" -p test_subscription_policy.py
applies_to:
  - ${EXTERNAL_ANGEL_ADAPTER}/**
---

# Codex-first allocation for Polytoken Angel

## Public snapshot dependency note

The allocation falsifier requires a separately installed external adapter, not shipped in this canonical repository. Set the required `${EXTERNAL_ANGEL_ADAPTER}` variable to its root containing `scripts/test_subscription_policy.py`. An absent variable or dependency makes validation unavailable (exit 2), not a pass or failure finding. The evaluated-by and status-quo results below are historical private adapter evidence, not publicly reproducible from this snapshot. No canonical test substitutes for that adapter check.

**Decision:** the user selected Codex-first default persona reviews on 2026-10-09, reserving GLM for explicitly selected checks. This allocation is adopted; formal ADR status remains draft pending a fresh-context reader.

**Why:** the user reports Z.ai subscription limits and previously wrote “moved back to $200/mo OAI” (a private owner instruction). Subscription-only/no-metered-spend authority remains `~/.claude/CLAUDE.md`; prices are not quota ratios.

**Rejected alternative:** Pair every persona but serialize GLM. That spreads bursts without reducing total Z.ai review calls.

**How to apply:** The live adapter owns instructions, selection examples and quota handling. `--full` controls breadth, not providers; `--cross-family` pairs all selected personas; `--glm-personas` pairs only named selected personas. One GLM pass at a time; stop further GLM dispatch on quota. Persist unselected lanes as allocation omissions. Never replace GLM with Codex and claim two families.

**Coverage boundary:** Keep the existing helper/schema/calibration and historical evidence unchanged. Unpaired output stays coverage-degraded with an unranked incomplete report. The workflow forbids automatic fixes without reconciled full cross-family coverage, even when the helper returns verified IDs from a degraded record. This is an orchestration rule, not a new runtime interceptor.

**Could-be-wrong-if:** The allocation tests fail, an ordinary invocation dispatches any GLM lane without explicit selection, or an unpaired run triggers an automatic fix. The tests check instruction anchors and offline records, not live orchestration compliance or review-quality equivalence. Revisit utility with the user if incomplete-only default delivery proves unhelpful; do not silently weaken coverage.

**Evaluated by:** `[ran 2026-10-09]` the command above exited 0 twice (once within full discovery of 112 tests and once as the focused three-test run); both printed `OK`. Source/installed skill, config, both reviewer definitions, persona22/22 and whitespace validators also passed.

**Status quo check:** `[ran 2026-10-09]` before instruction changes, the same three-test command exited 1 with two policy failures; the offline omission/report fixture passed. The test distinguishes old from selected allocation without changing production helpers. No provider calls or quality-equivalence measurements were made.
