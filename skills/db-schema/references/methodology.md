# DB Schema Methodology

Reference document for designing, reviewing, and evolving the project's database schema. Loaded by `/db-schema` and the project's backend reviewer agent.

> **Dialect note:** the methodology is written for **relational databases with row-level access control** (the most common shape for harness-managed backends). SQL examples below use Postgres-flavored syntax; adapt to your `backend_db_type`. The discipline (12-step process, decision table, design principles) is database-agnostic — the syntax is illustrative.

This document is the **how**. The **what** (hard rules) lives in the project's backend rule doc (referenced via `{{rule_sources}}`) — read both together. Do not restate rules from there; reference them.

## Order of operations

Follow this order every time. Skipping a step causes schema drift or duplicate modeling.

### 1. Survey the existing schema — READ-ONLY

Before proposing anything, know what is already there.

Read in this order:

1. **Every file under `{{migration_dir}}`** — source of truth for schema history. Read every file, not just the latest.
2. **The project's typed-DB-bindings file** (if any) — generated typed view of the current schema. Confirms what the app currently sees.
3. **The backend MCP / database client (read-only)** — query the live database to confirm migrations and types are in sync. Flag any drift to the user immediately; do not proceed until resolved.

At the end of this step, produce a **one-paragraph summary** of the schema areas relevant to the feature:

- Which existing tables are related?
- Which existing columns might be reused?
- Which access-control policies already cover the relevant rows?

### 2. Read the feature spec

Read `{{spec_dir}}<feature>.md` (Stage 2 artifact). Extract every data requirement:

- Entities that need to be stored
- Relationships between entities
- Access patterns (who reads what, who writes what, query shape)
- Retention / deletion behavior
- Search / indexing needs

If the spec does not answer one of these, stop and ask the user. Do not guess.

### 3. Compute the delta

Decide, for each data requirement from step 2, one of:

| Outcome                                         | When                                                        |
| ----------------------------------------------- | ----------------------------------------------------------- |
| **Reuse existing table/column as-is**           | Existing model already fits                                 |
| **Add columns to existing table**               | New attribute of an existing entity                         |
| **Add index to existing table**                 | New query pattern on existing data                          |
| **Add new table**                               | New entity with no existing home                            |
| **Modify existing access-control policy**       | New access pattern changes who can read/write existing rows |
| **Add new access-control policy**               | New table or new CRUD verb on existing table                |

**Never**:

- Rename or drop a column in a single migration — write an additive migration, let the app switch, then drop in a later migration.
- Reshape an existing table to "fit" a new feature if a new table is cleaner. Solo-maintainable beats clever reuse.

### 4. Design new tables (if any)

For each new table, decide in this order:

1. **Name** — plural, snake_case (or your stack's convention), domain-prefixed only if needed to avoid ambiguity.
2. **Primary key** — UUID with the backend's generator (e.g., `id uuid primary key default gen_random_uuid()` in Postgres) is the default. Use a composite PK only for pure junction tables.
3. **Foreign keys** — every relationship declared explicitly. Decide `on delete` per relationship: `cascade` for owned children, `set null` for soft references, `restrict` when deletion should be blocked.
4. **Timestamps** — `created_at` (timezone-aware) on every table, with default `now()`. `updated_at` only if the app reads it; maintain via trigger (see step 8).
5. **Columns** — pick the narrowest correct type. Prefer timezone-aware timestamps over naive ones. Prefer unbounded text types over arbitrary length caps unless you genuinely need the cap.
6. **Constraints** — `not null` by default; only omit when nullability is meaningful. `check` constraints for enumerations and ranges. Unique constraints for business keys.

### 5. Design indexes

For every `WHERE`, `ORDER BY`, and `JOIN` column the app will use, decide:

- **Single-column index** — default for simple equality / range filters.
- **Composite index** — when queries filter on multiple columns together. Column order matters: equality columns first, then range.
- **Partial index** — when queries always filter on a boolean/enum (`WHERE is_active = true`). Reduces index size.
- **No index** — justify in a comment in the migration. Small tables (< ~1000 rows expected) may skip indexes.

Cross-reference the project's backend rule doc for any project-specific indexing rules. Every `WHERE` column either has an index or a justified exclusion comment.

### 6. Design access-control policies

For every table, for every CRUD verb the app uses, write an explicit policy.

Postgres + RLS pattern (adapt to your backend's access-control model):

```sql
create policy "<verb> own <resource>"
on <table> for <select|insert|update|delete>
to authenticated
using ( <row matches caller via {{rls_auth_function}}> )
with check ( <row being written matches caller via {{rls_auth_function}}> );
```

Rules:

- Use the project's configured `{{rls_auth_function}}` for the auth-context expression (set at /init based on `backend_db_type`).
- Default deny. If a verb has no policy, it is denied.
- Split "own rows" and "others' rows" into separate policies when access rules differ — clearer than one complex `using` expression.
- Anonymous policies only when the feature explicitly requires public access; call this out to the user.

### 7. Storage buckets (if the feature uploads files)

If the feature uploads images or files and the backend supports file storage:

1. Declare the bucket in the migration.
2. Set the file_size_limit and allowed_mime_types in bucket metadata — do not leave these open-ended.
3. Write storage access-control policies for each CRUD verb the app uses, same pattern as table-level policies.
4. Reference the project's backend rule doc for the exact constraints.

If the backend doesn't manage file storage natively, document the chosen file-storage approach in the feature's implementation notes.

### 8. Triggers (if needed)

Only add a trigger when the invariant cannot be enforced at the app layer reliably.

Common cases:

- `updated_at` auto-maintenance.
- Derived/denormalized columns that must stay in sync.
- Search-index sync (see step 9).

Every trigger declares in a comment:

- **Purpose** — what invariant it enforces
- **Firing event** — `before insert`, `after update of <cols>`, etc.
- **Privilege mode** — invoker by default; definer only with a justification comment and security/privacy review.

### 9. Search-index sync (if the table is search-indexed)

If the new/modified table feeds an external search index (Meilisearch, Elasticsearch, Algolia, etc.), document the sync mechanism in the migration file or a sibling `.md`:

- **Trigger-based** — DB trigger writes to an outbox table; an ingest worker / edge function drains it.
- **Direct push from function** — backend function synchronously updates the search index on mutation.
- **Periodic job** — only for eventual-consistency-tolerant data.

State which one and why. Required if the project's backend rule doc mandates it.

### 10. PII and security review

If the table contains any of:

- Phone numbers, email addresses, real names
- Location data (coordinates, addresses)
- Chat messages or private content
- Reports, moderation data
- Payment information
- Any other personal data per the project's PII definition

**Flag for security/privacy reviewer.** Add a `-- PII: <what>` comment (or your backend's equivalent annotation) above the relevant columns in the migration. The security/privacy reviewer is called at the end of Stage 3 — mandatorily, not conditionally.

### 11. Write the migration

One migration file per logical change. Prefer one migration per feature; split only when the feature has clearly separable phases (e.g., schema first, then seed data).

File name: `{{migration_dir}}<timestamp>_<feature_or_change>.<ext>` — generate with the project's migration tool.

Structure inside the file, in this order:

1. Create new tables
2. Alter existing tables (add columns, constraints)
3. Create indexes
4. Enable access-control on new tables
5. Create access-control policies
6. Create functions and triggers
7. Storage bucket declarations + storage policies (if applicable)
8. Comments documenting PII, trigger purposes, non-obvious decisions

**Forward-only.** Never write a down migration. To undo, write a new forward migration.

### 12. Regenerate types

After the migration is applied, run the project's type-regeneration command (configured in `.harness/scripts/post-migration.sh`).

This step is part of Stage 3 completion. A feature cannot advance to Stage 4 with stale types.

## Output of a `/db-schema` run

At the end of Stage 3, the following must exist:

- One or more new files under `{{migration_dir}}`, applied locally.
- An updated typed-DB-bindings file (if the project uses one).
- Confirmation to the user that search-index sync (if applicable) is documented.
- Backend reviewer review complete (APPROVE).
- Security/privacy reviewer review complete (APPROVE, mandatory).
- Auditor review complete (APPROVE).

## Anti-patterns to reject

- `select *` in any code — always list columns.
- Access-control disabled on a table — never. Every table ships with access-control enabled.
- "We'll add access-control later" — rejected. Policies ship with the table.
- Rationalizing a missing index with "the table will be small" without a row-count estimate.
- A policy that mixes "own" and "others'" rules in one `using` expression when splitting would be clearer.
- Renaming a column to "clean up" — always additive, never in-place.
- Business logic in database triggers when the app layer can do it — triggers are for invariants, not convenience.

## Reference

- The project's backend rule doc (in `{{rule_sources}}`) — hard rules (access-control enabled, the `{{rls_auth_function}}` pattern, forward-only, secrets, etc.)
- The project's auth rule doc (in `{{rule_sources}}`) — auth context for access-control policies
- The project's env rule doc (in `{{rule_sources}}`) — secret handling for backend functions that read/write the DB
