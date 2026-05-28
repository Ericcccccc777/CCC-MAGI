#!/usr/bin/env bash
# checkpoint-recall.sh — SessionStart hook that surfaces in-progress feature checkpoints.
#
# Wired in .claude/settings.json under SessionStart. Runs every time Claude Code
# (or compatible CLI) opens a session. If the current git branch maps to an
# in-progress feature with a checkpoint file, injects additionalContext telling
# MAGI Core to surface the resume offer at first interaction.
#
# Silent if:
#   - Not in a git repo
#   - On main / master / develop / detached HEAD
#   - No checkpoint file for the current branch's feature
#
# Output protocol:
#   - Emits JSON on stdout: {"additionalContext": "..."} when something to surface
#   - Empty stdout when nothing to surface
#   - Exit 0 always (failure to detect is not failure of the session)

set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Bail if we can't run jq
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Bail if not in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

# Get current branch name
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ -z "$BRANCH" ]; then
  exit 0  # detached HEAD
fi

# Skip on main/master/develop and tag-named branches
case "$BRANCH" in
  main|master|develop|trunk|production|release|hotfix)
    exit 0
    ;;
esac

# Derive feature slug from branch name
# Strip common prefixes: feature/, feat/, fix/, bugfix/, hotfix/, chore/
# Use perl instead of sed: BSD sed (macOS default) handles alternation
# inconsistently across hosts; perl is uniform on Mac/Linux/Git-Bash.
if command -v perl >/dev/null 2>&1; then
  # Use ! as regex delimiter (avoid / collision with path separator in pattern)
  FEATURE_SLUG=$(echo "$BRANCH" | perl -pe 's!^(feature|feat|fix|bugfix|hotfix|chore)/!!')
else
  # Fallback: shell parameter expansion (POSIX, no regex needed)
  FEATURE_SLUG="$BRANCH"
  for prefix in feature/ feat/ fix/ bugfix/ hotfix/ chore/; do
    case "$FEATURE_SLUG" in
      "$prefix"*) FEATURE_SLUG="${FEATURE_SLUG#$prefix}"; break ;;
    esac
  done
fi

# Bail if slug equals branch (no prefix stripped → probably not a feature branch)
if [ "$FEATURE_SLUG" = "$BRANCH" ]; then
  # Could be a bare feature name like "user-login" — try anyway
  :
fi

# Look for checkpoint file
CHECKPOINT_FILE=".harness/state/workflow-checkpoints/${FEATURE_SLUG}.json"
if [ ! -f "$CHECKPOINT_FILE" ]; then
  exit 0  # no checkpoint for this feature
fi

# Validate JSON
if ! jq empty "$CHECKPOINT_FILE" 2>/dev/null; then
  # Corrupted — surface a warning instead of resume offer
  cat <<JSON
{"additionalContext": "⚠️ Found a corrupted checkpoint at $CHECKPOINT_FILE for feature '$FEATURE_SLUG'. Surface to the user: 'Found a workflow checkpoint that looks corrupted. Run /resume --force-restart to ignore it, or inspect the file manually.'"}
JSON
  exit 0
fi

# Extract checkpoint summary
CURRENT_STAGE=$(jq -r '.current_stage // "unknown"' "$CHECKPOINT_FILE")
LAST_ACTIVITY=$(jq -r '.last_activity_at // "unknown"' "$CHECKPOINT_FILE")
MODE=$(jq -r '.mode // "new-feature"' "$CHECKPOINT_FILE")
LANE=$(jq -r '.lane // "full"' "$CHECKPOINT_FILE")
FILES_DONE=$(jq -r '.stage_in_progress.files_done_list // [] | length' "$CHECKPOINT_FILE")
FILES_TOTAL=$(jq -r '.stage_in_progress.files_total // 0' "$CHECKPOINT_FILE")
RESUME_HINT=$(jq -r '.stage_in_progress.resume_hint // ""' "$CHECKPOINT_FILE")

# Calculate hours since last activity (best-effort; falls back gracefully)
HOURS_AGO="unknown"
if [ "$LAST_ACTIVITY" != "unknown" ]; then
  # Try GNU date first, then BSD date
  LAST_EPOCH=$(date -d "$LAST_ACTIVITY" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_ACTIVITY" +%s 2>/dev/null || echo "")
  if [ -n "$LAST_EPOCH" ]; then
    NOW=$(date +%s)
    DIFF=$((NOW - LAST_EPOCH))
    HOURS_AGO=$((DIFF / 3600))
    if [ "$HOURS_AGO" -lt 1 ]; then
      HOURS_AGO="< 1"
    fi
  fi
fi

# Build the additionalContext message for MAGI Core to surface
# We use a literal JSON-safe message (no embedded quotes that could break jq)
MESSAGE=$(jq -n \
  --arg feature "$FEATURE_SLUG" \
  --arg branch "$BRANCH" \
  --arg stage "$CURRENT_STAGE" \
  --arg mode "$MODE" \
  --arg lane "$LANE" \
  --arg files_done "$FILES_DONE" \
  --arg files_total "$FILES_TOTAL" \
  --arg hours_ago "$HOURS_AGO" \
  --arg hint "$RESUME_HINT" \
  '{
    additionalContext: (
      "🔍 MAGI Archivist detected an in-progress feature checkpoint:\n\n" +
      "  Feature: " + $feature + " (branch: " + $branch + ")\n" +
      "  Stage: " + $stage + " (" + $mode + " / " + $lane + " lane)\n" +
      "  Progress: " + $files_done + "/" + $files_total + " files in current stage\n" +
      "  Last activity: " + $hours_ago + " hours ago\n" +
      (if $hint != "" then "  Resume hint: " + $hint + "\n" else "" end) +
      "\nOn your first response to the user, surface this naturally (do not narrate this hook — phrase it as MAGI Archivist would). Offer:\n" +
      "  [1] /resume " + $feature + "  — continue from where left off (recommended)\n" +
      "  [2] /next " + $feature + "    — see full workflow status\n" +
      "  [3] Start something new — user can ignore the resume offer\n\n" +
      "If the user gives a specific request that's clearly unrelated to this feature (e.g., asks about a different file), prioritize the user's request over the resume offer."
    )
  }')

echo "$MESSAGE"
exit 0
