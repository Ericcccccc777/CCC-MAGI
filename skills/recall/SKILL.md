---
name: recall
description: |
  Fetch a recall/archive memory entry by id, feature, tag, or deep query. Companion to the manifest-mode memory-recall hook — the manifest only injects index lines; this skill pulls full bodies on demand.

  Trigger when:
  - User explicitly references prior context: "上次 / 之前 / 上回 / before / previously / we decided / 之前我们定的"
  - Current task's feature exactly matches a manifest entry's feature
  - User says "查一下半年前 / search history / older / archive" → use --deep
  - User invokes /recall <id>, /recall <feature|tag>, /recall --deep <query>

  HARD CAPS per session (CLAUDE.md § Memory Calling Rules):
  - ≤ 3 body fetches from Tier 2 (recall)
  - ≤ 1 deep search from Tier 3 (archive)
  - Do NOT fetch "for completeness". One trigger = one fetch.
allowed-tools: Bash(jq:*), Bash(grep:*), Bash(ls:*), Bash(cat:*), Bash(wc:*), Read
argument-hint: <id> | <feature|tag> | --deep <query>
---

# /recall

Just-in-time memory retrieval. The SessionStart hook only shows you the **manifest** (one index line per entry). When you need a body, you call this skill explicitly.

## When to call (HARD rules)

Per `CLAUDE.md § Memory Calling Rules`, you may call `/recall` only when **one** of these is true:

1. **User explicit reference**: words like "之前 / 上次 / 上回 / before / previously / we decided / 之前定的"
2. **Feature exact match**: current task's feature tag matches a manifest entry's feature
3. **Focus overlap**: a manifest entry's `focus="..."` indicates a prior decision relevant to the action you're about to take

You may **not** call `/recall` because:
- "It might be useful"
- "For completeness"
- "Multiple manifest entries look interesting"

Hard caps: ≤ 3 recall-body fetches and ≤ 1 archive deep search per session.

## Usage

### Form 1: by id (most common)

```
/recall SS-2026053001
/recall OBS-2026052901
```

Reads `.harness/memory/sessions/recall/snapshots.jsonl` or `observations.jsonl`, locates the entry whose `id` matches, prints the full body (pretty-printed JSON).

```bash
# Internal:
jq -c "select(.id == \"$ID\")" .harness/memory/sessions/recall/*.jsonl
```

### Form 2: by feature or tag

```
/recall auth
/recall rls
```

Lists all manifest lines in recall whose `feature == auth` OR `tags` includes `auth` (or `rls`). Output format is the same one-line manifest. User picks one, then calls `/recall <id>`.

### Form 3: deep search (archive tier)

```
/recall --deep auth
/recall --deep "rate limit"
```

Greps across `.harness/memory/sessions/archive/*.jsonl` for matching entries. Output: manifest lines, oldest visible. **Hard cap: 1 per session.**

```bash
# Internal:
grep -l "$QUERY" .harness/memory/sessions/archive/*.jsonl | xargs -I{} jq -r '
  "[" + .id + "] feature=" + (.feature // "general") + " kind=" + .kind + " date=" + (.ts[0:10]) + " focus=\"" + (.focus // .summary // "")[0:80] + "\""
' {}
```

## Output format

For `/recall <id>` (body fetch):
```
─── Recall: SS-2026053001 ──────────────────────────────

ts:         2026-05-30T18:30:00Z
kind:       session-snapshot
feature:    auth
focus:      Resolve OTP race condition in middleware
next_intent:Implement advisory lock in src/auth/middleware.ts

decisions:
  - [d-001] WHEN form submits with code, THE SYSTEM SHALL validate before navigation

open_problems:
  - [p-001] Concurrent submissions cause double-charge (blocked_by: need DB advisory lock)

files_touched:
  - src/auth/middleware.ts (added validation hook)

prev_session_id: SS-2026052801
source: handoff

─── 1/3 recall fetches used this session ───────────────
```

For `/recall <feature|tag>` (search recall):
```
Matching entries in recall tier:

[SS-2026053001] feature=auth kind=session-snapshot date=2026-05-30 focus="OTP race condition"
[DEC-2026052801] feature=auth kind=decision date=2026-05-28 focus="Use Supabase RLS not middleware"
[OBS-2026052501] feature=auth kind=observation date=2026-05-25 focus="JWT expiry causes silent logout"

To read the body: /recall <id>
```

For `/recall --deep <query>` (archive):
```
Matching entries in archive tier:

[2026-03] OBS-2026031501  feature=auth focus="Old token format deprecated"
[2026-02] DEC-2026021001  feature=auth focus="Switch from sessions to JWT"

To read the body: /recall <id>  (note: archived; fetch returns from archive)

─── Archive deep-search used this session (1/1) ──────
```

## Counter tracking

This skill is best-effort about cap enforcement. Maintain `.harness/state/_recall-count-<session-id>` (a 2-line file: `body_fetches:N` and `deep_searches:M`). Increment on each call. If exceeded, refuse:

```
⚠️ Recall cap reached this session (3/3 body fetches).
   Per CLAUDE.md § Memory Calling Rules, no more recall fetches this session.
   If this is genuinely critical, ask the user to confirm an override.
```

## Path resolution

Always use `${CLAUDE_PROJECT_DIR:-$(pwd)}` for paths. Files live at:
- `.harness/memory/sessions/recall/observations.jsonl`
- `.harness/memory/sessions/recall/snapshots.jsonl`
- `.harness/memory/sessions/archive/<YYYY-MM>.jsonl`

## Trust contract

- Read-only. Never writes to memory files.
- Never re-summarizes or translates body content — prints `decisions`, `open_problems`, `files_touched`, `next_intent`, `focus` **verbatim** as written in the jsonl entry. The recall body is a forensic record; translating it later breaks the "AI quote vs original" audit trail (same id, different language = trust broken).
- Only the structural wrapper (header line "─── Recall: <id> ───", field labels like "decisions:", footer like "X/3 fetches used") translates to the user's OS locale.
- If the body was originally written in a non-English language (e.g., CEO's locale at handoff time), present it in that original language — do not normalize to user's current locale.
- Never silently fetches when caps are exceeded.

## Completion criteria

- Body fetched and printed in the format above, OR
- No matching entry found → tell the user, suggest `/recall --deep` if Tier 2 came up empty, OR
- Cap reached → refuse with explanation.
