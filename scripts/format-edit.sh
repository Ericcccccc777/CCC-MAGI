#!/usr/bin/env bash
# Post-edit format hook — runs the project's formatter on the file just edited.
#
# Called from .claude/settings.json + .codex/hooks.json on Edit|Write tool use.
# Picks the formatter by file extension; silently skips unknown extensions.

set -euo pipefail

# Edited file path is passed as $1 or via $CLAUDE_FILE_PATHS / stdin JSON
FILE="${1:-}"
if [ -z "$FILE" ]; then
  # Try to extract from Claude Code's tool input JSON on stdin
  if [ -t 0 ]; then
    exit 0  # no stdin, no arg → nothing to format
  fi
  FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
fi

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────
# CUSTOMIZE: per-extension formatter
# ─────────────────────────────────────────────────────────────────────
# Add / remove cases as your stack requires.
# Failures here are silent (|| true) — formatter issues should not block edits.
# ─────────────────────────────────────────────────────────────────────

case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.jsonc|*.md|*.mdx|*.html|*.css|*.scss|*.yaml|*.yml)
    if command -v prettier >/dev/null 2>&1; then
      prettier --write "$FILE" >/dev/null 2>&1 || true
    elif command -v npx >/dev/null 2>&1; then
      npx --no-install prettier --write "$FILE" >/dev/null 2>&1 || true
    fi
    ;;

  *.py)
    if command -v black >/dev/null 2>&1; then
      black "$FILE" >/dev/null 2>&1 || true
    elif command -v ruff >/dev/null 2>&1; then
      ruff format "$FILE" >/dev/null 2>&1 || true
    fi
    ;;

  *.go)
    if command -v gofmt >/dev/null 2>&1; then
      gofmt -w "$FILE" >/dev/null 2>&1 || true
    fi
    ;;

  *.rs)
    if command -v rustfmt >/dev/null 2>&1; then
      rustfmt "$FILE" >/dev/null 2>&1 || true
    fi
    ;;

  *.swift)
    if command -v swift-format >/dev/null 2>&1; then
      swift-format -i "$FILE" >/dev/null 2>&1 || true
    fi
    ;;

  *.kt|*.kts)
    if command -v ktlint >/dev/null 2>&1; then
      ktlint -F "$FILE" >/dev/null 2>&1 || true
    fi
    ;;

  *)
    # No formatter configured for this extension. Silent.
    ;;
esac

exit 0
