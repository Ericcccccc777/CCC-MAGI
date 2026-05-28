---
name: abandon
description: |
  Mark an in-progress feature as abandoned. Archives the checkpoint to `_archived/<feature>-abandoned-<timestamp>.json`, logs the decision to decision-log.md, and optionally archives related artifact files (spec / implementation / plan). Does NOT touch git or source code — that's CEO's job (git revert, branch delete, etc.).
  
  Trigger when the user:
  - Invokes `/abandon <feature-slug>` or `/abandon` (resolves to current branch's feature)
  - Says "drop user-login, we're not doing it" / "放弃 user-login 这个功能" / "user-login 작업을 중단"
  - Says "remove the checkpoint for X" / "forget about the X feature"
argument-hint: <feature-slug> [--archive-artifacts] [--force]
---

# /abandon

> **MAGI position**: Operated by **MAGI Archivist**. Archivist's job is final-state record-keeping — when a feature dies, Archivist files the paperwork.

> *Constitutional basis: Stage 7 (CEO smoke test) of `CLAUDE.md § Workflow` empowers CEO to reject a feature outright. `/abandon` is the formal record of that rejection — without it, stale checkpoints accumulate and `/pickup --list` becomes noise.*

## When to use

Three legitimate scenarios:

1. **CEO rejects the feature post-spec** — after Stage 1 paraphrase + edge cases, CEO realizes the feature shouldn't exist. Abandon before any code is written.
2. **Smoke test fails irrecoverably** — after Stage 7, CEO decides the feature is fundamentally wrong. Abandon, do not `/commit`.
3. **Cleanup of dormant features** — `/pickup --list` shows a feature you started 3 months ago and never finished. If you're not going back, abandon it to clear the slot.

**Do NOT use `/abandon` for**:
- Temporary pauses (just close Claude — checkpoint persists)
- "Done shipped" features (`/commit` handles those via `--archive`)
- Renaming a feature (use `/feature-draft <new-name>` then `/abandon <old-name>`)

## What it does

```
─── /abandon user-login ───────────────────────────────────────

📂 Found checkpoint: .harness/state/workflow-checkpoints/user-login.json
   Stage: 5 (3/8 files done)
   Started: 2026-03-15 (73 days ago)
   Last activity: 2026-04-02 (54 days ago)
   
⚠️ Abandoning will:
   ✓ Move checkpoint → .harness/state/workflow-checkpoints/_archived/
   ✓ Log "abandoned" entry to .harness/memory/decision-log.md
   
Optional (use --archive-artifacts to enable):
   ◯ Move docs/features/user-login.md → docs/features/_abandoned/
   ◯ Move docs/features/user-login-implementation.md → docs/features/_abandoned/
   ◯ Move docs/features/user-login-plan.md → docs/features/_abandoned/

This does NOT touch:
   ✗ git history (use git revert / git branch -D yourself)
   ✗ Source code that was already implemented (use git checkout or git reset)
   ✗ Database migrations (run a rollback migration yourself)

Reason for abandoning? (required for decision-log)
> 
```

After user enters reason, MAGI Archivist:

```bash
# 1. Archive the checkpoint
.harness/scripts/checkpoint-write.sh \
  --feature user-login \
  --archive

# Rename archived file to mark as abandoned (not completed)
mv .harness/state/workflow-checkpoints/_archived/user-login-*.json \
   .harness/state/workflow-checkpoints/_archived/user-login-abandoned-$(date -u +%Y%m%dT%H%M%SZ).json

# 2. Log decision
.harness/scripts/decision-log-append.sh \
  --feature user-login --stage abandon --by "CEO" \
  --decision "abandoned: <user's reason>" \
  --evidence "$(git rev-parse --short HEAD 2>/dev/null || echo 'no-git')"

# 3. (if --archive-artifacts) Move artifact files
if [ "$ARCHIVE_ARTIFACTS" = "true" ]; then
  mkdir -p docs/features/_abandoned
  for artifact in docs/features/user-login.md docs/features/user-login-implementation.md docs/features/user-login-plan.md; do
    [ -f "$artifact" ] && mv "$artifact" docs/features/_abandoned/
  done
fi
```

Final report to CEO:

```
✓ Feature 'user-login' abandoned.
   Checkpoint archived: .harness/state/workflow-checkpoints/_archived/user-login-abandoned-20260528T034512Z.json
   Decision logged.
   Artifact files: kept in place (use --archive-artifacts to move)

Don't forget:
   • Delete git branch:    git branch -D feature/user-login
   • Revert unfinished code:  git checkout main -- src/auth/
   • Run any rollback migrations needed
```

## Behaviors

### No-args mode

```
/abandon
```
- Reads current git branch, derives feature slug
- If no checkpoint matches → tells user *"No checkpoint to abandon on this branch."*

### Force mode

```
/abandon user-login --force
```
- Skips the confirmation prompt
- Still requires a reason (will use `"(no reason given)"` if none provided in subsequent interaction)
- Use for scripting / programmatic cleanup

### Artifact archive mode

```
/abandon user-login --archive-artifacts
```
- Moves `docs/features/user-login*.md` to `docs/features/_abandoned/`
- Useful when the spec was misguided and shouldn't be confused with future correct specs
- Default OFF — most users prefer to keep spec for reference / future reuse

## Recovery (if you abandon by accident)

Within the same git session, an abandoned checkpoint is fully recoverable:

```bash
# Find the archived checkpoint
ls -t .harness/state/workflow-checkpoints/_archived/user-login-abandoned-*.json | head -1

# Move it back
mv .harness/state/workflow-checkpoints/_archived/user-login-abandoned-<ts>.json \
   .harness/state/workflow-checkpoints/user-login.json
```

The artifact files (if `--archive-artifacts` was used) can be moved back from `docs/features/_abandoned/` the same way.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| "No checkpoint found for `<feature>`" | Never had one OR already abandoned | Check `_archived/`; nothing to do |
| "Branch doesn't match feature slug" | You're on `main` or unrelated branch | Provide `--feature` explicitly: `/abandon user-login` |
| "decision-log-append failed" | `.harness/memory/` perms issue or jq missing | Fix perms or `brew install jq` |

## Completion criteria

- Checkpoint file moved to `_archived/` directory
- Decision-log entry written with CEO's reason
- Reason was captured (not silently abandoned)
- Final report displayed showing what happened + what user still needs to do (git, migrations)
