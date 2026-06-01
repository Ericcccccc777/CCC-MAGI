# Workflow detail

> **Reference for `CLAUDE.md § Workflow`.** Loaded on demand when AI needs full stage internals, mode-vs-lane distinction, or cross-model audit operationalization. The compact summary in CLAUDE.md is the load-bearing version; this file is the elaboration.

## Two sides, three lanes (full picture)

The **CEO (you, human)** sets intent. The **MAGI System** (the AI team) implements + reviews — see `AGENTS.md § MAGI System` for the 7 positions. Concretely:

- **MAGI Core** (your primary CLI, e.g. Claude Code) — orchestrator + workflow manager. Talks to you. Spawns subagents.
- **MAGI Verdict** (default `{{auditor_model}}`, e.g. Codex) — cross-model auditor. **Judgment authority. Not under MAGI Core's chain of command** — independent reviewer per Universal Core.
- **MAGI Planner / Programmer / Tester** — played by MAGI Core during the matching stage (mode switch, not separate processes).
- **MAGI Reviewer** — `{{junior_reviewers}}` rule-enforcement plugins (backend / frontend / security). Mechanical. Cite rule source; never invent.
- **MAGI Archivist** — `memory-recall.sh` / `memory-snapshot.sh` hook services.

Judgment is MAGI Verdict's; rule enforcement is MAGI Reviewer's; orchestration is MAGI Core's; intent is yours.

## Two modes (Stage 1 branches)

The workflow runs in two **modes** that share Stages 2–9. Stage 1 differs by mode:

- **New-feature mode** — for shipping new features. Stage 1 paraphrases CEO intent, runs an 8-category edge-case round, then writes a plain-language spec.
- **Audit mode** — for verifying existing features. Stage 1 runs the same intent rounds, then a fresh general-purpose subagent scans the codebase for an as-built read; the auditor independently reviews; CEO decides each delta; output is the same two-file model.

Stage-specific tools are in `.harness/` — see `CLAUDE.md § Tool map`.

## Full 9-stage description

1. **Draft / as-built spec** — `/feature-draft <name>` (new-feature mode) **or** `/audit-spec <name>` (audit mode, fresh-context subagent + auditor review)
2. **Finalize spec** — `/spec-finalize <name>` (auditor final cross-check)
3. **Design schema** (when data model changes; **skip if project has no backend**) — `/db-schema <name>`
4. **Write execution plan** — `/execution-plan <name>` (per-file checklist + auditor judgment audit)
5. **Implement per plan** — `/implement <name>` (mechanical reviewer chain + auditor judgment)
6. **Auto tests** — `/test-fix` (test-fixer subagent + auditor audit). **Skipped if `test_required = false`.**
7. **User smoke test** — CEO runs the application manually against the spec's smoke-test procedures (`{{spec_dir}}<name>.md` only — implementation file not consulted). *Mandated by Constitution § 4.*
8. **Commit & push** — `/commit` using Conventional Commits, with affected scenario IDs in the message body. Plan file is deleted in this commit. Pushed to GitHub only after **both** the CEO smoke test (Stage 7) **and** the auditor audit have passed.
9. **Watch after release** — for any change shipped, check `{{error_tracker}}` within 24h for new error groups or a drop in error-free rate. If anything spiked, hotfix or roll back before moving on.

Do not reorder stages. Do not advance to the next stage until the current stage's artifact exists or the user has approved skipping. Stages may only be skipped via one of the two explicit lanes below.

## Cross-model audit (operationalizing Constitution § 1)

The constitutional invariant is in `./constitution.md § 1`. Below is how it is operationalized stage-by-stage:

- Audit strength scales with change size: full review on the standard lanes, BLOCKING-only on the trivial lane.
- The auditor is invoked at stages 2, 3, 4, 5, 6 (post-fix), and on every commit gate.
- The auditor emits JSON per `AGENTS.md § Verdict output`.
- `FAIL` halts the flow; `CONCERNS` advances with a logged warning (see `.harness/audits/concerns-*.json`); `PASS with advisory_items` advances silently; `WAIVED` is a CEO override and is rejected by the gate if any blocking item is `category: "universal-core"`.

## Lanes (full description)

A change picks one of three lanes; lane decisions are Tech-Lead inferred and CEO-confirmed (never silently auto-changed mid-flow).

**Full workflow.** New feature, intent change (audit delta), schema change, or new external dependency. All 9 stages.

**Stability-fix lane.** Bug fix or hotfix where intent is unchanged, no new feature surface, no schema change, no new dependency. Skip stages 1–3. **Failing test is mandatory** (if `test_required = true`) — write it before the fix, confirm it fails on the broken code, then fix and watch it go green. Path-based reviewer auto-fire on the diff (Stage 5) plus auditor audit on the fix correctness + test legitimacy (Stage 6).

**Trivial-change lane.** < 20 LOC, no new feature surface, no schema change, no new dependency, no intent change (typo, copy tweak, single-line bug fix, dependency bump). Skip stages 1–3. Stage 4 reduces to applying the change with path-based reviewer auto-fire; Stage 5 confirms existing tests still pass. Auditor runs in **Quick mode (BLOCKING-only)** — security, data loss, and outright defects only. Stage 7 (smoke) skipped only for pure copy/text/translation; spot-check for any logic change. If the auditor's Quick audit surfaces non-trivial concerns, the lane is wrong — surface to CEO and re-classify.

Knowing the lane in advance lets you triage a bug correctly: "panic-fix in 30min" vs. "plan for 48h with a workaround in the meantime."
