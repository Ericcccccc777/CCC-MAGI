# {{project_name}} — Constitution

<!-- This file is the PROJECT CONSTITUTION. It is loaded by every agent
     (planner / programmer / reviewer / junior reviewers) BEFORE any
     other harness file. It contains the things that, if violated,
     mean this is no longer THIS project.

     Three sections:
       Section 1 — Universal core (harness-guaranteed; can't be removed)
       Section 2 — Project identity (filled at /init; edit via /constitution-edit)
       Section 3 — Project-specific red lines (starts empty; grows via /add-constitution-clause)

     CLAUDE.md describes HOW to work (workflow, lanes, tools).
     This file describes WHAT this project stands for. -->

<!-- ============================================================
SLOT REGISTRY (single source of truth for the whole harness)

Format: slot_name | level | source(s) | description

# L0 — must be filled before any work begins
project_name              | L0 | AUTO(manifest:name) → ASK_USER  | Project name
project_description       | L0 | ASK_USER                         | One-sentence project intro (plain language)
project_stage             | L0 | ASK_USER                         | early / beta / prod / scale
project_scale_target      | L0 | ASK_USER                         | Target scale
team_size                 | L0 | DEFAULT(solo) → ASK              | solo / small / large
primary_concern           | L0 | ASK_USER                         | What the harness is primarily responsible for
out_of_scope_items        | L0 | ASK_USER (list)                  | What the harness should NOT care about
auditor_model             | L0 | DEFAULT(Codex) → ASK             | Cross-model auditor display name; None = single-engine
auditor_model_id          | L1 | DEFAULT(gpt-5.5)                   | Cross-model auditor version string (for CLI config; change via /constitution-edit)
language_mode             | L0 | DEFAULT(plain) → ASK             | plain / professional
spec_dir                  | L0 | DEFAULT(docs/features/)          | Spec directory
implementation_dir        | L0 | DEFAULT(docs/features/)          | Implementation directory

# L0 — Constitution Section 2 identity slots
project_audience          | L0 | ASK_USER                         | Who we serve (one sentence)
project_non_goals         | L0 | ASK_USER                         | What we deliberately do NOT do
project_compliance        | L0 | ASK_USER                         | Compliance floors (GDPR/HIPAA/PCI/none/other)
project_performance_floor | L0 | ASK_USER                         | Performance floors
project_identity_other    | L0 | OPTIONAL                         | Other identity-level statements

# L1 — filled at appropriate stages
tech_stack                | L1 | AUTO(scan manifests)              | Primary tech stack
repo_structure            | L1 | AUTO(scan fs) → CONFIRM           | Repo structure
dependency_flow           | L1 | ASK (optional)                    | Module dependency order
release_lanes             | L1 | DEFAULT([git-push]) → ASK         | Release lanes
backend_change_lane       | L1 | OPTIONAL                          | Backend change lane
error_tracker             | L1 | ASK                                | Error tracker
test_required             | L1 | DEFAULT(true) → ASK                | Whether automated tests are enabled
junior_reviewers          | L1 | EXAMPLES → ASK                     | Which rule-enforcement reviewers to enable
rule_sources              | L1 | EMPTY → GROW                       | Index of per-domain rule files
supported_locales         | L1 | DEFAULT(["zh-Hans","en","ko"]) → ASK | Project-supported locales (i18n)
edge_case_categories      | L1 | DEFAULT(5 universal) + 3 user     | Edge-case round category list
test_framework            | L1 | AUTO(scan deps) → CONFIRM         | Test framework (jest/vitest/pytest, etc.)
test_runner_command       | L1 | AUTO(scan scripts)                | Test runner command
feature_folder_pattern    | L1 | AUTO(scan fs) → CONFIRM           | Feature folder pattern
client_code_paths         | L1 | AUTO(scan fs) → CONFIRM           | Frontend code path patterns (used to trigger reviewers)
backend_code_paths        | L1 | OPTIONAL                          | Backend code path patterns (skipped if no backend)
backend_db_type           | L1 | OPTIONAL                          | Database type; projects without a backend skip db-schema
high_trap_libraries       | L1 | EXAMPLES → ASK                     | High-risk libraries requiring context7 version verification
migration_dir             | L1 | OPTIONAL                          | Migration files directory (only if backend_db_type is set; typical default supabase/migrations/)
pii_columns               | L1 | DEFAULT([phone,email,name,address,payment]) → ASK | PII column list (used by db-schema / security-reviewer)
rls_auth_function         | L1 | OPTIONAL                          | Access-control auth-context expression (e.g., Postgres+RLS: (SELECT auth.uid()))

# L2 — grow over time
anti_flag_rules           | L2 | EXAMPLES_AS_SEED + GROW           | Anti-flag rules (in AGENTS.md)
project_red_lines         | L2 | EMPTY → GROW                       | See Section 3 of this file
============================================================ -->

---

## Section 1 — Universal core

> **Shipped with the harness. These items are this harness's load-bearing invariants. They cannot be removed, overridden, or carved out — not by lane choice, not by direct CEO instruction, not under any circumstances. The harness exists to enforce these; remove them and the harness is no longer the harness. The CEO can ADD to them but cannot REMOVE them, even by direct instruction.**

### 1. Cross-model audit is mandatory

Every code change passes the auditor ({{auditor_model}}) audit at the appropriate gate. No lane exemption, no surface exemption. The auditor is independent of the implementer — that independence is the point.

**Single-engine fallback:** if `auditor_model = None`, the audit step still runs but uses a fresh-context invocation of the same model. Bias-cancellation guarantee weakens; the discipline of a second look remains.

Pure documentation, comment-only, formatting-only, and meta-file changes are exempt.

### 2. Data ownership red line

User data never leaks into logs, errors, cache, or cross-user responses. Server-side access control enforces; client trust never substitutes for enforcement. Keeping PII out of telemetry is non-negotiable.

### 3. CEO has final authority — except on Universal Core

The CEO has the final word on intent, scope, and lane. STRONG operating preferences (see `CLAUDE.md § Operating Principles`) ARE overridable by CEO with reasoning recorded in `## Decision history`.

**Exception:** Universal Core items (Section 1 of this file) are NOT overridable, even by direct CEO instruction. The CEO cannot direct a PII leak, cannot direct skipping the auditor, cannot direct shipping without smoke test, cannot direct removing this section. If a CEO instruction would violate a Universal Core item, the manager surfaces the conflict and the instruction must be reformulated; it cannot be carried out as-stated.

Authority rules:
- A CEO rejection on a STRONG item is final; no reason required.
- A CEO decision is followed; the manager (Tech Lead / Main Claude) carries it out.
- The manager may surface risks ("CEO, this carries X risk"); after the CEO decides, the discussion ends.
- A CEO decision stands even when the manager finds it illogical — surface the disagreement, then carry out the decision.
- A CEO approval scopes only what was actually requested. It does not authorize related actions, broader changes, or repeat application in future contexts.

### 4. Real-human smoke test is mandatory

AI's self-report of "done" does not count. Before any push to GitHub, the real-human user (CEO) must run the application manually against the spec's smoke-test procedures (Stage 7 of `CLAUDE.md § Workflow`).

This step cannot be skipped, cannot be AI-substituted, and cannot be bypassed via any lane — with one narrow exception: the Trivial-change lane may skip Stage 7 for pure copy/text/translation changes (spot-check still required for any logic change).

### 5. Spec and reality stay in sync

User-visible behavior changes update the corresponding `{{spec_dir}}<name>.md` in the same commit. State-coordination invariants update `{{implementation_dir}}<name>-implementation.md` in the same commit.

Spec-vs-code drift makes the project lie about itself. Drift is caught by `/audit-spec`; correction is mandatory at the commit gate.

---

## Section 2 — Project identity

> **Filled at `/init` via 3-5 plain-language questions. Edit via `/constitution-edit`.**

**Who do we serve?**

{{project_audience}}

**What do we deliberately NOT do?**

{{project_non_goals}}

**Compliance / legal floors:**

{{project_compliance}}

**Performance floors that cannot be crossed:**

{{project_performance_floor}}

**Other "if-violated-it's-not-this-project-anymore" statements:**

{{project_identity_other}}

---

## Section 3 — Project-specific red lines

> **Starts empty. Grows via `/add-constitution-clause`.**

A rule should only be promoted to this section if it meets ALL THREE:

- **Project-wide scope** (not area-specific — area rules belong in rule sources)
- **Absolute** (no exceptions, no lane override)
- **Identity-changing** (violating it makes this no longer this project)

Most rules should stay in rule sources or anti-flag rules. Only promote here when the bar above is met.

{{project_red_lines}}
