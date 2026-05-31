---
name: handoff
description: |
  Generate a rich 5-slot session-snapshot entry so a fresh terminal can resume this session's work. Trigger at ~95% context as one of the three options offered by budget-monitor; also user-invokable any time.

  Trigger when the user:
  - Selects "[2] /handoff" from the 95% budget menu
  - Says "handoff / 转交会话 / 移交 / hand this off / fresh start with context / 开干净的接着干"
  - Invokes /handoff explicitly

  After this skill runs, the user typically /clear's or opens a new terminal. The next session's memory-recall will surface this snapshot at top of the manifest.
allowed-tools: Bash(git status:*), Bash(git rev-parse:*), Bash(git branch:*), Bash(git log:*), Bash(cat:*), Bash(jq:*), Bash(echo:*), Bash(mkdir:*), Bash(date:*), Read, Edit, Write
argument-hint: [optional note text]
---

# /handoff

User-invoked session snapshot. Writes ONE structured entry to
`.harness/memory/sessions/recall/snapshots.jsonl` with kind `session-snapshot`.

> *Companion to the auto-snapshot path (`memory-snapshot.sh` PreCompaction hook). That fires automatically with limited context; this one is user-invoked when the user knows the session is about to end and wants a deliberate, rich snapshot.*

## When this skill is the right answer

- Context is at ~95% and you want a fresh terminal but don't want to lose state
- You're switching machines (e.g., laptop → desktop) and want resume on the other side
- You're about to step away for hours/days and want a clean handover note
- A long Stage 5 implementation needs to span 2+ sessions

## When this skill is NOT the right answer

- Below ~75% context → just continue (no need)
- Working on a totally different unrelated task → that's not a handoff, that's a new feature
- Want to permanently capture a one-off decision → use `/remember` instead

## What this skill produces

A single new line appended to `.harness/memory/sessions/recall/snapshots.jsonl`:

```json
{
  "id": "SS-2026053018a",
  "ts": "2026-05-30T18:30:00Z",
  "kind": "session-snapshot",
  "feature": "auth",
  "focus": "Resolve OTP race condition in middleware",
  "decisions": [
    {"id": "d-001", "rule": "WHEN form submits with code, THE SYSTEM SHALL validate before navigation"}
  ],
  "open_problems": [
    {"id": "p-001", "what": "Concurrent submissions cause double-charge", "blocked_by": "need DB advisory lock"}
  ],
  "next_intent": "Implement advisory lock in src/auth/middleware.ts",
  "files_touched": [
    {"path": "src/auth/middleware.ts", "why": "added validation hook"}
  ],
  "prev_session_id": "SS-2026052801",
  "source": "handoff"
}
```

## Step-by-step

### Step 0 — Detect feature and prior snapshot

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
# Derive FEATURE the same way memory-recall.sh does (feat/X-... → X)

# Find prior snapshot for same feature (for prev_session_id)
PREV_ID=$(jq -r 'select(.feature == "'"$FEATURE"'") | .id' \
  .harness/memory/sessions/recall/snapshots.jsonl 2>/dev/null | tail -1)
```

### Step 1 — Draft each of the 5 slots

You (the AI) draft each slot based on:
- **focus** (≤200 chars, 1 line): What was THIS session about? Single sentence.
- **decisions[]** (0+ entries): Significant decisions made this session. Each entry has `id` (`d-001`...) and `rule` (preferably EARS-form: WHEN/IF... THE SYSTEM SHALL ...).
- **open_problems[]** (0+ entries): Things noticed but not solved. Each has `id` (`p-001`...), `what`, and `blocked_by`.
- **next_intent** (≤200 chars, 1 line): What does the next session need to do FIRST?
- **files_touched[]** (0+ entries): Files actually modified this session. Each: `{path, why}` where why is ≤80 chars.

Pull source material from:
- TodoWrite state (if any active list)
- `git status --short` (files in flight)
- `git log -5 --oneline` (recent commits this session)
- Conversation memory of decisions made

If `$ARGUMENTS` is non-empty, prepend it as extra context to focus.

### Step 2 — Show full draft to CEO for confirmation

Present in CEO's OS locale (per `CLAUDE.md § Language Awareness`):

```
─── Handoff Snapshot Draft ─────────────────────────────

  feature       : auth
  focus         : Resolve OTP race condition in middleware
  
  decisions:
    [d-001] WHEN form submits with code, THE SYSTEM SHALL validate before navigation
    [d-002] WHEN code expired, THE SYSTEM SHALL surface error within 200ms
  
  open_problems:
    [p-001] Concurrent submissions cause double-charge
            blocked_by: need DB advisory lock
  
  next_intent   : Implement advisory lock in src/auth/middleware.ts
  
  files_touched:
    src/auth/middleware.ts   ← added validation hook
    src/auth/types.ts        ← OTP state enum
  
  prev_session_id: SS-2026052801

Snapshot will be saved to:
  .harness/memory/sessions/recall/snapshots.jsonl

Confirm?
  [1] Yes, save and continue
  [2] Edit slot: focus / decisions / open_problems / next_intent / files_touched
  [3] Cancel (do not save)
```

**Wait for user response.**

If `[2]`, ask which slot, accept edit, re-show. Loop until `[1]` or `[3]`.

### Step 3 — Write the entry

On `[1]`:

```bash
mkdir -p .harness/memory/sessions/recall

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DATE_PART=$(echo "$TS" | cut -c1-10 | tr -d '-')
# Hash-based suffix avoids collisions when multiple snapshots same day
SUFFIX=$(echo "$TS$RANDOM" | shasum | cut -c1-3)
SS_ID="SS-${DATE_PART}${SUFFIX}"

ENTRY=$(jq -c -n \
  --arg id "$SS_ID" \
  --arg ts "$TS" \
  --arg feature "$FEATURE" \
  --arg focus "$FOCUS" \
  --argjson decisions "$DECISIONS_JSON" \
  --argjson open_problems "$OPEN_PROBLEMS_JSON" \
  --arg next_intent "$NEXT_INTENT" \
  --argjson files_touched "$FILES_TOUCHED_JSON" \
  --arg prev_id "$PREV_ID" \
  '{
    id: $id,
    ts: $ts,
    kind: "session-snapshot",
    feature: (if $feature=="" then null else $feature end),
    focus: $focus,
    decisions: $decisions,
    open_problems: $open_problems,
    next_intent: $next_intent,
    files_touched: $files_touched,
    prev_session_id: (if $prev_id=="" then null else $prev_id end),
    source: "handoff"
  }')

echo "$ENTRY" >> .harness/memory/sessions/recall/snapshots.jsonl
```

### Step 4 — Squash-merge against prior same-feature snapshot

If `PREV_ID` is set AND prior snapshot is <7 days old:

- Read the prior snapshot's `decisions[]` and `open_problems[]`.
- Identify items in prior that are NOT contradicted/superseded by current snapshot's items.
- Append non-contradicted items to current snapshot's lists (preserving id, marking `from: <prev_id>`).
- Mark prior snapshot as `superseded_by: <current_id>` by APPENDING a new override line (don't edit-in-place; jsonl is append-only).

This keeps chains bounded — a long-running feature accumulates current state in one rolling snapshot, not a growing chain.

### Step 5 — Tell CEO next steps

In CEO's locale:

```
✓ Snapshot saved (id=SS-2026053018a)

Next:
  → /clear  — clears current session, fresh start with this snapshot at top of manifest
  → Or open a new terminal — same effect, snapshot will be in the recall manifest

In the next session:
  - SessionStart will show "[SS-2026053018a] feature=auth ..." in manifest
  - If you (or AI) need the body: /recall SS-2026053018a
  - The snapshot's next_intent is your starting point
```

Do NOT auto-invoke `/clear` — that's the CEO's choice.

## Trust contract

- Writes to **exactly one file**: `.harness/memory/sessions/recall/snapshots.jsonl`
- Squash-merge (Step 4) only appends; never edits older lines in place
- Never auto-clears the session (CEO's prerogative)
- Never writes if Step 2 is cancelled

## Completion criteria

- Snapshot entry appended (Step 3) and CEO has seen Step 5 next-steps message, OR
- CEO cancelled at Step 2 (nothing written)
