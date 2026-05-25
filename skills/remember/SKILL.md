---
name: remember
description: Append an observation, decision, or failure to .harness/memory/observations.jsonl for future Claude Code sessions to recall. Reads $ARGUMENTS as the summary text; asks the user to clarify kind / feature / details if missing. Trigger when the user invokes /remember, says "remember this", "note for later", "save this decision", "记一下", "记到 memory", or similar intent.
allowed-tools: Bash(git rev-parse:*), Bash(git branch:*), Bash(git status:*), Bash(echo:*), Bash(mkdir:*), Bash(date:*), Bash(jq:*), Bash(cat:*), Read, Edit
argument-hint: <summary text>
---

# /remember

Manually capture a decision, failure, or observation into the project's memory layer so future Claude Code sessions can recall it.

> *Companion to the automatic capture path (`PreCompaction` hook). This skill is the user-curated entry point — what the human explicitly wants persisted, not what an LLM guesses is important.*

## Language Awareness

This skill's instructions are in English. When you talk to the user (proposing values, confirming the entry), use the user's OS locale language. See `CLAUDE.md § Language Awareness`. The JSON written to `observations.jsonl` defaults to English unless the user explicitly enters non-English content; do not translate user-entered strings.

## What this skill produces

A single new line appended to `.harness/memory/observations.jsonl`:

```json
{"ts":"2026-05-22T14:00:00Z","kind":"decision","summary":"<one-line, ≤200 chars>","details":"<optional longer text>","feature":"<name or null>","files":["..."],"tags":["..."],"source":"manual"}
```

If `.harness/memory/` or `observations.jsonl` doesn't exist, this skill creates them.

---

## Step 0 — Parse `$ARGUMENTS`

Treat `$ARGUMENTS` as the proposed `summary` text. If `$ARGUMENTS` is empty, ask the user:

```
What do you want to remember?
(One sentence, ≤200 chars. Examples:
 - "Use Supabase RLS, not middleware — middleware p99 was 800ms"
 - "Google Vision API too expensive at our scale; use local model"
 - "FlashList is 5x faster than FlatList here")
```

**Wait for user response before continuing.**

If the user-provided summary exceeds 200 chars, propose splitting: keep the first ≤200 chars in `summary`, move the rest into `details`. Ask the user to confirm or rewrite.

---

## Step 1 — Auto-extract `feature` from current git branch

Use the same logic as `.harness/scripts/memory-recall.sh`:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
```

Then derive `FEATURE`:

- If `BRANCH` matches `feat/<name>-*` or `fix/<name>-*` → `<name>` is everything between the prefix and the first dash (or the whole rest if no dash).
- Else if `BRANCH` matches `<name>/...` → `<name>` is the segment before the first slash.
- Else `FEATURE=""` (will be written as `null` in JSON).

Example: branch `feat/auth-rls-migration` → `FEATURE=auth`.
Example: branch `main` → `FEATURE=""`.

---

## Step 2 — Propose `kind` based on summary phrasing

Heuristic (case-insensitive):

| Phrase pattern in summary | Proposed kind |
|---------------------------|---------------|
| starts with "use X", "we use", "switch to", "chose", "decided" | `decision` |
| contains "didn't work", "failed", "broke", "too expensive", "too slow", "regression" | `failure` |
| anything else (general note, perf comparison, gotcha) | `observation` |

Don't over-engineer this — if it's ambiguous, default to `observation`.

---

## Step 3 — Auto-propose `files`

Run `git status --short` in the project root. Take the first 3 modified/staged paths as the proposed `files` array. If `git status` is empty, propose `[]`.

---

## Step 4 — Propose `tags`

Pick 1-3 short tags from the summary's key nouns. Examples:

- "Use Supabase RLS, not middleware" → `["auth", "rls", "supabase"]`
- "FlashList is 5x faster than FlatList here" → `["perf", "list-rendering"]`

If you can't infer meaningful tags, propose `[]`.

---

## Step 5 — Propose `details` (optional)

If the summary is self-explanatory (e.g., "FlashList is 5x faster than FlatList here"), propose `details=""`. Otherwise propose a short rationale line that adds context the summary couldn't fit (e.g., the "why" or the measurement).

---

## Step 6 — Confirm the proposed entry with the user

Display the full proposed JSON entry in the user's locale, formatted for human reading:

```
About to append this entry to .harness/memory/observations.jsonl:

  ts       : <ISO 8601 UTC of now>
  kind     : decision
  summary  : Use Supabase RLS, not middleware — middleware p99 was 800ms
  details  : (empty)
  feature  : auth
  files    : ["src/auth.ts", "supabase/migrations/0042_rls.sql"]
  tags     : ["auth", "rls", "supabase"]
  source   : manual

Looks right?
  [1] Yes, append it
  [2] Edit one or more fields
  [3] Cancel
```

**Wait for user response before continuing.**

If `[2]`, ask which field(s) to edit, accept new values, re-show the confirmation. Loop until `[1]` or `[3]`.

If `[3]`, abort silently — write nothing.

---

## Step 7 — Append to observations.jsonl

On `[1]`:

1. Ensure the directory exists:

   ```bash
   mkdir -p "$CLAUDE_PROJECT_DIR/.harness/memory"
   ```

2. Compute the ISO 8601 UTC timestamp:

   ```bash
   TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
   ```

3. Build the JSON line. Prefer `jq -c -n` to avoid quoting bugs:

   ```bash
   ENTRY=$(jq -c -n \
     --arg ts "$TS" \
     --arg kind "$KIND" \
     --arg summary "$SUMMARY" \
     --arg details "$DETAILS" \
     --arg feature "$FEATURE" \
     --argjson files "$FILES_JSON" \
     --argjson tags "$TAGS_JSON" \
     '{ts:$ts, kind:$kind, summary:$summary, details:$details, feature:(if $feature=="" then null else $feature end), files:$files, tags:$tags, source:"manual"}')
   ```

4. Append:

   ```bash
   echo "$ENTRY" >> "$CLAUDE_PROJECT_DIR/.harness/memory/observations.jsonl"
   ```

5. Confirm to the user (in their locale):

   ```
   ✓ Remembered at <TS>.
     File: .harness/memory/observations.jsonl (now <N> entries)
   ```

---

## Trust contract

- This skill writes to **exactly one file**: `.harness/memory/observations.jsonl`.
- It never reads, modifies, or deletes any other project file.
- The entry is always `source: "manual"` (auto-capture entries use `source: "session"`).
- If the user cancels at Step 6, nothing is written.
- If `jq` is missing, surface the error and abort — do not fall back to hand-rolled JSON (quoting bugs would corrupt the file).

---

## Anti-patterns the skill blocks

- **Writing without user confirmation** → always show the JSON and wait for `[1]`.
- **Translating user-entered summary/details into English** → write what the user typed, verbatim.
- **Inferring `feature` from the summary text** → only the git branch is authoritative; if branch doesn't yield a feature, ask the user or use `null`.
- **Setting `source: "session"`** → this skill is the manual path; auto-capture is a separate mechanism.

---

## Completion criteria

`/remember` is complete when:

- Either a single new line has been appended to `observations.jsonl` and the user has seen the confirmation message, **or**
- The user explicitly cancelled at Step 6 (nothing written).
