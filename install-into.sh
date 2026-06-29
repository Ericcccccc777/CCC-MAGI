#!/usr/bin/env bash
# install-into.sh — quick-and-dirty local install of CCC-MAGI into a test directory.
#
# This script is NOT the production installer. It's a local convenience for
# testing the harness without needing the npx package published. It does
# what `npx create-ccc-magi` does, but copies from this working dir's
# outcome/ instead of cloning from GitHub.
#
# USAGE:
#   bash install-into.sh <target-dir>
#   bash install-into.sh <target-dir> --force                  # overwrite existing CCC-MAGI files (implies --force-load-bearing)
#   bash install-into.sh <target-dir> --force-load-bearing     # reset LOAD_BEARING files even if user-modified (backs them up)
#   bash install-into.sh <target-dir> --dry-run                # show what would be done
#
# EXAMPLES:
#   bash install-into.sh ~/Desktop/test-harness-demo
#   bash install-into.sh ~/projects/my-todo-app --force

set -eu

# Ensure brew-installed tools (jq, etc.) are on PATH even in non-interactive
# shells where ~/.zprofile isn't loaded. macOS Apple Silicon path comes first.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ─────────────────────────────────────────────────────────────────────
# Args
# ─────────────────────────────────────────────────────────────────────

if [ $# -lt 1 ]; then
  cat <<EOF
Usage: bash install-into.sh <target-dir> [--force] [--force-load-bearing] [--dry-run]

Installs CCC-MAGI from this repo's outcome/ into <target-dir>.

Examples:
  bash install-into.sh ~/Desktop/test-harness-demo
  bash install-into.sh ~/projects/my-app --force
EOF
  exit 1
fi

TARGET="$1"
shift

FORCE=0
FORCE_LOAD_BEARING=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --force)               FORCE=1; FORCE_LOAD_BEARING=1 ;;
    --force-load-bearing)  FORCE_LOAD_BEARING=1 ;;
    --dry-run)             DRY=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────
# Resolve paths
# ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source resolution: dev mode (this repo) has harness contents under outcome/.
# Publish mode (CCC-MAGI GitHub repo) has them at the script's same level.
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
# Run prereq check — fail fast if hard prereqs missing
# ─────────────────────────────────────────────────────────────────────
PREREQ_SCRIPT="$SCRIPT_DIR/scripts/check-prereqs.sh"
if [ ! -f "$PREREQ_SCRIPT" ]; then
  # Fall back to outcome/scripts/ in dev mode
  PREREQ_SCRIPT="$SCRIPT_DIR/outcome/scripts/check-prereqs.sh"
fi
if [ -f "$PREREQ_SCRIPT" ]; then
  bash "$PREREQ_SCRIPT" || exit 1
fi

# ─────────────────────────────────────────────────────────────────────
# Prerequisite checks (safety net — check-prereqs.sh above should catch this)
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
  echo "     npx create-ccc-magi@latest" >&2
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
[ "$FORCE" -eq 1 ]              && echo "   mode:   FORCE (will overwrite existing files; implies --force-load-bearing)"
[ "$FORCE_LOAD_BEARING" -eq 1 ] && [ "$FORCE" -eq 0 ] && echo "   mode:   FORCE-LOAD-BEARING (will reset LOAD_BEARING files with backup)"
[ "$DRY"   -eq 1 ]              && echo "   mode:   DRY RUN (no writes)"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Content-hash registry helpers
#
# .harness/state/shipped-hashes.json records SHA-256 of every file the
# installer shipped. On re-install, we compare:
#   dest_hash vs recorded_hash → "has the user modified this file since last install?"
#   dest_hash vs src_hash      → "is the file already at the new version?"
# This lets us safely deliver harness updates without clobbering user changes.
# ─────────────────────────────────────────────────────────────────────

REGISTRY_DIR="$TARGET/.harness/state"
REGISTRY_FILE="$REGISTRY_DIR/shipped-hashes.json"

# Compute SHA-256 of a file. Use shasum on macOS, sha256sum on Linux.
sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    echo "ERROR: neither sha256sum nor shasum available" >&2
    return 1
  fi
}

ensure_registry() {
  mkdir -p "$REGISTRY_DIR"
  if [ ! -f "$REGISTRY_FILE" ]; then
    echo '{"harness_version":"0.9.0","shipped_at":"","hashes":{}}' > "$REGISTRY_FILE"
  fi
}

get_recorded_hash() {
  local dst_path="$1"
  jq -r --arg p "$dst_path" '.hashes[$p] // empty' "$REGISTRY_FILE" 2>/dev/null
}

record_hash() {
  local dst_path="$1"
  local hash_value="$2"
  local tmp
  tmp="$(mktemp -t ccc-registry.XXXXXX)" || return 1
  jq --arg p "$dst_path" --arg h "$hash_value" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.shipped_at = $ts | .harness_version = "0.9.0" | .hashes[$p] = $h' \
     "$REGISTRY_FILE" > "$tmp" && mv "$tmp" "$REGISTRY_FILE"
}

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
  "CLAUDE.md" "AGENTS.md" "AGENT.md" \
  ".github/copilot-instructions.md" \
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
  echo "   CCC-MAGI handles these gracefully — the AI-driven bootstrap"
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
  ".harness/docs|.harness/docs|dir-merge"
  ".harness/workflows|.harness/workflows|dir-merge"
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
  "README.md|CCC_MAGI_README.md|file"
  "LICENSE|CCC_MAGI_LICENSE|file"
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

# Initialize the hash registry before doing any work.
ensure_registry

# Load-bearing files — these carry the Bootstrap Status Check block and other
# entry-point logic. Special handling under --force-load-bearing: even if user
# has modified them, back them up and overwrite. Otherwise content-hash logic
# applies (preserve user-modified files; auto-update unmodified ones).
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
  local backup="$dst_path.pre-ccc-magi"
  if [ -e "$backup" ]; then
    backup="$dst_path.pre-ccc-magi.$(date +%Y%m%d-%H%M%S)"
  fi
  mv "$dst_path" "$backup"
  echo "$(basename "$backup")"
}

# ─────────────────────────────────────────────────────────────────────
# install_file_with_hash — unified content-hash decision tree for a single
# src→dst file pair. Updates the hash registry and the COPIED/UPDATED/SKIPPED
# counters. Used by both top-level file mappings and dir-merge recursion.
#
# Args: <src_file> <dst_relative_path> <abs_dst_path> <force_lb_flag>
# Returns (via stdout): one of NEW / UPDATED / CURRENT / PRESERVED / FORCED
# ─────────────────────────────────────────────────────────────────────
install_file_with_hash() {
  local src_file="$1"
  local dst_rel="$2"
  local dst_path="$3"
  local force_lb="$4"

  mkdir -p "$(dirname "$dst_path")"

  if [ ! -e "$dst_path" ]; then
    cp "$src_file" "$dst_path"
    local h
    h="$(sha256_of "$src_file")"
    record_hash "$dst_rel" "$h"
    echo "NEW"
    return 0
  fi

  local dest_hash src_hash
  dest_hash="$(sha256_of "$dst_path")"
  src_hash="$(sha256_of "$src_file")"

  if [ "$dest_hash" = "$src_hash" ]; then
    # No change needed; ensure registry has it
    record_hash "$dst_rel" "$dest_hash"
    echo "CURRENT"
    return 0
  fi

  local recorded
  recorded="$(get_recorded_hash "$dst_rel")"

  if [ -n "$recorded" ]; then
    if [ "$dest_hash" = "$recorded" ]; then
      # User hasn't modified since last install → safe to overwrite
      cp "$src_file" "$dst_path"
      record_hash "$dst_rel" "$src_hash"
      echo "UPDATED"
      return 0
    else
      # User modified → preserve, unless --force-load-bearing + LOAD_BEARING file
      # (the explicit "reset everything" escape hatch).
      if [ "$force_lb" -eq 1 ] && is_load_bearing "$dst_rel"; then
        backup_existing "$dst_path" >/dev/null
        cp "$src_file" "$dst_path"
        record_hash "$dst_rel" "$src_hash"
        echo "FORCED"
        return 0
      fi
      # Don't update registry — preserves "user-modified" detection
      echo "PRESERVED"
      return 0
    fi
  else
    # No registry entry. The hash registry (.harness/state/shipped-hashes.json)
    # is gitignored, so ANY cloned / shared / re-checked-out project has none —
    # not just "old v0.8 installs". Decide by ownership instead of blanket-
    # preserving (the old default silently turned every update into a no-op on
    # cloned projects: with no recorded hash, no file ever matched, so nothing
    # was overwritten):
    if is_load_bearing "$dst_rel"; then
      # User-owned identity files (constitution / CLAUDE / AGENTS): never clobber
      # silently. Record the current hash and preserve, unless the explicit
      # --force-load-bearing escape hatch is set.
      record_hash "$dst_rel" "$dest_hash"
      if [ "$force_lb" -eq 1 ]; then
        backup_existing "$dst_path" >/dev/null
        cp "$src_file" "$dst_path"
        record_hash "$dst_rel" "$src_hash"
        echo "FORCED"
        return 0
      else
        echo "PRESERVED"
        return 0
      fi
    else
      # Harness-internal files (skills / scripts / agents / docs / hooks) are
      # OURS — updates must land. Overwrite with the shipped version. These are
      # committed to the project's git, so a prior hand-edit stays recoverable.
      cp "$src_file" "$dst_path"
      record_hash "$dst_rel" "$src_hash"
      echo "UPDATED"
      return 0
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────
# dir-merge with content-hash semantics.
#
# For each file in source: invoke install_file_with_hash. Returns "<new>:<updated>:<preserved>".
# bash 3.2 compat: no declare -A, no mapfile; use find -print0 | while read -d ''.
# ─────────────────────────────────────────────────────────────────────
merge_dir_recursive() {
  local src="$1"
  local dst="$2"
  local dst_prefix="$3"   # relative path prefix for registry keys (e.g., ".harness/skills")
  local new_ct=0
  local upd_ct=0
  local pres_ct=0
  mkdir -p "$dst"
  while IFS= read -r -d '' src_file; do
    local rel="${src_file#$src/}"
    local dst_file="$dst/$rel"
    local dst_rel="$dst_prefix/$rel"
    local result
    result="$(install_file_with_hash "$src_file" "$dst_rel" "$dst_file" "$FORCE_LOAD_BEARING")"
    case "$result" in
      NEW)       new_ct=$((new_ct + 1)) ;;
      UPDATED)   upd_ct=$((upd_ct + 1)) ;;
      PRESERVED) pres_ct=$((pres_ct + 1)) ;;
      CURRENT)   pres_ct=$((pres_ct + 1)) ;;
      FORCED)    upd_ct=$((upd_ct + 1)) ;;
    esac
  done < <(find "$src" -type f -print0)
  echo "${new_ct}:${upd_ct}:${pres_ct}"
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
#      a. Back up to <path>.pre-ccc-magi ONCE (skip if backup exists).
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

  # Back up the existing file ONCE (skip if .pre-ccc-magi already exists).
  local backup="$dst_path.pre-ccc-magi"
  local backed_up=0
  if [ ! -e "$backup" ]; then
    cp "$dst_path" "$backup"
    backed_up=1
  fi

  # Build merged JSON. The merge logic:
  #   - For each hook event, the harness OWNS its scripts: prune from the user's
  #     entries any inner hook invoking a .harness/scripts/* script we also ship
  #     (matched by script basename, ignoring an optional "bash " prefix), then
  #     append our canonical entries. This REPLACES old hook definitions on
  #     update (e.g. a direct-path command superseded by its bash-prefixed form)
  #     instead of leaving a stale duplicate. The user's own custom hooks — and
  #     harness hooks we no longer ship — are preserved. Idempotent.
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
    # Normalize a hook command to the harness script it invokes (basename), or
    # null if not a harness-owned hook. Strips an optional leading "bash " so
    # that "<path>/x.sh" and "bash <path>/x.sh" map to the SAME key — this is
    # what lets an update REPLACE an old direct-path hook with the bash-prefixed
    # one instead of appending a duplicate.
    | def harness_script_key($cmd):
        ($cmd // "" | sub("^\\s*bash\\s+"; "")) as $c
        | if ($c | test("\\.harness/scripts/[A-Za-z0-9._-]+\\.sh"))
          then ($c | capture("\\.harness/scripts/(?<n>[A-Za-z0-9._-]+\\.sh)").n)
          else null end;
      # Merge one event hook array: prune harness-owned hooks from the user
      # array that we also ship (kept: user custom hooks + harness hooks we no
      # longer ship), then append all of ours. Malformed/non-array user values
      # fall back to [] (mirrors the JS installer). Idempotent.
      def merge_event($event):
        ($user.hooks[$event] // []) as $raw
        | (if ($raw | type) == "array" then $raw else [] end) as $u
        | ($o.hooks[$event] // []) as $oraw
        | (if ($oraw | type) == "array" then $oraw else [] end) as $oarr
        | ([ $oarr[] | (.hooks // [])[]? | harness_script_key(.command) | select(. != null) ] | unique) as $our_keys
        | [ $u[]
            | . as $entry
            | ((.hooks // []) | map(select(
                harness_script_key(.command) as $k
                | ($k == null) or (($k | IN($our_keys[])) | not)
              ))) as $kept
            | if ((.hooks // []) | length) > 0 and ($kept | length) == 0
              then empty
              else (.hooks = $kept) end
          ] as $u_pruned
        | $u_pruned + $oarr;
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
UPDATED=0
PRESERVED=0
BACKED_UP=0
for entry in "${MAPPINGS[@]}"; do
  IFS='|' read -r src dst type <<< "$entry"
  SRC_PATH="$SOURCE/$src"
  DST_PATH="$TARGET/$dst"

  if [ ! -e "$SRC_PATH" ]; then
    echo "   $src → (not in source; skipping)"
    continue
  fi

  # dir-merge: per-file install/preserve under the destination directory
  # using content-hash decisions.
  if [ "$type" = "dir-merge" ]; then
    RESULT=$(merge_dir_recursive "$SRC_PATH" "$DST_PATH" "$dst")
    NEW_CT="${RESULT%%:*}"
    REST="${RESULT#*:}"
    UPD_CT="${REST%%:*}"
    PRES_CT="${REST##*:}"
    if [ "$NEW_CT" -gt 0 ] && [ "$UPD_CT" -gt 0 ] && [ "$PRES_CT" -gt 0 ]; then
      printf "   ⊕ %-40s → %s/ (%d new, %d updated, %d preserved)\n" "$src" "$dst" "$NEW_CT" "$UPD_CT" "$PRES_CT"
    elif [ "$NEW_CT" -gt 0 ] && [ "$UPD_CT" -gt 0 ]; then
      printf "   ⊕ %-40s → %s/ (%d new, %d updated)\n" "$src" "$dst" "$NEW_CT" "$UPD_CT"
    elif [ "$NEW_CT" -gt 0 ] && [ "$PRES_CT" -gt 0 ]; then
      printf "   ⊕ %-40s → %s/ (%d new, %d preserved)\n" "$src" "$dst" "$NEW_CT" "$PRES_CT"
    elif [ "$UPD_CT" -gt 0 ] && [ "$PRES_CT" -gt 0 ]; then
      printf "   ↗ %-40s → %s/ (%d updated, %d preserved)\n" "$src" "$dst" "$UPD_CT" "$PRES_CT"
    elif [ "$NEW_CT" -gt 0 ]; then
      printf "   ✓ %-40s → %s/ (%d new)\n" "$src" "$dst" "$NEW_CT"
    elif [ "$UPD_CT" -gt 0 ]; then
      printf "   ↗ %-40s → %s/ (%d updated)\n" "$src" "$dst" "$UPD_CT"
    else
      printf "   = %-40s → %s/ (%d already current/preserved)\n" "$src" "$dst" "$PRES_CT"
    fi
    COPIED=$((COPIED + NEW_CT))
    UPDATED=$((UPDATED + UPD_CT))
    PRESERVED=$((PRESERVED + PRES_CT))
    continue
  fi

  # JSON merge: settings.json / hooks.json — never plain-overwrite, never skip.
  # Always merge ours into user's (creates target if absent; preserves user content if present).
  if [ "$type" = "json-merge" ]; then
    mkdir -p "$(dirname "$DST_PATH")"
    if [ ! -e "$DST_PATH" ]; then
      cp "$SRC_PATH" "$DST_PATH"
      H=$(sha256_of "$DST_PATH")
      record_hash "$dst" "$H"
      printf "   ✓ %-40s → %s (new)\n" "$src" "$dst"
      COPIED=$((COPIED + 1))
    else
      MERGE_RESULT=$(merge_json_settings "$SRC_PATH" "$DST_PATH") || {
        PRESERVED=$((PRESERVED + 1))
        continue
      }
      # Record post-merge hash so future content-hash checks see "user-modified".
      H=$(sha256_of "$DST_PATH")
      record_hash "$dst" "$H"
      if [ "$MERGE_RESULT" = "BACKED_UP" ]; then
        printf "   ⊕ %-40s → %s (merged; user file backed up to %s.pre-ccc-magi)\n" "$src" "$dst" "$(basename "$dst")"
        BACKED_UP=$((BACKED_UP + 1))
      else
        printf "   ⊕ %-40s → %s (re-merged; idempotent)\n" "$src" "$dst"
      fi
      UPDATED=$((UPDATED + 1))
    fi
    continue
  fi

  # All remaining types (file, dir) → unified content-hash file install.
  if [ "$type" = "dir" ]; then
    # dir type: treat as a recursive copy, but apply per-file hash logic via merge.
    RESULT=$(merge_dir_recursive "$SRC_PATH" "$DST_PATH" "$dst")
    NEW_CT="${RESULT%%:*}"
    REST="${RESULT#*:}"
    UPD_CT="${REST%%:*}"
    PRES_CT="${REST##*:}"
    printf "   ✓ %-40s → %s/ (%d new, %d updated, %d preserved)\n" "$src" "$dst" "$NEW_CT" "$UPD_CT" "$PRES_CT"
    COPIED=$((COPIED + NEW_CT))
    UPDATED=$((UPDATED + UPD_CT))
    PRESERVED=$((PRESERVED + PRES_CT))
    continue
  fi

  # type = file
  RESULT=$(install_file_with_hash "$SRC_PATH" "$dst" "$DST_PATH" "$FORCE_LOAD_BEARING")
  case "$RESULT" in
    NEW)
      printf "   ✓ %-40s → %s (new)\n" "$src" "$dst"
      COPIED=$((COPIED + 1))
      ;;
    UPDATED)
      printf "   ↗ %-40s → %s (updated; unchanged since last install)\n" "$src" "$dst"
      UPDATED=$((UPDATED + 1))
      ;;
    CURRENT)
      printf "   = %-40s → %s (already current)\n" "$src" "$dst"
      PRESERVED=$((PRESERVED + 1))
      ;;
    PRESERVED)
      if is_load_bearing "$dst"; then
        printf "   = %-40s → %s (preserved; local modifications — use --force-load-bearing to reset)\n" "$src" "$dst"
      else
        printf "   = %-40s → %s (preserved; local modifications)\n" "$src" "$dst"
      fi
      PRESERVED=$((PRESERVED + 1))
      ;;
    FORCED)
      printf "   ⚠ %-40s → %s (force-overwritten; original backed up)\n" "$src" "$dst"
      UPDATED=$((UPDATED + 1))
      BACKED_UP=$((BACKED_UP + 1))
      ;;
  esac
done

# chmod +x on shell scripts
SCRIPTS_DIR="$TARGET/.harness/scripts"
if [ -d "$SCRIPTS_DIR" ]; then
  chmod +x "$SCRIPTS_DIR"/*.sh 2>/dev/null || true
  echo "   ✓ chmod +x .harness/scripts/*.sh"
fi

# ─────────────────────────────────────────────────────────────────────
# Project todolist backfill (migration for projects that predate the
# todolist feature). Runs ONLY when the project is already configured
# (install.json present) — i.e. an update of a live project, not a fresh
# pre-bootstrap install. Idempotent: skips if the todolist already has
# functions; seeds them from existing checkpoints + specs otherwise.
# ─────────────────────────────────────────────────────────────────────
if [ "$DRY" -eq 0 ] \
   && [ -f "$TARGET/.harness/state/install.json" ] \
   && [ -f "$SCRIPTS_DIR/todolist-backfill.sh" ]; then
  echo "   → backfilling project todolist from existing history..."
  ( cd "$TARGET" && bash .harness/scripts/todolist-backfill.sh ) || \
    echo "   ⚠ todolist backfill skipped (non-fatal)"
fi

# ─────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────────────────────"
if [ "$BACKED_UP" -gt 0 ]; then
  echo "✅ Installed. ($COPIED new, $UPDATED updated, $PRESERVED preserved, $BACKED_UP file(s) backed up)"
  echo ""
  echo "Note: $BACKED_UP existing file(s) at the target had pre-existing user content."
  echo "They were backed up with .pre-ccc-magi suffix before CCC-MAGI's"
  echo "versions were installed."
else
  echo "✅ Installed. ($COPIED new, $UPDATED updated, $PRESERVED preserved)"
fi
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "Next: open Claude Code in the target directory."
echo ""
echo "  cd \"$TARGET\""
echo "  claude"
echo ""
echo "🤖 What happens when you open Claude Code:"
echo ""
echo "  Phase 1 — Environment check (~30s)"
echo "    MAGI Core will greet you and propose two-phase setup."
echo "    Say yes, and it will detect git/jq/claude/codex automatically."
echo "    Anything missing → conversational install (no terminal output to interpret)."
echo ""
echo "  Phase 2 — Project deployment (~3-15 min)"
echo "    After env check passes, MAGI Core asks Simple (5 questions, ~3 min)"
echo "    or Pro (16 questions, ~15 min) mode. The 5 simple questions can be"
echo "    upgraded to all 16 anytime later by saying \"升级到专业版\" / \"upgrade to pro\"."
echo ""
echo "  All progress saved to .harness/state/ — close terminal anytime, /resume picks up."
echo ""
echo "Read first (optional):"
echo "  CCC_MAGI_README.md             — overview"
echo "  docs-harness/adoption-playbook.md — full walkthrough"
echo ""
