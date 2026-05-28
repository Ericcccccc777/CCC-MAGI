---
name: pickup
description: |
  Resume an in-progress feature from where you left off (across sessions, devices, days). Reads `.harness/state/workflow-checkpoints/<feature>.json` and restores: which stage you were at, which artifacts exist, what files were already implemented, what audit verdicts have been issued, and what CEO decisions were made.
  
  Trigger when the user:
  - Invokes `/pickup` (no args = resume current git-branch's feature; with feature name = resume that one)
  - Says "continue where I left off" / "继续上次的进度" / "前回の続きから" / "이어서 작업"
  - Says "what was I doing on user-login?" / "user-login 我做到哪了？"
  - Reopens Claude on a branch that matches an existing checkpoint (SessionStart hook auto-surfaces this)
argument-hint: [<feature-slug>] [--list] [--force-restart]
---

# /pickup

> *Operational basis: Stage 7 of `CLAUDE.md § Workflow` (CEO smoke test) and Stage 8 (commit) presume a coherent workflow state. When a session is interrupted between stages, `/pickup` reconstructs that state.*

> **MAGI position**: This skill is operated by **MAGI Archivist** (per `AGENTS.md § MAGI System`). Archivist's job is to recall and announce prior state, then hand control back to MAGI Core for the next stage.

## When to use

Three common entry points:

1. **Cross-day continuation** — you stopped Friday at Stage 5 (3/8 files done), come back Monday. `/pickup` picks up exactly there.
2. **Cross-device continuation** — you started on laptop, finish on desktop. Both have the same git branch + checkpoint file (if committed) or separate checkpoint files (if gitignored, which is the default).
3. **Session timeout / compaction loss** — context window filled up, conversation compacted. `/pickup` reloads the structural state without re-paraphrasing every prior decision.

## What it produces

Standard output (in user's locale):

```
─── MAGI Archivist · Resume Report ─────────────────────────────

📂 Feature: user-login
   Branch: feature/user-login
   Mode: new-feature (full lane)
   
   Started:        2026-05-25 14:00
   Last activity:  2026-05-26 18:30  (16 hours ago)
   
   ─── Progress ───────────────────────────────────
   ✅ Stage 1 — spec drafted        (docs/features/user-login.md, sha 4f7a)
   ✅ Stage 2 — spec finalized      (MAGI Verdict: PASS, risk=3)
   ⏭️  Stage 3 — db schema           (skipped: no backend)
   ✅ Stage 4 — execution plan      (docs/features/user-login-plan.md)
                                     (MAGI Verdict: CONCERNS, risk=6)
                                     ↳ CEO accepted, added index before commit
   ⏳ Stage 5 — implementing        (3 of 8 files done)
       ✓ src/auth/types.ts
       ✓ src/auth/session.ts
       ✓ src/auth/login.ts
       ▢ src/auth/middleware.ts     ← next
       ▢ src/auth/index.ts
       ▢ tests/auth/login.test.ts
       ▢ tests/auth/session.test.ts
       ▢ src/routes/auth.ts
   ⬜ Stage 6 — test-fix             (pending)
   ⬜ Stage 7 — CEO smoke            (pending — CEO required for this)
   ⬜ Stage 8 — commit               (pending)
   
   ─── Recent decisions (from decision-log.md, 3 most recent) ───
   • 2026-05-26 15:00 — CEO: "accept index on session_id"
   • 2026-05-26 14:50 — MAGI Verdict: CONCERNS — session_id needs index
   • 2026-05-25 14:05 — CEO: "edge case #3 (race condition) is in scope"

What now?
   [1] Continue Stage 5 — pick up at src/auth/middleware.ts (recommended)
   [2] Re-run MAGI Verdict on Stage 4 (re-validate before continuing)
   [3] /status — see full checkpoint detail
   [4] /abandon user-login — mark this feature dead
   [5] Switch to different feature
> 
```

## How to invoke

### No args — resume current branch's feature
```
/pickup
```
- Reads current git branch (e.g., `feature/user-login`)
- Strips prefix `feature/` → feature slug `user-login`
- Reads `.harness/state/workflow-checkpoints/user-login.json`
- Surfaces the report above
- If no checkpoint exists for this branch → tells user: *"No checkpoint for user-login. Start fresh with /feature-draft, or run /pickup --list to see other features."*

### Explicit feature name
```
/pickup user-login
```
- Reads `.harness/state/workflow-checkpoints/user-login.json` regardless of current branch
- If user is on a different branch, asks: *"Switch to feature/user-login first? [Y/n]"*

### List all in-progress
```
/pickup --list
```
Outputs:
```
In-progress features:
   ● user-login          Stage 5  (16h ago)  ← current branch
   ○ notifications       Stage 2  (3 days ago)
   ○ billing             Stage 1  (5 days ago)
   ○ admin-dashboard     Stage 6  (1 day ago)  ⚠️ test-fix iter 3/3, escalate
```

### Force restart from current stage
```
/pickup --force-restart
```
- Re-loads the checkpoint but invalidates the "in-progress" state of the current stage
- Useful when you want to redo Stage 5 from scratch (e.g., wholesale plan change)
- Does NOT reset prior stages' artifacts — those are kept

## Checkpoint schema (for reference; auto-written by stage skills)

Path: `.harness/state/workflow-checkpoints/<feature-slug>.json`

```json
{
  "schema_version": 1,
  "feature": "user-login",
  "feature_slug": "user-login",
  "branch": "feature/user-login",
  "started_at": "2026-05-25T14:00:00Z",
  "last_activity_at": "2026-05-26T18:30:00Z",
  "mode": "new-feature",                    // or "audit"
  "lane": "full",                            // or "stability-fix" / "trivial"
  "current_stage": 5,
  "stages_completed": [1, 2, 4],
  "stages_skipped": [3],
  "stages_skipped_reasons": {"3": "no backend"},
  "artifacts": {
    "spec":           {"path": "docs/features/user-login.md", "sha256": "4f7a...", "exists": true},
    "implementation": {"path": "docs/features/user-login-implementation.md", "sha256": "8c11...", "exists": true},
    "plan":           {"path": "docs/features/user-login-plan.md", "sha256": "2bb0...", "exists": true},
    "schema":         null
  },
  "audits": [
    {"stage": 2, "verdict": "PASS",     "risk": 3, "at": "2026-05-25T14:30:00Z"},
    {"stage": 4, "verdict": "CONCERNS", "risk": 6, "at": "2026-05-26T14:50:00Z"}
  ],
  "stage_in_progress": {
    "stage_number": 5,
    "files_total": 8,
    "files_done_list":      ["src/auth/types.ts", "src/auth/session.ts", "src/auth/login.ts"],
    "files_remaining_list": ["src/auth/middleware.ts", "src/auth/index.ts", "tests/auth/login.test.ts", "tests/auth/session.test.ts", "src/routes/auth.ts"],
    "last_action": "Wrote src/auth/login.ts (87 lines)",
    "resume_hint": "Continue /implement from src/auth/middleware.ts (5 files remaining)"
  },
  "decisions": [
    {"at": "2026-05-25T14:05:00Z", "stage": 1, "by": "CEO", "decision": "edge-case #3 (race condition) is in scope"},
    {"at": "2026-05-26T14:50:00Z", "stage": 4, "by": "MAGI Verdict", "decision": "CONCERNS — session_id needs index"},
    {"at": "2026-05-26T15:00:00Z", "stage": 4, "by": "CEO", "decision": "accept index addition before commit"}
  ],
  "session_chain": [
    {"session_id": "abc-123", "started": "2026-05-25T14:00:00Z", "ended": "2026-05-25T15:30:00Z"},
    {"session_id": "def-456", "started": "2026-05-26T14:00:00Z", "ended": "2026-05-26T18:30:00Z"}
  ]
}
```

## How checkpoints get written (built into stage skills)

Each stage skill writes/updates the checkpoint at its END:

| Stage skill | What it writes |
|---|---|
| `/feature-draft <name>` | Creates checkpoint. `current_stage = 1`, artifact.spec recorded |
| `/audit-spec <name>` | Creates or updates. `current_stage = 1` (audit mode) |
| `/spec-finalize <name>` | `current_stage = 2`, audit verdict appended |
| `/db-schema <name>` | `current_stage = 3`, audit verdict appended. Skipped → `stages_skipped += [3]` |
| `/execution-plan <name>` | `current_stage = 4`, audit verdict appended, artifact.plan recorded |
| `/implement <name>` | `current_stage = 5`. **Updates `stage_in_progress.files_done_list` after every Edit/Write tool use** (via PostToolUse hook) |
| `/test-fix` | `current_stage = 6`, audit verdict appended |
| `/commit <name>` | `current_stage = 8`, all stages marked complete, then checkpoint moved to `.harness/state/workflow-checkpoints/_archived/<feature>-<timestamp>.json` |

If you implement a new stage skill, follow the same pattern (see `/implement` for the reference implementation of mid-stage progress tracking).

## How the welcome-back UX works

The SessionStart hook (`outcome/scripts/checkpoint-recall.sh` wired in `.claude/settings.json`) runs every time Claude Code opens:

1. Reads current git branch (`git symbolic-ref HEAD`)
2. Strips `feature/` / `feat/` / `fix/` prefix → feature slug
3. Tests for `.harness/state/workflow-checkpoints/<slug>.json` — if exists, reads it
4. Injects `additionalContext` to Claude: *"There's an in-progress feature `user-login` at Stage 5 (3/8 files done). The user may want to /pickup; surface it on first interaction."*
5. Claude (acting as MAGI Core) greets the user with the resume offer at first response

This is the same pattern Continue.dev uses with `HistoryManager.loadLastSession()` but feature-scoped instead of session-scoped.

## What this skill does NOT do

- **Doesn't roll back code** — if you have uncommitted changes that conflict with the checkpoint's expected state (e.g., you manually deleted a file the checkpoint says is done), `/pickup` warns but doesn't auto-fix. You decide.
- **Doesn't re-run MAGI Verdict automatically** — even if `last_activity_at` is months ago, prior verdicts still stand. Run `/audit-spec` to re-validate if you need a fresh judgment.
- **Doesn't handle multi-developer conflict** — checkpoint is gitignored, so two devs on the same feature have independent checkpoints. Git branch is the conflict resolution mechanism, not the checkpoint.
- **Doesn't replace `/next`** — `/next` is the workflow status inspector (which command should I run next?). `/pickup` is the state restoration mechanism (what was I doing?). Both are complementary.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| "No checkpoint for current branch" | You're on a non-feature branch (e.g., `main`) or this feature was started without going through the standard skills | Start the feature via `/feature-draft <name>` to create a checkpoint |
| "Checkpoint references missing file `<path>`" | An artifact was manually deleted | Either restore the file from git or use `/feature-draft <name> --reset` to redo Stage 1 |
| "Multiple checkpoints found, ambiguous" | Branch name doesn't cleanly map to feature slug | Use explicit form: `/pickup <feature-slug>` |
| "Checkpoint schema version mismatch" | You upgraded CCC-MAGI to a newer schema | The harness offers `/pickup --migrate-checkpoint` to upgrade old checkpoints |

## Completion criteria

- Checkpoint read successfully → MAGI Archivist surfaces full report
- User picks a continuation option → control hands to the appropriate stage skill (e.g., `/implement` for Stage 5 continuation)
- If no checkpoint exists → tell the user clearly + suggest `/feature-draft <name>` to start one
