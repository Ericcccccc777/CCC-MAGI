#!/usr/bin/env bash
# Pre-commit typecheck. Blocks commit if type/syntax check fails.
#
# Called from .claude/settings.json + .codex/hooks.json on `git commit:*`.
# Constitution § 5 (Spec and reality stay in sync) — typecheck is one of the
# mechanical gates that catch reality drift at the syntax level.

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# CUSTOMIZE: pick your stack's typecheck command
# ─────────────────────────────────────────────────────────────────────
# TypeScript:    COMMAND=(npx tsc --noEmit)
# TypeScript+pnpm: COMMAND=(pnpm exec tsc --noEmit)
# Python+mypy:   COMMAND=(mypy .)
# Python+pyright: COMMAND=(pyright)
# Go:            COMMAND=(go vet ./...)
# Rust:          COMMAND=(cargo check --all-targets)
# Swift:         COMMAND=(swift build --build-tests)
# None / skip:   exit 0
# ─────────────────────────────────────────────────────────────────────

COMMAND=(npx tsc --noEmit)

# ─────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────
if ! command -v "${COMMAND[0]}" >/dev/null 2>&1; then
  echo "warning: ${COMMAND[0]} not found; skipping typecheck" >&2
  exit 0
fi

"${COMMAND[@]}"
