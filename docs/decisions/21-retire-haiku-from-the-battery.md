---
id: 21-retire-haiku-from-the-battery
name: Haiku is retired from the battery — Sonnet is the cheapest Claude tier
date: 2026-09-12
status: active
until: null
amends: [19-retire-fable-from-the-battery]
supersedes: null
commits: []
depends_on:
  - ref: angel:19
    claim: the standing table is Sonnet/Opus with Fable retired; this ADR only moves three rows within that table and inherits its degradation rung
  - ref: mem:feedback-no-haiku
    claim: the user's 2026-09-12 rule "do not use Haiku for anything" is in force fleet-wide; if that memory is withdrawn this ADR's premise goes with it
falsifier_cmd:
  - label: haiku-successor-shipped
    cmd: 'python3 scripts/haiku-successor-check.py'
  - label: haiku-row-in-model-table
    cmd: 'if grep -hE "^\|" SKILL.md unattended.md | grep -qi haiku; then echo "haiku in a model-table row"; exit 1; else echo "no haiku table rows in SKILL.md/unattended.md"; fi'
applies_to: [SKILL.md, unattended.md, scripts/validate-personas.py]
---

# Haiku is retired from the battery — Sonnet is the cheapest Claude tier

**Decision**: No persona dispatches Haiku. The three breadth lanes that ran `claude-haiku-4-5-20251001` — naive, fresh, pii — run `claude-sonnet-5[1m]` on both acting paths (SKILL.md §1, unattended.md Step 3). `--model-override` and `MODEL_OVERRIDE` drop `haiku` from their vocabulary, and `scripts/validate-personas.py` rejects a `haiku` tier so the drift guard enforces the retirement rather than tolerating it. Everything else in the ADR-19 table stands.

**Why**: the user, 2026-09-12, as fleet policy rather than a battery finding: *"new general policy: do not use Haiku for anything. it is both expensive and bad"*, and on the replacement, *"shell out to ChatGPT terra if you want something that shape, which is both cheaper and smarter."* Haiku 4.5 spends the Claude subscription window on lanes whose whole justification was cheapness (ADR-07: "Haiku = cheapest breadth"), and Codex `gpt-5.6-terra` now fills that shape off-subscription. The battery is the largest Haiku consumer in `~/.claude` (three lanes per run, both passes on unattended runs), so it moves with the policy. Recorded as a price-and-policy decision: no benchmark was run on Sonnet-naive vs Haiku-naive, and ADR-07 leg 3 never measured the breadth lanes separately.

**Rejected alternative**: route the three breadth lanes to Codex `gpt-5.6-terra` directly, since that is the shape the user named. Rejected because on interactive runs pass 2 already goes to Codex (ADR-18); sending pass 1 there too would make those lanes homogeneous-Codex and lose the one cross-model comparison the N=2 structure exists to buy. Sonnet is the cheapest remaining Claude tier, so the Claude pass takes it. Also rejected: leaving Haiku as a legal `--model-override` value the way ADR-19 kept `fable`. Fable was retired as a *default* on price; Haiku is retired as a *choice* on quality ("bad"), so there is no deliberate same-model comparison it should remain reachable for.

**Could-be-wrong-if**: (a) A Haiku successor ships — the user's own reconsider clause, *"if/when we get a Haiku update we'll reconsider that policy."* Observable as a `claude-haiku-*` id from a generation newer than 4.5 in the installed Claude Code binary; `haiku-successor-check.py` fires on it and the answer is *ask the user*, not re-tier. (b) The three lanes' cost on Sonnet turns out to matter: if a standard run's `usage.jsonl` shows naive+fresh+pii above 25% of pass-1 Claude `total_tokens` across 10 post-ADR runs, the "cheapest tier" framing is wrong and the Codex-direct alternative should be reopened. Not registered as a `falsifier_cmd` because `total_tokens` is peak single-turn context, not spend (ADR-17), and no instrument prices a lane in isolation yet.

**Evaluated by**: the `falsifier_cmd:` entries above, verbatim → `[ran 2026-09-12]`:
- `haiku-successor-shipped` → `no Haiku id newer than 4.5 in claude.exe; rule premise holds`, exit 0. Backward: a fake binary carrying `claude-haiku-5-20260801` → exit 1 with the id named; a missing binary → exit 2.
- `haiku-row-in-model-table` → `no haiku table rows in SKILL.md/unattended.md`, exit 0.

**Status quo check**: the same table grep against `HEAD` before this change (`git show HEAD:SKILL.md | grep -E '^\|' | grep -ci haiku`) → **3** rows in SKILL.md and **3** in unattended.md, so the threshold (any row) discriminates the pre-change state from the post-change one. The successor check against the installed 2.1.270 binary finds generations 3, 3.5, 3.55, 4, 4.5 and nothing newer, so it reads clean today and cannot be satisfied by the status quo.

**Promoted 2026-09-13** (retro §4.7 fresh-context read): both `falsifier_cmd` entries re-run forward under the sweep's cwd contract (`command_cwd` → the angel skill root, so the relative paths resolve) → `no Haiku id newer than 4.5 in claude.exe; rule premise holds` exit 0, and `no haiku table rows in SKILL.md/unattended.md` exit 0. Neither ran in the 2026-09-10 sweep because this file postdates it; the first sweep to see them is 2026-09-14. No `fired:`/`support_lost:` line to adjudicate; both `depends_on` refs resolve — angel:19 is `active`, `mem:feedback-no-haiku` exists.

**How to apply**: any edit to either model table, any new persona, any `--model-override` handling, and any CHANGELOG entry that names a tier. A new persona whose mandate is "cheap breadth" gets Sonnet, or gets designed as a Codex leg through `dispatch-leg.sh`; it does not get Haiku. When `haiku-successor-shipped` fires, the Claude Follow-up task it opens is a question for the user; do not re-tier on the sweep's say-so.
