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
#   0 — PASS, CONCERNS, or WAIVED (all advance; caller reads JSON for nuance)
#   1 — script error (CLI not found, malformed output, IO failure, JSON validation,
#       Universal Core WAIVED attempt, missing waiver_reason, legacy verdict, etc.)
#   2 — FAIL (halt)
#
# OUTPUT FILE
#   review:     .harness/state/auditor-approvals/<feature>-stage<N>.json
#   diagnostic: .harness/state/auditor-approvals/<feature>-stage<N>-diagnostic.json

set -euo pipefail

# Ensure brew-installed tools (jq, etc.) are on PATH even in non-interactive
# shells where ~/.zprofile isn't loaded. macOS Apple Silicon path comes first.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

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
  "additionalProperties": false,
  "required": ["verdict", "risk_score", "waiver_reason", "blocking_items", "advisory_items"],
  "properties": {
    "verdict": {"type": "string", "enum": ["PASS", "CONCERNS", "FAIL", "WAIVED"]},
    "risk_score": {"type": "integer", "minimum": 0, "maximum": 10},
    "waiver_reason": {"type": "string"},
    "blocking_items": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["category", "rule_source", "finding"],
        "properties": {
          "category": {"type": "string", "enum": ["universal-core", "strong", "advisory"]},
          "rule_source": {"type": "string"},
          "finding": {"type": "string"}
        }
      }
    },
    "advisory_items": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["rule_source", "finding"],
        "properties": {
          "rule_source": {"type": "string"},
          "finding": {"type": "string"}
        }
      }
    }
  }
}
JSON

read -r -d '' DIAGNOSTIC_SCHEMA <<'JSON' || true
{
  "type": "object",
  "additionalProperties": false,
  "required": ["hypotheses"],
  "properties": {
    "hypotheses": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
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
# Note: mktemp template without .json suffix — macOS BSD mktemp doesn't
# substitute X chars when a dot extension follows. The output file is JSON
# regardless; the extension doesn't matter for jq parsing.
TEMP_OUTPUT="$(mktemp /tmp/auditor-gate.XXXXXX)"

invoke_codex() {
  # Codex CLI 0.130.0+ removed `--file <path>` support. Embed TARGET content
  # in the prompt body instead (same pattern as invoke_claude_fresh).
  local schema_file="$(mktemp /tmp/schema.XXXXXX)"
  if [ "$MODE" = "review" ]; then
    echo "$REVIEW_SCHEMA" > "$schema_file"
  else
    echo "$DIAGNOSTIC_SCHEMA" > "$schema_file"
  fi

  local prompt_with_target="$FULL_PROMPT"
  if [ -n "$TARGET" ] && [ -f "$TARGET" ]; then
    prompt_with_target+=$'\n\n=== TARGET ===\n'"$(cat "$TARGET")"
  fi

  codex exec \
    --model "$AUDITOR_MODEL_ID" \
    --output-schema "$schema_file" \
    -- "$prompt_with_target" > "$TEMP_OUTPUT"

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
    schema_hint=$'\n\nRespond with JSON only matching schema: {"verdict": "PASS" | "CONCERNS" | "FAIL" | "WAIVED", "risk_score": 0-10, "waiver_reason": "string (required if WAIVED)", "blocking_items": [{"category": "universal-core" | "strong" | "advisory", "rule_source": "...", "finding": "..."}], "advisory_items": [{"rule_source": "...", "finding": "..."}]}'
  else
    schema_hint=$'\n\nRespond with JSON only matching schema: {"hypotheses": [{"summary": "...", "evidence": "...", "next_step": "..."}, ...]}'
  fi

  claude --output-format json --no-session -- "${FULL_PROMPT}${schema_hint}${target_text}" > "$TEMP_OUTPUT"
}

invoke_none() {
  # No auditor configured. Emit a structured "skipped" verdict and let the caller decide.
  echo "warning: AUDITOR_CLI=none — emitting auto-PASS without verification" >&2
  cat > "$TEMP_OUTPUT" <<JSON
{
  "verdict": "PASS",
  "risk_score": 0,
  "blocking_items": [],
  "advisory_items": [
    {
      "rule_source": "constitution.md § 1",
      "finding": "auditor skipped (AUDITOR_CLI=none); single-engine fallback not engaged either — config error?"
    }
  ]
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
RISK_SCORE=$(jq -r '.risk_score // 0' "$OUTPUT_FILE")
BLOCKING_COUNT=$(jq '.blocking_items // [] | length' "$OUTPUT_FILE")
ADVISORY_COUNT=$(jq '.advisory_items // [] | length' "$OUTPUT_FILE")

case "$VERDICT" in
  PASS)
    echo "✓ ${LABEL}: PASS (risk_score=${RISK_SCORE})"
    if [ "$ADVISORY_COUNT" -gt 0 ]; then
      echo "  (note: $ADVISORY_COUNT advisory item(s) in $OUTPUT_FILE)"
    fi
    exit 0
    ;;
  CONCERNS)
    # Log to .harness/audits/ for CEO review
    AUDIT_DIR=".harness/audits"
    mkdir -p "$AUDIT_DIR"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    CONCERNS_FILE="$AUDIT_DIR/concerns-${FEATURE}-stage${STAGE}-${TIMESTAMP}.json"
    cp "$OUTPUT_FILE" "$CONCERNS_FILE"
    echo "⚠ ${LABEL}: CONCERNS (risk_score=${RISK_SCORE}, $BLOCKING_COUNT item(s); advancing)"
    echo "  Logged to: $CONCERNS_FILE"
    echo "  CEO should review before commit."
    exit 0
    ;;
  FAIL)
    echo "✗ ${LABEL}: FAIL (risk_score=${RISK_SCORE}, $BLOCKING_COUNT blocking item(s))"
    echo "  See: $OUTPUT_FILE"
    exit 2
    ;;
  WAIVED)
    # Verify no Universal Core items are being waived
    UNIVERSAL_CORE_COUNT=$(jq '[.blocking_items[]? | select(.category == "universal-core")] | length' "$OUTPUT_FILE")
    if [ "$UNIVERSAL_CORE_COUNT" -gt 0 ]; then
      echo "✗ ${LABEL}: WAIVED rejected — $UNIVERSAL_CORE_COUNT Universal Core item(s) cannot be waived (constitution.md § 3 — CEO has final authority EXCEPT on Universal Core)" >&2
      echo "  See: $OUTPUT_FILE" >&2
      exit 1
    fi
    WAIVER_REASON=$(jq -r '.waiver_reason // "(no reason given)"' "$OUTPUT_FILE")
    if [ "$WAIVER_REASON" = "(no reason given)" ] || [ "$WAIVER_REASON" = "null" ]; then
      echo "✗ ${LABEL}: WAIVED rejected — waiver_reason is required" >&2
      exit 1
    fi
    AUDIT_DIR=".harness/audits"
    mkdir -p "$AUDIT_DIR"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    WAIVER_FILE="$AUDIT_DIR/waivers-${FEATURE}-stage${STAGE}-${TIMESTAMP}.json"
    cp "$OUTPUT_FILE" "$WAIVER_FILE"
    echo "⚠ ${LABEL}: WAIVED (advancing; reason: $WAIVER_REASON)"
    echo "  Logged to: $WAIVER_FILE"
    exit 0
    ;;
  APPROVE|"REQUEST CHANGES")
    echo "auditor returned legacy verdict '$VERDICT' — schema migration incomplete. Update the auditor's prompt to use PASS/CONCERNS/FAIL/WAIVED." >&2
    exit 1
    ;;
  *)
    echo "auditor returned unexpected verdict: $VERDICT" >&2
    exit 1
    ;;
esac
