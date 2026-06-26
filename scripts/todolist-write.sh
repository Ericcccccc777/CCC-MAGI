#!/usr/bin/env bash
# todolist-write.sh — atomic writer for .harness/state/todolist.json
#
# The project todolist is a function-grouped work ledger: the project is split
# into FUNCTIONS (features / capability areas), each holding ITEMS that are
# done / doing / todo. It records "what we've built, what we're building, what
# we want to build next" — the durable answer to "where is this project at".
#
# This is the single source of truth for the todolist schema (mirror of the
# checkpoint-write.sh pattern: change the schema here, every consumer inherits
# it). Read by:
#   - /todolist skill (human-facing view + edits)
#   - CCC 灵动岛 dashboard (todolist page, function-categorized board)
#   - the updater's backfill step (seeds functions from existing checkpoints)
#
# USAGE:
#   todolist-write.sh <operation> [options]
#
# OPERATIONS:
#   --init                       Create todolist.json if missing (no-op if present).
#   --add-function               Add a function group. Requires --fn-id, --fn-title.
#   --add-item                   Add an item to a function. Requires --fn-id, --item-text.
#                                Prints the new item id to stdout.
#   --set-item-status            Change an item's status. Requires --fn-id, --item-id, --item-status.
#   --set-function-status        Set a function's status explicitly. Requires --fn-id, --fn-status.
#   --derive-function-status     Recompute a function's status from its items. Requires --fn-id.
#   --remove-item                Remove an item. Requires --fn-id, --item-id.
#   --remove-function            Remove a function (and its items). Requires --fn-id.
#   --list                       Print the whole todolist JSON to stdout (for dashboards / AI).
#
# OPTIONS:
#   --fn-id <slug>               Function id (kebab-case; usually the feature slug).
#   --fn-title <text>            Function display title.
#   --fn-desc <text>             Function one-line description (optional).
#   --fn-status <status>         planned | in-progress | done | abandoned
#   --linked-feature <slug>      Feature slug this function maps to (docs/features/<slug>.md).
#   --item-id <id>               Item id (e.g. auth-3).
#   --item-text <text>           Item description (what the work is).
#   --item-status <status>       todo | doing | done   (default: todo on add)
#   --item-note <text>           Optional note on the item.
#   --source <src>               Where the item came from: manual | spec | plan |
#                                research | ai-suggested | backfill (default: manual)
#   --project <name>             Project name (used by --init; default from install.json or "project").
#
# OUTPUT:
#   - On success: prints a "✓ ..." line (or requested data) to stdout, exits 0.
#   - On error:   prints error to stderr, exits 1.
#
# DESIGN NOTES:
#   - Atomic write: tmp + rename (never leaves a half-written todolist).
#   - Idempotent where it can be: --init is a no-op if the file exists; adding a
#     function with an existing id updates its metadata rather than duplicating.
#   - Item ids are stable: <fn-id>-<seq>, seq = (max existing seq for fn) + 1,
#     never reused even after removal.
#   - Function status auto-derives from items on any item change UNLESS the
#     function status was set explicitly via --set-function-status (sticky:
#     "abandoned" and "done" set by hand are preserved).
#   - jq is required.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v jq >/dev/null 2>&1; then
  echo "todolist-write.sh requires jq. Install with: brew install jq" >&2
  exit 1
fi

SCHEMA_VERSION=1
TODOLIST_FILE=".harness/state/todolist.json"

# ─── Parse args ────────────────────────────────────────────────────────
OP=""
FN_ID=""
FN_TITLE=""
FN_DESC=""
FN_STATUS=""
LINKED_FEATURE=""
ITEM_ID=""
ITEM_TEXT=""
ITEM_STATUS=""
ITEM_NOTE=""
SOURCE="manual"
PROJECT=""

set_op() {
  if [ -n "$OP" ]; then
    echo "todolist-write.sh: multiple operations given ($OP and $1); pick one" >&2
    exit 1
  fi
  OP="$1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --init)                   set_op "init"; shift ;;
    --add-function)           set_op "add-function"; shift ;;
    --add-item)               set_op "add-item"; shift ;;
    --set-item-status)        set_op "set-item-status"; shift ;;
    --set-function-status)    set_op "set-function-status"; shift ;;
    --derive-function-status) set_op "derive-function-status"; shift ;;
    --remove-item)            set_op "remove-item"; shift ;;
    --remove-function)        set_op "remove-function"; shift ;;
    --list)                   set_op "list"; shift ;;
    --fn-id)                  FN_ID="$2"; shift 2 ;;
    --fn-title)               FN_TITLE="$2"; shift 2 ;;
    --fn-desc)                FN_DESC="$2"; shift 2 ;;
    --fn-status)              FN_STATUS="$2"; shift 2 ;;
    --linked-feature)         LINKED_FEATURE="$2"; shift 2 ;;
    --item-id)                ITEM_ID="$2"; shift 2 ;;
    --item-text)              ITEM_TEXT="$2"; shift 2 ;;
    --item-status)            ITEM_STATUS="$2"; shift 2 ;;
    --item-note)              ITEM_NOTE="$2"; shift 2 ;;
    --source)                 SOURCE="$2"; shift 2 ;;
    --project)                PROJECT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$OP" ]; then
  echo "todolist-write.sh: no operation given (e.g. --init, --add-item, --list)" >&2
  exit 1
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STATE_DIR=".harness/state"
mkdir -p "$STATE_DIR"

# ─── Validation helpers ────────────────────────────────────────────────
valid_fn_status() { case "$1" in planned|in-progress|done|abandoned) return 0 ;; *) return 1 ;; esac; }
valid_item_status() { case "$1" in todo|doing|done) return 0 ;; *) return 1 ;; esac; }

require() {
  # require <value> <flag-name>
  if [ -z "$1" ]; then
    echo "todolist-write.sh: $OP requires $2" >&2
    exit 1
  fi
}

# ─── Resolve project name for --init ───────────────────────────────────
resolve_project() {
  if [ -n "$PROJECT" ]; then echo "$PROJECT"; return; fi
  if [ -f "$STATE_DIR/install.json" ]; then
    local p
    p=$(jq -r '.slots.project_name // empty' "$STATE_DIR/install.json" 2>/dev/null || true)
    if [ -n "$p" ]; then echo "$p"; return; fi
  fi
  echo "project"
}

# ─── Ensure file exists (used by all mutating ops) ─────────────────────
ensure_file() {
  if [ ! -f "$TODOLIST_FILE" ]; then
    local proj
    proj=$(resolve_project)
    jq -n \
      --argjson schema_version "$SCHEMA_VERSION" \
      --arg project "$proj" \
      --arg now "$NOW" \
      '{
         schema_version: $schema_version,
         project: $project,
         created_at: $now,
         updated_at: $now,
         functions: []
       }' > "$TODOLIST_FILE"
  fi
}

# ─── Atomic apply: run a jq filter over the file with given args ───────
apply() {
  # apply <jq-filter> [jq-args...]
  local filter="$1"; shift
  local tmp
  tmp=$(mktemp "${TODOLIST_FILE}.tmp.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  jq "$@" "$filter" "$TODOLIST_FILE" > "$tmp"
  mv "$tmp" "$TODOLIST_FILE"
  trap - EXIT
}

# ─── Operations ────────────────────────────────────────────────────────
case "$OP" in
  init)
    ensure_file
    echo "✓ todolist ready: $TODOLIST_FILE"
    ;;

  list)
    if [ ! -f "$TODOLIST_FILE" ]; then
      # Emit a valid empty todolist so consumers never choke on a missing file.
      jq -n --argjson sv "$SCHEMA_VERSION" '{schema_version:$sv, project:"", functions:[]}'
    else
      cat "$TODOLIST_FILE"
    fi
    ;;

  add-function)
    require "$FN_ID" "--fn-id"
    require "$FN_TITLE" "--fn-title"
    if [ -n "$FN_STATUS" ] && ! valid_fn_status "$FN_STATUS"; then
      echo "todolist-write.sh: invalid --fn-status '$FN_STATUS' (planned|in-progress|done|abandoned)" >&2
      exit 1
    fi
    ensure_file
    apply '
      .updated_at = $now
      | if any(.functions[]; .id == $fn_id)
        then
          # Update existing function metadata in place (idempotent add).
          .functions |= map(
            if .id == $fn_id then
              .title = $fn_title
              | .description = (if $fn_desc == "" then .description else $fn_desc end)
              | .linked_feature = (if $linked == "" then .linked_feature else $linked end)
              | (if $fn_status == "" then . else .status = $fn_status end)
              | .updated_at = $now
            else . end
          )
        else
          .functions += [{
            id: $fn_id,
            title: $fn_title,
            description: (if $fn_desc == "" then null else $fn_desc end),
            status: (if $fn_status == "" then "planned" else $fn_status end),
            linked_feature: (if $linked == "" then null else $linked end),
            created_at: $now,
            updated_at: $now,
            items: []
          }]
        end
    ' --arg now "$NOW" --arg fn_id "$FN_ID" --arg fn_title "$FN_TITLE" \
      --arg fn_desc "$FN_DESC" --arg fn_status "$FN_STATUS" --arg linked "$LINKED_FEATURE"
    echo "✓ function: $FN_ID"
    ;;

  add-item)
    require "$FN_ID" "--fn-id"
    require "$ITEM_TEXT" "--item-text"
    local_status="${ITEM_STATUS:-todo}"
    if ! valid_item_status "$local_status"; then
      echo "todolist-write.sh: invalid --item-status '$local_status' (todo|doing|done)" >&2
      exit 1
    fi
    ensure_file
    # Auto-create the function if it doesn't exist yet (title defaults to id).
    if ! jq -e --arg fn_id "$FN_ID" 'any(.functions[]; .id == $fn_id)' "$TODOLIST_FILE" >/dev/null; then
      apply '
        .updated_at = $now
        | .functions += [{
            id: $fn_id, title: $fn_id, description: null, status: "planned",
            linked_feature: null, created_at: $now, updated_at: $now, items: []
          }]
      ' --arg now "$NOW" --arg fn_id "$FN_ID"
    fi
    # Compute next item id = <fn-id>-<maxseq+1>.
    NEXT_SEQ=$(jq -r --arg fn_id "$FN_ID" '
      (.functions[] | select(.id == $fn_id) | .items
        | map(.id | capture("-(?<n>[0-9]+)$") | .n | tonumber) | max) // 0
      | . + 1
    ' "$TODOLIST_FILE")
    NEW_ITEM_ID="${FN_ID}-${NEXT_SEQ}"
    apply '
      .updated_at = $now
      | .functions |= map(
          if .id == $fn_id then
            .items += [{
              id: $item_id,
              text: $item_text,
              status: $item_status,
              source: $source,
              note: (if $item_note == "" then null else $item_note end),
              created_at: $now,
              updated_at: $now
            }]
            | .updated_at = $now
            # Re-derive function status from items (sticky: never auto-clear abandoned).
            | (if .status == "abandoned" then .
               elif (.items | length) > 0 and all(.items[]; .status == "done") then .status = "done"
               elif any(.items[]; .status == "doing" or .status == "done") then .status = "in-progress"
               else .status = "planned" end)
          else . end
        )
    ' --arg now "$NOW" --arg fn_id "$FN_ID" --arg item_id "$NEW_ITEM_ID" \
      --arg item_text "$ITEM_TEXT" --arg item_status "$local_status" \
      --arg source "$SOURCE" --arg item_note "$ITEM_NOTE"
    echo "$NEW_ITEM_ID"
    ;;

  set-item-status)
    require "$FN_ID" "--fn-id"
    require "$ITEM_ID" "--item-id"
    require "$ITEM_STATUS" "--item-status"
    if ! valid_item_status "$ITEM_STATUS"; then
      echo "todolist-write.sh: invalid --item-status '$ITEM_STATUS' (todo|doing|done)" >&2
      exit 1
    fi
    if [ ! -f "$TODOLIST_FILE" ]; then echo "todolist-write.sh: no todolist yet" >&2; exit 1; fi
    if ! jq -e --arg fn "$FN_ID" --arg it "$ITEM_ID" \
         'any(.functions[]; .id==$fn and any(.items[]; .id==$it))' "$TODOLIST_FILE" >/dev/null; then
      echo "todolist-write.sh: item not found: $FN_ID / $ITEM_ID" >&2; exit 1
    fi
    apply '
      .updated_at = $now
      | .functions |= map(
          if .id == $fn_id then
            .items |= map(if .id == $item_id then .status = $item_status | .updated_at = $now else . end)
            | .updated_at = $now
            # Re-derive function status from items unless it was hand-set to a sticky terminal state.
            | (if .status == "abandoned" then .
               elif (.items | length) > 0 and all(.items[]; .status == "done") then .status = "done"
               elif any(.items[]; .status == "doing" or .status == "done") then .status = "in-progress"
               else .status = "planned" end)
          else . end
        )
    ' --arg now "$NOW" --arg fn_id "$FN_ID" --arg item_id "$ITEM_ID" --arg item_status "$ITEM_STATUS"
    echo "✓ $FN_ID / $ITEM_ID → $ITEM_STATUS"
    ;;

  set-function-status)
    require "$FN_ID" "--fn-id"
    require "$FN_STATUS" "--fn-status"
    if ! valid_fn_status "$FN_STATUS"; then
      echo "todolist-write.sh: invalid --fn-status '$FN_STATUS' (planned|in-progress|done|abandoned)" >&2
      exit 1
    fi
    if [ ! -f "$TODOLIST_FILE" ]; then echo "todolist-write.sh: no todolist yet" >&2; exit 1; fi
    apply '
      .updated_at = $now
      | .functions |= map(if .id == $fn_id then .status = $fn_status | .updated_at = $now else . end)
    ' --arg now "$NOW" --arg fn_id "$FN_ID" --arg fn_status "$FN_STATUS"
    echo "✓ function $FN_ID → $FN_STATUS"
    ;;

  derive-function-status)
    require "$FN_ID" "--fn-id"
    if [ ! -f "$TODOLIST_FILE" ]; then echo "todolist-write.sh: no todolist yet" >&2; exit 1; fi
    apply '
      .updated_at = $now
      | .functions |= map(
          if .id == $fn_id then
            (if .status == "abandoned" then .
             elif (.items | length) > 0 and all(.items[]; .status == "done") then .status = "done"
             elif any(.items[]; .status == "doing" or .status == "done") then .status = "in-progress"
             else .status = "planned" end)
            | .updated_at = $now
          else . end
        )
    ' --arg now "$NOW" --arg fn_id "$FN_ID"
    echo "✓ derived status for $FN_ID"
    ;;

  remove-item)
    require "$FN_ID" "--fn-id"
    require "$ITEM_ID" "--item-id"
    if [ ! -f "$TODOLIST_FILE" ]; then echo "todolist-write.sh: no todolist yet" >&2; exit 1; fi
    apply '
      .updated_at = $now
      | .functions |= map(
          if .id == $fn_id then .items |= map(select(.id != $item_id)) | .updated_at = $now else . end
        )
    ' --arg now "$NOW" --arg fn_id "$FN_ID" --arg item_id "$ITEM_ID"
    echo "✓ removed item $FN_ID / $ITEM_ID"
    ;;

  remove-function)
    require "$FN_ID" "--fn-id"
    if [ ! -f "$TODOLIST_FILE" ]; then echo "todolist-write.sh: no todolist yet" >&2; exit 1; fi
    apply '
      .updated_at = $now | .functions |= map(select(.id != $fn_id))
    ' --arg now "$NOW" --arg fn_id "$FN_ID"
    echo "✓ removed function $FN_ID"
    ;;

  *)
    echo "todolist-write.sh: unhandled operation: $OP" >&2
    exit 1
    ;;
esac
