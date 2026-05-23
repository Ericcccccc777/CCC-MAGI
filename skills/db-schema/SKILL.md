---
name: db-schema
description: This skill should be used whenever the project's database schema is being designed, extended, or reviewed. Trigger it when /db-schema is called, when a feature spec introduces new data requirements, when writing or reviewing any file under the project's migration directory, when evaluating whether to add a column or create a new table, when designing access-control policies, or when deciding on indexes. The skill drives stage 3 of the feature workflow and pairs with the project's backend rule doc (referenced via {{rule_sources}}) and the detailed methodology in references/methodology.md.
argument-hint: [feature-name]
optional: true
requires: backend_db_type
---

# /db-schema

Drive stage 3 of the feature workflow: assess the current database schema, design the delta for the feature, and produce a migration.

> **⟦OPTIONAL PLUGIN⟧** This skill is **only loaded when `backend_db_type` is configured** (i.e., the project has a relational data layer the harness manages). If the project has no backend, no managed database, or uses a NoSQL store where `/db-schema` does not apply, the harness should skip this stage entirely and `/spec-finalize` should route directly to `/execution-plan`. /init confirms this at setup.

> **Backend dialect note:** the methodology and examples below default to relational SQL with Postgres-flavored syntax. Adapt the SQL primitives (RLS expressions, type names, UUID generation) to your backend per the slots: `{{rls_auth_function}}`, your DB's timezone-aware timestamp type, your UUID primitive. If your backend's access-control model differs fundamentally (NoSQL document permissions, mesh authz, etc.), the discipline still applies but the syntax does not — adapt the methodology, keep the process.

## Invocation

- Typical: `/db-schema <feature-name>` (e.g., `/db-schema messaging`)
- The feature name is passed as `$ARGUMENTS` and identifies the spec file at `{{spec_dir}}$ARGUMENTS.md`.

## Authoritative sources

Before doing anything, load:

1. **The project's backend rule doc** — referenced from `{{rule_sources}}` (project-specific hard rules: RLS enabled by default, the `{{rls_auth_function}}` pattern for the project's backend, forward-only migrations, secrets handling, PII flagging, search-index sync, type regeneration, etc.)
2. **`references/methodology.md`** (in this skill directory) — the full 12-step design process
3. **`{{spec_dir}}$ARGUMENTS.md`** — the **CEO spec** (Stage 2 artifact, plain language)
4. **`{{implementation_dir}}$ARGUMENTS-implementation.md`** — the **implementation notes** (Stage 1/2 artifact, manager domain), if it exists. May contain explicit data-shape decisions; read it but don't take it as canonical — the CEO spec is canonical.

The CEO spec drives the data requirements (every persistent entity, access pattern, retention rule). The implementation notes file may contain prior tech decisions; treat them as input, not gospel.

## Workflow for this stage

1. **Survey existing schema** (read-only) — read every file under `{{migration_dir}}`, then the project's typed-DB-bindings file (if any), then query the live DB via the configured backend MCP / database client to confirm migrations and types are in sync. If drift is found, stop and report to the user before proceeding.

2. **Read the feature spec** — extract every data requirement (entities, relationships, access patterns, retention, search/indexing).

3. **Compute the delta** — for each data requirement, decide: reuse existing / add column / add index / new table / modify access-control policy / add access-control policy. Follow the decision table in `references/methodology.md` § 3.

4. **Design per methodology** — follow steps 4–10 in `references/methodology.md`: new tables, indexes, access-control policies, storage, triggers, search-index sync (if applicable), PII flagging.

5. **Present the proposal to the user** — tables to add, columns, indexes, access-control policies, PII comments. Wait for discussion and approval before writing files.

6. **On approval, write the migration file** — `{{migration_dir}}<timestamp>_$ARGUMENTS.<ext>` using the project's migration generator. Follow the file structure in `references/methodology.md` § 11.

7. **Invoke backend reviewer agent** to review the migration before it is committed. The reviewer is a **mechanical rule reviewer** — it cites rules from the project's backend rule doc (in `{{rule_sources}}`) and `references/methodology.md`. Judgment about whether the migration is _good_ belongs to the auditor in step 9.

8. **Invoke security/privacy reviewer agent** to review the migration. **Mandatory for every migration** — invocation is not conditional on the writer's self-assessment of whether PII / auth / access-control is touched. Self-assessment is a bias source; mechanical invocation removes it. On a migration that does not touch its scope, the reviewer will return `PASS` quickly; that is the cost of removing the bias.

9. **Auditor cross-model review (judgment layer).** After both junior reviewers return `PASS` (or `CONCERNS`, which advances with a warning), invoke the gate with the adversarial preset. The preset wraps the focus text below with skeptical-review framing and a code-shaped attack surface (auth, data loss, idempotency, races, partial failure, schema drift) that maps directly onto migration hazards.

   ```bash
   AUDITOR_GATE_PRESET=adversarial \
   AUDITOR_GATE_TARGET_LABEL="<feature-name> Stage 3 migration" \
   bash .harness/scripts/auditor-gate.sh review <feature-name> 3 \
     "Review this migration. Junior reviewers from {{junior_reviewers}} have approved project-rule conformance. Your job: catch what they may share blind spots on. Beyond the preset's attack surface, weigh migration-specific traps: access-control holes (a policy that compiles but doesn't enforce what the spec needs — missing 'with check' on insert/update on backends that support it, an 'OR' in the policy that grants more than intended, a USING expression that lets through rows the spec excludes); missing indexes on policy columns or foreign keys; irreversibility traps (a column add that can't be safely rolled forward without data loss, a backfill DEFAULT that is wrong for some pre-existing rows); PII gaps (a personal-data column without a PII comment, or with overly permissive access-control); enum/type evolution pitfalls (adding values is usually fine; renaming or removing values is painful). Do NOT flag: project conventions per the backend rule doc (forward-only migrations, the {{rls_auth_function}} pattern, type conventions, NOT NULL defaults, RLS-enabled-on-every-table)." \
     {{migration_dir}}<the-migration-file>
   ```

   - **Exit 0 (PASS / CONCERNS / WAIVED)** → proceed to step 10. For CONCERNS, surface the logged warning path (`.harness/audits/concerns-*.json`) and remind the CEO to review before commit. For WAIVED, surface the `waiver_reason`.
   - **Exit 2 (FAIL)** → surface every blocking item verbatim, halt. Do not apply the migration. The user fixes the issues and re-invokes `/db-schema`, or applies fixes inline and re-runs the gate manually.
   - **Exit 1 (script error / Universal Core WAIVED rejected / missing waiver_reason / legacy verdict)** → surface stderr, halt.

10. **Remind the user** to run `bash .harness/scripts/post-migration.sh` after applying the migration **locally**. The script does whatever the project needs after a migration:
    - **Refresh / reload backend caches** that don't auto-reload on `migration up` (e.g., schema caches in some setups).
    - **Regenerate typed bindings** from the live local DB. Stage 4 (execution-plan) and any feature code that imports from the typed bindings cannot proceed with stale types.
    The exact contents of `post-migration.sh` are project-specific; /init seeds it based on the configured `backend_db_type` and `tech_stack`.

11. **Check whether the app is hitting a remote backend project.** Inspect the project's `.env` (or equivalent) for the backend URL. If it points at anything other than a local instance, the migration must ALSO be pushed to the remote project — otherwise smoke-testing the feature in Stage 7 will fail against the remote, even though the local stack is healthy. Apply via the backend's MCP / CLI tool. Managed backends usually auto-refresh their schema cache after a migration applies — no separate restart needed there. Confirm per your backend's documentation.

## Trust contract

- **Surface every reviewer verdict verbatim.** No "reviewer says it's fine, proceeding." The user sees each reviewer's findings and verdict line in full before any next step is taken.
- **Reviewer invocation is mandatory and ordered.** Backend reviewer first, security/privacy reviewer second (always, not conditional on self-assessment), auditor third. Skill has no judgment authority to skip a reviewer "because the migration looks simple."
- **Auditor verdict is parsed deterministically from the gate's exit code.** No prose interpretation. The four verdicts are `PASS` (advance silently), `CONCERNS` (advance with logged warning at `.harness/audits/concerns-*.json` for CEO commit-time review), `FAIL` (halt), and `WAIVED` (CEO override only; rejected by the gate if any blocking item cites Universal Core).
- **On disagreement** (junior reviewers approve, auditor requests changes): auditor wins by default. Surface both views; user overrides explicitly if they disagree.
- **Migration is not applied locally until all three reviewers advance (PASS, CONCERNS, or — for the auditor only — a CEO-issued WAIVED with valid `waiver_reason`).** Halt-on-FAIL means actually halting; do not "apply locally to test, then fix later." CONCERNS advances but the warning must be surfaced to the CEO before commit.

## Completion criteria

Stage 3 is complete when:

- A new migration file exists under `{{migration_dir}}` and has been applied locally
- `bash .harness/scripts/post-migration.sh` has been run (cache refreshed + types regenerated)
- Backend reviewer has returned `PASS` or `CONCERNS` (FAIL halts)
- Security/privacy reviewer has returned `PASS` or `CONCERNS` (mandatory for every migration, not conditional; FAIL halts)
- `.harness/scripts/auditor-gate.sh` returned exit 0 for stage 3 (`PASS`, `CONCERNS`, or `WAIVED`) — `.harness/state/auditor-approvals/<feature>-stage3.json` exists with a non-FAIL `verdict`
- Search-index sync mechanism is documented (if applicable)

## Anti-patterns to reject

See `references/methodology.md` § "Anti-patterns to reject" for the full list. Common ones:

- `select *` in any code
- Access-control disabled on a table
- "We'll add access-control later"
- Renaming a column in place (always additive)
- Business logic in triggers when the app layer can do it
