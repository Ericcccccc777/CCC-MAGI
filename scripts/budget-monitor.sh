#!/usr/bin/env bash
# budget-monitor.sh — UserPromptSubmit hook for CCC-Harness (P1.6).
#
# Monitors Claude Code session context size by reading the transcript file
# Claude Code passes via stdin. At 50% / 75% / 90% of the configured budget,
# emits hookSpecificOutput additionalContext warnings that instruct Claude to:
#   - 50% (medium): prefer Sonnet over Opus for subagent dispatches; narrow reads
#   - 75% (high):   skip Explore-type research subagents; use Bash+head/grep
#                   instead of full Read for large files
#   - 90% (critical): refuse new subagents unless critical; surface to user
#                     that /compact is recommended
#
# DESIGN: Claude Code does not support hook-driven model switching at runtime.
# This hook is ADVISORY — it instructs Claude via additionalContext but cannot
# physically force a model change. Claude follows the guidance because the
# guidance is in its context.
#
# CONTRACT (Claude Code hook spec):
#   stdin:  JSON containing the user's prompt + transcript_path field
#   stdout: empty (under 50%) or hookSpecificOutput JSON envelope (>= 50%)
#   exit 0: hook completed
#   exit non-zero: hook failed
#
# Pattern reference: bootstrap-check.sh + memory-recall.sh
#
# Budget can be tuned via env var CCC_CONTEXT_BUDGET (default 200000 tokens,
# the historical Opus baseline). Users on 1M-context model variants set this
# higher in their .env or shell profile.

set -eu

# v0.2 PATH bug fix: scripts must work in non-interactive shells where
# ~/.zprofile isn't loaded.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ─────────────────────────────────────────────────────────────────────
# Read hook input (Claude Code passes JSON via stdin)
# ─────────────────────────────────────────────────────────────────────

HOOK_INPUT="$(cat 2>/dev/null || true)"

# We need transcript_path. Bail silently if we can't parse the JSON.
TRANSCRIPT_PATH=""
if [ -n "$HOOK_INPUT" ] && command -v jq >/dev/null 2>&1; then
  TRANSCRIPT_PATH="$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")"
fi

# If no transcript_path or file doesn't exist, exit silently. Can't measure
# without it. The hook is opportunistic — if we can't read, we no-op.
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────
# Estimate token usage
# ─────────────────────────────────────────────────────────────────────

# Use byte count as a proxy. ~4 chars per token is a rough but workable
# heuristic for English+JSON. For mixed CJK content it's closer to 2,
# but the proxy doesn't need to be perfect — the thresholds are coarse.
SIZE_BYTES="$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null | tr -d ' ' || echo 0)"
APPROX_TOKENS=$((SIZE_BYTES / 4))

# ─────────────────────────────────────────────────────────────────────
# Compute percentage of budget
# ─────────────────────────────────────────────────────────────────────

# Default 200K — Opus historical baseline. Users on 1M-context models can
# raise via env var (export CCC_CONTEXT_BUDGET=1000000 in shell profile).
CONTEXT_BUDGET="${CCC_CONTEXT_BUDGET:-200000}"

# Guard against zero/invalid budget (would div-by-zero).
if [ "$CONTEXT_BUDGET" -le 0 ]; then
  exit 0
fi

PCT=$((APPROX_TOKENS * 100 / CONTEXT_BUDGET))

# ─────────────────────────────────────────────────────────────────────
# Decide threshold level
# ─────────────────────────────────────────────────────────────────────

LEVEL=""
if [ "$PCT" -ge 90 ]; then
  LEVEL="critical"
elif [ "$PCT" -ge 75 ]; then
  LEVEL="high"
elif [ "$PCT" -ge 50 ]; then
  LEVEL="medium"
fi

# Under 50% → silent exit. Zero token overhead on lightweight sessions.
if [ -z "$LEVEL" ]; then
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────
# Emit hookSpecificOutput with budget advisory
# ─────────────────────────────────────────────────────────────────────

# Compose the additionalContext text per level. Each level escalates.
# Use jq to safely construct the JSON so embedded quotes/newlines don't
# break the payload.

case "$LEVEL" in
  medium)
    MSG="⚠️ BUDGET WATCH (~${PCT}% of ${CONTEXT_BUDGET} tokens estimated context budget). This is a soft warning — not a halt.

Recommended for the rest of this session:
  • For new subagent dispatches (Agent tool): prefer Sonnet over Opus where the task allows. Reserve Opus for tasks that genuinely need its capability.
  • Keep file reads focused (use Read tool with offset/limit for large files).
  • If the user is about to start a big new feature, surface a gentle note that /compact would help.

Behavior change is advisory. Don't refuse work; just be cost-conscious."
    ;;
  high)
    MSG="⚠️⚠️ BUDGET PRESSURE (~${PCT}% of ${CONTEXT_BUDGET} tokens estimated context budget). This is a firm warning.

Recommended for the rest of this session:
  • Avoid Explore-type research subagents unless the question genuinely requires multi-file exploration.
  • Prefer Sonnet (or Haiku for simple checks) over Opus for subagent dispatches.
  • For long file reads, use Bash + head/grep/sed to extract narrow slices instead of full Read.
  • Surface this to the user — suggest /compact at the next natural break point.

Lean cost-conscious. Don't block work, but think before each tool call."
    ;;
  critical)
    MSG="🚨 BUDGET CRITICAL (~${PCT}% of ${CONTEXT_BUDGET} tokens estimated context budget). This is a hard warning.

Strongly recommended now:
  • Refuse new subagent dispatches unless absolutely required for correctness.
  • TELL THE USER EXPLICITLY in your next response: 'Context is at ${PCT}% — strongly recommend /compact before continuing major work.'
  • Use Bash for narrow extracts only; do NOT do full-file Read on large files.
  • Postpone any non-essential work to after /compact.

The user may not realize how full the context is. Your job this turn is partly to surface that."
    ;;
esac

# Construct JSON with jq to handle escaping properly.
jq -n --arg msg "$MSG" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $msg
  }
}'

exit 0
