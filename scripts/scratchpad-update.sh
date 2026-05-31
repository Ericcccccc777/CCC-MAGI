#!/usr/bin/env bash
# scratchpad-update.sh — Stop hook for v2 working memory (Tier 1).
#
# DESIGN NOTE (v2.1 — 2026-05-31):
# Claude Code's Stop hook schema does NOT support `hookSpecificOutput.additionalContext`
# (only PreToolUse / UserPromptSubmit / PostToolUse / PostToolBatch do). So this hook
# CANNOT inject text instructions back to the AI.
#
# Instead, the scratchpad rewrite rule lives in CLAUDE.md § Working Scratchpad, which the
# AI reads at SessionStart. The AI rewrites the scratchpad as the final act of each turn
# because the CLAUDE.md rule tells it to — no hook nudge required.
#
# This hook's job is now just to:
#   1. Ensure the scratchpad file + parent dir exist (defensive)
#   2. Stay silent (suppressOutput=true) so it never spams the user's screen
#
# Returning `{}` would also work, but `{"suppressOutput": true}` is the explicit
# "I have nothing to say" signal.

set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRATCHPAD="$PROJECT_DIR/.harness/state/scratchpad.md"
TEMPLATE="$PROJECT_DIR/.harness/state/scratchpad.md.template"

# Drain stdin
cat >/dev/null 2>&1 || true

# Ensure dir + file exist (so next SessionStart's scratchpad-recall finds something)
mkdir -p "$(dirname "$SCRATCHPAD")" 2>/dev/null || true
if [ ! -f "$SCRATCHPAD" ] && [ -f "$TEMPLATE" ]; then
  cp "$TEMPLATE" "$SCRATCHPAD" 2>/dev/null || true
fi

# Emit a valid Stop schema response: suppress any output
printf '{"suppressOutput": true}\n'

exit 0
