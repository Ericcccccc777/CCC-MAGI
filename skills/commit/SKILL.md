---
name: commit
description: This skill should be used at stage 8 of the feature workflow, after the user has completed their smoke test (stage 7) and wants to commit the changes. It inspects the staged and unstaged diff, proposes a Conventional Commits message, and runs git commit — which in turn triggers the project's pre-commit hooks. Use this always for commits; do not commit freely without this skill. Trigger when the user invokes /commit, says "commit this", "ship it", "let's commit", or similar intent.
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(git log:*), Read
argument-hint: [optional-subject-override]
---

# /commit

Drive stage 8 of the feature workflow: produce a Conventional Commits message and commit the changes. Hooks enforce quality gates.

> *Constitutional basis: Constitution § 5 (Spec and reality stay in sync) — the doc-in-sync check in Step 1 is the operational guard against spec drift at commit time. Constitution § 1 & § 4 — push to GitHub only after BOTH the CEO smoke test (Stage 7) and the auditor audit have passed.*

## Authoritative sources

1. **Conventional Commits** convention — `<type>(<scope>): <subject>` format
2. **The diff itself** — the single most important input
3. **Root `CLAUDE.md` § Doc-in-sync responsibility** — doc-in-sync rule
4. **CEO spec at `{{spec_dir}}<feature>.md`** — read when Step 1's doc-in-sync check needs to enumerate touched scenarios

## Current repo context

Inspect before proposing a message:

<git_status>
!`git status --short`
</git_status>

<git_diff_cached>
!`git diff --cached`
</git_diff_cached>

<git_diff_unstaged>
!`git diff`
</git_diff_unstaged>

<recent_commits>
!`git log -5 --oneline`
</recent_commits>

## Workflow

### Step 1 — Review what's being committed

Look at the output above.

- If there are **unstaged changes** that should be in this commit, ask the user whether to `git add` them. Do not stage blindly.
- If the **staged diff is empty**, stop. Nothing to commit. Report to the user.
- If the **staged diff mixes unrelated changes** (e.g., one feature's code + an unrelated doc fix), propose splitting into separate commits and wait for user direction.
- **Doc-in-sync check** (per root `CLAUDE.md` § Two-file feature spec model + § Doc-in-sync responsibility):

  From `git diff --name-only` (cached + unstaged), identify touched feature surfaces using `{{feature_folder_pattern}}`. For backend-touching paths (`{{backend_code_paths}}`, if configured), map to the owning feature by name match; when ambiguous, ask the user.

  For each touched feature `<X>`, decide which file the change demands updating:

  - **User-visible behavior, data model, public API** → `{{spec_dir}}<X>.md` (CEO spec)
  - **Internal tech detail only** (file split, library swap with same shape, store key rename) → `{{implementation_dir}}<X>-implementation.md`

  Check whether the appropriate file is **also in the diff**. If NOT, surface to the user before proposing the commit message:

  > "Doc-in-sync check: this commit touches `<feature>` code (paths: `<list>`) but neither `{{spec_dir}}<feature>.md` nor `{{implementation_dir}}<feature>-implementation.md` is in the diff. Per the doc-in-sync rule:
  >
  > - User-visible / data-model / API changes → CEO spec must update in same commit
  > - Internal-only refactors → implementation notes must update if the file exists; exception otherwise
  > - Stylistic / rename / formatting / behavior-preserving fixes → exception (no doc update needed)
  >
  > Which category does this commit fall into?
  >
  > - **Exception** → proceed (I'll note the category in the commit body if material)
  > - **CEO spec needs update** → halt; you update the spec, re-stage, re-invoke `/commit`
  > - **Implementation notes need update** → halt; you update the file, re-stage, re-invoke `/commit`
  > - **Override with reason** → proceed and the reason goes in the commit body"

  If user picks any "needs update" option, halt the skill cleanly. Do not proceed to Step 2.

  If multiple features are touched at once, double-check that each owning spec covers what its feature now does, and that no _untouched_ spec is silently invalidated by a cross-feature change (e.g., feature X code adds a column to a shared table that feature Y's spec also references). Heuristic only; ask the user when uncertain.

  **Do NOT skip this check.** It is the structural defense against spec drift, which Constitution § 5 mandates the harness prevent. The skill has no judgment authority to bypass it.

- **Plan file deletion check** (per root `CLAUDE.md` § Doc-in-sync responsibility / Plan files are transient): if `{{spec_dir}}<feature>-plan.md` exists for any feature touched by this commit and the implementation has landed, the plan file must be **deleted in this commit**. Surface to the user:

  > "`{{spec_dir}}<feature>-plan.md` is still in the tree. Plan files are transient — they exist for Stage 4 → Stage 5 hand-off and are deleted at Stage 8. If this commit ships the implementation, the plan file should be deleted as part of it. Delete now and re-stage?"

  Wait for confirmation. The skill stages the deletion if the user agrees.

### Step 2 — Derive the Conventional Commits message

Follow Conventional Commits:

- Format: `<type>(<scope>): <subject>`
- Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`, `style`
- `<scope>` is optional; use it when the change is clearly scoped to a feature or area
- `<subject>` is imperative, lowercase, no period
- If the user passed `$ARGUMENTS`, treat it as a subject override — honor it, but still pick the correct type/scope

Pick the type from what the diff actually does:

- New user-visible capability → `feat`
- Bug fix → `fix`
- Changes code shape without changing behavior → `refactor`
- Performance improvement only → `perf`
- Tests added/updated only → `test`
- Documentation only (including `CLAUDE.md`, `constitution.md`, scoped rule files) → `docs`
- Tooling, config, dependencies → `chore`
- Formatting only, no meaning change → `style`

**Body should reference affected scenario IDs.** When the commit changes user-visible behavior, list the scenarios from `{{spec_dir}}<feature>.md` it touches, by ID:

```
feat(<feature>): <subject>

Affected scenarios:
- <feature> scenario 3.4 (<one-line behavior description> — fix)
- <feature> scenario 3.8 (<one-line behavior description> — new)

Doc-in-sync:
- {{spec_dir}}<feature>.md updated
- {{implementation_dir}}<feature>-implementation.md updated
```

Why: months later when an error tracker regression points at a commit, `git blame` of the test that fails maps directly to a scenario ID, which maps directly to the CEO-spec section that defines the expected behavior. Trivial commits (typo, formatting) don't need this; behavior commits do.

### Step 3 — Propose, don't commit yet

Show the user:

- The type, scope, subject you chose (and a body, if the change warrants one)
- A one-line summary of what the diff actually does, so the user can sanity-check

Wait for user approval before running `git commit`.

**Wait for user response before continuing.**

### Step 4 — Commit

On approval, run:

```
git commit -m "<type>(<scope>): <subject>"
```

Or, with a body:

```
git commit -m "<subject line>" -m "<body>"
```

### Step 5 — Hook results

Pre-commit hooks run automatically (see CLAUDE.md § Hooks):

- **Pre-commit typecheck** — blocks commit on type/syntax errors
- **Pre-commit lint bans** — blocks commit on anti-flag patterns (per `{{anti_flag_rules}}` in AGENTS.md)
- **Pre-commit cycles** — blocks commit if dependency cycles detected (only enabled when `dependency_flow` is non-empty)

If a hook blocks the commit:

1. Report the hook output to the user verbatim.
2. Offer to fix the specific issues the hook flagged.
3. Do not attempt to bypass the hook (`--no-verify`) unless the user explicitly instructs, with reason.

On successful commit, report the commit hash and one-line message.

### Step 6 — State cleanup

After a successful commit, clean up transient state files for this feature:

```bash
rm -f .harness/state/auditor-approvals/<feature>-stage*.json
rm -f .harness/state/test-fix/<feature>-attempts.json
```

Why: state files exist to gate Stages 2 / 3 / 4 / 5 / 6 in flight. Once the commit lands, the gates have served their purpose; leaving them around invites confusion in future work on the same feature ("did Stage 5 already approve, or is that an old approval?"). For trivial-change and stability-fix lanes, the relevant state files are typically absent — the cleanup is a no-op then.

If a feature was committed but the user wants to start a follow-up commit on the same feature without re-running stages, ask before cleanup.

### Step 7 — Push to GitHub (only after both gates passed)

Per Constitution § 1 & § 4, push to GitHub only after BOTH:
- Stage 7 CEO smoke test PASSED
- Stage 6 / Stage 5 auditor audit returned PASS, CONCERNS, or WAIVED (FAIL halts; CONCERNS advances but should be reviewed; WAIVED requires explicit `waiver_reason` and cannot have Universal Core blocking items)

If either failed for this change, **do not push**. Surface to the user: "Push withheld — Constitution § 4 requires CEO smoke test pass before push; please complete Stage 7 then re-invoke push."

On approval, push:

```bash
git push
```

## Rules

- **Never use `--no-verify`** except on explicit user instruction with a stated reason.
- **Never commit without showing the proposed message first.** The user must see the message before it becomes history.
- **Never force-push, rebase, or rewrite history** from this skill. Out of scope.
- **Branching:** commit directly to `main` by default unless the project's commit convention says otherwise. Only use a feature branch if the user already has one checked out or explicitly asks.
- **Never squash multiple logically distinct changes into one commit.** If the diff mixes concerns, split it.
- **Never push to GitHub** if either Stage 7 (CEO smoke test) or the auditor audit has failed for this change. (Constitution § 1 & § 4.)

## Completion criteria

Stage 8 is complete when:

- A commit exists on the current branch with a message that matches Conventional Commits format
- All pre-commit hooks passed (or the user explicitly overrode them with a documented reason)
- The user has seen the resulting commit hash and message
- (If pushing) The push happened only after both the CEO smoke test and the auditor audit passed

---

## Checkpoint + decision-log integration (MAGI Archivist)

After the commit is created and (if applicable) pushed, **archive the checkpoint** — the feature is done, no more `/pickup` needed:

```bash
.harness/scripts/checkpoint-write.sh \
  --feature <feature-slug> \
  --stage-complete 8 \
  --archive
```

This moves `.harness/state/workflow-checkpoints/<feature>.json` → `.harness/state/workflow-checkpoints/_archived/<feature>-<timestamp>.json`. The archived file is gitignored but kept locally for audit / retrospective.

Log the commit decision:

```bash
.harness/scripts/decision-log-append.sh \
  --feature <feature-slug> --stage 8 --by "CEO" \
  --decision "shipped <feature>" \
  --evidence "$(git rev-parse --short HEAD)"
```

If you smoke-tested and decided NOT to ship (rollback / defer), do NOT archive — leave the checkpoint open so resume works:

```bash
.harness/scripts/decision-log-append.sh \
  --feature <feature-slug> --stage 7 --by "CEO" \
  --decision "smoke test failed: <symptom>; reverting to Stage 5 to fix"

.harness/scripts/checkpoint-write.sh \
  --feature <feature-slug> --stage 5
  # (resets current_stage; preserves audit history + stages_completed)
```
