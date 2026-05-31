---
name: next
description: Inspect the current workflow state and suggest the next CCC-MAGI command. Use when the user doesn't know which skill to invoke next, or wants a sanity check on workflow progress. Reads constitution.md + spec_dir + git state; does NOT auto-invoke any other skill. Trigger when the user invokes /next OR says any of these (any language; match by intent, not exact wording) — English "what's next", "where am I", "next step", "what should I do", "what now", "I'm lost", "which skill should I run"; 中文「下一步干嘛」「下一步该跑啥」「接下来咋办」「接下来呢」「现在该做啥」「现在该跑哪个 skill」「我该跑啥」「我迷路了」「下一步推荐」; 日本語「次は何」「次どうする」「次のステップ」; 한국어「다음 뭐 해야」「다음 단계」「뭘 해야 돼」; or similar workflow-disambiguation intent in any locale.
allowed-tools: Read, Bash(test:*), Bash(ls:*), Bash(git rev-parse:*), Bash(git status:*), Bash(git branch:*), Bash(grep:*), Bash(find:*)
argument-hint: <optional feature name>
---

# /next

Inspect the current state of the project and the active feature, then **suggest** the next CCC-MAGI command to run. This skill is a wayfinder — it never auto-invokes another skill, never modifies any file. Decision authority stays with the user.

> *Companion to the 9-stage workflow + 13 skills. The harness intentionally requires explicit confirmation at every stage; `/next` reduces the cognitive cost of figuring out which stage you're at without erasing the discipline.*

## Language Awareness

This skill's instructions are in English. When you talk to the user (presenting state, the recommendation, asking clarifying questions), use the user's OS locale language. See `CLAUDE.md § Language Awareness`. File paths, slot names, JSON keys, and skill names (`/feature-draft`, etc.) stay in English regardless of locale.

## What this skill produces

A single human-readable status block in the user's locale that:

1. States the detected feature and inferred workflow stage.
2. Lists the filesystem signals it read.
3. Recommends the next command (or asks for disambiguation if state is ambiguous).
4. Surfaces alternative commands the user might pick instead.

**This skill writes nothing to disk.** It is read-only.

---

## Step 0 — Pre-flight: is CCC-MAGI configured?

Check `.harness/state/install.json` exists:

```bash
test -f .harness/state/install.json
```

If it does NOT exist, print exactly:

```
❌ CCC-MAGI is not configured for this project (no .harness/state/install.json).

Next: run /init to configure.
```

Then halt the skill. Do not proceed to later steps.

---

## Step 1 — Resolve current feature

If `$ARGUMENTS` is non-empty, use that string (trimmed) as the feature name and skip auto-detection.

Otherwise, auto-detect in priority order:

1. **Git branch name.** Run `git rev-parse --abbrev-ref HEAD 2>/dev/null`. If the branch matches one of these patterns, extract `<name>`:
   - `feat/<name>-...` or `feat/<name>` (no trailing dash)
   - `fix/<name>-...` or `fix/<name>`
   - `audit/<name>-...` or `audit/<name>`

2. **Most recently modified spec file.** Look in `${spec_dir}` (resolved at Step 2) for `<feature>.md` files (exclude `<feature>-plan.md` and `<feature>-implementation.md`). Pick the one with the newest modification time as the candidate feature.

3. **Ask the user.** If neither yields a feature, list any `<feature>.md` files found in `${spec_dir}` and ask:

   ```
   I couldn't auto-detect which feature you're working on.

   Either:
     - Tell me the feature name (I'll inspect its state)
     - Or list active features: I see <list of <name>.md files in spec_dir>

   Wait for user response before continuing.
   ```

   Wait for the user's reply. Do not guess.

---

## Step 2 — Read constitution.md to find directories

Read `constitution.md` to extract slot values:

- `spec_dir` — feature spec directory. Default fallback: `docs/features/`.
- `implementation_dir` — implementation notes directory. Default fallback: `docs/features/`.
- `backend_db_type` — used in Step 3 to decide whether to check for a schema doc.

If `constitution.md` is missing or unreadable, fall back to the defaults above and note the fallback in the final report.

---

## Step 3 — Inspect filesystem state for the feature

Compute these state booleans for the resolved feature. Use the resolved directory values from Step 2.

- `SPEC_EXISTS` — `test -f "${spec_dir}${feature}.md"`
- `SPEC_FINALIZED` — only if `SPEC_EXISTS`: `grep -q "FINALIZED" "${spec_dir}${feature}.md"`
- `IMPL_EXISTS` — `test -f "${implementation_dir}${feature}-implementation.md"`
- `PLAN_EXISTS` — `test -f "${spec_dir}${feature}-plan.md"`
- `BACKEND_PROJECT` — `backend_db_type` slot is non-empty and not `none`
- `SCHEMA_DOC_EXISTS` — heuristic: `test -f "${implementation_dir}${feature}-schema.md"` OR any file matching `${implementation_dir}${feature}-schema*.md`. If uncertain after these checks, treat as `false` and note the uncertainty in the report rather than guessing.
- `GIT_HAS_CHANGES` — `git status --porcelain` returns at least one line.
- `STATE_AUDITS_EXIST` — `test -d .harness/state/auditor-approvals` AND `ls .harness/state/auditor-approvals/${feature}-*.json 2>/dev/null` returns ≥1 entry.
- `CHECKPOINT_EXISTS` — `test -f .harness/state/workflow-checkpoints/${feature}.json`
- `CHECKPOINT_DATA` — if `CHECKPOINT_EXISTS`: parse with `jq '.current_stage, .stages_completed, .stages_skipped, .last_activity_at, .stage_in_progress'` for state cross-check.

If any check errors out (e.g., directories don't exist yet), treat the corresponding boolean as `false` and continue.

### Step 3a — Cross-check filesystem state vs checkpoint (MAGI Archivist)

If `CHECKPOINT_EXISTS`, the checkpoint is the **canonical truth** for workflow state. Filesystem booleans serve as drift detection:

- If checkpoint says `current_stage = 5` but `SPEC_EXISTS = false` → drift; surface to CEO ("Checkpoint expects spec at `${spec_dir}${feature}.md` but it's missing. Suggest /pickup to inspect, or /feature-draft to restart").
- If checkpoint says `stages_skipped: [3]` and reason is "no backend" → skip Stage 3 in the recommendation.
- If checkpoint's `stage_in_progress.files_done_list` is non-empty → the user is mid-Stage-5; suggest `/pickup` instead of `/implement` (resume picks up at the right file).
- If `last_activity_at` is > 7 days ago → add a flag: "Last activity 8 days ago — `/pickup` for context recall recommended."

Without checkpoint, fall back to pure filesystem inference (existing logic below).

---

## Step 4 — Determine workflow stage + recommended next command

Apply this state machine in priority order. The first matching branch wins.

```
IF NOT SPEC_EXISTS:
  → Stage: 0 (pre-Stage 1)
  → Suggest: /feature-draft ${feature}
  → Reason: "No spec file yet at ${spec_dir}${feature}.md."

ELIF SPEC_EXISTS AND NOT SPEC_FINALIZED:
  → Stage: 1 done, Stage 2 pending
  → Suggest: /spec-finalize ${feature}
  → Reason: "Spec exists but not FINALIZED. Run /spec-finalize to lock it in."

ELIF SPEC_FINALIZED AND BACKEND_PROJECT AND NOT SCHEMA_DOC_EXISTS:
  → Stage: 2 done, Stage 3 pending
  → Suggest: /db-schema ${feature}
  → Reason: "Spec finalized; backend project but no schema design yet. Run /db-schema (or skip if no DB change)."

ELIF SPEC_FINALIZED AND NOT PLAN_EXISTS:
  → Stage: 3 done (or skipped), Stage 4 pending
  → Suggest: /execution-plan ${feature}
  → Reason: "Spec ready. Time to write the per-file execution plan."

ELIF PLAN_EXISTS AND NOT GIT_HAS_CHANGES:
  → Stage: 4 done, Stage 5 not started
  → Suggest: /implement ${feature}
  → Reason: "Plan exists but no code changes yet. Run /implement to start coding."

ELIF PLAN_EXISTS AND GIT_HAS_CHANGES:
  → Stage: 5 in progress
  → Suggest: /test-fix OR continue /implement ${feature}
  → Reason: "Code changes detected. Either continue /implement or move to /test-fix when implementation is done."

ELIF GIT_HAS_CHANGES AND NOT PLAN_EXISTS:
  → Lane: stability-fix or trivial-change (no Stage 4 plan needed)
  → Suggest: /test-fix (if test_required) then /commit
  → Reason: "Changes detected without a plan file. This looks like a trivial-change or stability-fix lane. Run /test-fix (if test_required) then /commit when ready."

ELIF NOT GIT_HAS_CHANGES AND PLAN_EXISTS:
  → Stage: 6 / 7 done; plan file expected to be deleted at Stage 8 (commit)
  → Suggest: /commit
  → Reason: "Looks like all stages done. Run /commit to ship + clean up the plan file."

ELSE:
  → Idle state
  → Suggest: /feature-draft <new-feature>  OR  /audit-spec <existing-feature>
  → Reason: "No active work detected. Either start a new feature or audit an existing one."
```

If the detected state matches multiple branches in confusing ways (e.g., plan exists AND a different feature has uncommitted changes), default to **surfacing the ambiguity** to the user rather than picking one — see Step 5.

---

## Step 5 — Present the recommendation

Print a structured report in the user's locale. Use this shape (translate the prose; keep skill names, file paths, and slot names verbatim):

```
📍 Current state for feature: <feature>

Stage: <stage number / name>
Workflow lane: <inferred lane — full / stability-fix / trivial — or "ambiguous, ask">

Detected state:
  ✓/✗ Spec exists (${spec_dir}${feature}.md)
  ✓/✗ Spec FINALIZED
  ✓/✗ Implementation notes (${implementation_dir}${feature}-implementation.md)
  ✓/✗ Plan file (${spec_dir}${feature}-plan.md)
  ✓/✗ Git uncommitted changes
  ✓/✗ Auditor approvals on file

▶ Recommended next: <command>

Reason: <one-sentence explanation>

You can also (NL-first — just tell me in plain words; slash forms shown in parens only as fallback):
  - Switch features: name the other feature (e.g., "看 X 这个 feature")
  - Start something new: tell me what to build (e.g., "做个 X 功能")
  - Audit an existing feature: ask me to check it (e.g., "审一下 X")
  - See full workflow stages: see CLAUDE.md § Workflow
```

After printing, **wait for the user to respond** (Spec-Kit discipline). Do NOT auto-invoke the recommended command. The user has to type the command explicitly themselves.

If the state was ambiguous, replace the `▶ Recommended next` line with:

```
▶ Ambiguous — please clarify:
  <enumerate the candidate next commands and which signal points to each>
```

…and wait for the user's pick.

---

## Rules / Anti-patterns

- **NEVER auto-invoke another skill** — `/next` only suggests; the user must explicitly type the recommended command.
- **NEVER modify any file** — read-only inspection. No writes to `.harness/state/`, no edits to constitution.md or spec files.
- **NEVER run `git commit` or `git push`** — out of scope.
- **NEVER guess a feature name from prose** — only the explicit `$ARGUMENTS`, the git branch pattern, or the most-recently-modified spec file are authoritative. If none yield a feature, ask the user.
- **NEVER translate file paths, slot names, or skill names** — those stay in English regardless of locale.
- **Surface ambiguity rather than picking arbitrarily** — if multiple features look active or the state doesn't match a single branch cleanly, ask the user instead of guessing.

---

## Trust contract

- This skill writes to **zero files**. It is strictly read-only.
- It reads at most: `constitution.md`, `.harness/state/install.json`, files in `${spec_dir}` and `${implementation_dir}`, and runs read-only git commands (`rev-parse`, `status`, `branch`).
- The user always types the next command themselves — `/next` is a wayfinder, not an autopilot.

---

## Completion criteria

`/next` is complete when:

- Step 0 has run (CCC-MAGI presence verified, or skill halted with the install message).
- Step 1 has resolved a feature name (either from `$ARGUMENTS`, auto-detection, or a user response).
- Steps 2–4 have computed state and selected a recommendation (or flagged ambiguity).
- Step 5 has displayed the report to the user and the skill has stopped without invoking any other command.
