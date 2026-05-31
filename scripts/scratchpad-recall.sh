#!/usr/bin/env bash
# scratchpad-recall.sh — SessionStart hook for v2 working memory (Tier 1).
#
# Reads .harness/state/scratchpad.md and emits it as additionalContext so the
# AI starts the session aware of:
#   - Current objective (carried from prior session, if any)
#   - Last step taken
#   - Next step planned
#   - Open blockers
#
# If the file doesn't exist (fresh project), copies from template. If empty,
# emits a brief "no carryover" notice.

set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRATCHPAD="$PROJECT_DIR/.harness/state/scratchpad.md"
TEMPLATE="$PROJECT_DIR/.harness/state/scratchpad.md.template"

# Drain stdin
cat >/dev/null 2>&1 || true

# Bootstrap from template if missing
if [ ! -f "$SCRATCHPAD" ] && [ -f "$TEMPLATE" ]; then
  cp "$TEMPLATE" "$SCRATCHPAD" 2>/dev/null || true
fi

# If still missing or empty, emit a brief notice
if [ ! -f "$SCRATCHPAD" ] || [ ! -s "$SCRATCHPAD" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: "📋 Working scratchpad (.harness/state/scratchpad.md) is empty — fresh start. Per CLAUDE.md § Working Scratchpad, you will rewrite it at end of your first turn."
      }
    }'
  fi
  exit 0
fi

# Cap: read at most 500 lines (defensive against runaway files)
CONTENT=$(head -500 "$SCRATCHPAD")

# Char cap: ~2000 chars (~500 tokens). If oversized, truncate and warn.
if [ "${#CONTENT}" -gt 2000 ]; then
  CONTENT=$(printf '%s' "$CONTENT" | head -c 2000)
  CONTENT="$CONTENT

⚠️ (scratchpad exceeded 500-token cap; truncated. Rewrite leaner this turn.)"
fi

# Build additionalContext: prepend header explaining what this is and how AI should treat it
HEADER='## Working Scratchpad (Tier 1 memory — read at SessionStart)

The file below is the AI working scratchpad: the agent-managed core memory for this project. It survives compaction and `/clear` because it lives on disk. Per `CLAUDE.md § Working Scratchpad`:

- **Trust it**: it reflects state at end of last AI turn
- **Update it**: at the end of THIS turn, the Stop hook will instruct you to rewrite it with the current objective, last step, next step, and blockers
- **Keep it lean**: ≤500 tokens (~2000 chars). If you find yourself needing more, it belongs in `/remember` or `/handoff`, not the scratchpad

Current contents:

```markdown
'

FOOTER='
```

---'

FULL="${HEADER}${CONTENT}${FOOTER}"

if command -v jq >/dev/null 2>&1; then
  printf '%s' "$FULL" | jq -Rs '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: .
    }
  }'
fi

exit 0
