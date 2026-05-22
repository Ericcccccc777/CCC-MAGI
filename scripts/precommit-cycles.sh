#!/usr/bin/env bash
# Pre-commit dependency-cycle check.
#
# Only meaningful if the project has declared a dependency_flow (e.g.,
# `shared → ui → features → app`). If dependency_flow is empty, this script
# should exit 0 silently — /init removes the hook entry in that case.

set -euo pipefail

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
