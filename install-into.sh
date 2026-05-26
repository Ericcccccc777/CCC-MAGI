#!/usr/bin/env bash
# install-into.sh — quick-and-dirty local install of CCC-Harness into a test directory.
#
# This script is NOT the production installer. It's a local convenience for
# testing the harness without needing the npx package published. It does
# what `npx create-ccc-harness` does, but copies from this working dir's
# outcome/ instead of cloning from GitHub.
#
# USAGE:
#   bash install-into.sh <target-dir>
#   bash install-into.sh <target-dir> --force        # overwrite existing CCC-Harness files
#   bash install-into.sh <target-dir> --dry-run      # show what would be done
#
# EXAMPLES:
#   bash install-into.sh ~/Desktop/test-harness-demo
#   bash install-into.sh ~/projects/my-todo-app --force

set -eu

# ─────────────────────────────────────────────────────────────────────
# Args
# ─────────────────────────────────────────────────────────────────────

if [ $# -lt 1 ]; then
  cat <<EOF
Usage: bash install-into.sh <target-dir> [--force] [--dry-run]

Installs CCC-Harness from this repo's outcome/ into <target-dir>.

Examples:
  bash install-into.sh ~/Desktop/test-harness-demo
  bash install-into.sh ~/projects/my-app --force
EOF
  exit 1
fi

TARGET="$1"
shift

FORCE=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --force)   FORCE=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────
# Resolve paths
# ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source resolution: dev mode (this repo) has harness contents under outcome/.
# Publish mode (CCC-Harness GitHub repo) has them at the script's same level.
if [ -d "$SCRIPT_DIR/outcome" ]; then
  SOURCE="$SCRIPT_DIR/outcome"
else
  SOURCE="$SCRIPT_DIR"
fi

if [ ! -d "$SOURCE" ]; then
  echo "❌ Source not found: $SOURCE" >&2
  echo "   This script expects to live in the Harness/ working dir with outcome/ as sibling." >&2
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────
# Prerequisite checks
# ─────────────────────────────────────────────────────────────────────

# jq is required for merging .claude/settings.json and .codex/hooks.json with
# any pre-existing user-side JSON (preserving user's MCP permissions / custom
# hooks rather than blowing them away). Bash-only JSON parsing is too error-prone.
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is not installed but is required for safely merging settings.json / hooks.json." >&2
  echo "   Install it and re-run:" >&2
  echo "     macOS:  brew install jq" >&2
  echo "     Linux:  sudo apt install jq   (or your distro's equivalent)" >&2
  echo "" >&2
  echo "   Alternatively, use the npx installer which does not require jq:" >&2
  echo "     npx create-ccc-harness@latest" >&2
  exit 1
fi

# Resolve target to absolute path. Validate parent dir exists FIRST so we don't
# corrupt the displayed error path when only the parent is missing.
TARGET_INPUT="$TARGET"
TARGET_PARENT="$(dirname "$TARGET_INPUT")"
TARGET_BASE="$(basename "$TARGET_INPUT")"

if [ ! -d "$TARGET_PARENT" ]; then
  echo "❌ Parent directory does not exist: $TARGET_PARENT" >&2
  echo "   (You typed: $TARGET_INPUT)" >&2
  echo "   Create the parent first, or check for typos in the path." >&2
  exit 1
fi

TARGET="$(cd "$TARGET_PARENT" && pwd)/$TARGET_BASE"

if [ ! -d "$TARGET" ]; then
  echo "❌ Target directory does not exist: $TARGET" >&2
  echo "   Create it first: mkdir -p \"$TARGET\"" >&2
  exit 1
fi

echo ""
echo "📦 install-into.sh"
echo "   source: $SOURCE"
echo "   target: $TARGET"
[ "$FORCE" -eq 1 ] && echo "   mode:   FORCE (will overwrite existing files)"
[ "$DRY"   -eq 1 ] && echo "   mode:   DRY RUN (no writes)"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Pre-install detection (lightweight — full AI-driven detection happens
# in the bootstrap when user opens Claude Code post-install)
# ─────────────────────────────────────────────────────────────────────

EXISTING=()
for marker in \
  ".bmad-core" "bmad-method" ".bmad" \
  ".speckit" "speckit.yml" "speckit.yaml" \
  ".openspec" ".superpowers" ".ruflo" ".claude-flow" \
  ".cursorrules" ".cursor" \
  ".clinerules" ".windsurfrules" \
  ".aider.conf.yml" \
  "constitution.md" ".harness"; do
  if [ -e "$TARGET/$marker" ]; then
    EXISTING+=("$marker")
  fi
done

if [ ${#EXISTING[@]} -gt 0 ]; then
  echo "⚠️  Detected possible existing harness configs:"
  for m in "${EXISTING[@]}"; do
    echo "    • $m"
  done
  echo ""
  echo "   CCC-Harness handles these gracefully — the AI-driven bootstrap"
  echo "   inside Claude Code will ask you what to do (archive / overwrite / decline)."
  echo "   This installer just gets files on disk."
  echo ""
fi

# ─────────────────────────────────────────────────────────────────────
# File mappings (mirror of installer/bin.js FILE_MAPPINGS + /init Step 4)
# Format: "<src-relative>|<dst-relative>|<type:file|dir|dir-merge|json-merge>"
#
# dir-merge: for each file under the source directory, install if absent in
# destination; preserve if present (skip). Protects user customizations
# (e.g., a user-added skill at .harness/skills/custom/) while still
# delivering new harness files (e.g., a newly-added /remember skill).
# See merge_dir_recursive() below for the trade-off note.
# ─────────────────────────────────────────────────────────────────────

declare -a MAPPINGS=(
  "constitution.md|constitution.md|file"
  "CLAUDE.md|CLAUDE.md|file"
  "AGENTS.md|AGENTS.md|file"
  "skills|.harness/skills|dir-merge"
  "agents|.harness/agents|dir-merge"
  "scripts|.harness/scripts|dir-merge"
  "cli-configs/claude/settings.json|.claude/settings.json|json-merge"
  "cli-configs/claude/commands|.claude/commands|dir-merge"
  "cli-configs/codex/config.toml|.codex/config.toml|file"
  "cli-configs/codex/hooks.json|.codex/hooks.json|json-merge"
  # docs-harness dir MUST come before cli-configs/README.md placement.
  # Same reason as installer/bin.js: dir-merge mapping mirrors the whole tree;
  # if a file mapping pre-creates docs-harness/, file-level conflicts arise.
  "docs-harness|docs-harness|dir-merge"
  "cli-configs/README.md|docs-harness/cli-configs-README.md|file"
  ".claude-plugin/plugin.json|.claude-plugin/plugin.json|file"
  ".gitignore|.gitignore|file"
  "README.md|CCC_HARNESS_README.md|file"
  "LICENSE|CCC_HARNESS_LICENSE|file"
)

# ─────────────────────────────────────────────────────────────────────
# Execute
# ─────────────────────────────────────────────────────────────────────

if [ "$DRY" -eq 1 ]; then
  echo "📋 DRY RUN — files that would be installed:"
  for entry in "${MAPPINGS[@]}"; do
    IFS='|' read -r src dst type <<< "$entry"
    printf "    %-40s → %s\n" "$src" "$dst"
  done
  echo ""
  echo "(No writes performed. Re-run without --dry-run to install.)"
  exit 0
fi

# Load-bearing files — these carry the Bootstrap Status Check block and other
# entry-point logic. If we skip installing them due to a name collision, the
# harness simply doesn't work (the user's existing file has no bootstrap trigger).
# Strategy: back up the user's existing file to <name>.pre-ccc-harness, then install ours.
# Note: on case-insensitive filesystems (macOS default), `claude.md` and `CLAUDE.md`
# are THE SAME FILE — the backup approach handles this correctly because the
# backup name has a unique `.pre-ccc-harness` suffix.
LOAD_BEARING_FILES=("CLAUDE.md" "AGENTS.md" "constitution.md")

is_load_bearing() {
  local file="$1"
  local lb
  for lb in "${LOAD_BEARING_FILES[@]}"; do
    [ "$file" = "$lb" ] && return 0
  done
  return 1
}

backup_existing() {
  local dst_path="$1"
  local backup="$dst_path.pre-ccc-harness"
  if [ -e "$backup" ]; then
    backup="$dst_path.pre-ccc-harness.$(date +%Y%m%d-%H%M%S)"
  fi
  mv "$dst_path" "$backup"
  echo "$(basename "$backup")"
}

# ─────────────────────────────────────────────────────────────────────
# dir-merge semantics: for each file in source, install if absent in dest,
# preserve if present. This protects user customizations (e.g., a user-added
# skill at .harness/skills/custom/) while still delivering new harness files
# (e.g., a newly-added /remember skill).
#
# Trade-off: if the harness UPDATES an existing skill (e.g., /init gets
# a bug fix), users with the old version installed will NOT get the update
# unless they pass --force. This is conservative — better to underinstall
# updates than silently overwrite user customizations. Long-term we may
# add a content-hash check ("if file is unchanged from harness original,
# safe to overwrite"), but v0.2 keeps it simple.
#
# Returns "<copied>:<skipped>" on stdout.
# bash 3.2 compat: no declare -A, no mapfile; use find -print0 | while read -d ''.
# ─────────────────────────────────────────────────────────────────────
merge_dir_recursive() {
  local src="$1"
  local dst="$2"
  local force="$3"
  local copied=0
  local skipped=0
  mkdir -p "$dst"
  # Use find to traverse the source; for each file, mirror to dst preserving structure.
  while IFS= read -r -d '' src_file; do
    local rel="${src_file#$src/}"
    local dst_file="$dst/$rel"
    local dst_dir="$(dirname "$dst_file")"
    mkdir -p "$dst_dir"
    if [ -e "$dst_file" ] && [ "$force" -ne 1 ]; then
      skipped=$((skipped + 1))
    else
      cp "$src_file" "$dst_file"
      copied=$((copied + 1))
    fi
  done < <(find "$src" -type f -print0)
  echo "${copied}:${skipped}"
}

# ─────────────────────────────────────────────────────────────────────
# JSON merge for .claude/settings.json and .codex/hooks.json
#
# Why: if the user already has a settings.json (MCP perms, custom hooks),
# a plain copy either skips (no --force → our bootstrap hook never wires
# up) or clobbers (--force → wipes user's perms). Merge instead.
#
# Rules:
#   1. Target absent → copy ours verbatim.
#   2. Target present →
#      a. Back up to <path>.pre-ccc-harness ONCE (skip if backup exists).
#      b. For each of our hook entries (identified by command substring
#         matching .harness/scripts/<script>), check if same command path
#         already exists in the corresponding event array; if yes, leave
#         user's alone (idempotent). If no, append ours.
#      c. permissions.allow array: union ours with user's.
#      d. Preserve all other user keys untouched.
#      e. Write merged JSON with 2-space indent.
# ─────────────────────────────────────────────────────────────────────

merge_json_settings() {
  local src_path="$1"
  local dst_path="$2"

  # Case 1: target absent — just copy.
  if [ ! -e "$dst_path" ]; then
    mkdir -p "$(dirname "$dst_path")"
    cp "$src_path" "$dst_path"
    return 0
  fi

  # Case 2: target present — merge.
  # Validate target is parseable JSON; if not, refuse to merge and bail.
  if ! jq empty "$dst_path" >/dev/null 2>&1; then
    echo "   ❌ $(basename "$dst_path") exists but is not valid JSON — skipping merge (manual fix required)." >&2
    return 1
  fi
  if ! jq empty "$src_path" >/dev/null 2>&1; then
    echo "   ❌ Source $(basename "$src_path") is not valid JSON — skipping merge." >&2
    return 1
  fi

  # Back up the existing file ONCE (skip if .pre-ccc-harness already exists).
  local backup="$dst_path.pre-ccc-harness"
  local backed_up=0
  if [ ! -e "$backup" ]; then
    cp "$dst_path" "$backup"
    backed_up=1
  fi

  # Build merged JSON. The merge logic:
  #   - For each event in our hooks (UserPromptSubmit, PreToolUse, PostToolUse),
  #     for each entry in our event array, append to target's array unless an
  #     entry already exists with at least one inner hook whose command string
  #     equals one of ours (idempotency by command path).
  #   - For permissions.allow, union our list with user's (preserving order:
  #     user first, then our additions).
  #   - Preserve all other keys in the user file.
  #
  # The jq program below takes our settings as $ours via --slurpfile and the
  # target as the main input, and emits merged JSON.

  local tmp
  tmp="$(mktemp -t ccc-merge.XXXXXX)" || { echo "mktemp failed" >&2; return 1; }

  if ! jq --indent 2 --slurpfile ours "$src_path" '
    . as $user
    | ($ours[0]) as $o
    # Flatten an event-level array (e.g., hooks.UserPromptSubmit) into the
    # set of inner command strings it contains. Used for idempotency check.
    | def commands_in_array($arr):
        [ $arr[]? | (.hooks // [])[]? | .command // empty ];
      # For a given event name, return user array with our entries appended
      # iff none of their inner-command strings are already present in user.
      def merge_event($event):
        # If the user has the key but it is not an array (malformed schema or
        # a documentation key like _comment with a string value), fall back to
        # [] so the merge still produces a valid array — mirrors the JS
        # installer (Array.isArray(userArr) ? [...userArr] : []).
        ($user.hooks[$event] // []) as $raw
        | (if ($raw | type) == "array" then $raw else [] end) as $u
        | ($o.hooks[$event] // []) as $oraw
        | (if ($oraw | type) == "array" then $oraw else [] end) as $oarr
        | commands_in_array($u) as $u_cmds
        | $u + [
            $oarr[]
            | . as $entry
            | ([ (.hooks // [])[]? | .command // empty ]) as $entry_cmds
            | ($entry_cmds | map(IN($u_cmds[]))) as $matches
            | if ($entry_cmds | length) > 0
                 and ($matches | all)
              then empty   # every command in this entry already in user → skip (idempotent)
              else $entry
              end
          ];
      # Build merged hooks: union of event names from both sides.
      # Only include keys whose VALUES are arrays — documentation keys like
      # `_comment` (string value) are NOT events and must be preserved verbatim.
      (($user.hooks // {}) | to_entries | map(select(.value | type == "array") | .key)) as $u_events
    | (($o.hooks // {}) | to_entries | map(select(.value | type == "array") | .key)) as $o_events
    | (($u_events + $o_events) | unique) as $all_events
    | (reduce $all_events[] as $ev (
        ($user.hooks // {});
        .[$ev] = merge_event($ev)
      )) as $merged_hooks
    # Merged permissions.allow (union: user first, then ours not already in user).
    | (($user.permissions.allow // [])) as $u_allow
    | (($o.permissions.allow // [])) as $o_allow
    | ($u_allow + [ $o_allow[] | select(. as $x | $u_allow | index($x) | not) ]) as $merged_allow
    | $user
    | .hooks = $merged_hooks
    | if ($o.permissions.allow // null) != null or ($user.permissions.allow // null) != null
        then .permissions.allow = $merged_allow
        else .
      end
  ' "$dst_path" > "$tmp"; then
    echo "   ❌ jq merge failed for $(basename "$dst_path") — leaving target unchanged." >&2
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$dst_path"

  if [ "$backed_up" -eq 1 ]; then
    echo "BACKED_UP"
  else
    echo "MERGED"
  fi
  return 0
}

echo "Installing..."
COPIED=0
SKIPPED=0
BACKED_UP=0
for entry in "${MAPPINGS[@]}"; do
  IFS='|' read -r src dst type <<< "$entry"
  SRC_PATH="$SOURCE/$src"
  DST_PATH="$TARGET/$dst"

  if [ ! -e "$SRC_PATH" ]; then
    echo "   $src → (not in source; skipping)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Special handling for load-bearing files: always install, but back up existing first.
  if is_load_bearing "$dst" && [ -e "$DST_PATH" ]; then
    # Check whether the existing file is already our version (e.g., re-running install).
    # Signature: our CLAUDE.md contains "Bootstrap Status Check"; constitution.md contains "SLOT REGISTRY";
    # AGENTS.md contains "external auditor model". If signature matches, just reinstall fresh (no backup needed).
    SIG=""
    case "$dst" in
      "CLAUDE.md")       SIG="Bootstrap Status Check" ;;
      "constitution.md") SIG="SLOT REGISTRY" ;;
      "AGENTS.md")       SIG="external auditor model" ;;
    esac
    if [ -n "$SIG" ] && grep -q "$SIG" "$DST_PATH" 2>/dev/null; then
      printf "   ↻ %-40s → %s (existing CCC-Harness version; reinstalling fresh)\n" "$src" "$dst"
      cp "$SRC_PATH" "$DST_PATH"
      COPIED=$((COPIED + 1))
      continue
    fi
    # Existing file is the user's — back it up before overwriting.
    BACKUP_NAME=$(backup_existing "$DST_PATH")
    printf "   ⚠ %-40s → %s (existing user file backed up to %s)\n" "$src" "$dst" "$BACKUP_NAME"
    cp "$SRC_PATH" "$DST_PATH"
    COPIED=$((COPIED + 1))
    BACKED_UP=$((BACKED_UP + 1))
    continue
  fi

  # dir-merge: per-file install/preserve under the destination directory.
  # See merge_dir_recursive() comment for trade-off note.
  if [ "$type" = "dir-merge" ]; then
    RESULT=$(merge_dir_recursive "$SRC_PATH" "$DST_PATH" "$FORCE")
    COPIED_CT="${RESULT%:*}"
    SKIPPED_CT="${RESULT#*:}"
    if [ "$COPIED_CT" -gt 0 ] && [ "$SKIPPED_CT" -gt 0 ]; then
      printf "   ⊕ %-40s → %s/ (%d new, %d preserved)\n" "$src" "$dst" "$COPIED_CT" "$SKIPPED_CT"
    elif [ "$COPIED_CT" -gt 0 ]; then
      printf "   ✓ %-40s → %s/ (%d files)\n" "$src" "$dst" "$COPIED_CT"
    else
      printf "   = %-40s → %s/ (all %d files already existed)\n" "$src" "$dst" "$SKIPPED_CT"
    fi
    COPIED=$((COPIED + COPIED_CT))
    SKIPPED=$((SKIPPED + SKIPPED_CT))
    continue
  fi

  # JSON merge: settings.json / hooks.json — never plain-overwrite, never skip.
  # Always merge ours into user's (creates target if absent; preserves user content if present).
  if [ "$type" = "json-merge" ]; then
    mkdir -p "$(dirname "$DST_PATH")"
    if [ ! -e "$DST_PATH" ]; then
      cp "$SRC_PATH" "$DST_PATH"
      printf "   ✓ %-40s → %s (new)\n" "$src" "$dst"
      COPIED=$((COPIED + 1))
    else
      MERGE_RESULT=$(merge_json_settings "$SRC_PATH" "$DST_PATH") || {
        SKIPPED=$((SKIPPED + 1))
        continue
      }
      if [ "$MERGE_RESULT" = "BACKED_UP" ]; then
        printf "   ⊕ %-40s → %s (merged; user file backed up to %s.pre-ccc-harness)\n" "$src" "$dst" "$(basename "$dst")"
        BACKED_UP=$((BACKED_UP + 1))
      else
        printf "   ⊕ %-40s → %s (re-merged; idempotent)\n" "$src" "$dst"
      fi
      COPIED=$((COPIED + 1))
    fi
    continue
  fi

  # Non-load-bearing files: preserve existing unless --force
  if [ -e "$DST_PATH" ] && [ "$FORCE" -ne 1 ]; then
    echo "   $dst (already exists; preserving — use --force to overwrite)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Ensure parent dir exists
  mkdir -p "$(dirname "$DST_PATH")"

  if [ "$type" = "dir" ]; then
    [ -e "$DST_PATH" ] && rm -rf "$DST_PATH"
    cp -R "$SRC_PATH" "$DST_PATH"
  else
    cp "$SRC_PATH" "$DST_PATH"
  fi
  printf "   ✓ %-40s → %s\n" "$src" "$dst"
  COPIED=$((COPIED + 1))
done

# chmod +x on shell scripts
SCRIPTS_DIR="$TARGET/.harness/scripts"
if [ -d "$SCRIPTS_DIR" ]; then
  chmod +x "$SCRIPTS_DIR"/*.sh 2>/dev/null || true
  echo "   ✓ chmod +x .harness/scripts/*.sh"
fi

# ─────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────────────────────"
if [ "$BACKED_UP" -gt 0 ]; then
  echo "✅ Installed. ($COPIED copied, $SKIPPED skipped, $BACKED_UP user file(s) backed up)"
  echo ""
  echo "Note: $BACKED_UP existing file(s) at the target had pre-existing user content."
  echo "They were backed up with .pre-ccc-harness suffix before CCC-Harness's"
  echo "versions were installed. The bootstrap flow (inside Claude Code) will"
  echo "ask you what to do with the user content."
else
  echo "✅ Installed. ($COPIED copied, $SKIPPED skipped)"
fi
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "Next: open Claude Code in the target directory."
echo ""
echo "  cd \"$TARGET\""
echo "  claude"
echo ""
echo "The AI will detect that CCC-Harness needs configuration"
echo "(because .harness/state/install.json doesn't exist) and walk"
echo "you through the bootstrap + /init flow."
echo ""
echo "Read first:"
echo "  CCC_HARNESS_README.md             — overview"
echo "  docs-harness/adoption-playbook.md — full walkthrough"
echo ""
