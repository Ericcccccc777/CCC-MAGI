#!/usr/bin/env bash
# todolist-backfill.sh — seed .harness/state/todolist.json from a project's
# existing workflow history, for projects that adopted CCC-MAGI before the
# todolist feature existed (run by the updater) or any time you want to
# reconstruct the function ledger from what's already on disk.
#
# It is IDEMPOTENT and NON-DESTRUCTIVE:
#   - If todolist.json already has functions, it does nothing (won't clobber
#     a CEO-curated todolist). Pass --force to backfill anyway (still only ADDS
#     functions/items that don't exist; never deletes).
#   - Each discovered feature becomes one FUNCTION (linked_feature = slug) with a
#     single summary ITEM whose status reflects the feature's lifecycle:
#       shipped (archived checkpoint)        → done
#       in-flight (active checkpoint)        → doing
#       spec exists, no checkpoint           → todo  (planned)
#     Function status auto-derives from that item.
#
# Sources (in priority order, deduped by feature slug):
#   1. .harness/state/workflow-checkpoints/_archived/<slug>-<ts>.json  → done
#   2. .harness/state/workflow-checkpoints/<slug>.json                 → doing
#   3. <spec_dir>/<slug>.md  (excluding *-plan.md / *-implementation.md) → todo
#
# USAGE:
#   todolist-backfill.sh [--force] [--dry-run]
#
# Run from the project root. Requires jq + scripts/todolist-write.sh sibling.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v jq >/dev/null 2>&1; then
  echo "todolist-backfill.sh requires jq." >&2
  exit 1
fi

FORCE=0
DRY=0
for a in "$@"; do
  case "$a" in
    --force)   FORCE=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "Unknown arg: $a" >&2; exit 1 ;;
  esac
done

STATE_DIR=".harness/state"
CHECKPOINT_DIR="$STATE_DIR/workflow-checkpoints"
ARCHIVE_DIR="$CHECKPOINT_DIR/_archived"
TODOLIST_FILE="$STATE_DIR/todolist.json"

# Locate the writer (same dir as this script, or deployed .harness/scripts).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/todolist-write.sh"
if [ ! -f "$WRITER" ]; then
  WRITER=".harness/scripts/todolist-write.sh"
fi
if [ ! -f "$WRITER" ]; then
  echo "todolist-backfill.sh: cannot find todolist-write.sh" >&2
  exit 1
fi

# Resolve spec dir from install.json (slot), default docs/features/.
SPEC_DIR="docs/features"
if [ -f "$STATE_DIR/install.json" ]; then
  s=$(jq -r '.slots.spec_dir // empty' "$STATE_DIR/install.json" 2>/dev/null || true)
  [ -n "$s" ] && SPEC_DIR="${s%/}"
fi

# Bail early if todolist already populated (unless --force).
if [ -f "$TODOLIST_FILE" ] && [ "$FORCE" -eq 0 ]; then
  existing=$(jq '.functions | length' "$TODOLIST_FILE" 2>/dev/null || echo 0)
  if [ "$existing" -gt 0 ]; then
    echo "✓ todolist already has $existing function(s); nothing to backfill (use --force to add anyway)"
    exit 0
  fi
fi

# ─── Collect feature → status, priority: done > doing > todo ────────────
# bash 3.2 compatible: parallel slug list + status list (no assoc arrays).
SLUGS=""
STATUSES=""

upsert() {
  # upsert <slug> <status>; first writer wins (priority order of callers).
  local slug="$1" status="$2"
  case " $SLUGS " in
    *" $slug "*) return ;;   # already recorded at higher priority
  esac
  SLUGS="$SLUGS $slug"
  STATUSES="$STATUSES $status"
}

status_of() {
  local slug="$1" i=1 s
  for s in $SLUGS; do
    if [ "$s" = "$slug" ]; then
      echo "$STATUSES" | awk -v n="$i" '{print $n}'
      return
    fi
    i=$((i + 1))
  done
}

# 1. Archived checkpoints → shipped → done
if [ -d "$ARCHIVE_DIR" ]; then
  for f in "$ARCHIVE_DIR"/*.json; do
    [ -e "$f" ] || continue
    slug=$(jq -r '.feature // .feature_slug // empty' "$f" 2>/dev/null || true)
    [ -n "$slug" ] && upsert "$slug" "done"
  done
fi

# 2. Active checkpoints → in-flight → doing
if [ -d "$CHECKPOINT_DIR" ]; then
  for f in "$CHECKPOINT_DIR"/*.json; do
    [ -e "$f" ] || continue
    slug=$(jq -r '.feature // .feature_slug // empty' "$f" 2>/dev/null || true)
    [ -n "$slug" ] && upsert "$slug" "doing"
  done
fi

# 3. Spec files with no checkpoint → planned → todo
if [ -d "$SPEC_DIR" ]; then
  for f in "$SPEC_DIR"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f" .md)
    case "$base" in
      *-plan|*-implementation) continue ;;
    esac
    upsert "$base" "todo"
  done
fi

if [ -z "$SLUGS" ]; then
  echo "✓ no existing features found (no checkpoints or specs); todolist left empty"
  # Still ensure the file exists so the dashboard has something to read.
  [ "$DRY" -eq 0 ] && bash "$WRITER" --init >/dev/null
  exit 0
fi

# Human-readable title: first H1 of the spec, else the slug.
title_of() {
  local slug="$1" spec="$SPEC_DIR/$slug.md" t=""
  if [ -f "$spec" ]; then
    t=$(grep -m1 '^# ' "$spec" 2>/dev/null | sed 's/^# *//' || true)
  fi
  [ -n "$t" ] && echo "$t" || echo "$slug"
}

# ─── Apply ──────────────────────────────────────────────────────────────
[ "$DRY" -eq 0 ] && bash "$WRITER" --init >/dev/null

count=0
for slug in $SLUGS; do
  st=$(status_of "$slug")
  title=$(title_of "$slug")
  case "$st" in
    done)  label="✅ shipped" ;;
    doing) label="🔵 in-flight" ;;
    *)     label="⚪ planned" ;;
  esac
  if [ "$DRY" -eq 1 ]; then
    printf "   would backfill: %-28s %s (item: %s)\n" "$slug" "$label" "$st"
  else
    bash "$WRITER" --add-function --fn-id "$slug" --fn-title "$title" --linked-feature "$slug" >/dev/null
    bash "$WRITER" --add-item --fn-id "$slug" --item-text "$title" --item-status "$st" --source backfill >/dev/null
  fi
  count=$((count + 1))
done

if [ "$DRY" -eq 1 ]; then
  echo "(dry run — $count feature(s) would be backfilled into $TODOLIST_FILE)"
else
  echo "✓ backfilled $count feature(s) into $TODOLIST_FILE"
fi
