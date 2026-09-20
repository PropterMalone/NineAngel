---
id: 15-domain-angels
name: Domain angels — reviewing against an organization's policy
date: 2026-08-13
status: active
amends: null
supersedes: null
commits: []
---

# Domain angels — reviewing against an organization's policy

**Decision**: Add a class of persona that reviews against a **specific organization's written rules** rather than against craft, starting with `caritas`. Each domain gets its **own persona name** — not one parameterized `policy` engine — and its rules live in a layered, provenance-tagged registry outside the reviewed project. `caritas` ships `default: yes` / `experimental: false`, gated by a new `caritas_project` signal so it fires on Caritas work and nowhere else.

**Why**: On 2026-08-12, two Caritas rules were broken in one session while both sat readable in memory: a bounty-activation ask drafted against `feedback_dont_start_clock_before_control`, and client-confidential material drafted to an apprentice's personal Gmail. Neither is hook-catchable — hooks catch mechanical violations (commit identity, path guards, secret scan); both of these were judgment-shaped, where the rule was known, written down, and not applied at the moment of drafting. That is a reviewer's job, and no existing persona does it: all 21 ask "is this good?", none asks "does this comply?"

the user chose `default: yes` over the `CONTRIBUTING.md` entry convention (`default: opt-in` + `experimental: true`) on the argument that **a gate you have to remember is the gate that already failed** — both misses happened with the rule readable. The signal gate is what confines the blast radius: `caritas_project` fires on Caritas work only, so the standing cost lands on client-work runs and nowhere else. The retirement falsifier below replaces the proving period that was skipped.

**Rejected alternative**: One `policy` persona parameterized by domain (`caritas` / `claim` / `minor-data`), which is what `DESIGN.md:85`'s "consolidate, not add" argues for on its face. Rejected because **the evaluation instrument keys on persona name and nothing else**: every accumulator in `mine-runs.py:110-127` is a `defaultdict` on a bare persona string, `findings-snapshot.json` findings carry no domain/tag/category field (`integrator.md:241-256`), and the retro §4.8 retirement trigger fires per persona name. Three domains behind one name blend into one `fp%` that condemns none of them and exonerates none of them — you could still stop a domain firing by deleting a signal from `requires.any_of`, but never justify it from data. That is an actuator with no sensor, the exact failure `DESIGN.md:89` ("cut on precision data") and ADR-02 ("do not return either persona to the default stack without precision data") exist to prevent. Restoring attribution would mean a new per-finding `domain` field in five coordinated places including `parse-findings.py` and **both** integration paths — and ADR-13 exists precisely because snapshot fields already drifted between the dispatched and inline integrators once. Sibling personas get per-domain precision, cost, and demotion for free. Precedent: `DESIGN.md:87` kept Recipient separate from `user` for the same reason.

**Also rejected**: consolidating the registry into one flat policy file. Caritas policy is scattered across `~/Projects/client-work/CLAUDE.md`, ~40 `feedback_*.md` files, and per-project CLAUDE.mds; a consolidated copy duplicates the source of truth and drifts from it. The registry is an **index of checkable rule statements**, each pointing at its authoritative file.

## The registry

Four layers, composing rather than replacing. Where two conflict the stricter governs, and the conflict is itself a finding.

| Layer | Fires | Layer ceiling |
|-------|-------|---------------|
| `firm` | every Caritas review | Critical |
| `user` | every Caritas review — the operator's own principles | Important |
| `client` | when that client is in scope | per rule |
| `bounty` | **v2** — live Arlos fetch, status-dependent rules | — |

**Provenance is an attribution right, not a confidence score.** `stated` (the firm issued it, cited) permits "Caritas policy requires X". `derived` (the user's standing practice) permits only "your standing practice is X" and **never** attribution to the firm or to a named colleague. `inferred` is raised as a question. This tier exists because the user already tags it by hand: `feedback_expand_work_not_reduce_fte`'s own frontmatter says *"the user's value, NOT GSD policy"*, and its body says *"do NOT attribute to GSD or put in Christian's mouth."* Misattribution is one of the violations the reviewer catches, so a reviewer that misattributes is broken in its own lane.

**Two ceilings, one composition rule: the effective ceiling is the LOWER of the layer's and the provenance's.** Corrected 2026-08-13 after this ADR's own review (f15, CONFIRMED): the layer table above and the persona's provenance table each capped severity independently, neither mentioned the other, and one seeded rule sits where they disagree — `firm` layer (Critical) but `derived` provenance (Important), because the firm's material is the subject while the caution about it is the user's. Nothing said which governed. Lower-wins is the rule in both directions, and it is the only one consistent with provenance being an attribution right: a ceiling that let a `derived` rule be filed as Critical would be licensing the misattribution the tier exists to prevent. Stated now in `personas/caritas.md`, the registry index, and `DESIGN.md`.

**Staleness downgrades to a question at 90 days.** The July 2026 rebrand is the proof case: a registry still asserting `@example.com` would flag correct drafts as violations. A missing rule costs one catch; a retired rule asserted confidently costs trust in every subsequent finding.

**Anti-rules are first-class.** Three seeded rules exist to say what is *not* a violation (one the user-layer, two client-layer), because over-gating is the recorded failure mode on this material — on 2026-07-23 the assistant offered to strip a client's own business terminology out of a questions email addressed to that client's operator, and the correction of record was that discussing the client's business is not what the rule gates. Rule IDs are deliberately not quoted here: they name a client, and this file ships to the public mirror while the registry does not.

**Location**: `~/.claude/projects/{encoded-org-cwd}/memory/caritas-policy/`. Org-scoped at a fixed absolute path, deliberately **not** `$HANDOFF_DIR` — that is keyed to encoded cwd (`init-run.sh:55`), so two sub-projects of the same engagement would accrete two divergent copies of one firm's policy. It sits in the gitignored `projects/` tree because `~/.claude` is a git repo with remote `PropterMalone/claude-config` and `.gitignore:2` excludes `projects/` — the one place client policy cannot be committed and pushed. Same reasoning as `pii-registry.md` (`DESIGN.md:75`, `SECURITY.md:31`).

**Dispatch**: a `<policy_index>` block appended **after** the `## Your Persona` tail, carrying absolute paths rather than contents (the leaf reads its own modules, as it already reads its own persona file). After-tail placement preserves the shared cacheable prefix — the `<artifact_paths>` shape, not `<pii_findings>`'s mid-prompt one. **Never dispatch without the block**: if the registry does not resolve, skip and record the reason.

**`caritas` is exempt from `--all`'s signal bypass.** `--all` and `PERSONAS: all` skip signal gating for every other persona; caritas still requires `caritas_project`. Corrected 2026-08-13 after this ADR's own review (run `20260813T132632Z-a638626d`, finding f2, CONFIRMED): the original text claimed registry resolvability was what protected the `--all` path, which cannot be true — the registry is org-scoped at a fixed path, so it resolves on every project and can never distinguish one from another. That guard was inert exactly where it was advertised to work, and with it the "signal bounds the blast radius" justification for shipping `default: yes` did not hold. Resolvability remains as an independent second guard for a different failure: a genuinely-Caritas run whose registry is missing or moved.

**Could-be-wrong-if**: across `caritas`'s first ~5 client-work runs, its **combined wrong-finding rate** exceeds **15%** on **n ≥ 10** scored findings of which **≥5 carry a human disposition** — or ≥60% of its Important+ findings are co-caught by `editor` or `user` (the lane-is-a-re-slice test from `DESIGN.md:87`). Either fires → demote to `default: opt-in`.

**Evaluated by**: `python3 scripts/mine-runs.py --json`, reading `personas.caritas` and `portfolio.overlap_important_plus`. Both clauses were restated 2026-08-13 after this ADR's own review (f11, f12) — as first written, neither was computable from the instrument named:

- **Rate** = `false_positives / disposed`, which is what the report's `fp% (n)` column shows. That figure spans **two channels**: a human `rejected-wrong` disposition, and a machine `REFUTED` verdict on a finding no human ruled on (`mine-runs.py:229-243`). Both are evidence a finding was wrong, so the combined rate is the metric worth gating on — but it is not the single-channel "`rejected-wrong` rate" this ADR originally named, and at n=10 one machine verdict swings it 10 points. Hence the human-disposition floor: fire only when `disposed - (false_positives - human_false_positives) ≥ 5`. Below that the number is a verdict artifact, not a precision measurement. Cross-check `human_false_positives` against `false_positives`; a wide gap means the machine channel is carrying the result and the demotion should wait for human rulings.
- **Co-attribution** = pairs in `portfolio.overlap_important_plus` containing `caritas`, over `personas.caritas.severity_total.critical + .important`. Read it from `--json`, **not** from the report's persona-overlap table: that table truncates to the top 10 pairs by raw count (`mine-runs.py:380`), and its current floor is far above anything a new persona reaches, so caritas would silently read as never-co-caught for its whole first year. The `--json` list is untruncated and the denominator is a share rather than a count. A finding caught by *both* `editor` and `user` appears in both pair counts, so take the larger single pair as the conservative read and inspect snapshots if the sum crosses 60% where the max does not.

Not-yet-met output, run 2026-08-13: **no `caritas` row exists** — 0 runs, 157/292 run dirs parseable, 60 carrying dispositions.

**Status quo check** [ran 2026-08-13]: across the 19 personas at n ≥ 10 dispositioned findings, `fp%` has a **median of 1%** and a **maximum of 7%** — `recip` 7% (n=15), `deanon` 6% (n=31), `thousand` 5% (n=21), `naive` 4% (n=72), and every other lane at 0–2%, seven of them at 0%. Below the n ≥ 10 line the values are noise: `penny` 14% (n=7), `pii` 67% (n=3). **This is why the threshold is 15% and not the 30% published in `DESIGN.md:249`.** A 30% bar sits so far outside the observed distribution that a persona at 14% — fourteen times the corpus median, and plainly broken — would pass it. 15% is ~2× the worst lane in the corpus and ~15× its median: above anything a healthy persona has ever produced, below what a broken one produces. The `n ≥ 10` guard is `DESIGN.md:89`'s "do not cut on thin data" made mechanical, and `pii`'s 67% on n=3 is exactly the artifact it prevents. (Corrected 2026-08-13, f10: the shipped text claimed "0–2% for every established persona" and was falsified by its own parenthetical, which listed `naive` at 4%; the multipliers were derived against a 2% median that the table does not support. The honest re-derivation is the stronger argument.)

> **Note for a future retro**: `DESIGN.md:249`'s published graduation bar of "false-positive rate <30%" appears miscalibrated against the corpus it is meant to police, for the same reason. Not changed here — that bar governs every persona and is not this ADR's to move. Filed to `backlog.md`.

**Known dependency**: the falsifier is only computable if dispositions get recorded. **60 of 292 run dirs carry any** — four fifths of all runs contribute nothing to persona evaluation. Recording dispositions on caritas runs is part of shipping it `default: yes`.

## Scope shipped

v1 is `caritas` only: persona, `caritas_project` signal, `<policy_index>` plumbing on both orchestrator paths, and a seeded registry (3 firm rules, 9 the user rules, 5 rules in one client appendix). Claim/legal and minor-data are approved in `backlog.md` and become near-copies on this substrate.

**Deferred to v2**: the bounty layer (live `mcp__arlos__get_bounty`, status-dependent rules, the project→bounty join key); automated registry accretion via the integrator's two-hop `registry-updates.json` merge (v1 has the persona emit `registry candidate:` findings for manual merge); policy ingest from firm announcements in the kickoff comms sweep, which is where the rebrand came from and is the real answer to keeping the registry current; the cross-client contamination check when two client appendices activate on one artifact; and any automatic invocation trigger — v1 fires on `/angel` only.
