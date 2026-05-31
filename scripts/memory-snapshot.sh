#!/usr/bin/env bash
# memory-snapshot.sh — PreCompaction hook (v2: deterministic harvest).
#
# v1 (DEPRECATED): asked Claude to write 3 summary entries before compaction.
#   Problem: fights Sonnet 4.5+ native compaction; LLM-cost on the critical path.
#
# v2 (ACTIVE): deterministically harvests structured state already on disk
#   into a single session-snapshot entry. No LLM call. Sources:
#     1. .harness/state/scratchpad.md          (current objective + next step)
#     2. .harness/state/workflow-checkpoints/  (current feature's stage + files done)
#     3. .harness/memory/conventions.md        (project conventions, sampled)
#     4. git status --short                    (files in flight)
#
# Result is written to .harness/memory/sessions/recall/snapshots.jsonl as a
# session-snapshot entry. Survives compaction because it's on disk, not in
# chat. /handoff (user-invoked) writes richer snapshots; this is the
# fallback for un-supervised auto-compaction.
#
# CONTRACT:
#   stdin:  JSON (drained)
#   stdout: hookSpecificOutput JSON with a brief notification
#   exit 0: always
#
# bash 3.2 compatible.

set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRATCHPAD="$PROJECT_DIR/.harness/state/scratchpad.md"
CHECKPOINT_DIR="$PROJECT_DIR/.harness/state/workflow-checkpoints"
SNAP_FILE="$PROJECT_DIR/.harness/memory/sessions/recall/snapshots.jsonl"

# Drain stdin
cat >/dev/null 2>&1 || true

mkdir -p "$(dirname "$SNAP_FILE")" 2>/dev/null || true

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Determine current feature from git branch
BRANCH=""
FEATURE=""
if command -v git >/dev/null 2>&1; then
  BRANCH=$(cd "$PROJECT_DIR" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ -n "$BRANCH" ]; then
    case "$BRANCH" in
      feat/*|fix/*)
        rest="${BRANCH#*/}"
        case "$rest" in
          *-*) FEATURE="${rest%%-*}" ;;
          *)   FEATURE="$rest" ;;
        esac
        ;;
      */*) FEATURE="${BRANCH%%/*}" ;;
    esac
  fi
fi

# Read scratchpad fields (best effort)
FOCUS=""
NEXT_INTENT=""
if [ -f "$SCRATCHPAD" ]; then
  FOCUS=$(awk '/^## Current objective/{flag=1; next} /^## /{flag=0} flag' "$SCRATCHPAD" 2>/dev/null | sed '/^$/d' | head -1 | head -c 200)
  NEXT_INTENT=$(awk '/^## Next step/{flag=1; next} /^## /{flag=0} flag' "$SCRATCHPAD" 2>/dev/null | sed '/^$/d' | head -1 | head -c 200)
fi
[ -z "$FOCUS" ] && FOCUS="Auto-snapshot at compaction (no scratchpad)"
[ -z "$NEXT_INTENT" ] && NEXT_INTENT="(unset)"

# Read latest checkpoint for the feature (if any)
CHECKPOINT_FILES_DONE="[]"
CHECKPOINT_STAGE="null"
if [ -n "$FEATURE" ] && [ -f "$CHECKPOINT_DIR/${FEATURE}.json" ]; then
  CHECKPOINT_STAGE=$(jq -r '.current_stage // "null"' "$CHECKPOINT_DIR/${FEATURE}.json" 2>/dev/null || echo "null")
  CHECKPOINT_FILES_DONE=$(jq -c '.stage_in_progress.files_done_list // []' "$CHECKPOINT_DIR/${FEATURE}.json" 2>/dev/null || echo "[]")
fi

# Files in flight from git status
FILES_TOUCHED="[]"
if command -v git >/dev/null 2>&1; then
  FILES_TOUCHED=$(cd "$PROJECT_DIR" 2>/dev/null && git status --short 2>/dev/null | head -10 | awk '{print $NF}' | jq -R . | jq -sc '.' || echo "[]")
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DATE_PART=$(echo "$TS" | cut -c1-10 | tr -d '-')
RAND_SUFFIX=$(printf '%03d' $((RANDOM % 1000)))
SS_ID="SS-${DATE_PART}${RAND_SUFFIX}"

# Build snapshot entry (auto kind)
ENTRY=$(jq -c -n \
  --arg id "$SS_ID" \
  --arg ts "$TS" \
  --arg feature "$FEATURE" \
  --arg focus "$FOCUS" \
  --arg next_intent "$NEXT_INTENT" \
  --argjson checkpoint_stage "$CHECKPOINT_STAGE" \
  --argjson files_done "$CHECKPOINT_FILES_DONE" \
  --argjson files_touched "$FILES_TOUCHED" \
  '{
    id: $id,
    ts: $ts,
    kind: "session-snapshot",
    feature: (if $feature=="" then null else $feature end),
    focus: $focus,
    decisions: [],
    open_problems: [],
    next_intent: $next_intent,
    files_touched: $files_touched,
    checkpoint_stage: $checkpoint_stage,
    checkpoint_files_done: $files_done,
    source: "auto-precompaction"
  }')

echo "$ENTRY" >> "$SNAP_FILE"

# Notify Claude (this is just observational; the snapshot is already saved)
jq -n --arg id "$SS_ID" '{
  hookSpecificOutput: {
    hookEventName: "PreCompaction",
    additionalContext: ("📸 Auto-snapshot saved (id=" + $id + ") to sessions/recall/snapshots.jsonl. The next session will see this in its recall manifest. For a richer snapshot, use /handoff before compaction next time.")
  }
}'
