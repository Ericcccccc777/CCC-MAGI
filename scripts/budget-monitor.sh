#!/usr/bin/env bash
# budget-monitor.sh — UserPromptSubmit hook for CCC-MAGI v2 context arch.
#
# v2 CHANGES vs v1:
#   1. Token accuracy: prefer reading `cache_read_input_tokens` + `input_tokens`
#      from transcript's most recent assistant turn (Anthropic-reported) instead
#      of byte/4 estimate. Falls back to byte/4 if transcript can't be parsed.
#   2. New 95% threshold (critical-95): emits the 3-option handoff menu
#      as a DEFERRED end-of-turn instruction. Dedupped per session via flag.
#   3. New 75% [4] option: /offload <task> for subagent isolation.
#   4. Same-level dedup: 50/75/90 advisories only fire on threshold CROSS
#      (not every prompt). Tracked in .harness/state/_budget-last-level.
#
# v2.1 (v0.10.3) CHANGES:
#   5. Auto-detect context budget from transcript's `model` field instead of
#      hardcoded 200K. Eliminates false-positive warnings for users on
#      extended-context models (e.g., Opus 4.7 [1m] = 1,000,000 tokens).
#      Resolution order: $CCC_CONTEXT_BUDGET env var (explicit override)
#      → transcript model lookup → 200K safe fallback.

set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$PROJECT_DIR/.harness/state"
LEVEL_FILE="$STATE_DIR/_budget-last-level"
HANDOFF_OFFERED_DIR="$STATE_DIR/_handoff-offered"
HANDOFF_DISMISSED_DIR="$STATE_DIR/_handoff-dismissed"

mkdir -p "$STATE_DIR" "$HANDOFF_OFFERED_DIR" "$HANDOFF_DISMISSED_DIR" 2>/dev/null || true

# ─── Read hook input ────────────────────────────────────────────────
HOOK_INPUT="$(cat 2>/dev/null || true)"

SESSION_ID=""
TRANSCRIPT_PATH=""
if [ -n "$HOOK_INPUT" ] && command -v jq >/dev/null 2>&1; then
  SESSION_ID="$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")"
  TRANSCRIPT_PATH="$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")"
fi

# No transcript = can't measure; silent exit
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# ─── Token measurement: accurate path (parse usage) ──────────────────
APPROX_TOKENS=0
if command -v jq >/dev/null 2>&1; then
  # Read most recent assistant message's `usage` field. Sum input + cache.
  # The transcript is JSONL; scan from end for first assistant entry with .message.usage.
  USAGE_LINE=$(tac "$TRANSCRIPT_PATH" 2>/dev/null | grep -m1 '"usage"' || tail -100 "$TRANSCRIPT_PATH" | grep '"usage"' | tail -1)
  if [ -n "$USAGE_LINE" ]; then
    USAGE_TOTAL=$(printf '%s' "$USAGE_LINE" | jq -r '
      (.message.usage // {}) |
      ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))
    ' 2>/dev/null || echo "0")
    if [ -n "$USAGE_TOTAL" ] && [ "$USAGE_TOTAL" -gt 0 ] 2>/dev/null; then
      APPROX_TOKENS="$USAGE_TOTAL"
    fi
  fi
fi

# Fallback to byte/4 if we couldn't read usage (e.g., new session, no assistant turns yet)
if [ "$APPROX_TOKENS" -eq 0 ] 2>/dev/null; then
  SIZE_BYTES="$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null | tr -d ' ' || echo 0)"
  APPROX_TOKENS=$((SIZE_BYTES / 4))
fi

# ─── Detect model + resolve context budget ──────────────────────────
# Priority: explicit env var > transcript model detection > 200K fallback.
# Detection looks up the most recent assistant turn's `model` field in the
# JSONL transcript; maps known model families to their context limits.
DETECTED_MODEL=""
if command -v jq >/dev/null 2>&1; then
  MODEL_LINE=$(tac "$TRANSCRIPT_PATH" 2>/dev/null | grep -m1 '"model"' || tail -100 "$TRANSCRIPT_PATH" 2>/dev/null | grep '"model"' | tail -1)
  if [ -n "$MODEL_LINE" ]; then
    DETECTED_MODEL=$(printf '%s' "$MODEL_LINE" | jq -r '.message.model // .model // empty' 2>/dev/null || echo "")
  fi
fi

CONTEXT_BUDGET="${CCC_CONTEXT_BUDGET:-}"
if [ -z "$CONTEXT_BUDGET" ]; then
  # Map model identifier to context size. The `[1m]` suffix marks Anthropic's
  # 1M-token extended-context tier (separate model ID with different pricing).
  case "$DETECTED_MODEL" in
    *"[1m]"*)
      CONTEXT_BUDGET=1000000  # Claude Opus/Sonnet 1M extended context
      ;;
    claude-opus-*|claude-sonnet-*|claude-haiku-*)
      CONTEXT_BUDGET=200000   # Standard Claude 4.x models (Opus/Sonnet/Haiku)
      ;;
    *gpt-5*|*o3*|*o4*)
      CONTEXT_BUDGET=200000   # OpenAI flagship — conservative; override via env for higher
      ;;
    *gpt-4*)
      CONTEXT_BUDGET=128000   # gpt-4 / gpt-4o / gpt-4-turbo standard
      ;;
    *)
      CONTEXT_BUDGET=200000   # Unknown model — safe default matches pre-detection behavior
      ;;
  esac
fi

if [ "$CONTEXT_BUDGET" -le 0 ]; then exit 0; fi
PCT=$((APPROX_TOKENS * 100 / CONTEXT_BUDGET))

# Build a short model label for warning messages (so users can see what was
# detected without grepping logs). Empty if unknown.
MODEL_LABEL=""
[ -n "$DETECTED_MODEL" ] && MODEL_LABEL=" / model: $DETECTED_MODEL"
[ -n "${CCC_CONTEXT_BUDGET:-}" ] && MODEL_LABEL="$MODEL_LABEL (override via CCC_CONTEXT_BUDGET)"

# ─── Determine level ────────────────────────────────────────────────
LEVEL=""
if [ "$PCT" -ge 95 ]; then
  LEVEL="critical-95"
elif [ "$PCT" -ge 90 ]; then
  LEVEL="critical"
elif [ "$PCT" -ge 75 ]; then
  LEVEL="high"
elif [ "$PCT" -ge 50 ]; then
  LEVEL="medium"
fi

if [ -z "$LEVEL" ]; then
  # Under 50%, also reset level tracker
  rm -f "$LEVEL_FILE" 2>/dev/null || true
  exit 0
fi

# ─── Dedup: only fire when level CHANGES (not every prompt at same level) ───
LAST_LEVEL=""
[ -f "$LEVEL_FILE" ] && LAST_LEVEL=$(cat "$LEVEL_FILE" 2>/dev/null || echo "")

# Special case: critical-95 (handoff menu) has its own per-session dedup
if [ "$LEVEL" = "critical-95" ]; then
  # Check session-level dedup
  if [ -n "$SESSION_ID" ]; then
    OFFERED_FLAG="$HANDOFF_OFFERED_DIR/${SESSION_ID}.flag"
    DISMISSED_FLAG="$HANDOFF_DISMISSED_DIR/${SESSION_ID}.flag"
    # If dismissed this session, stay silent forever
    if [ -f "$DISMISSED_FLAG" ]; then
      exit 0
    fi
    # If already offered this session, skip (user is either choosing or pondering)
    if [ -f "$OFFERED_FLAG" ]; then
      # Re-fire only if PCT crossed 98% (user actively typing while ignoring)
      if [ "$PCT" -lt 98 ]; then
        exit 0
      fi
    fi
    touch "$OFFERED_FLAG"
  fi
elif [ "$LEVEL" = "$LAST_LEVEL" ]; then
  # Same level as last fire → stay quiet (anti-noise rule)
  exit 0
fi
echo "$LEVEL" > "$LEVEL_FILE"

# ─── Compose message per level ──────────────────────────────────────
case "$LEVEL" in
  medium)
    MSG="⚠️ BUDGET WATCH (~${PCT}% of ${CONTEXT_BUDGET} tokens${MODEL_LABEL}). Soft warning.

Suggested for the rest of this session:
  • Prefer Sonnet over Opus for subagent dispatches where the task allows
  • Use Read tool offset/limit for large files (don't read whole files)
  • If starting a big new task, /compact would be a clean break

Behavior change is advisory; don't refuse work."
    ;;
  high)
    MSG="⚠️⚠️ BUDGET PRESSURE (~${PCT}% of ${CONTEXT_BUDGET} tokens${MODEL_LABEL}). Firm warning.

Strongly recommended:
  • Avoid Explore-type research subagents unless multi-file exploration is required
  • Prefer Sonnet / Haiku over Opus for subagent dispatches
  • Use Bash + head/grep/sed for narrow slices, not full Read on big files

NEW 4-option exit menu (surface to CEO at end-of-turn):
  [1] /compact            in-session compress conversation history
  [2] /offload <task>     spawn a fresh-context subagent for the current sub-task; main thread stays clean
  [3] /handoff            generate a session snapshot, /clear, continue in a fresh session
  [4] continue            dismiss; I'll keep going at ~${PCT}%"
    ;;
  critical)
    MSG="🚨 BUDGET CRITICAL (~${PCT}% of ${CONTEXT_BUDGET} tokens${MODEL_LABEL}). Hard warning.

Required:
  • TELL THE USER EXPLICITLY in your next response: 'Context is at ~${PCT}% — strongly recommend /handoff or /compact before continuing major work.'
  • Refuse new subagent dispatches unless absolutely required
  • Use Bash for narrow extracts only; do NOT do full-file Read on large files

If user does nothing, the 95% menu will fire next."
    ;;
  critical-95)
    MSG="🚨🚨 BUDGET 95%+ (~${PCT}% of ${CONTEXT_BUDGET} tokens${MODEL_LABEL}). Hard limit nearing.

CRITICAL INSTRUCTION: at the END of your current response (after completing the user's request, NOT mid-task), surface this 3-option menu in their OS locale:

─── Context > 95% — pick one ───────────────────────
  [1] /compact     in-session compress (geometry: ~18K floor stays; rest summarized)
  [2] /handoff     generate a session snapshot → /clear or new terminal
  [3] continue     I acknowledge; don't ask again this session
────────────────────────────────────────────────────

Rules:
  - Do NOT pop the menu mid-tool-call; finish current task first
  - If user picks [3], stay silent for the rest of THIS session (re-fires only at 98%+)
  - If user picks [2], invoke /handoff skill
  - If user picks [1], invoke /compact (Claude Code built-in)"
    ;;
esac

jq -n --arg msg "$MSG" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $msg
  }
}'

exit 0
