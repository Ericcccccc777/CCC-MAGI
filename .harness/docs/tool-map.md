# Tool map — detail

> **Reference for `CLAUDE.md § Tool map`.** Loaded on demand when AI needs per-skill purpose, full subagent role inventory, hook trigger conditions, or memory mechanism details. The compact list in CLAUDE.md is the load-bearing index; this file is the elaboration.

## Bootstrap (not a skill; see top of CLAUDE.md)

Before any skill runs, the Bootstrap Status Check at the top of CLAUDE.md decides whether harness is configured. If not:
- **CCC mode**: CCC's bundled Step 1 driver runs (detects existing harness + 3-option menu + git clone)
- **Standalone mode**: `.harness/scripts/standalone-bootstrap.md` runs (same logic minus git clone, since user already cloned manually)

Both bootstrap paths converge on invoking `/init` to fill project-specific values.

## Slash commands & skills (`.harness/skills/`)

Each skill lives at `.harness/skills/<name>/SKILL.md`. Skills with a `description` are auto-discoverable and create the `/<name>` invocation.

Skills are invokable two ways:

- **Slash syntax**: `/<skill-name> <args>` (e.g., `/remember 这事很重要`). Forwarded via `.claude/commands/` shims to the actual skill at `.harness/skills/<name>/SKILL.md`.
- **Natural language**: phrases listed in each skill's `description` field will trigger the same skill (e.g., "记一下: 这事很重要" triggers /remember). See individual SKILL.md `description` for accepted phrases.

### Per-skill detail

- `/init` — **Step 2** of harness setup: fills L0/L1 slots interactively, writes `.harness/state/install.json` as the canonical "configured" marker. Re-runnable for re-configuration with `--force`. Does NOT run detection — bootstrap handles that before /init is invoked.
- `/next` — workflow state inspector: detects current feature progress and suggests next command. Doesn't auto-invoke; pure wayfinder. Use when unsure which skill to run.
- `/pickup` — session resume: reads `.harness/state/workflow-checkpoints/<feature>.json` and restores stage / artifact / progress state. Auto-surfaced at SessionStart if a checkpoint matches the current git branch. Use after multi-day breaks, cross-device work, or context-compaction loss.
- `/abandon` — mark a feature dead: moves checkpoint to `_archived/`, logs reason to decision-log. Does NOT touch git or source code (CEO's job). Use when CEO rejects a feature post-spec or when cleaning dormant features from `/pickup --list`.
- `/uninstall` — cleanly remove CCC-MAGI from the project. Detects whether a prior harness archive exists (`old_version_harness/` from bootstrap option 1); if so, offers to restore it. Preserves source code, `docs/features/*.md` specs, git history. Constitutional basis: § 3 (CEO Final Authority).
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
- `/remember` — user-curated entry into Tier 2 memory (and Tier 1 shared `decisions.jsonl` for high-signal calls)
- `/recall <id|feature|tag>` / `/recall --deep <query>` — JIT body fetch from memory tiers
- `/handoff` — user-invoked at 95% context. Generates a rich 5-slot snapshot entry into Tier 2.
- `/offload <task>` — spawn fresh-context subagent for a sub-task at ~75% budget.

## Constitution versioning

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

## Subagents (`.harness/agents/`)

Subagents enforce **mechanical rules only** — they do not exercise judgment, propose new patterns, or evaluate business logic. Judgment is MAGI Verdict's job; pattern proposals belong to MAGI Core; intent decisions are CEO's. A subagent finding always cites the rule source (a `CLAUDE.md` or rule file); if it can't, that's not a finding to report.

**Core MAGI positions (built-in):**
- **MAGI Planner** — Stage 1 + 4. Played by MAGI Core: turns CEO intent into a plain-language spec, then a per-file execution plan.
- **MAGI Programmer** — Stage 5. Played by MAGI Core: implements per the plan.
- **MAGI Tester** — Stage 6. Played by `test-fixer` subagent (fresh context, so it doesn't inherit Programmer's rationalizations).
- **MAGI Verdict** — Stages 2-6 + commit gate. Cross-model judgment auditor (default `{{auditor_model}}`). Single-engine fallback (fresh-context same-model) when no second model available.
- **MAGI Archivist** — Hook-triggered (SessionStart / PreCompaction). Memory layer service.

**MAGI Reviewer plugins** (`{{junior_reviewers}}` — user picks at /init):
<!-- ⟦L1⟧ Filled per project. Examples shipped: frontend-reviewer,
     backend-reviewer, security-reviewer, infra-reviewer. User selects
     which plugins to enable based on tech stack. -->

**Test programmer:**
- `test-fixer` — junior **programmer** (not reviewer): writes/edits test code from a fresh context. Spawned by `/test-fix`; does not exercise judgment about whether the test is right — that's the auditor's job in the post-fix audit.

## Hooks (`.harness/settings.json`)

Hooks are deterministic checks that run automatically.

- **Pre-commit typecheck** — blocks commit if static type/syntax check fails. Script: `scripts/precommit-typecheck.sh`.
- **Pre-commit lint bans** — blocks commit if anti-flag patterns are found. Script: `scripts/lint-bans.sh`.
- **Pre-commit cycles** — blocks commit if a dependency cycle is detected (enabled only if `dependency_flow` is non-empty). Script: `scripts/precommit-cycles.sh`.
- **Post-edit format** — runs the project's formatter on edited files. Script: `scripts/format-edit.sh`.
- **Budget pressure monitor** — `outcome/scripts/budget-monitor.sh` (UserPromptSubmit). Monitors transcript size; emits `additionalContext` at 50%/75%/90% of `CCC_CONTEXT_BUDGET` (default 200000 tokens) advising Claude to prefer cheaper models for subagents, skip Explore-type research, recommend `/compact`. Advisory-only; can't force model switch (Claude Code doesn't expose runtime model switching to hooks). Silent under 50%.

> **Install-time registry**: `.harness/state/shipped-hashes.json` records SHA-256 of every file the installer shipped, so re-installs can content-hash-detect "user-modified" vs "unmodified" files and safely deliver harness updates without clobbering local changes.

## Memory layer (`.harness/memory/` + `.harness/state/scratchpad.md`) — v2 3-tier

> Full architectural rationale: `docs-harness/context-architecture-v2.md`.

Cross-session persistence in 3 tiers (Letta pattern):

| Tier | Location | Purpose | In-context at SessionStart? |
|---|---|---|---|
| **1 — Working** | `.harness/state/scratchpad.md` | Current objective + last/next step + blockers; rewritten every turn (Stop hook) | ✅ Always (~500 tokens) |
| **2 — Recall** | `.harness/memory/sessions/recall/*.jsonl` (`observations` + `snapshots`) | Last 30 days of decisions/failures/snapshots | ✅ Manifest only (~500-1000 tokens), bodies on demand |
| **3 — Archive** | `.harness/memory/sessions/archive/<YYYY-MM>.jsonl` | Older entries, cold storage | ❌ Never — only via `/recall --deep <query>` |

Shared (team, committed): `conventions.md` (long-form rules) + `decisions.jsonl` (`/remember` writes here).

Mechanisms:

- **`memory-archive.sh`** (SessionStart) — migrates Tier 2 entries >30 days into Tier 3. Back-fills `id` on legacy entries. Idempotent.
- **`memory-recall.sh`** (SessionStart) — emits a **manifest** of one-line index entries from Tier 2 (`[<id>] feature=<f> kind=<k> date=<YYYY-MM-DD> focus="<≤80 chars>"`). **Does NOT load entry bodies** — that requires `/recall <id>`.
- **`scratchpad-recall.sh`** (SessionStart) — reads `scratchpad.md`, injects as additionalContext.
- **`scratchpad-update.sh`** (Stop hook) — instructs AI to rewrite scratchpad at end of each turn.
- **`memory-snapshot.sh`** (PreCompaction) — deterministically harvests scratchpad + checkpoint + git status into a snapshot entry. **No LLM call** (was v1; now deprecated).
- **`/remember`** — user-curated entry into Tier 2 (and Tier 1 shared `decisions.jsonl` for high-signal calls).
- **`/handoff`** — user-invoked at 95% context. Generates a rich 5-slot snapshot entry into Tier 2.
- **`/recall <id|feature|tag>`** / **`/recall --deep <query>`** — JIT body fetch.

Token economics (v2):
- SessionStart cost: ~1-1.5K tokens regardless of project age (Tier 1 + Tier 2 manifest, bounded). v1's eager-injection often hit 2-5K.
- Per fetch: ~1-2K tokens (body load). Hard cap: ≤3 recall + ≤1 archive search per session.
- Net: same-or-cheaper than v1 in common cases; only more expensive in extreme-history-mining sessions, where the cost is justified.
