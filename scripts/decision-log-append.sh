#!/usr/bin/env bash
# decision-log-append.sh — appends a human-readable row to .harness/memory/decision-log.md
#
# Per BMAD-style decision-log pattern (the v0.9.0 "memory layer upgrade").
# Each call appends one line; file is gitignored (per-developer record).
#
# USAGE:
#   decision-log-append.sh \
#     --feature <slug> \
#     --stage <N> \
#     --by <CEO|MAGI-Core|MAGI-Verdict|MAGI-Planner|MAGI-Programmer|MAGI-Tester|MAGI-Reviewer|MAGI-Archivist|system> \
#     --decision "<short prose>"
#
# OPTIONS:
#   --feature <slug>     Required. Feature slug.
#   --stage <N>          Required. Stage number (1-9) or word ("init", "audit", "config").
#   --by <actor>         Required. Who made the decision.
#   --decision "<text>"  Required. One-line description. ≤120 chars recommended.
#   --evidence "<text>"  Optional. Brief evidence / link / commit / verdict file.
#
# OUTPUT:
#   - On success: prints "✓ decision logged" to stdout, exits 0.
#   - On error:   prints error to stderr, exits 1.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

FEATURE=""
STAGE=""
BY=""
DECISION=""
EVIDENCE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --feature)   FEATURE="$2"; shift 2 ;;
    --stage)     STAGE="$2"; shift 2 ;;
    --by)        BY="$2"; shift 2 ;;
    --decision)  DECISION="$2"; shift 2 ;;
    --evidence)  EVIDENCE="$2"; shift 2 ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$FEATURE" ] || [ -z "$STAGE" ] || [ -z "$BY" ] || [ -z "$DECISION" ]; then
  echo "decision-log-append.sh: --feature, --stage, --by, --decision all required" >&2
  exit 1
fi

LOG_FILE=".harness/memory/decision-log.md"
mkdir -p "$(dirname "$LOG_FILE")"

# Initialize file with header if missing
if [ ! -f "$LOG_FILE" ]; then
  cat > "$LOG_FILE" <<'HEADER'
# Decision Log

> Per-developer chronological log of workflow decisions. Each row captures
> WHO decided WHAT at WHICH stage of WHICH feature. Maintained automatically
> by stage skills + MAGI Archivist. Gitignored — your private project diary.
>
> Use cases:
> - Release-note source ("why we chose Redis over Memcached")
> - Onboarding new teammates (paste relevant rows into Slack/Wiki)
> - Post-mortem after incidents ("what did MAGI Verdict flag, did CEO accept?")
> - Quarterly review of personal decision quality

| Timestamp (UTC) | Feature | Stage | Actor | Decision | Evidence |
|-----------------|---------|-------|-------|----------|----------|
HEADER
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Escape pipe characters in text fields so they don't break the markdown table
escape_pipes() {
  echo "$1" | sed 's/|/\\|/g'
}

DECISION_ESC=$(escape_pipes "$DECISION")
EVIDENCE_ESC=$(escape_pipes "${EVIDENCE:-—}")

printf "| %s | %s | %s | %s | %s | %s |\n" \
  "$NOW" "$FEATURE" "$STAGE" "$BY" "$DECISION_ESC" "$EVIDENCE_ESC" \
  >> "$LOG_FILE"

echo "✓ decision logged to $LOG_FILE"
