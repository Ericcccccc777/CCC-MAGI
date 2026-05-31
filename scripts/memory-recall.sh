#!/usr/bin/env bash
# memory-recall.sh — SessionStart hook for CCC-MAGI v2 (manifest mode).
#
# v2 CHANGE: instead of injecting full entry bodies (~2-3KB), inject ONLY a
# manifest of one-line index entries (~80 tokens each) for the AI to scan. If
# the AI decides a body is relevant per CLAUDE.md § Memory Calling Rules, it
# fetches the body explicitly via the /recall <id> skill.
#
# This cuts SessionStart token cost by ~70% on average and prevents "context
# distraction" (Drew Breunig) from eager injection.
#
# SCANS:
#   .harness/memory/sessions/recall/observations.jsonl
#   .harness/memory/sessions/recall/snapshots.jsonl
# IGNORES (Tier 3):
#   .harness/memory/sessions/archive/  (use /recall --deep instead)
#
# OUTPUT FORMAT (one line per entry):
#   [<id>] feature=<f> kind=<k> date=<YYYY-MM-DD> focus="<≤80 chars>"
#
# RANKING:
#   - Snapshots always sort BEFORE observations (higher signal density).
#   - Within each, feature-match (+5) and recency (+1 if <7d) score apply.
#   - Cap: top 12 entries OR ~1000 tokens of manifest, whichever first.
#
# bash 3.2 compatible.

set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
RECALL_DIR="$PROJECT_DIR/.harness/memory/sessions/recall"
OBS_FILE="$RECALL_DIR/observations.jsonl"
SNAP_FILE="$RECALL_DIR/snapshots.jsonl"

# Drain stdin
cat >/dev/null 2>&1 || true

# Bail if neither file exists with content
if [ ! -s "$OBS_FILE" ] && [ ! -s "$SNAP_FILE" ]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Derive current feature from git branch
BRANCH=""
if command -v git >/dev/null 2>&1; then
  BRANCH=$(cd "$PROJECT_DIR" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
fi

FEATURE=""
if [ -n "$BRANCH" ]; then
  case "$BRANCH" in
    feat/*|fix/*)
      rest="${BRANCH#*/}"
      case "$rest" in
        *-*) FEATURE="${rest%%-*}" ;;
        *)   FEATURE="$rest" ;;
      esac
      ;;
    */*)
      FEATURE="${BRANCH%%/*}"
      ;;
  esac
fi

# 7-day cutoff
CUTOFF=""
if date -u -v-7d +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
  CUTOFF=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)
else
  CUTOFF=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
fi

# Score one file's entries. Args: <file> <source_kind:snap|obs>
# Output to stdout: "<score>\t<ts>\t<id>\t<kind>\t<feature>\t<focus_or_summary>"
score_file() {
  local file="$1"
  local source_kind="$2"
  [ -s "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    if ! echo "$line" | jq empty >/dev/null 2>&1; then
      continue
    fi

    local entry_id entry_ts entry_feature entry_kind entry_focus
    entry_id=$(echo "$line" | jq -r '.id // ""')
    entry_ts=$(echo "$line" | jq -r '.ts // ""')
    entry_feature=$(echo "$line" | jq -r '.feature // ""')
    entry_kind=$(echo "$line" | jq -r '.kind // "observation"')
    # focus comes from .focus (snapshot) or .summary (observation)
    entry_focus=$(echo "$line" | jq -r '.focus // .summary // ""')
    # Truncate focus to 80 chars
    if [ "${#entry_focus}" -gt 80 ]; then
      entry_focus="${entry_focus:0:77}..."
    fi
    # Strip tabs and newlines from focus (output field separator safety)
    entry_focus=$(printf '%s' "$entry_focus" | tr '\t\n' '  ')

    [ -n "$entry_id" ] || continue  # skip entries without id (v1 entries get id'd by memory-archive.sh)

    local score=0
    # Snapshot kind bonus
    if [ "$source_kind" = "snap" ]; then
      score=$((score + 10))
    fi
    # Feature match
    if [ -n "$FEATURE" ] && [ "$entry_feature" = "$FEATURE" ]; then
      score=$((score + 5))
    fi
    # Recency
    if [ -n "$CUTOFF" ] && [ -n "$entry_ts" ]; then
      if [ "$entry_ts" \> "$CUTOFF" ] || [ "$entry_ts" = "$CUTOFF" ]; then
        score=$((score + 1))
      fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$score" "$entry_ts" "$entry_id" "$entry_kind" "${entry_feature:-general}" "$entry_focus"
  done < "$file"
}

SCORED=$(mktemp /tmp/memory-recall.XXXXXX)
trap 'rm -f "$SCORED" "$SCORED.sorted" 2>/dev/null || true' EXIT

# Score snapshots and observations
score_file "$SNAP_FILE" "snap" >> "$SCORED"
score_file "$OBS_FILE" "obs" >> "$SCORED"

if [ ! -s "$SCORED" ]; then
  exit 0
fi

# Sort by score DESC, then ts DESC
sort -t "$(printf '\t')" -k1,1nr -k2,2r "$SCORED" > "$SCORED.sorted"

# Build manifest. Cap: 12 entries OR ~1000 tokens (~4000 chars)
MAX_ENTRIES=12
MAX_CHARS=4000

HEADER="## Recent project memory — index (v2)

Below is the **manifest** of recent recall-tier entries. Each line is one entry's index, NOT its body. The full body is fetched on demand via the \`/recall <id>\` skill.

**When to fetch a body (per CLAUDE.md § Memory Calling Rules)**:
- User explicitly references prior context (\"上次 / 之前 / before / previously / we decided\")
- Current task's feature exactly matches an entry's feature
- An entry's focus indicates a prior decision relevant to your upcoming action

**Hard caps**: ≤ 3 body fetches per session. Do NOT fetch \"for completeness\".

For older entries (>30d), use \`/recall --deep <query>\` (archive tier, ≤ 1 per session).

---

"

BODY=""
count=0
total_chars=${#HEADER}

while IFS= read -r entry_line || [ -n "$entry_line" ]; do
  [ "$count" -ge "$MAX_ENTRIES" ] && break

  # Parse: score \t ts \t id \t kind \t feature \t focus
  entry_id=$(printf '%s' "$entry_line" | cut -f3)
  entry_kind=$(printf '%s' "$entry_line" | cut -f4)
  entry_feature=$(printf '%s' "$entry_line" | cut -f5)
  entry_focus=$(printf '%s' "$entry_line" | cut -f6-)
  entry_date=$(printf '%s' "$entry_line" | cut -f2 | cut -c1-10)

  manifest_line="[$entry_id] feature=$entry_feature kind=$entry_kind date=$entry_date focus=\"$entry_focus\""$'\n'

  new_chars=$((total_chars + ${#manifest_line}))
  if [ "$new_chars" -gt "$MAX_CHARS" ] && [ "$count" -gt 0 ]; then
    break
  fi

  BODY="$BODY$manifest_line"
  total_chars=$new_chars
  count=$((count + 1))
done < "$SCORED.sorted"

if [ "$count" -eq 0 ]; then
  exit 0
fi

FULL="$HEADER$BODY"
printf '%s' "$FULL" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: .
  }
}'
