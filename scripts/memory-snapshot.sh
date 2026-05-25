#!/usr/bin/env bash
# memory-snapshot.sh — PreCompaction hook for CCC-Harness memory layer.
#
# Strategy: don't try to auto-summarize the session ourselves (that requires an
# LLM call). Instead, inject an instruction telling Claude (whose context is
# about to be compacted) to summarize the session's key decisions into
# .harness/memory/observations.jsonl BEFORE the compaction proceeds.
#
# CONTRACT (Claude Code hook spec):
#   stdin:  JSON containing session info (drained — not parsed)
#   stdout: a JSON envelope per hookSpecificOutput schema
#   exit 0: always
#
# bash 3.2 compatible.

set -eu

# Ensure brew-installed tools (jq, etc.) are on PATH even in non-interactive
# shells where ~/.zprofile isn't loaded. macOS Apple Silicon path comes first.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ─────────────────────────────────────────────────────────────────────
# Resolve project root + ensure memory directory exists
# ─────────────────────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
MEM_DIR="$PROJECT_DIR/.harness/memory"
OBS_FILE="$MEM_DIR/observations.jsonl"

mkdir -p "$MEM_DIR" 2>/dev/null || true
if [ ! -f "$OBS_FILE" ]; then
  : > "$OBS_FILE" 2>/dev/null || true
fi

# Drain stdin
cat >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────────────
# Emit the hookSpecificOutput JSON envelope.
# ─────────────────────────────────────────────────────────────────────
cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreCompaction",
    "additionalContext": "⚠️ Context is about to be compacted. Before compaction proceeds, summarize this session's key decisions and observations into .harness/memory/observations.jsonl so they survive the compression.\n\nPick AT MOST 3 of the most important items from this session. For each, append a JSON line to .harness/memory/observations.jsonl with this schema:\n\n{\"ts\": \"<ISO 8601 UTC>\", \"kind\": \"decision|failure|observation\", \"summary\": \"<≤200 chars>\", \"details\": \"<optional longer text>\", \"feature\": \"<name or null>\", \"files\": [...], \"tags\": [...], \"source\": \"session\"}\n\nUse the Bash tool to append (e.g., `echo '{\"ts\":...}' >> .harness/memory/observations.jsonl`). Skip if nothing significant happened this session."
  }
}
JSON

exit 0
