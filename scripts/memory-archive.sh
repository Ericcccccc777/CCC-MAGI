#!/usr/bin/env bash
# memory-archive.sh — Tier 2 → Tier 3 migration (v2 context architecture).
#
# Scans .harness/memory/sessions/recall/*.jsonl. Entries with `ts` older than
# CCC_ARCHIVE_AGE_DAYS (default 30) are moved to
# .harness/memory/sessions/archive/<YYYY-MM>.jsonl (by entry's original month).
#
# CONTRACT (Claude Code hook spec):
#   stdin:  JSON (drained, not parsed)
#   stdout: hookSpecificOutput JSON (silent if nothing archived)
#   exit 0: always
#
# IDEMPOTENT: safe to run on every SessionStart. Skips silently if nothing
# qualifies for archival.
#
# Also assigns `id` to any entries lacking one (back-fill for v1 → v2
# migration). ID format: <KIND_PREFIX>-<YYYYMMDDNNN> where NNN is a 3-digit
# sequence number within the day.
#
# bash 3.2 compatible.

set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
RECALL_DIR="$PROJECT_DIR/.harness/memory/sessions/recall"
ARCHIVE_DIR="$PROJECT_DIR/.harness/memory/sessions/archive"
AGE_DAYS="${CCC_ARCHIVE_AGE_DAYS:-30}"

# Drain stdin
cat >/dev/null 2>&1 || true

# Required dirs
[ -d "$RECALL_DIR" ] || exit 0
mkdir -p "$ARCHIVE_DIR" 2>/dev/null || true

# jq required
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Compute cutoff timestamp (UTC ISO 8601)
CUTOFF=""
if date -u -v-${AGE_DAYS}d +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
  CUTOFF=$(date -u -v-${AGE_DAYS}d +%Y-%m-%dT%H:%M:%SZ)
else
  CUTOFF=$(date -u -d "${AGE_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
fi
[ -n "$CUTOFF" ] || exit 0

ARCHIVED_COUNT=0
RETAINED_COUNT=0

# Process each recall file
for RECALL_FILE in "$RECALL_DIR"/*.jsonl; do
  [ -f "$RECALL_FILE" ] || continue
  [ -s "$RECALL_FILE" ] || continue

  TMP_RETAIN=$(mktemp /tmp/memory-archive.retain.XXXXXX)
  trap 'rm -f "$TMP_RETAIN" 2>/dev/null || true' EXIT

  # Read each line, classify retain vs archive
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    if ! echo "$line" | jq empty >/dev/null 2>&1; then
      # malformed: retain so user can fix
      echo "$line" >> "$TMP_RETAIN"
      RETAINED_COUNT=$((RETAINED_COUNT + 1))
      continue
    fi

    entry_ts=$(echo "$line" | jq -r '.ts // ""')

    # Back-fill id if missing
    has_id=$(echo "$line" | jq -r 'has("id")')
    if [ "$has_id" = "false" ]; then
      kind=$(echo "$line" | jq -r '.kind // "observation"')
      case "$kind" in
        session-snapshot) prefix="SS" ;;
        decision)         prefix="DEC" ;;
        failure)          prefix="FAIL" ;;
        *)                prefix="OBS" ;;
      esac
      # Date part from ts (YYYYMMDD) + a content-hash-derived suffix
      date_part=$(echo "$entry_ts" | cut -c1-10 | tr -d '-')
      [ -z "$date_part" ] && date_part="00000000"
      hash_suffix=$(echo "$line" | shasum 2>/dev/null | cut -c1-3 || echo "001")
      new_id="${prefix}-${date_part}${hash_suffix}"
      line=$(echo "$line" | jq -c --arg id "$new_id" '.id = $id')
    fi

    # Compare ts to cutoff (ISO 8601 UTC string-compare works)
    if [ -n "$entry_ts" ] && [ "$entry_ts" \< "$CUTOFF" ]; then
      # Archive — destination by year-month of entry
      year_month=$(echo "$entry_ts" | cut -c1-7)
      [ -z "$year_month" ] && year_month="undated"
      ARCHIVE_FILE="$ARCHIVE_DIR/${year_month}.jsonl"
      echo "$line" >> "$ARCHIVE_FILE"
      ARCHIVED_COUNT=$((ARCHIVED_COUNT + 1))
    else
      echo "$line" >> "$TMP_RETAIN"
      RETAINED_COUNT=$((RETAINED_COUNT + 1))
    fi
  done < "$RECALL_FILE"

  # Replace recall file with retained content (atomic)
  if [ -s "$TMP_RETAIN" ]; then
    mv "$TMP_RETAIN" "$RECALL_FILE"
  else
    : > "$RECALL_FILE"
    rm -f "$TMP_RETAIN" 2>/dev/null || true
  fi
done

# If anything was archived, emit additionalContext so the AI knows
if [ "$ARCHIVED_COUNT" -gt 0 ]; then
  jq -n \
    --arg n "$ARCHIVED_COUNT" \
    --arg r "$RETAINED_COUNT" \
    --arg age "$AGE_DAYS" \
    '{
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: ("📦 Memory layer maintenance: archived " + $n + " entries older than " + $age + " days. " + $r + " entries remain in recall. Use /recall --deep <query> to search archived entries.")
      }
    }'
fi

exit 0
