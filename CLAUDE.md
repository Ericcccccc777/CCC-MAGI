# {{project_name}} — Harness CLAUDE.md

## ⟦Language Awareness⟧ (perform once at session start, before anything else)

CCC-Harness's internal files (this CLAUDE.md, skills, agents, scripts, drivers, prompts) are written in English by design — it's stable, token-efficient, and what AI models follow most reliably. But when you talk to the **human user**, talk in their language.

**At the start of each session, detect the user's OS locale:**

```bash
locale 2>/dev/null | head -1 | sed 's/LANG=//' | sed 's/\..*//'
```

Or read `$LANG` directly. Common values:
- `en_US`, `en_GB`, etc. → respond in English (default if undetected)
- `zh_CN`, `zh_TW`, `zh_HK` → respond in 简体中文 / 繁體中文
- `ja_JP` → respond in 日本語
- `ko_KR` → respond in 한국어
- Any other → use that locale's natural language

**Apply translation here**: USER-FACING text (questions, confirmations, status reports, error explanations, the 3-option menu, the 16 L0 questions, etc.). Translate naturally; don't translate machine identifiers.

**Do NOT translate**: 
- Tool calls, file paths, environment variables, shell commands
- Frontmatter fields (`name`, `description`, etc.)
- File CONTENT we write (constitution.md slot values, etc.) — those default to English unless the user explicitly asks otherwise
- The two completion markers: `✓ Task complete, close terminal` and `✗ Task cancelled, close terminal` — these are byte-exact strings that CCC matches against; translating them breaks integration
- Code identifiers, log lines, JSON keys

**Default**: If locale detection fails (no `locale` command, no `$LANG`, returns garbage), default to English. Don't ask the user "which language?" — just default to English; they can ask you to switch if needed.

---

> **Project context** (build commands, tech stack, code style, anti-flag rules, auditor brief): see `./AGENTS.md` — that file is the AGENTS.md ecosystem-standard format, read by Codex, Cursor, Cline, Aider, and other AI tools alongside this file. Read `AGENTS.md` first for project-level context, then this file for Claude-specific workflow rules.

---

## ⟦Bootstrap Status Check⟧ (perform first, every session)

**Before any other work in this conversation**, check whether CCC-Harness has been configured for this project:

```bash
test -f .harness/state/install.json
```

**If the file DOES NOT exist** → CCC-Harness has NOT been configured for this project yet.

- Read `.harness/scripts/standalone-bootstrap.md` and run that flow first, before any user request.
- The bootstrap flow detects any existing harness configs in the project, presents a 3-option menu to the user, and either installs CCC-Harness (options 1/2) or yields control back to normal Claude Code workflow for this session (option 3).
- If the user previously declined CCC-Harness **in this same conversation**, you may proceed with normal Claude Code workflow without invoking harness skills. Treat the user's decline as binding for the rest of this session; do NOT re-prompt within the same conversation.
- Re-prompt at the start of the **next** session (because `install.json` still won't exist).

**If the file DOES exist** → CCC-Harness is fully configured. Proceed with normal harness workflow:

- All skills in `.harness/skills/` are available (`/feature-draft`, `/audit-spec`, `/spec-finalize`, `/db-schema`, `/execution-plan`, `/implement`, `/test-fix`, `/commit`, plus `/init` for re-configuration, `/constitution-edit` for editing project identity, `/add-constitution-clause`, `/add-anti-flag`).
- This file (CLAUDE.md) and `constitution.md` carry the operating rules.

> **Belt-and-suspenders design**: this Bootstrap Status Check block is the "employee handbook" layer — it tells Claude *what* to do. The actual *enforcement* lives in the UserPromptSubmit hook at `.harness/scripts/bootstrap-check.sh`, wired in `.claude/settings.json`. The hook fires deterministically on every user prompt regardless of whether Claude reads this block. Together = robust against any single failure mode (e.g., this block missing because CLAUDE.md was overwritten by an earlier session's edit).

---

> **Constitution:** see `./constitution.md` — that file is loaded by every agent **before** this one. It contains the project's Universal Core (Section 1, harness-guaranteed), Project Identity (Section 2, /init-filled), and Project-specific Red Lines (Section 3, grows over time).
>
> **Slot registry:** lives at the top of `./constitution.md` (single source of truth). This file uses slot names like `{{project_name}}` without re-declaring them.
>
> **Division of labor:** Constitution = *what this project stands for*. `AGENTS.md` = *universal project context + auditor brief*. This file = *how to work in this project (Claude-specific)*.

**Project overview**: see `AGENTS.md § Project Overview`.

Build for today, don't add infrastructure you don't need yet (sharding, queue infra, partitioning, multi-region etc.), but don't take shortcuts that are painful to undo later.

## Scope of Claude's work

Claude's job in this repo is **{{primary_concern}}**.

Out-of-scope items (do not surface as concerns or block progress): {{out_of_scope_items}}. If something is genuinely unclear, ask once — do not pad replies with "you should also consider…" lists for non-{{primary_concern}} concerns.

## Operating Principles

> **HARD (non-negotiable) principles live in `./constitution.md § Section 1`** — they are not duplicated here. Those Universal Core items cannot be removed, overridden, or carved out — not by lane choice, not by direct CEO instruction, not under any circumstances. The principles below are **STRONG**: overridable by CEO with reasoning recorded in `## Decision history`.

### STRONG (justify trade-offs)

1. **Simplicity over completeness.**
   Failure mode: LLM overbuilds. Speculative abstractions, unrequested config, error handling for impossible scenarios.
   Rule: Minimum code that solves the stated problem. No features beyond what was asked. If the code you are adding or directly modifying could be 50 lines instead of 200, rewrite it. Adjacent or orthogonal code that you happen to read is out of scope for compression even if it is verbose. Reuse existing patterns first; new patterns require explicit justification of why the existing thing doesn't fit.

2. **Surgical changes.**
   Failure mode: LLM drives-by "improves" adjacent code, comments, formatting, or refactors orthogonal things.
   Rule: Every changed line traces directly to the request. Don't reformat, rename, or "clean up" anything you weren't asked to. If you notice unrelated dead code, mention it. Don't delete it. When your changes create orphans, remove only the imports/variables your changes made unused.

3. **Diagnosable in production.**
   Failure mode: Bug ships, can't reproduce, no signal to debug from.
   Rule: {{error_tracker}} on key surfaces. Funnel events at critical user actions. Performance signals captured. When something goes wrong, the data needed to answer "why" should already exist.

4. **Spec and reality match.** *(Operational corollary of Constitution § 5.)*
   Failure mode: Code change lands but spec drifts. Or state-coordination invariant lives only in code and drifts silently.
   Rule: User-visible behavior changes → `{{spec_dir}}<name>.md` updated in the same commit. State-coordination invariants → `{{implementation_dir}}<name>-implementation.md` "State Coordination Invariants" section, same commit. Spec-vs-code drift is caught by `/audit-spec`.

## Working with the CEO

> *Operational application of Constitution § 3 (CEO Final Authority). Authority itself is constitutional; how the manager behaves toward the CEO is operational and lives here.*

- Don't second-guess CEO intent at later stages. Paraphrase to confirm understanding (Stage 1) — never to challenge.
- Don't ask the CEO technical questions; translate them to user-result questions, or decide internally and document the reasoning.
- **Language mode is `{{language_mode}}`.** If `plain` (default), CEO-facing prompts strip jargon — every question and every confirmation phrased so a non-engineer can answer. If `professional`, technical terms allowed.
- When Sam (the {{auditor_model}} auditor) disagrees with the CEO on a BLOCKING item, route through the escalation pattern: present both views, name the user/cost/security impact, then let the CEO decide. The CEO still has the final word (unless the disagreement is over a Universal Core item, in which case the constitution wins).

## Repo structure

**Repo structure**: see `AGENTS.md § Repository Structure`.

## Dependency flow

<!-- ⟦L1⟧ Optional. If your project enforces module-level import direction
     (e.g. shared → ui → features → app), describe it here. Leave blank
     if no such enforcement. /init asks whether to enable a cycle-detection hook. -->
{{dependency_flow}}

## Workflow

Two roles, three lanes. Roles are **CEO (you)** and **Tech Lead (Main Claude + Sam, the {{auditor_model}} auditor)**; junior reviewers (plugins from `{{junior_reviewers}}`) enforce mechanical rules; the junior programmer (`test-fixer`) writes test code only. Judgment is Sam's (the auditor's); rule enforcement is the subagents'; intent is yours.

The workflow runs in two **modes** that share Stages 2–9. Stage 1 differs by mode:

- **New-feature mode** — for shipping new features. Stage 1 paraphrases CEO intent, runs an 8-category edge-case round, then writes a plain-language spec.
- **Audit mode** — for verifying existing features. Stage 1 runs the same intent rounds, then a fresh general-purpose subagent scans the codebase for an as-built read; the auditor independently reviews; CEO decides each delta; output is the same two-file model.

Stage-specific tools are in `.harness/` — see Tool map below.

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

### Cross-model audit (operationalizing Constitution § 1)

The constitutional invariant is in `./constitution.md § 1`. Below is how it is operationalized stage-by-stage:

- Audit strength scales with change size: full review on the standard lanes, BLOCKING-only on the trivial lane.
- The auditor is invoked at stages 2, 3, 4, 5, 6 (post-fix), and on every commit gate.
- The auditor emits JSON per `AGENTS.md § Verdict output`.
- `FAIL` halts the flow; `CONCERNS` advances with a logged warning (see `.harness/audits/concerns-*.json`); `PASS with advisory_items` advances silently; `WAIVED` is a CEO override and is rejected by the gate if any blocking item is `category: "universal-core"`.

### Lanes

A change picks one of three lanes; lane decisions are Tech-Lead inferred and CEO-confirmed (never silently auto-changed mid-flow).

**Full workflow.** New feature, intent change (audit delta), schema change, or new external dependency. All 9 stages.

**Stability-fix lane.** Bug fix or hotfix where intent is unchanged, no new feature surface, no schema change, no new dependency. Skip stages 1–3. **Failing test is mandatory** (if `test_required = true`) — write it before the fix, confirm it fails on the broken code, then fix and watch it go green. Path-based reviewer auto-fire on the diff (Stage 5) plus auditor audit on the fix correctness + test legitimacy (Stage 6).

**Trivial-change lane.** < 20 LOC, no new feature surface, no schema change, no new dependency, no intent change (typo, copy tweak, single-line bug fix, dependency bump). Skip stages 1–3. Stage 4 reduces to applying the change with path-based reviewer auto-fire; Stage 5 confirms existing tests still pass. Auditor runs in **Quick mode (BLOCKING-only)** — security, data loss, and outright defects only. Stage 7 (smoke) skipped only for pure copy/text/translation; spot-check for any logic change. If the auditor's Quick audit surfaces non-trivial concerns, the lane is wrong — surface to CEO and re-classify.

### Release lanes

<!-- ⟦L1⟧ How a change reaches users. Default is single lane: `git push` to main.
     For projects with hot-update channels (e.g. OTA, hotpatch) or staged
     environments, /init asks the user to describe additional lanes here. -->
{{release_lanes}}

### Backend changes

<!-- ⟦L1⟧ OPTIONAL — skip entirely if project has no backend.
     Otherwise describe the backend release path (migrations, deploys,
     environment promotion, secret rotations). -->
{{backend_change_lane}}

Knowing the lane in advance lets you triage a bug correctly: "panic-fix in 30min" vs. "plan for 48h with a workaround in the meantime."

## Two-file feature spec model

Every feature has up to two docs:

- `{{spec_dir}}<name>.md` — **CEO domain.** Plain language, no tech terms. Happy path, edge-case behaviors, scenario classification (`[Required automated test]` / `[Smoke test only]`), smoke-test procedures. CEO signs off; CEO is the only one who reads this end-to-end at smoke-test time. **Categorical list of tech terms that must NEVER appear here** (translate to behavior instead): framework / library names, hook / function names, store / state names, router / navigation APIs, RPC / function / table / column names, payload shapes (JSON field lists), file paths, migration timestamps, SDK error type names, HTTP status codes as primary verbs, query key constants, **test file paths and test descriptions**. **The shape test:** if a non-engineer reading the sentence aloud would stumble, the sentence belongs in the implementation file. Translate to outcome ("nothing about the user reaches the device before the gate is passed"), not mechanism ("the RPC returns only `{state, reason, dormancy_required}`").

- `{{implementation_dir}}<name>-implementation.md` — **manager domain (optional).** Routing tables, component map, state keys, access-control policies, library + version notes, i18n key index, boundary contracts, **scenario → automated test map**. Tech Lead and reviewers read this; CEO doesn't have to. Simple features may skip this file entirely; complex features typically have a rich one. **All audit-delta ledgers (Stage 1 audit findings, code-vs-spec reconciliation) belong in this file — never in `<name>.md`.** By definition they track how code matches spec, which is manager-domain content. The CEO spec records intent and behavior; the implementation file records how the code currently honors that intent.

### Manager-file functional requirements: EARS notation

Functional requirements in `{{implementation_dir}}<name>-implementation.md` use **EARS notation** (Easy Approach to Requirements Syntax). EARS is structured natural language — each requirement names the trigger and the expected behavior in a testable format.

**Primary pattern** (event-driven — covers ~80% of cases):

```
WHEN [trigger/condition] THE SYSTEM SHALL [expected behavior]
```

Examples:
- `WHEN the user submits the OTP form with a valid code, THE SYSTEM SHALL navigate to home screen within 500ms.`
- `WHEN the upload request returns 401, THE SYSTEM SHALL clear local session and redirect to login.`
- `WHEN a user cancels the upload mid-stream, THE SYSTEM SHALL delete the partial S3 object within 60s.`

**Other EARS variants** (use when the primary pattern doesn't fit):

| Variant | Pattern | When to use |
|---|---|---|
| Ubiquitous | `THE SYSTEM SHALL [behavior]` | Always-true invariant (no trigger) |
| Event-driven (primary) | `WHEN [event] THE SYSTEM SHALL [response]` | Most functional requirements |
| Unwanted behavior | `IF [undesired event] THEN THE SYSTEM SHALL [recovery]` | Error handling, anomaly recovery |
| State-driven | `WHILE [state] THE SYSTEM SHALL [behavior]` | Constraints that hold during a state |
| Optional | `WHERE [feature included] THE SYSTEM SHALL [behavior]` | Behavior gated by a feature flag |

**Why EARS for manager domain:**
- Each `SHALL` clause maps directly to a test assertion. Stage 6 (`/test-fix`) can generate tests from EARS requirements with minimal interpretation.
- All-caps keywords (`WHEN`, `THE SYSTEM SHALL`) scan visually as load-bearing — distinguishes functional requirements from architectural notes / library version notes / scenario→test mappings (which stay as prose).
- Industry standard (AWS Kiro default, NASA / aerospace adoption).

**Where EARS does NOT apply:**
- `{{spec_dir}}<name>.md` (CEO domain). The CEO file stays plain prose — no `SHALL`, no all-caps keywords. The 16-category tech-term ban in the CEO file (see § above) implicitly excludes EARS keywords; this section makes it explicit: **CEO file = no EARS.**
- Manager-file sections OTHER than functional requirements: routing tables, component maps, store keys, RLS policies, library + version notes, i18n key index, boundary contracts, scenario→test maps — these stay as their natural format (tables, lists, prose). EARS is for the **Functional requirements** section only.

**Migration note:** existing manager files with prose-style functional requirements don't need to be retroactively rewritten. New manager files written from this point on should use EARS for the Functional requirements section. Run `/audit-spec <name>` to surface drift — including manager-file requirements that could be promoted to EARS.

The CEO spec is the canonical source of truth. The implementation file is a working notebook.

## Doc-in-sync responsibility

> *Constitutional basis: `./constitution.md § 5` (Spec and reality stay in sync). Operational details below.*

Specs at `{{spec_dir}}<name>.md` are load-bearing only when they match reality. Drift kills them.

**Rule.** Any commit that changes a feature's data model, public API, or user-visible behavior MUST update the corresponding `{{spec_dir}}<name>.md` in the same commit. This applies to commits made via any lane — full workflow, stability-fix, or trivial-change. If only the technical surface changes (file split, query refactor with same shape), update `{{implementation_dir}}<name>-implementation.md` instead.

**Exceptions.** Stylistic refactors, internal renames, formatting, and bug fixes that preserve external behavior do not require doc updates.

**Cross-feature touches.** When a change touches multiple features' surfaces, update the doc for the feature that _owns_ the affected surface, not just the feature you happened to be working in. The owner is whichever feature's spec was the original source of that artifact.

**Plan files are transient.** `{{spec_dir}}<name>-plan.md` is the Stage 4 execution checklist. Once the implementation lands at Stage 8, the plan has done its job — delete it as part of the commit that ships the implementation. Stale plan files with un-ticked checkboxes mislead future-you.

**Catching drift.** If you suspect a spec has drifted from reality, run `/audit-spec <name>` to produce a fresh as-built reading from code (fresh subagent author, Sam — the auditor — reviews independently), then iterate to a corrected canonical spec. The audit mechanism IS the maintenance mechanism.

## Tool map

### Bootstrap (not a skill; see top of this file)

Before any skill runs, the Bootstrap Status Check at the top of this file decides whether harness is configured. If not:
- **CCC mode**: CCC's bundled Step 1 driver runs (detects existing harness + 3-option menu + git clone)
- **Standalone mode**: `.harness/scripts/standalone-bootstrap.md` runs (same logic minus git clone, since user already cloned manually)

Both bootstrap paths converge on invoking `/init` to fill project-specific values.

### Slash commands & skills (`.harness/skills/`)

Each skill lives at `.harness/skills/<name>/SKILL.md`. Skills with a `description` are auto-discoverable and create the `/<name>` invocation.

Skills are invokable two ways:

- **Slash syntax**: `/<skill-name> <args>` (e.g., `/remember 这事很重要`). Forwarded via `.claude/commands/` shims to the actual skill at `.harness/skills/<name>/SKILL.md`.
- **Natural language**: phrases listed in each skill's `description` field will trigger the same skill (e.g., "记一下: 这事很重要" triggers /remember). See individual SKILL.md `description` for accepted phrases.

- `/init` — **Step 2** of harness setup: fills L0/L1 slots interactively, writes `.harness/state/install.json` as the canonical "configured" marker. Re-runnable for re-configuration with `--force`. Does NOT run detection — bootstrap handles that before /init is invoked.
- `/next` — workflow state inspector: detects current feature progress and suggests next command. Doesn't auto-invoke; pure wayfinder. Use when unsure which skill to run.
- `/feature-draft <name>` — stage 1, **new-feature mode**
- `/audit-spec <name>` — stage 1, **audit mode**
- `/spec-finalize <name>` — stage 2
- `/db-schema <name>` — stage 3 (skip if no backend)
- `/execution-plan <name>` — stage 4
- `/implement <name>` — stage 5
- `/test-fix` — stage 6 (skip if `test_required = false`)
- `/commit` — stage 8
- `/constitution-edit` — edit Section 2 / Section 3 / slot registry of constitution.md. Cannot modify Section 1 (Universal Core — harness-guaranteed invariants). Generates a versioned Sync Impact Report at the top of constitution.md (Spec-Kit-pattern audit trail).
- `/add-constitution-clause` — append to Section 3 of constitution (new project-specific red line)
- `/add-anti-flag` — grow the L2 anti-flag rules over time (in AGENTS.md)

### Constitution versioning

`constitution.md` follows semver. Edits via `/constitution-edit` prepend a Sync Impact Report HTML comment at the top of the file documenting:
- Version bump (MAJOR / MINOR / PATCH)
- What changed in which section
- Downstream templates that may need review

Ad-hoc edits (raw `vim constitution.md`) skip the report. Use `/constitution-edit` for material changes — the audit trail is worth it.

Semver rules:
- **MAJOR** — removes / substantively changes an existing principle or slot
- **MINOR** — adds a new principle or slot
- **PATCH** — typo / clarification / non-semantic rewording

Section 1 (Universal Core) is harness-guaranteed and cannot be modified by `/constitution-edit`.

### Subagents (`.harness/agents/`)

Subagents enforce **mechanical rules only** — they do not exercise judgment, propose new patterns, or evaluate business logic. Judgment is the auditor's job; pattern proposals belong to the Tech Lead; intent decisions are the CEO's. A subagent finding always cites the rule source (a `CLAUDE.md` or rule file); if it can't, that's not a finding to report.

**Core three (always present):**
- **Planner** — turns CEO intent into a plain-language spec, then a per-file execution plan.
- **Programmer** — implements per the plan.
- **Reviewer (Sam)** — judgment-based auditor (default model: {{auditor_model}}), known as Sam in conversational mentions; single-engine fallback if no second model available.

**Rule-enforcement plugins** (`{{junior_reviewers}}` — user picks at /init):
<!-- ⟦L1⟧ Filled per project. Examples shipped: frontend-reviewer,
     backend-reviewer, security-reviewer, infra-reviewer. User selects
     which plugins to enable based on tech stack. -->

**Test programmer:**
- `test-fixer` — junior **programmer** (not reviewer): writes/edits test code from a fresh context. Spawned by `/test-fix`; does not exercise judgment about whether the test is right — that's the auditor's job in the post-fix audit.

### Hooks (`.harness/settings.json`)

Hooks are deterministic checks that run automatically.

- **Pre-commit typecheck** — blocks commit if static type/syntax check fails. Script: `scripts/precommit-typecheck.sh`.
- **Pre-commit lint bans** — blocks commit if anti-flag patterns are found. Script: `scripts/lint-bans.sh`.
- **Pre-commit cycles** — blocks commit if a dependency cycle is detected (enabled only if `dependency_flow` is non-empty). Script: `scripts/precommit-cycles.sh`.
- **Post-edit format** — runs the project's formatter on edited files. Script: `scripts/format-edit.sh`.
- **Budget pressure monitor** — `outcome/scripts/budget-monitor.sh` (UserPromptSubmit). Monitors transcript size; emits `additionalContext` at 50%/75%/90% of `CCC_CONTEXT_BUDGET` (default 200000 tokens) advising Claude to prefer cheaper models for subagents, skip Explore-type research, recommend `/compact`. Advisory-only; can't force model switch (Claude Code doesn't expose runtime model switching to hooks). Silent under 50%.

> **Install-time registry**: `.harness/state/shipped-hashes.json` records SHA-256 of every file the installer shipped, so re-installs can content-hash-detect "user-modified" vs "unmodified" files and safely deliver harness updates without clobbering local changes.

### Memory layer (`.harness/memory/`)

Cross-session persistence. The harness keeps a small notebook of prior decisions, failures, and observations so each new Claude Code session starts with relevant context instead of blank.

- `observations.jsonl` — append-only JSONL; one entry per decision/failure/observation
- `conventions.md` — long-form project conventions (markdown)

Mechanism:

- **SessionStart hook** (`.harness/scripts/memory-recall.sh`) reads `observations.jsonl`, scores entries by relevance to the current git branch's feature, and injects the top relevant entries into the session's additionalContext.
- **PreCompaction hook** (`.harness/scripts/memory-snapshot.sh`) instructs Claude (via additionalContext) to summarize the session's key decisions to `observations.jsonl` before context compaction proceeds. Claude does the summarization; the hook just orchestrates the prompt.
- **`/remember` skill** — user-invokable manual entry. Captures decisions/failures/observations curated by the user.

Token economics: memory recall adds ~1-3K tokens to session startup. Net savings only materialize on multi-session work on the same feature. Empty memory file → zero token impact.

Privacy: by default `.harness/memory/` is NOT gitignored — useful for team collaboration. Solo developers may add it to `.gitignore` if they prefer.

## Rule sources

<!-- ⟦L1⟧ Per-area rules live in scoped files. /init seeds an empty registry;
     /audit-spec may suggest splitting CLAUDE.md into scoped files when it
     grows past ~250 lines. Example:
       - docs/architecture/stack.md — pinned versions and rationale
       - docs/design/tokens.md       — colors, typography, spacing
       - src/<area>/CLAUDE.md        — area-specific rules
-->
{{rule_sources}}

## Never

> *Constitutional Nevers (`./constitution.md § 1-5`) are not duplicated here. Items below are operational, scoped to this file's domain.*

- Never skip workflow stages outside the explicit trivial-change or stability-fix lanes.
- Never put tech terms in `{{spec_dir}}<name>.md` (the CEO file). Tech detail goes in `{{implementation_dir}}<name>-implementation.md` or stays in code. See Two-file feature spec model § for the categorical ban list (RPC / function / table / column names, payload shapes, file paths, migration timestamps, SDK error types, etc.) and the audit-delta-ledger exclusion.
- Never hardcode secrets in code; never commit `.env`-style files.
- Never hardcode user-facing strings (use the project's i18n mechanism if any, or extract to constants otherwise).
- Never let a `{{spec_dir}}<name>-plan.md` file outlive the commit that ships its implementation. Delete it at Stage 8.
- Never let a junior reviewer subagent or `test-fixer` make a judgment call (new pattern, business logic, intent) — that's auditor / Tech Lead / CEO territory.

<!-- ⟦L2⟧ Area-specific bans (anti-flag rules) live in `.harness/anti-flag-rules.md`
     and grow over time via /add-anti-flag. /init seeds with stack-appropriate
     examples; user removes / replaces / adds as the project develops. -->
