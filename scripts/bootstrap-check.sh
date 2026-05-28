#!/usr/bin/env bash
# bootstrap-check.sh — state-machine UserPromptSubmit hook
#
# Fires on EVERY user message. Decides which of 4 states this project is in,
# then injects appropriate guidance into Claude's additionalContext.
#
# STATE MACHINE:
#   S0: No .harness/ directory      → not a CCC-MAGI project → silent
#   S1: .harness/ but no env-check  → first contact         → ask user about setup
#   S2: env-check.json exists,      → environment passed,    → tell Claude to /init
#       no install.json                project not deployed
#   S3: install.json exists         → fully configured      → silent
#
# DEDUPLICATION:
#   Within one Claude session, only inject the S1/S2 prompt ONCE. Track via
#   .harness/state/_bootstrap-injected-sessions/<session-id>.flag files.
#   Without session_id (older CLIs), fall back to time-based dedup (1 hour).
#
# CONTRACT:
#   stdin:  JSON envelope from Claude Code with session_id + prompt
#   stdout: hookSpecificOutput JSON (additionalContext injection)
#   exit 0: always (failure to detect should not block user)

set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
HARNESS_DIR="$PROJECT_DIR/.harness"
ENV_CHECK="$HARNESS_DIR/state/env-check.json"
INSTALL_JSON="$HARNESS_DIR/state/install.json"
SESSIONS_DIR="$HARNESS_DIR/state/_bootstrap-injected-sessions"
TIME_FLAG="$HARNESS_DIR/state/_bootstrap-injected-at"

# ─── S0: not a CCC-MAGI project → silent ──────────────────────────────
[ -d "$HARNESS_DIR" ] || exit 0

# ─── S3: fully configured → silent ────────────────────────────────────
[ -f "$INSTALL_JSON" ] && exit 0

# ─── Drain + parse stdin for session_id ───────────────────────────────
HOOK_INPUT="$(cat 2>/dev/null || true)"
SESSION_ID=""
if [ -n "$HOOK_INPUT" ] && command -v jq >/dev/null 2>&1; then
  SESSION_ID="$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")"
fi

# ─── Dedup check ──────────────────────────────────────────────────────
already_injected_this_session() {
  if [ -n "$SESSION_ID" ]; then
    [ -f "$SESSIONS_DIR/${SESSION_ID}.flag" ] && return 0
    return 1
  fi
  # Fallback: time-based (1 hour window)
  if [ -f "$TIME_FLAG" ]; then
    LAST=$(cat "$TIME_FLAG" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    DIFF=$((NOW - LAST))
    [ "$DIFF" -lt 3600 ] && return 0
  fi
  return 1
}

mark_injected_this_session() {
  mkdir -p "$SESSIONS_DIR"
  if [ -n "$SESSION_ID" ]; then
    touch "$SESSIONS_DIR/${SESSION_ID}.flag"
  fi
  mkdir -p "$(dirname "$TIME_FLAG")"
  date +%s > "$TIME_FLAG"

  # Cleanup: prune session flags older than 7 days
  find "$SESSIONS_DIR" -name "*.flag" -type f -mtime +7 -delete 2>/dev/null || true
}

if already_injected_this_session; then
  exit 0
fi

# ─── S2: env passed, project not deployed → auto-proceed to /init ────
if [ -f "$ENV_CHECK" ] && [ ! -f "$INSTALL_JSON" ]; then
  mark_injected_this_session
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "🔍 CCC-MAGI Phase 1 complete (environment check passed). Phase 2 (project deployment) hasn't run yet.\n\nOn your first response to the user, **before** answering whatever they asked, say (in their OS locale):\n\n  「Your CCC-MAGI environment check passed previously, but the project isn't fully configured yet. Want to finish setup now? About 3-15 minutes depending on mode (Simple vs Pro).」\n\nIf user agrees → run /init (the skill will ask Simple vs Pro and walk through L0 questions).\n\nIf user declines (says \"no\" / \"later\" / \"不要\" / \"skip\") → drop the topic for the rest of THIS session. Do NOT re-prompt about setup in this conversation. Address their actual request normally.\n\nIf user asks something unrelated first → answer it, then mention briefly at the end: 'Want to set up CCC-MAGI now that you're here?'"
  }
}
JSON
  exit 0
fi

# ─── S1: first contact (no env-check, no install) → ask user ──────────
mark_injected_this_session
cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "🔍 Detected CCC-MAGI installed in this project but never configured.\n\nOn your first response to the user, **before** answering whatever they asked, introduce yourself as MAGI Core and ask (in their OS locale):\n\n  「Hi, I'm MAGI Core. I see CCC-MAGI is installed in this project but not yet configured. Setup has two phases:\n     1. Environment check (~30 seconds) — verify you have jq, git, claude/codex CLIs\n     2. Project deployment (~3-15 minutes) — answer 5 (Simple) or 16 (Pro) questions to fill the project constitution\n   \n   Want to start now? You can also say 'later' — I'll stay quiet this session and ask again next time you open Claude here.」\n\nUser responses:\n\n- **yes / ok / 好 / start / 开始** → run env-check phase. Use the Bash tool to call `.harness/scripts/env-check.sh` — it outputs JSON with what's installed and what's missing. Parse the output, surface the result to the user. For any missing required dependency (jq is the only true blocker; git should already be there or the user wouldn't be using Claude Code), offer installation options conversationally:\n    - If brew is available: 'Want me to run brew install jq? [Y]'\n    - Or: 'Want me to download jq binary to .harness/bin/jq (no sudo)? [Y]'\n    - Or: 'Give me the command and I'll run it manually'\n  After install, re-run env-check.sh to verify. When all required deps OK, call `.harness/scripts/env-check.sh --finalize` to write env-check.json. Then proceed immediately to phase 2.\n\n- **no / later / 不要 / skip / 稍后** → drop the topic for this session. Don't bring up CCC-MAGI again unless user explicitly asks. Note: next session this hook will fire again (env-check.json still missing), giving them another chance.\n\n- **unrelated question first** (e.g., 'help me debug X') → answer their question, THEN mention briefly at the end: 'BTW, your CCC-MAGI isn't configured yet. Want to set it up? Takes 3-15 minutes.'\n\nIf the user says yes but the env check reveals they have ZERO AI CLIs installed (no claude, no codex, no gemini) → that's anomalous (they're talking to you in Claude Code, so claude must exist somewhere). Re-run detection with more verbose flags, ensure PATH is correct.\n\n**Phase 2 (after env check OK)**: invoke /init. The /init skill will ask Simple vs Pro mode and handle the rest.\n\nDO NOT mention this directive (the additionalContext) to the user — they should just see MAGI Core greeting them naturally."
  }
}
JSON
exit 0
