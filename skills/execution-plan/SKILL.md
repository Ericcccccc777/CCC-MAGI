---
name: execution-plan
description: This skill should be used after a feature spec is finalized (stage 2) and (if applicable) the data-layer schema is approved (stage 3), to produce a per-file implementation checklist before writing any feature code. It is stage 4 of the feature workflow and produces {{spec_dir}}<name>-plan.md. Use this always — do not start writing feature code without a plan. Trigger when the user invokes /execution-plan, says "write the plan", "plan how to implement", "plan the implementation", "what files need to change for X", or when moving from schema to feature code.
argument-hint: [feature-name]
---

# /execution-plan

Drive stage 4 of the feature workflow: produce a per-file implementation checklist that the user can review before implementation starts.

## Invocation

- Typical: `/execution-plan <feature-name>` (e.g., `/execution-plan messaging`)
- `$ARGUMENTS` identifies the feature; reads `{{spec_dir}}$ARGUMENTS.md` and produces `{{spec_dir}}$ARGUMENTS-plan.md`.

## Authoritative sources

Load before planning:

1. **`{{spec_dir}}$ARGUMENTS.md`** — finalized **CEO spec** from Stage 2 (plain language)
2. **`{{implementation_dir}}$ARGUMENTS-implementation.md`** — manager-domain implementation notes from Stage 1/2 (when present); contains routing tables, state keys, library decisions, etc. that the plan should respect
3. **Stage 3 migration** (if this feature touches the data layer and `backend_db_type` is configured) — produced under `{{migration_dir}}` by `/db-schema`
4. **Root `CLAUDE.md`** — repo structure, dependency flow, tool map, two-file model, lanes
5. **`constitution.md`** — universal core (audit invariant, spec-reality sync, smoke-test mandate)
6. **`{{rule_sources}}`** — scoped rule docs (pinned versions, design tokens, area-specific conventions)

## Version verification rule (context7)

Claude's training data has an effective cutoff. For libraries that have moved past it with breaking API changes, Claude confidently suggests stale APIs — sometimes with plausible-looking method names that no longer exist. This catches plan-time staleness before it cascades into Stage 5 implementation.

### When to verify via `context7`

**Always verify** when the plan references the API surface of any library in `{{high_trap_libraries}}` (filled at /init based on the project's stack — typically frameworks / SDKs / libraries with frequent breaking changes).

**Also verify** any other external library / SDK / platform API where version-specific behavior is load-bearing for the decision (a native module's TS API surface, a CLI tool's flag set, etc.).

### When to skip

- Language primitives (`useState`, `Array.map`, `Promise.all`, `Object.entries`, etc., per the project's primary language)
- Stable, long-lived framework patterns
- Project-internal code
- Patterns where a recent commit or test in this codebase already exercises them correctly — that's stronger evidence than docs

### Inline annotation

Each verified decision gets a bullet attached to its file or step in the plan:

```
- [ ] `<path>/<file>` — <one-line purpose>
  • verified: <library> <version> — <key facts>. (context7)
```

Inline annotations make verification auditable later — future-you (or the implementer) can see which decisions were checked and which weren't.

### When `context7` fails

If `context7` is unreachable or returns nothing useful for a library, do NOT guess. Annotate `• unverified: <library> — recommend manual check before implementation` and surface to the user before finalizing the plan.

### Canonical-source escalation

`context7` is a third-party docs mirror. Its snapshots can be incomplete. The rule above is sufficient for **additive** lookups (verifying an API before using it). For two cases the bar is higher:

**Destructive findings.** When a lookup conclusion would drive a _removal_, _deletion_, _rename_, or contradicts working code already in the repo, you MUST also fetch the canonical source — official docs site or upstream GitHub README — via WebFetch, and cite the URL. `context7` alone is not enough.

**Negative findings.** Concluding "feature X is unsupported" or "field Y doesn't exist" requires positive citation of an exhaustive reference (e.g., a "supported fields" table on the canonical doc page) that demonstrably omits it. "I queried `context7` and didn't see it" is NOT a valid basis for action — the mirror's snapshot may be incomplete.

**Asymmetric burden.** Adding new code based on a lookup needs one source. Removing or contradicting working code based on a lookup needs canonical confirmation. Working configuration is its own evidence; deleting it needs stronger proof than confirming a missing line in one mirror.

**URL in annotation.** When the citation is canonical, format the annotation as `(canonical: <URL>)` instead of `(context7)` so the source is auditable later. Both forms are valid; the format makes the strength of the citation visible.

## Workflow

1. **Read the spec** — extract every screen, user action, data dependency, and external integration.

2. **Walk the feature folder structure** — for this feature, decide which subfolders are needed based on `{{feature_folder_pattern}}`. Typical shapes (adapt to the project's actual structure):

   - `<feature_root>/screens/` or equivalent entry layer
   - `<feature_root>/components/` (UI building blocks)
   - `<feature_root>/hooks/` or `<feature_root>/composables/` (behavior)
   - `<feature_root>/queries/` or `<feature_root>/api/` (data access)
   - `<feature_root>/utils/` (optional)
   - `<feature_root>/contexts/` or `<feature_root>/store/` (optional)
   - Route / entry-point wiring (if the project has a router)

3. **Identify cross-layer work** — does this feature need:

   - New shared UI primitives? (If yes, list each with a note on platform-divergence needs.)
   - New shared helpers? (Only if another feature will reuse.)
   - New i18n keys for any of `{{supported_locales}}`? (List them by namespace.)
   - Backend changes (only if `backend_code_paths` is configured)?
   - Other integrations (search index, queue, etc.)?

4. **Build the file-by-file checklist** using the template below. As you write each entry whose correctness depends on a specific library version's behavior, **verify against current docs via `context7`** (see "Version verification rule" above) and add the inline `• verified:` annotation.

5. **Flag any open design decisions** that surfaced while planning. Do not resolve them unilaterally — stop and ask the user.

6. **Present the plan** — the user reviews and approves before auditor judgment audit (Step 7). **Wait for user response before continuing.**

7. **Auditor judgment audit on the plan.** Run after the user approves the file list and any open decisions are resolved:

   ```bash
   bash .harness/scripts/auditor-gate.sh review <feature> 4 \
     "Review this execution plan against the CEO spec at {{spec_dir}}<feature>.md, the implementation notes (if present) at {{implementation_dir}}<feature>-implementation.md, the migration at {{migration_dir}} (if applicable), and the project's pinned-versions doc (if any). Your job: catch what shared-model planning may miss before any code is written. Look for: false assumptions in library API surface (a planned call that doesn't exist in the pinned version, a method signature that changed); dependency-flow violations (per the project's declared {{dependency_flow}}, if non-empty); plan-spec contradictions (the plan implements scenario X.Y differently from how the CEO spec describes it; a scenario classified as [Required automated test] in the spec has no test entry in the plan); missing files (a referenced new component / hook / query has no corresponding 'Files to create' entry; an i18n key set used by the plan isn't listed); risk areas the plan glosses over (a complex async flow with no explicit error/timeout strategy; a long list view with no memoization plan); whether the implementation order will compile cleanly at each step (e.g., a hook that imports from a query that doesn't yet exist). Do NOT flag: project conventions already in scoped CLAUDE.md files or {{anti_flag_rules}} (those are reviewer territory at Stage 5); formatting; naming preferences; refactor opinions; speculative future-proofing." \
     {{spec_dir}}<feature>-plan.md
   ```

   Read the gate's exit code:

   - **Exit 0 (PASS / CONCERNS / WAIVED)** — surface any advisory items. For CONCERNS, also surface the logged warning path (`.harness/audits/concerns-*.json`) and remind the CEO to review before commit. For WAIVED, surface the `waiver_reason`. Stage 4 complete; user may proceed to `/implement <feature>`.
   - **Exit 2 (FAIL)** — surface every blocking item verbatim. Halt. Update the plan to address findings, re-invoke `/execution-plan` (or have the gate re-run manually after edits).
   - **Exit 1 (script error / Universal Core WAIVED rejected / missing waiver_reason / legacy verdict)** — surface stderr, halt.

   The gate writes `.harness/state/auditor-approvals/<feature>-stage4.json`. Stage 5 (`/implement`) checks for this file's existence.

## Plan template

Write the plan to `{{spec_dir}}$ARGUMENTS-plan.md`:

```markdown
# Execution plan: <Feature Name>

Spec: `{{spec_dir}}$ARGUMENTS.md`
Migration: `{{migration_dir}}<timestamp>_$ARGUMENTS.<ext>` (or N/A — no backend changes)

## Scope of this plan

One paragraph. What this plan covers and what it defers.

## Files to create

### Feature code (under <feature_root>)

- [ ] `screens/<Name>Screen.<ext>` — <one line>
- [ ] `queries/use<Entity>.<ext>` — <one line>
      • verified: <library> <version> — <key facts> (context7) ← only when API-surface depends on version
- [ ] `components/<Component>.<ext>` — <one line>
- [ ] `hooks/use<Behavior>.<ext>` — <one line>
- ...

### Route / entry wiring (if applicable)

- [ ] `<route-path>` — re-export or mount the screen

### New shared UI primitives — only if existing ones don't cover

- [ ] `<Primitive>` — <why needed, including platform divergence notes if any>

### Shared helpers — only if multi-feature reuse is required

- [ ] `<helper>` — <why shared>

### Backend (only if `backend_code_paths` is configured)

- [ ] Migration already produced in Stage 3
- [ ] Function / endpoint `<path>` — <purpose> (if applicable)

### i18n keys (for each locale in `{{supported_locales}}`)

- [ ] `$ARGUMENTS.title`
- [ ] `$ARGUMENTS.<key>`
- ...

## Files to modify

- [ ] `<path>` — <what changes>

## Tests

Per the project's testing convention. Co-locate or follow `{{test_framework}}`'s convention.

- [ ] `queries/use<Entity>.test.<ext>` — <scenarios>
- [ ] `components/<Component>.test.<ext>` — <scenarios>
- [ ] `hooks/use<Behavior>.test.<ext>` — <scenarios>

## Implementation order

A numbered sequence that minimizes integration pain. Typically:

1. Queries and hooks (data layer)
2. Components (pure UI)
3. Screens (compose components + hooks)
4. Route / entry wiring
5. Tests alongside each of the above
6. i18n keys (can run in parallel with earlier steps)

## Open decisions

Numbered list of things surfaced during planning that the user must decide.

## Review gates

- [ ] Junior reviewers from `{{junior_reviewers}}` (mechanically selected from diff paths at Stage 5)
- [ ] Auditor ({{auditor_model}}) judgment audit at Stage 5
```

## Completion criteria

Stage 4 is complete when:

- `{{spec_dir}}$ARGUMENTS-plan.md` exists
- User has reviewed and approved the file list and order
- All open decisions surfaced during planning are resolved or explicitly deferred
- Every plan entry whose correctness depends on a versioned library API has a `• verified:` annotation (or an explicit `• unverified:` with reason)
- `.harness/scripts/auditor-gate.sh` returned exit 0 for stage 4 (`PASS`, `CONCERNS`, or `WAIVED`) — `.harness/state/auditor-approvals/<feature>-stage4.json` exists with a non-FAIL `verdict`. CONCERNS advances but the logged warning must be surfaced to the CEO before commit.

Do not start writing feature code during Stage 4. The plan is the Stage 4 artifact; code is Stage 5.

---

## Checkpoint + decision-log integration (MAGI Archivist)

After auditor-gate passes for Stage 4:

```bash
.harness/scripts/checkpoint-write.sh \
  --feature <feature-slug> \
  --stage 5 \
  --stage-complete 4 \
  --artifact-plan docs/features/<feature-slug>-plan.md \
  --append-audit "$(jq -c '{stage:4, verdict, risk:.risk_score, at:now|todate}' .harness/state/auditor-approvals/<feature>-stage4.json)"

# Log any material trade-off the plan made (e.g., chose technique X over Y):
.harness/scripts/decision-log-append.sh \
  --feature <feature-slug> --stage 4 --by "CEO" \
  --decision "<e.g. 'chose pessimistic lock over optimistic; reads are 10x more common'>"
```
