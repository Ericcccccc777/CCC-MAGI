#!/usr/bin/env bash
# memory-recall.sh — SessionStart hook for CCC-Harness memory layer.
#
# Reads .harness/memory/observations.jsonl, scores each entry for relevance to
# the current git branch's feature, and injects the top-N entries into Claude's
# additionalContext so a new session starts with the project's prior decisions
# instead of blank.
#
# CONTRACT (Claude Code hook spec):
#   stdin:  JSON containing session info (drained — we don't need to parse it)
#   stdout: either empty (no recall) or a JSON envelope per hookSpecificOutput schema
#   exit 0: always (silent on no-op)
#
# WHEN THIS HOOK SHOULD DO NOTHING:
#   - observations.jsonl is missing or empty → silent exit
#   - No entries pass the recall filter → silent exit
#
# bash 3.2 compatible (no declare -A, no mapfile, no readarray).

set -eu

# Ensure brew-installed tools (jq, etc.) are on PATH even in non-interactive
# shells where ~/.zprofile isn't loaded. macOS Apple Silicon path comes first.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ─────────────────────────────────────────────────────────────────────
# Resolve project root + observations file
# ─────────────────────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
OBS_FILE="$PROJECT_DIR/.harness/memory/observations.jsonl"

# Drain stdin (Claude Code passes JSON; we don't need to parse it but must read it)
cat >/dev/null 2>&1 || true

# Missing or empty file → silent exit
if [ ! -f "$OBS_FILE" ]; then
  exit 0
fi
if [ ! -s "$OBS_FILE" ]; then
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────
# jq is required
# ─────────────────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "memory-recall.sh requires jq. Install with: brew install jq" >&2
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────
# Determine current context: branch + feature
# ─────────────────────────────────────────────────────────────────────
BRANCH=""
if command -v git >/dev/null 2>&1; then
  BRANCH=$(cd "$PROJECT_DIR" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
fi

# Extract feature from branch name.
# Matches: feat/<name>-* | fix/<name>-* | <name>/...
FEATURE=""
if [ -n "$BRANCH" ]; then
  case "$BRANCH" in
    feat/*|fix/*)
      # strip "feat/" or "fix/" prefix
      rest="${BRANCH#*/}"
      # take everything up to first "-" (or whole rest if no dash)
      case "$rest" in
        *-*) FEATURE="${rest%%-*}" ;;
        *)   FEATURE="$rest" ;;
      esac
      ;;
    */*)
      FEATURE="${BRANCH%%/*}"
      ;;
    *)
      FEATURE=""
      ;;
  esac
fi

# ─────────────────────────────────────────────────────────────────────
# Score each entry. Output: "<score>\t<ts>\t<line>" per entry.
# Recency: +1 if ts within last 7 days.
# Feature match: +5 if entry.feature == current feature.
# ─────────────────────────────────────────────────────────────────────
# Compute 7-days-ago cutoff (ISO 8601 UTC). macOS/Linux compatible.
CUTOFF=""
if date -u -v-7d +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
  CUTOFF=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)
else
  CUTOFF=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
fi

SCORED_FILE=$(mktemp /tmp/memory-recall.XXXXXX)
# Cleanup on exit
trap 'rm -f "$SCORED_FILE" "$SCORED_FILE.sorted" "$SCORED_FILE.filtered" "$SCORED_FILE.fallback" 2>/dev/null || true' EXIT

# Read each line, validate JSON, compute score
while IFS= read -r line || [ -n "$line" ]; do
  # skip empty/blank lines
  if [ -z "$line" ]; then
    continue
  fi
  # validate JSON; skip malformed
  if ! echo "$line" | jq empty >/dev/null 2>&1; then
    continue
  fi
  entry_ts=$(echo "$line" | jq -r '.ts // ""')
  entry_feature=$(echo "$line" | jq -r '.feature // ""')

  score=0
  # Feature match: +5
  if [ -n "$FEATURE" ] && [ -n "$entry_feature" ] && [ "$entry_feature" = "$FEATURE" ]; then
    score=$((score + 5))
  fi
  # Recency: +1 if within last 7 days
  if [ -n "$CUTOFF" ] && [ -n "$entry_ts" ]; then
    # String comparison works on ISO 8601 UTC ("Z" suffix)
    if [ "$entry_ts" \> "$CUTOFF" ] || [ "$entry_ts" = "$CUTOFF" ]; then
      score=$((score + 1))
    fi
  fi

  # Emit: score<TAB>ts<TAB>line
  printf '%s\t%s\t%s\n' "$score" "$entry_ts" "$line" >> "$SCORED_FILE"
done < "$OBS_FILE"

if [ ! -s "$SCORED_FILE" ]; then
  # No usable entries
  exit 0
fi

# Sort by score DESC, then by ts DESC (numeric on col 1, reverse on col 2)
# Using sort -k1,1nr -k2,2r
sort -t "$(printf '\t')" -k1,1nr -k2,2r "$SCORED_FILE" > "$SCORED_FILE.sorted"

# Filter to entries with score > 0 (i.e., feature-match or recent)
awk -F'\t' '$1 > 0' "$SCORED_FILE.sorted" > "$SCORED_FILE.filtered" || true

# If 0 entries pass, fall back to top 3 most-recent regardless of score
USE_FILE="$SCORED_FILE.filtered"
if [ ! -s "$SCORED_FILE.filtered" ]; then
  # Re-sort by ts DESC only
  sort -t "$(printf '\t')" -k2,2r "$SCORED_FILE" | head -3 > "$SCORED_FILE.fallback"
  USE_FILE="$SCORED_FILE.fallback"
fi

if [ ! -s "$USE_FILE" ]; then
  # Truly nothing
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────
# Build the human-readable context block.
# Limit: top 10 entries OR until accumulated text exceeds ~8000 chars.
# Format per entry:
#   [<YYYY-MM-DD>] <kind> (<feature or "general">): <summary>
#     → <details first line, truncated to ~150 chars>
# ─────────────────────────────────────────────────────────────────────
HEADER="## Recent project decisions and observations (from .harness/memory/)

The entries below are prior decisions, failures, and observations from this project — stored across CLI sessions so context doesn't get lost.

**When the user's request involves a feature, code design, or implementation decision, EXPLICITLY cite any relevant memory entry** (\"I see from memory that we decided X — going with that\"). For casual conversation (greetings, off-topic questions), citation is unnecessary.

The bar is: would a future engineer reading the session log learn something useful from the citation? If yes, cite. If no (e.g., the entry is unrelated), don't bring it up.

Even if you don't cite, treat memory as load-bearing context that shapes your answer.

"

BODY=""
count=0
total_chars=${#HEADER}
MAX_ENTRIES=10
MAX_CHARS=8000

while IFS= read -r scored_line || [ -n "$scored_line" ]; do
  if [ "$count" -ge "$MAX_ENTRIES" ]; then
    break
  fi
  # Extract third field onward (the JSON line) — handle JSON containing tabs
  # by taking everything after the second tab.
  entry_json=$(printf '%s' "$scored_line" | awk -F'\t' '{ for (i=3; i<=NF; i++) { printf "%s", $i; if (i<NF) printf "\t" } }')
  if [ -z "$entry_json" ]; then
    continue
  fi
  if ! printf '%s' "$entry_json" | jq empty >/dev/null 2>&1; then
    continue
  fi

  e_ts=$(printf '%s' "$entry_json" | jq -r '.ts // ""')
  e_kind=$(printf '%s' "$entry_json" | jq -r '.kind // "observation"')
  e_feature=$(printf '%s' "$entry_json" | jq -r '.feature // ""')
  e_summary=$(printf '%s' "$entry_json" | jq -r '.summary // ""')
  e_details=$(printf '%s' "$entry_json" | jq -r '.details // ""')

  # Date: first 10 chars of ts (YYYY-MM-DD)
  e_date="${e_ts:0:10}"
  if [ -z "$e_date" ]; then
    e_date="????-??-??"
  fi

  # Feature label
  e_feature_label="$e_feature"
  if [ -z "$e_feature_label" ] || [ "$e_feature_label" = "null" ]; then
    e_feature_label="general"
  fi

  line_main="[$e_date] $e_kind ($e_feature_label): $e_summary"
  entry_block="$line_main"$'\n'

  # Details: first line, truncated to ~150 chars
  if [ -n "$e_details" ] && [ "$e_details" != "null" ]; then
    # Take first line only
    details_first=$(printf '%s' "$e_details" | head -1)
    # Truncate to 150 chars
    if [ "${#details_first}" -gt 150 ]; then
      details_first="${details_first:0:150}..."
    fi
    if [ -n "$details_first" ]; then
      entry_block="$entry_block  → $details_first"$'\n'
    fi
  fi

  # Append separator newline between entries
  entry_block="$entry_block"$'\n'

  new_chars=$((total_chars + ${#entry_block}))
  if [ "$new_chars" -gt "$MAX_CHARS" ] && [ "$count" -gt 0 ]; then
    break
  fi

  BODY="$BODY$entry_block"
  total_chars=$new_chars
  count=$((count + 1))
done < "$USE_FILE"

if [ "$count" -eq 0 ]; then
  exit 0
fi

FULL_CONTEXT="$HEADER$BODY"

# ─────────────────────────────────────────────────────────────────────
# Emit the hookSpecificOutput JSON envelope.
# Use jq to encode the additionalContext string safely.
# ─────────────────────────────────────────────────────────────────────
printf '%s' "$FULL_CONTEXT" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: .
  }
}'
