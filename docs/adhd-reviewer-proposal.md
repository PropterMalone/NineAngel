# User-attention reviewer — implementation record

Status: implemented as `attention`, experimental and opt-in, 2026-10-10. No live review or effectiveness evaluation has run as part of implementation. The filename preserves the original exploratory note's location, not a diagnostic mandate.

## Origin and selected mandate

The owner originally asked to note a possible ADHD reviewer during feedback work on a private project. The later authorized mandate is user attention: **can we ask less of the user and achieve as good a result? And if not, is it still worth trading down on user tax for a somewhat worse result?** The implementation reviews both changes and whole projects, with separate tests for equally good results at lower burden and worthwhile explicit quality/burden tradeoffs. It may challenge a working feature when its benefits do not justify the demands it imposes.

The canonical mandate, evidence requirements, examples/counterexamples, constraints, abstention rule, and existing finding format live in `../personas/attention.md`. The reviewer traces demands to notice/read/choose/remember/configure/copy/switch/monitor/re-enter/maintain, their accumulation, and the ability to disengage. It requires concrete workflow evidence, consequences, an alternative, quality retained/lost, and rationale tied to stated user purpose. Shorter text or fewer clicks need not reduce total burden; clarity and setup can reduce uncertainty and rework.

Safety, privacy, consent, irreversible-action approval, and required accuracy remain constraints. Redundant approvals differ from necessary authorization. The mandate excludes diagnosing, capacity assumptions about a specific person, ADHD-uniformity assumptions, and clinical-benefit claims. Unknown tradeoff preferences require abstention, not an assumed preference for convenience. Unmeasured benefits remain hypotheses.

## Integration and boundaries

- Shared file: `personas/attention.md`; no duplicate adapter body.
- Legacy selection: `/angel attention` (diff), `/angel attention --full` (project); unattended `PERSONAS: attention` with either mode. Registered in both legacy tables using the existing Sonnet route, without changing other model pins.
- Polytoken selection: `angel attention` or `angel attention --full`; Codex-first remains the default. GLM requires explicit `--glm-personas attention` or `--cross-family`, as for other lanes. No helper schema or provider default changed.
- `default: opt-in`, `experimental: true`, `modes: [diff, full]`; excluded from automatic batteries and `--all` / `PERSONAS: all`.
- Distinct question: user demands versus their delivered benefit, not generic UX/minimalism. User reviews broken/confusing/silent flows; Naive tests newcomer comprehension; Coach reviews prompt quality; Hypercritical critiques engineering. Pennypincher includes cognitive and maintenance cost but does not center result-quality tradeoffs across the user's workflow.

## Evidence still needed

Offline tests check selection instructions, frontmatter/registry parity, mandate clauses, examples, and existing record compatibility. They cannot show that a model follows the mandate or that it adds useful coverage.

For later owner-selected evaluation, use representative diff and full-project targets containing both burden-reduction opportunities and cases where added clarity/setup/authorization is justified. Retain the exact workflow citations, raw findings, verification, and dispositions. Compare with User, Naive, Coach, Hypercritical, and Pennypincher for unique grounded catches and overlap; include counterexamples and unknown-preference cases to assess overreach and abstention. Use existing experimental graduation/retirement rules in `../DESIGN.md`, not a promised benefit or provisional "good for" recommendation. Quality and attention effects require comparable workflow evidence; no live performance, savings, or clinical effectiveness is claimed.

Apply those criteria within a single recorded workflow/calibration era, not by pooling stores. Legacy evaluations use `usage.log` and `outcomes.log`; `scripts/mine-runs.py` can locate their run evidence. For a Polytoken evaluation, use the finalized run index `~/.angel/polytoken/usage.jsonl` and its bound raw findings, snapshots, verification, and dispositions. Count at least five actual Attention reviews across diverse projects in that era; reviews of the Attention implementation itself do not count. Check completion, reconciliation, family coverage, and target identity for each run rather than counting attempted, stopped, or repeated passes as separate evaluations. Explicitly label the covered model families; do not infer missing-family results or mix legacy observations into that cohort.

For either era, an owner-reviewed evaluation record must identify the qualifying run IDs, the grounded Attention findings judged true or false, and the denominator used for the false-positive calculation; unresolved findings cannot silently count as correct. Apply the Coach-pass and false-positive criteria from `../DESIGN.md` to that record before changing experimental status. Existing Polytoken `family_summary.py` reports family measurements only; it neither supplies this adjudication nor decides graduation.
