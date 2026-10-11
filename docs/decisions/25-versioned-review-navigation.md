---
id: 25-versioned-review-navigation
name: Versioned review navigation without weakened coverage
date: 2026-10-11
status: draft
until: null
amends: 24-codex-first-polytoken-allocation
supersedes: null
commits: []
depends_on: []
falsifier_cmd:
  - label: Presentation and historical-read regressions
    cmd: if [ -z "${EXTERNAL_ANGEL_ADAPTER:-}" ] || [ ! -f "${EXTERNAL_ANGEL_ADAPTER}/scripts/test_presentation_v3.py" ]; then printf '%s\n' 'Validation unavailable; separately installed external adapter required' >&2; exit 2; fi; python3 -B -m unittest discover -s "${EXTERNAL_ANGEL_ADAPTER}/scripts" -p test_presentation_v3.py
  - label: Grounded battery selection regressions
    cmd: python3 -B scripts/test_battery_policy.py
applies_to:
  - ${EXTERNAL_ANGEL_ADAPTER}/**
  - SKILL.md
---

# Versioned review navigation without weakened coverage

## Public snapshot dependency note

The presentation falsifier requires a separately installed external adapter, not shipped in this canonical repository. Set the required `${EXTERNAL_ANGEL_ADAPTER}` variable to its root containing `scripts/test_presentation_v3.py`. An absent variable or dependency makes validation unavailable (exit 2), not a pass or failure finding. The battery falsifier runs locally from the canonical repository root as `python3 -B scripts/test_battery_policy.py`; it does not substitute for the adapter check. The finalized review record, adapter test results, and status-quo checks below are historical private evidence, not publicly reproducible from this snapshot.

**Decision:** the user selected contract-3 snapshot-derived decision navigation, strictly provisional triage for successful reconciled Codex-only allocation, early disclosure when requested outcomes need paired coverage, and silent grounded battery selection when only the exclusion count would trigger a question. Formal status remains draft pending fresh-context review.

**Why:** the user requested these bounded presentation improvements after Codex dogfood and explicitly approved the paired Attention check and supported fixes. Finalized evidence: `a private finalized review record`, target `private target fingerprint omitted`. All five originals remain distinct. Codex Important early-choice severity is disputed by GLM; structural coverage is confirmed by frozen source, recurrence and attention benefits remain unmeasured. This decision is owner-selected design, not an automatic Critical/Important fix or proof of savings.

**Rejected alternative:** Edit complete-v2 bytes or substitute a Top 5/narrative for the full ledger. That would invalidate historical evidence or discard candidates. Also rejected: infer GLM consent from `--full`/`--loop`, rank failed/unobserved/unreconciled output, or weaken fix gates.

**Could-be-wrong-if:** Either command exits 1: the tests detect missing/wrongly labeled IDs, unsafe summary literals, changed historical readers, an incomplete clean bill/fix implication, or a count-only selection prompt. Exit 2/tool failure is a validation gap, not a finding. These are offline contract checks, not measured utility or live orchestration compliance; revisit the design with the user after observed operator decisions if the navigation does not help.

**Evaluated by:** `[ran 2026-10-11]` presentation suite passed repeatedly as it expanded from 11 to 13 tests; battery suite passed twice (3 tests). Full adapter127/127 and canonical248/0 passed, with three pre-existing historical fixture skips. Registry23/23, source/installed skill, merged config, both reviewer definitions, compilation, shell syntax and whitespace passed. Historical renderer/serializer dependency and literal-fixture bytes matched HEAD; finalized contract-2 Attention evidence revalidated with new readers. Python LSP root discovery refused; no config change or LSP-success claim.

**Status quo check:** `[ran 2026-10-11]` the initial 11-test presentation command exited 1 with 11 assertion failures (including subtests) and one missing-v3-function error; the pre-existing 114 adapter tests had no additional failures. The red policy check rejected the old numeric trigger and absent early disclosure. Historical literal fixtures were not regenerated.

**How to apply:** Amend ADR24's unranked-only delivery clause only for successful reconciled observed-Codex lanes paired with exact intentional GLM allocation omissions. No overall verdict, quality-equivalence claim or automatic fixes from degraded runs, even if helper eligibility lists IDs. Current complete-v3 includes every finding ID and status plus the full JSON/lineage/evidence ledger. Reader dispatch retains immutable v1/v2 renderers/serializers. Disclose outcome mismatch before costly review only for an explicit complete actionable/fix request without sufficient selected coverage; ask at most once, preserve manual selection and bare Codex-first behavior. Canonical selection asks for real ambiguity, not a count; preserve artifact-class exclusions, overrides, preflight, experimental and consent questions.
