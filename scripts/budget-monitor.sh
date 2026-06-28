#!/usr/bin/env bash
# budget-monitor.sh — intentionally a NO-OP (context-monitor redesign).
#
# WHY THIS IS A NO-OP NOW:
#   This hook used to estimate context usage from the transcript and fire
#   50/75/90/95% advisories. It divided the (accurate) Anthropic token count by
#   a GUESSED context-window size — defaulting to 200K when the real window is
#   often 1M — so the percentage came out up to 5x too high and produced false
#   "context critical" alarms. A UserPromptSubmit hook only receives
#   session_id + transcript_path; it CANNOT see the model's real context-window
#   size, so any percentage computed here is necessarily a guess.
#
# NEW DESIGN — context management is owned by the layers that have the real
# number, instead of a guess in this hook:
#   - Claude Code natively shows context % and auto-compacts when the window
#     fills (the official signal).
#   - CCC reads the real context_window.used_percentage from Claude Code's
#     statusLine and surfaces a "compress vs handoff" prompt at a high
#     threshold — accurate, no guessing.
#   - The PreCompaction hook (memory-snapshot.sh) snapshots scratchpad +
#     checkpoint so nothing is lost whether the session compacts or hands off.
#
# WHY KEEP THE FILE (instead of deleting + unwiring):
#   Leaving the hook wired but making the SCRIPT a no-op lets the "off" state
#   propagate to existing installs through the normal `update` flow — the
#   settings JSON-merge replaces the old hook command and dir-merge refreshes
#   this body to the no-op. Removing the hook from settings.json would NOT
#   propagate, because the merge preserves harness hooks we no longer ship.
#
# To resurrect proactive in-hook nags, see this file's git history for the prior
# threshold implementation.

# Drain stdin so the prompt is never blocked, then exit silently (no output =
# no additionalContext injected).
cat >/dev/null 2>&1 || true
exit 0
