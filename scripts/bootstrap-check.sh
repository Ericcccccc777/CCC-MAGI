#!/usr/bin/env bash
# bootstrap-check.sh — UserPromptSubmit hook for CCC-Harness.
#
# Fires on EVERY user message in Claude Code (and Codex, if their hook system
# supports UserPromptSubmit). Its job: enforce that the harness bootstrap runs
# before the AI does anything else, on any project where CCC-Harness is on disk
# but .harness/state/install.json doesn't exist.
#
# This is the "punch clock" half of the bootstrap design. The other half is the
# Bootstrap Status Check block in CLAUDE.md (the "employee handbook" half). The
# hook fires deterministically regardless of what CLAUDE.md says; CLAUDE.md
# provides context for HOW to do the bootstrap. Both layers together = robust.
#
# CONTRACT (Claude Code hook spec):
#   stdin:  JSON containing the user's prompt (we don't need to read it; presence is enough)
#   stdout: either empty (no action) or a JSON envelope per hookSpecificOutput schema
#   exit 0: hook completed; Claude Code reads stdout for any additional context
#   exit non-zero: hook failed; Claude Code surfaces the error
#
# WHEN THIS HOOK SHOULD DO NOTHING:
#   - .harness/state/install.json exists (harness fully configured)
#   - The hook script itself can't find the project root (rare; e.g., $CLAUDE_PROJECT_DIR not set)

set -eu

# Ensure brew-installed tools (jq, etc.) are on PATH even in non-interactive
# shells where ~/.zprofile isn't loaded. macOS Apple Silicon path comes first.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ─────────────────────────────────────────────────────────────────────
# Resolve project root
# ─────────────────────────────────────────────────────────────────────
# Claude Code sets CLAUDE_PROJECT_DIR for hooks. Fall back to current dir if unset.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

INSTALL_JSON="$PROJECT_DIR/.harness/state/install.json"

# ─────────────────────────────────────────────────────────────────────
# Already configured? Nothing to do.
# ─────────────────────────────────────────────────────────────────────
if [ -f "$INSTALL_JSON" ]; then
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────
# Is CCC-Harness even installed here?
# If no Bootstrap Status Check in CLAUDE.md AND no .harness/scripts/, this is
# probably not a CCC-Harness project at all — don't inject anything.
# ─────────────────────────────────────────────────────────────────────
HAS_BOOTSTRAP_FILE=0
HAS_HARNESS_DIR=0

if [ -f "$PROJECT_DIR/.harness/scripts/standalone-bootstrap.md" ]; then
  HAS_BOOTSTRAP_FILE=1
fi

if [ -d "$PROJECT_DIR/.harness" ]; then
  HAS_HARNESS_DIR=1
fi

if [ "$HAS_BOOTSTRAP_FILE" -eq 0 ] && [ "$HAS_HARNESS_DIR" -eq 0 ]; then
  # Probably no CCC-Harness here. Silent exit.
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────
# Drain stdin (Claude Code passes JSON; we don't need to parse it but must read it)
# ─────────────────────────────────────────────────────────────────────
cat >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────────────
# Inject the bootstrap directive into Claude's additional context.
# ─────────────────────────────────────────────────────────────────────
cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "⚠️ CCC-Harness BOOTSTRAP REQUIRED — DO THIS FIRST\n\nThis project has CCC-Harness files on disk but `.harness/state/install.json` does NOT exist. That means the bootstrap (harness setup) has NOT been completed yet.\n\nBEFORE addressing the user's request, you MUST:\n\n1. Read `.harness/scripts/standalone-bootstrap.md`\n2. Follow its flow EXACTLY: detect existing harness configs in this project, present the 3-option menu to the user, wait for the user's choice, then execute that choice (which may invoke /init).\n\nLANGUAGE NOTE: When you actually TALK to the user (asking questions, presenting the menu, etc.), use the language matching their OS locale. See CLAUDE.md § Language Awareness for the rule. The standalone-bootstrap.md driver is written in English; translate its user-facing prompts to the user's locale when displaying. The completion markers ('✓ Task complete, close terminal' / '✗ Task cancelled, close terminal') are byte-exact and NEVER translated.\n\nEXCEPTION — user already declined in THIS SAME CONVERSATION (Option 3 chosen earlier this session):\n  → Proceed with the user's request without using harness skills. Treat the decline as binding for the rest of this session. Do NOT re-prompt the user about bootstrap again this session.\n  → Note: this hook will fire again on the NEXT session because install.json is still missing; that's by design — user can change their mind later.\n\nThis directive comes from the harness's UserPromptSubmit hook (`.harness/scripts/bootstrap-check.sh`). The hook fires on every user message until `install.json` exists. It is NOT the user's request; it is a precondition the user's request depends on. Do the bootstrap first, then respond to the user."
  }
}
JSON
