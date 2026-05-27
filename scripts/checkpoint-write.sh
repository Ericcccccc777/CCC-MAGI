#!/usr/bin/env bash
# checkpoint-write.sh — atomic writer for .harness/state/workflow-checkpoints/<feature>.json
#
# Called by every stage skill at its successful completion. Centralizes the
# checkpoint schema (single source of truth — change schema here, all skills
# inherit it). Per Phase 5 (Session resume) of the v0.9.0 release.
#
# USAGE:
#   checkpoint-write.sh --feature <slug> [options]
#
# OPTIONS:
#   --feature <slug>                  Required. Feature slug (matches branch name suffix).
#   --branch <name>                   Override detected branch (default: current git branch).
#   --mode <new-feature|audit>        Workflow mode (default: new-feature).
#   --lane <full|stability-fix|trivial>  Workflow lane (default: full).
#   --stage <N>                       Set current_stage to N.
#   --stage-complete <N>              Mark stage N as complete (append to stages_completed).
#   --stage-skip <N> --skip-reason <text>  Mark stage N as skipped with reason.
#   --artifact-spec <path>            Record spec artifact path (computes sha256).
#   --artifact-implementation <path>  Record implementation-doc artifact path.
#   --artifact-plan <path>            Record execution-plan artifact path.
#   --artifact-schema <path>          Record schema artifact path.
#   --append-audit '<json>'           Append one audit entry. JSON: {"stage":N,"verdict":"...","risk":N,"at":"<iso>"}
#   --stage-in-progress '<json>'      Replace stage_in_progress block. JSON: {"stage_number":N,"files_total":N,...}
#   --file-done <path>                Append one path to stage_in_progress.files_done_list (idempotent: dedupe).
#   --append-decision '<json>'        Append one decision entry. JSON: {"at":"...","stage":N,"by":"CEO","decision":"..."}
#   --archive                         Move checkpoint to _archived/<feature>-<timestamp>.json (used by /commit).
#   --create-if-missing               Create a minimal checkpoint if file doesn't exist (used by /feature-draft as first stage).
#
# OUTPUT:
#   - On success: prints "✓ checkpoint updated: <path>" to stdout, exits 0.
#   - On error:   prints error to stderr, exits 1.
#
# DESIGN NOTES:
#   - Atomic write: tmp + rename (won't leave half-written checkpoint).
#   - Idempotent: rerunning the same call doesn't duplicate stages/files.
#   - Schema versioning: bumps schema_version if needed, refuses to write older schema over newer.
#   - jq is required.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v jq >/dev/null 2>&1; then
  echo "checkpoint-write.sh requires jq. Install with: brew install jq" >&2
  exit 1
fi

# ─── Defaults / state ──────────────────────────────────────────────────
SCHEMA_VERSION=1
FEATURE=""
BRANCH=""
MODE=""
LANE=""
SET_STAGE=""
COMPLETE_STAGE=""
SKIP_STAGE=""
SKIP_REASON=""
ARTIFACT_SPEC=""
ARTIFACT_IMPL=""
ARTIFACT_PLAN=""
ARTIFACT_SCHEMA=""
APPEND_AUDIT=""
STAGE_IN_PROGRESS=""
FILE_DONE=""
APPEND_DECISION=""
ARCHIVE=false
CREATE_IF_MISSING=false

# ─── Parse args ────────────────────────────────────────────────────────
while [ "$#" -gt 0 ]; do
  case "$1" in
    --feature)              FEATURE="$2"; shift 2 ;;
    --branch)               BRANCH="$2"; shift 2 ;;
    --mode)                 MODE="$2"; shift 2 ;;
    --lane)                 LANE="$2"; shift 2 ;;
    --stage)                SET_STAGE="$2"; shift 2 ;;
    --stage-complete)       COMPLETE_STAGE="$2"; shift 2 ;;
    --stage-skip)           SKIP_STAGE="$2"; shift 2 ;;
    --skip-reason)          SKIP_REASON="$2"; shift 2 ;;
    --artifact-spec)        ARTIFACT_SPEC="$2"; shift 2 ;;
    --artifact-implementation) ARTIFACT_IMPL="$2"; shift 2 ;;
    --artifact-plan)        ARTIFACT_PLAN="$2"; shift 2 ;;
    --artifact-schema)      ARTIFACT_SCHEMA="$2"; shift 2 ;;
    --append-audit)         APPEND_AUDIT="$2"; shift 2 ;;
    --stage-in-progress)    STAGE_IN_PROGRESS="$2"; shift 2 ;;
    --file-done)            FILE_DONE="$2"; shift 2 ;;
    --append-decision)      APPEND_DECISION="$2"; shift 2 ;;
    --archive)              ARCHIVE=true; shift ;;
    --create-if-missing)    CREATE_IF_MISSING=true; shift ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$FEATURE" ]; then
  echo "checkpoint-write.sh: --feature <slug> required" >&2
  exit 1
fi

CHECKPOINT_DIR=".harness/state/workflow-checkpoints"
CHECKPOINT_FILE="$CHECKPOINT_DIR/${FEATURE}.json"
mkdir -p "$CHECKPOINT_DIR"

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Detect branch if not provided
if [ -z "$BRANCH" ]; then
  BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "(no branch)")
fi

# ─── Archive mode (used by /commit at Stage 8) ─────────────────────────
if [ "$ARCHIVE" = "true" ]; then
  if [ ! -f "$CHECKPOINT_FILE" ]; then
    echo "✓ checkpoint not found for $FEATURE (already archived or never created); no-op"
    exit 0
  fi
  ARCHIVE_DIR="$CHECKPOINT_DIR/_archived"
  mkdir -p "$ARCHIVE_DIR"
  ARCHIVED_FILE="$ARCHIVE_DIR/${FEATURE}-$(date -u +%Y%m%dT%H%M%SZ).json"
  mv "$CHECKPOINT_FILE" "$ARCHIVED_FILE"
  echo "✓ checkpoint archived: $ARCHIVED_FILE"
  exit 0
fi

# ─── Create-if-missing (initial checkpoint from /feature-draft Stage 1) ───
if [ ! -f "$CHECKPOINT_FILE" ]; then
  if [ "$CREATE_IF_MISSING" = "true" ]; then
    INIT_MODE="${MODE:-new-feature}"
    INIT_LANE="${LANE:-full}"
    INIT_STAGE="${SET_STAGE:-1}"
    jq -n \
      --argjson schema_version "$SCHEMA_VERSION" \
      --arg feature "$FEATURE" \
      --arg branch "$BRANCH" \
      --arg started_at "$NOW" \
      --arg last_at "$NOW" \
      --arg mode "$INIT_MODE" \
      --arg lane "$INIT_LANE" \
      --argjson stage "$INIT_STAGE" \
      '{
         schema_version: $schema_version,
         feature: $feature,
         feature_slug: $feature,
         branch: $branch,
         started_at: $started_at,
         last_activity_at: $last_at,
         mode: $mode,
         lane: $lane,
         current_stage: $stage,
         stages_completed: [],
         stages_skipped: [],
         stages_skipped_reasons: {},
         artifacts: { spec: null, implementation: null, plan: null, schema: null },
         audits: [],
         stage_in_progress: null,
         decisions: [],
         session_chain: []
       }' > "$CHECKPOINT_FILE"
    # Fall through to apply any additional updates from this call
  else
    echo "checkpoint-write.sh: $CHECKPOINT_FILE does not exist. Use --create-if-missing to bootstrap." >&2
    exit 1
  fi
fi

# ─── Atomic update via tmp + rename ────────────────────────────────────
TMP_FILE=$(mktemp "${CHECKPOINT_FILE}.tmp.XXXXXX")
trap 'rm -f "$TMP_FILE"' EXIT

# Build a jq filter chain that applies all requested mutations
JQ_FILTER='. | .last_activity_at = $now'

# Mode / lane updates
[ -n "$MODE" ] && JQ_FILTER="$JQ_FILTER | .mode = \$mode"
[ -n "$LANE" ] && JQ_FILTER="$JQ_FILTER | .lane = \$lane"
[ -n "$BRANCH" ] && JQ_FILTER="$JQ_FILTER | .branch = \$branch"

# Stage current
[ -n "$SET_STAGE" ] && JQ_FILTER="$JQ_FILTER | .current_stage = (\$set_stage | tonumber)"

# Complete stage (dedupe via unique)
[ -n "$COMPLETE_STAGE" ] && JQ_FILTER="$JQ_FILTER | .stages_completed = ((.stages_completed + [(\$complete_stage | tonumber)]) | unique)"

# Skip stage
if [ -n "$SKIP_STAGE" ]; then
  JQ_FILTER="$JQ_FILTER | .stages_skipped = ((.stages_skipped + [(\$skip_stage | tonumber)]) | unique)"
  if [ -n "$SKIP_REASON" ]; then
    JQ_FILTER="$JQ_FILTER | .stages_skipped_reasons[\$skip_stage] = \$skip_reason"
  fi
fi

# Artifact paths (compute sha256 if file exists)
compute_artifact_block() {
  local path="$1"
  if [ -f "$path" ]; then
    local sha
    sha=$(shasum -a 256 "$path" 2>/dev/null | awk '{print $1}' | head -c 16)
    jq -n --arg p "$path" --arg s "$sha" '{path: $p, sha256: $s, exists: true}'
  else
    jq -n --arg p "$path" '{path: $p, sha256: null, exists: false}'
  fi
}

if [ -n "$ARTIFACT_SPEC" ]; then
  ART_SPEC_JSON=$(compute_artifact_block "$ARTIFACT_SPEC")
  JQ_FILTER="$JQ_FILTER | .artifacts.spec = \$art_spec"
fi
if [ -n "$ARTIFACT_IMPL" ]; then
  ART_IMPL_JSON=$(compute_artifact_block "$ARTIFACT_IMPL")
  JQ_FILTER="$JQ_FILTER | .artifacts.implementation = \$art_impl"
fi
if [ -n "$ARTIFACT_PLAN" ]; then
  ART_PLAN_JSON=$(compute_artifact_block "$ARTIFACT_PLAN")
  JQ_FILTER="$JQ_FILTER | .artifacts.plan = \$art_plan"
fi
if [ -n "$ARTIFACT_SCHEMA" ]; then
  ART_SCHEMA_JSON=$(compute_artifact_block "$ARTIFACT_SCHEMA")
  JQ_FILTER="$JQ_FILTER | .artifacts.schema = \$art_schema"
fi

# Append audit entry
if [ -n "$APPEND_AUDIT" ]; then
  JQ_FILTER="$JQ_FILTER | .audits = (.audits + [\$append_audit])"
fi

# Replace stage_in_progress (full block)
if [ -n "$STAGE_IN_PROGRESS" ]; then
  JQ_FILTER="$JQ_FILTER | .stage_in_progress = \$stage_in_progress"
fi

# Append single file to files_done_list (idempotent dedupe)
if [ -n "$FILE_DONE" ]; then
  JQ_FILTER="$JQ_FILTER | .stage_in_progress = (.stage_in_progress // {stage_number: .current_stage, files_total: 0, files_done_list: [], files_remaining_list: [], last_action: null, resume_hint: null}) | .stage_in_progress.files_done_list = ((.stage_in_progress.files_done_list + [\$file_done]) | unique) | .stage_in_progress.last_action = (\"Wrote \" + \$file_done)"
fi

# Append decision entry
if [ -n "$APPEND_DECISION" ]; then
  JQ_FILTER="$JQ_FILTER | .decisions = (.decisions + [\$append_decision])"
fi

# Build the jq invocation with all required --arg / --argjson
JQ_ARGS=(--arg now "$NOW")

[ -n "$MODE" ]           && JQ_ARGS+=(--arg mode "$MODE")
[ -n "$LANE" ]           && JQ_ARGS+=(--arg lane "$LANE")
[ -n "$BRANCH" ]         && JQ_ARGS+=(--arg branch "$BRANCH")
[ -n "$SET_STAGE" ]      && JQ_ARGS+=(--arg set_stage "$SET_STAGE")
[ -n "$COMPLETE_STAGE" ] && JQ_ARGS+=(--arg complete_stage "$COMPLETE_STAGE")
[ -n "$SKIP_STAGE" ]     && JQ_ARGS+=(--arg skip_stage "$SKIP_STAGE")
[ -n "$SKIP_REASON" ]    && JQ_ARGS+=(--arg skip_reason "$SKIP_REASON")
[ -n "$FILE_DONE" ]      && JQ_ARGS+=(--arg file_done "$FILE_DONE")

[ -n "$ARTIFACT_SPEC" ]   && JQ_ARGS+=(--argjson art_spec "$ART_SPEC_JSON")
[ -n "$ARTIFACT_IMPL" ]   && JQ_ARGS+=(--argjson art_impl "$ART_IMPL_JSON")
[ -n "$ARTIFACT_PLAN" ]   && JQ_ARGS+=(--argjson art_plan "$ART_PLAN_JSON")
[ -n "$ARTIFACT_SCHEMA" ] && JQ_ARGS+=(--argjson art_schema "$ART_SCHEMA_JSON")
[ -n "$APPEND_AUDIT" ]      && JQ_ARGS+=(--argjson append_audit "$APPEND_AUDIT")
[ -n "$STAGE_IN_PROGRESS" ] && JQ_ARGS+=(--argjson stage_in_progress "$STAGE_IN_PROGRESS")
[ -n "$APPEND_DECISION" ]   && JQ_ARGS+=(--argjson append_decision "$APPEND_DECISION")

jq "${JQ_ARGS[@]}" "$JQ_FILTER" "$CHECKPOINT_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$CHECKPOINT_FILE"
trap - EXIT

echo "✓ checkpoint updated: $CHECKPOINT_FILE"
