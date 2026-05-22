#!/usr/bin/env bash
# Pre-commit lint bans — scans staged changes for project-specific anti-patterns.
#
# This script enforces FORBIDDEN patterns, not the inverse anti-flag rules.
# Anti-flag rules in AGENTS.md say "X is correct, Y is BANNED — don't suggest Y."
# This script greps for Y in the diff and blocks if found.
#
# Constitution § 1 — anti-flag rules are part of the harness's signal-quality
# guarantee. Mechanical enforcement prevents banned patterns from leaking in.

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# CUSTOMIZE: list of banned patterns (one regex per entry)
# ─────────────────────────────────────────────────────────────────────
# Each pattern is matched line-by-line on staged diff additions (lines starting
# with `+`). Edit this list to mirror AGENTS.md § "Anti-flag rules" inverses.
#
# Examples (delete what doesn't apply, add what does):
#
# React Native projects:
#   PATTERNS+=('TouchableOpacity|TouchableHighlight|TouchableNativeFeedback')
#   PATTERNS+=('from .react-native. import .*KeyboardAvoidingView')
#   PATTERNS+=('StyleSheet\.create')
#   PATTERNS+=('forwardRef\(')
#
# Postgres/Supabase projects:
#   PATTERNS+=('\.select\(.\*.\)')
#   PATTERNS+=("import.*from\s+['\"]@supabase/auth-helpers")  # if deprecated
#
# Python projects:
#   PATTERNS+=('print\(')   # if logging-only is the rule
#
# Generic:
#   PATTERNS+=('console\.log\(')  # if console.log banned outside dev
#   PATTERNS+=('debugger;')
#   PATTERNS+=('@ts-ignore')      # if @ts-expect-error is preferred
# ─────────────────────────────────────────────────────────────────────

PATTERNS=()

# ─────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────
if [ ${#PATTERNS[@]} -eq 0 ]; then
  # No patterns configured — skip silently. /init may pre-fill these based on stack.
  exit 0
fi

# Get added lines from staged diff
ADDED_LINES=$(git diff --cached --unified=0 --no-color | grep -E '^\+[^+]' || true)

if [ -z "$ADDED_LINES" ]; then
  exit 0
fi

FOUND=0
for pattern in "${PATTERNS[@]}"; do
  matches=$(echo "$ADDED_LINES" | grep -E "$pattern" || true)
  if [ -n "$matches" ]; then
    echo "❌ Banned pattern found: $pattern"
    echo "$matches" | sed 's/^/    /'
    echo ""
    FOUND=1
  fi
done

if [ "$FOUND" -eq 1 ]; then
  echo "Commit blocked. See AGENTS.md § Anti-flag rules for context."
  echo "If this is a deliberate exception, edit .harness/scripts/lint-bans.sh"
  echo "and document the change in your commit body."
fi

exit "$FOUND"
