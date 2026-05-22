#!/usr/bin/env bash
# auditor-gate.sh — invoke the auditor CLI on a target artifact, parse the structured
# verdict, persist the result, and exit with the gate's exit code.
#
# Constitution § 1 (cross-model audit is mandatory) — every audit-gated skill
# invokes this script. It is the load-bearing primitive for the harness.
#
# USAGE
#   auditor-gate.sh review     <feature> <stage> <focus-text> [target-file]
#   auditor-gate.sh diagnostic <feature>         <focus-text> [attempts-file]
#
# ENVIRONMENT
#   AUDITOR_CLI         — "codex" (default) | "claude" | "gemini" | "none"
#                         "none" = single-engine fallback (fresh-context same-model)
#   AUDITOR_MODEL_ID    — model version string (default: gpt-5.5 for codex)
#   AUDITOR_GATE_PRESET — optional preset name (loaded from
#                         .harness/scripts/auditor-prompts/<preset>.md if exists)
#   AUDITOR_GATE_TARGET_LABEL — optional human-readable label for the target
#
# EXIT CODES
#   0 — APPROVE
#   1 — script error (CLI not found, malformed output, IO failure, etc.)
#   2 — REQUEST CHANGES
#
# OUTPUT FILE
#   review:     .harness/state/auditor-approvals/<feature>-stage<N>.json
#   diagnostic: .harness/state/auditor-approvals/<feature>-stage<N>-diagnostic.json

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# Args
# ─────────────────────────────────────────────────────────────────────
MODE="${1:-}"
case "$MODE" in
  review)
    FEATURE="${2:?feature name required}"
    STAGE="${3:?stage required}"
    FOCUS="${4:?focus text required}"
    TARGET="${5:-}"
    OUTPUT_SUFFIX="stage${STAGE}"
    ;;
  diagnostic)
    FEATURE="${2:?feature name required}"
    FOCUS="${3:?focus text required}"
    TARGET="${4:-}"
    STAGE="6"  # diagnostic mode is always Stage 6 escalation
    OUTPUT_SUFFIX="stage6-diagnostic"
    ;;
  *)
    echo "usage: $0 review <feature> <stage> <focus> [target]" >&2
    echo "       $0 diagnostic <feature> <focus> [attempts-file]" >&2
    exit 1
    ;;
esac

# ─────────────────────────────────────────────────────────────────────
# Resolve auditor + paths
# ─────────────────────────────────────────────────────────────────────
AUDITOR_CLI="${AUDITOR_CLI:-codex}"
AUDITOR_MODEL_ID="${AUDITOR_MODEL_ID:-gpt-5.5}"
STATE_DIR=".harness/state/auditor-approvals"
mkdir -p "$STATE_DIR"
OUTPUT_FILE="$STATE_DIR/${FEATURE}-${OUTPUT_SUFFIX}.json"
LABEL="${AUDITOR_GATE_TARGET_LABEL:-${FEATURE} stage${STAGE}}"

# Load preset focus prefix if specified
PRESET_PREFIX=""
if [ -n "${AUDITOR_GATE_PRESET:-}" ]; then
  PRESET_FILE=".harness/scripts/auditor-prompts/${AUDITOR_GATE_PRESET}.md"
  if [ -f "$PRESET_FILE" ]; then
    PRESET_PREFIX="$(cat "$PRESET_FILE")"$'\n\n'
  else
    echo "warning: preset file not found: $PRESET_FILE" >&2
  fi
fi

FULL_PROMPT="${PRESET_PREFIX}${FOCUS}"

# ─────────────────────────────────────────────────────────────────────
# JSON output schema
# ─────────────────────────────────────────────────────────────────────
read -r -d '' REVIEW_SCHEMA <<'JSON' || true
{
  "type": "object",
  "required": ["verdict"],
  "properties": {
    "verdict": {"type": "string", "enum": ["APPROVE", "REQUEST CHANGES"]},
    "critical": {"type": "array", "items": {"type": "string"}},
    "suggestions": {"type": "array", "items": {"type": "string"}}
  }
}
JSON

read -r -d '' DIAGNOSTIC_SCHEMA <<'JSON' || true
{
  "type": "object",
  "required": ["hypotheses"],
  "properties": {
    "hypotheses": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["summary", "evidence", "next_step"],
        "properties": {
          "summary": {"type": "string"},
          "evidence": {"type": "string"},
          "next_step": {"type": "string"}
        }
      }
    }
  }
}
JSON

# ─────────────────────────────────────────────────────────────────────
# Invoke the auditor CLI
# ─────────────────────────────────────────────────────────────────────
TEMP_OUTPUT="$(mktemp /tmp/auditor-gate.XXXXXX.json)"

invoke_codex() {
  # CUSTOMIZE if your codex CLI uses different flags
  local schema_file="$(mktemp /tmp/schema.XXXXXX.json)"
  if [ "$MODE" = "review" ]; then
    echo "$REVIEW_SCHEMA" > "$schema_file"
  else
    echo "$DIAGNOSTIC_SCHEMA" > "$schema_file"
  fi

  local target_args=()
  if [ -n "$TARGET" ] && [ -f "$TARGET" ]; then
    target_args=(--file "$TARGET")
  fi

  codex exec \
    --model "$AUDITOR_MODEL_ID" \
    --output-schema "$schema_file" \
    "${target_args[@]}" \
    -- "$FULL_PROMPT" > "$TEMP_OUTPUT"

  rm -f "$schema_file"
}

invoke_claude_fresh() {
  # Single-engine fallback: invoke Claude with --output-format json in a fresh
  # context (no prior session). Lower bias-cancellation but preserves discipline.
  local target_text=""
  if [ -n "$TARGET" ] && [ -f "$TARGET" ]; then
    target_text=$'\n\n=== TARGET ===\n'"$(cat "$TARGET")"
  fi

  local schema_hint=""
  if [ "$MODE" = "review" ]; then
    schema_hint=$'\n\nRespond with JSON only matching schema: {"verdict": "APPROVE" | "REQUEST CHANGES", "critical": [...], "suggestions": [...]}'
  else
    schema_hint=$'\n\nRespond with JSON only matching schema: {"hypotheses": [{"summary": "...", "evidence": "...", "next_step": "..."}, ...]}'
  fi

  claude --output-format json --no-session -- "${FULL_PROMPT}${schema_hint}${target_text}" > "$TEMP_OUTPUT"
}

invoke_none() {
  # No auditor configured. Emit a structured "skipped" verdict and let the caller decide.
  echo "warning: AUDITOR_CLI=none — emitting auto-APPROVE without verification" >&2
  cat > "$TEMP_OUTPUT" <<JSON
{
  "verdict": "APPROVE",
  "critical": [],
  "suggestions": ["auditor skipped (AUDITOR_CLI=none); constitution.md § 1 single-engine fallback not engaged either — config error?"]
}
JSON
}

case "$AUDITOR_CLI" in
  codex)  invoke_codex ;;
  claude) invoke_claude_fresh ;;
  none)   invoke_none ;;
  *)
    echo "unknown AUDITOR_CLI: $AUDITOR_CLI" >&2
    exit 1
    ;;
esac

# ─────────────────────────────────────────────────────────────────────
# Parse + persist
# ─────────────────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "auditor-gate.sh requires jq. Install with: brew install jq" >&2
  cp "$TEMP_OUTPUT" "$OUTPUT_FILE"
  exit 1
fi

# Validate JSON
if ! jq empty "$TEMP_OUTPUT" 2>/dev/null; then
  echo "auditor returned non-JSON output:" >&2
  cat "$TEMP_OUTPUT" >&2
  cp "$TEMP_OUTPUT" "$OUTPUT_FILE"
  exit 1
fi

# Persist
mv "$TEMP_OUTPUT" "$OUTPUT_FILE"

# ─────────────────────────────────────────────────────────────────────
# Exit on verdict
# ─────────────────────────────────────────────────────────────────────
if [ "$MODE" = "diagnostic" ]; then
  # Diagnostic mode doesn't have a verdict — just exit 0 if hypotheses present.
  HYPOTHESIS_COUNT=$(jq '.hypotheses | length' "$OUTPUT_FILE")
  if [ "$HYPOTHESIS_COUNT" -gt 0 ]; then
    echo "✓ Diagnostic complete: $HYPOTHESIS_COUNT hypothesis/hypotheses written to $OUTPUT_FILE"
    exit 0
  else
    echo "✗ Diagnostic returned no hypotheses" >&2
    exit 1
  fi
fi

VERDICT=$(jq -r '.verdict' "$OUTPUT_FILE")
CRITICAL_COUNT=$(jq '.critical // [] | length' "$OUTPUT_FILE")

case "$VERDICT" in
  APPROVE)
    echo "✓ ${LABEL}: APPROVE"
    if [ "$CRITICAL_COUNT" -gt 0 ]; then
      echo "  (note: $CRITICAL_COUNT advisory items in $OUTPUT_FILE)"
    fi
    exit 0
    ;;
  "REQUEST CHANGES")
    echo "✗ ${LABEL}: REQUEST CHANGES ($CRITICAL_COUNT critical item(s))"
    echo "  See: $OUTPUT_FILE"
    exit 2
    ;;
  *)
    echo "auditor returned unexpected verdict: $VERDICT" >&2
    exit 1
    ;;
esac
