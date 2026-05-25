#!/usr/bin/env bash
# Pre-commit dependency-cycle check.
#
# Only meaningful if the project has declared a dependency_flow (e.g.,
# `shared → ui → features → app`). If dependency_flow is empty, this script
# should exit 0 silently — /init removes the hook entry in that case.

set -euo pipefail

# Ensure brew-installed tools (jq, etc.) are on PATH even in non-interactive
# shells where ~/.zprofile isn't loaded. macOS Apple Silicon path comes first.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Filter: only fire on `git commit` invocations. The PreToolUse hook contract
# passes the tool call payload via stdin; we parse it and silently exit if
# the Bash command isn't a git commit.
#
# (We do this filtering here instead of relying on settings.json's `if`
# clause because that clause was found NOT to be honored consistently —
# see harness-testing-2026-05-25.md § P0.Z.)

# Read stdin (Claude Code passes JSON with tool_input.command for Bash hooks)
HOOK_INPUT="$(cat 2>/dev/null || true)"
if [ -n "$HOOK_INPUT" ]; then
  # Try to extract the Bash command. If jq is available, use it. Otherwise
  # fall back to grep (best-effort).
  if command -v jq >/dev/null 2>&1; then
    BASH_CMD="$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")"
  else
    # Best-effort fallback: extract "command":"..." substring via grep
    BASH_CMD="$(printf '%s' "$HOOK_INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")"
  fi
  # Silent exit unless this is a git commit invocation
  case "$BASH_CMD" in
    git\ commit*|*\ git\ commit*)
      # proceed
      ;;
    *)
      exit 0
      ;;
  esac
fi

# === Original hook logic continues below ===

# ─────────────────────────────────────────────────────────────────────
# CUSTOMIZE: pick your stack's cycle-detection command
# ─────────────────────────────────────────────────────────────────────
# JS/TS (madge):       COMMAND=(npx madge --circular src/)
# JS/TS (dpdm):        COMMAND=(npx dpdm --no-warning src/)
# Python:              COMMAND=(pylint --disable=all --enable=cyclic-import .)
# Go:                  COMMAND=(go vet ./...)  # detects import cycles
# Rust:                # rustc detects cycles natively
# None / skip:         exit 0
# ─────────────────────────────────────────────────────────────────────

COMMAND=(npx madge --circular src/)

# ─────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────
if ! command -v "${COMMAND[0]}" >/dev/null 2>&1; then
  echo "warning: ${COMMAND[0]} not found; skipping cycle check" >&2
  exit 0
fi

if ! "${COMMAND[@]}"; then
  echo ""
  echo "❌ Dependency cycle detected."
  echo "If this is a deliberate exception, document the cycle in your"
  echo "commit body with reasoning, then bypass with --no-verify (per"
  echo "AGENTS.md § Anti-flag rules), but expect the auditor to question it."
  exit 1
fi
