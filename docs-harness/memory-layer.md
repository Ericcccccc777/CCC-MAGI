# Memory Layer (`.harness/memory/`)

Cross-session persistence for CCC-MAGI. File-based, hooks-driven, zero external dependencies, zero network calls.

## What it does

Think of it as the project's **sticky-note wall**: a small notebook where Claude writes down decisions ("we use RLS, not middleware"), failures ("Google Vision was too expensive"), and observations ("FlashList beats FlatList here"). When you open a new Claude Code session on the same project, the harness reads the relevant notes and pins them to the conversation's context, so Claude starts informed instead of blank.

Without this layer, each new session is amnesia: Claude re-derives the same decisions, re-tries the same failed approaches, asks the same questions. With it, multi-session work on a feature accumulates rather than restarts.

## How it works

### Files

```
.harness/memory/
├── observations.jsonl     # append-only JSONL; one entry per line
└── conventions.md         # markdown long-form for project conventions
```

### Entry schema (`observations.jsonl`)

One JSON object per line:

```json
{
  "ts": "2026-05-24T14:00:00Z",
  "kind": "decision",
  "summary": "Use Supabase RLS instead of middleware",
  "details": "middleware p99 = 800ms; RLS keeps the check at the DB layer",
  "feature": "auth",
  "files": ["src/auth.ts", "supabase/migrations/0042_rls.sql"],
  "tags": ["auth", "rls", "supabase"],
  "source": "manual"
}
```

- **`kind`** — `decision` (a choice made), `failure` (an approach that didn't work), or `observation` (a general note).
- **`feature`** — name of the feature the entry relates to, or `null` for cross-cutting notes.
- **`source`** — `manual` (via `/remember`) or `session` (auto-captured at compaction time).

### Hooks

| Hook | Script | Purpose | Frequency |
|------|--------|---------|-----------|
| `SessionStart` | `.harness/scripts/memory-recall.sh` | Read `observations.jsonl`, score entries by relevance to the current git branch's feature, inject top entries into `additionalContext`. | Every session start |
| `PreCompaction` | `.harness/scripts/memory-snapshot.sh` | Inject an instruction telling Claude to summarize the session's key decisions to `observations.jsonl` before compaction proceeds. | Only when context approaches limit |

We deliberately do **not** use `PostToolUse` (too noisy — fires on every tool call) or `Stop`/`SessionEnd` (too frequent / unreliable across CLI versions).

### Relevance scoring (memory-recall.sh)

For each entry in `observations.jsonl`:

- **+5** if the entry's `feature` matches the feature derived from the current git branch (`feat/<name>-*` → `<name>`).
- **+1** if the entry's timestamp is within the last 7 days.

Sort by score DESC, then by timestamp DESC. Take the top 10 entries, OR stop when accumulated text exceeds ~8000 chars. If 0 entries pass the score filter, fall back to the top 3 most-recent regardless. If truly empty, emit nothing.

## The `/remember` skill

User-invokable manual entry. Captures decisions/failures/observations curated by the human, not the LLM.

```
/remember Use Supabase RLS, not middleware — middleware p99 was 800ms
```

The skill:

1. Parses `$ARGUMENTS` as the summary.
2. Auto-extracts `feature` from the current git branch.
3. Proposes `kind` based on phrasing (e.g., "use X" → `decision`; "didn't work" → `failure`).
4. Proposes `files` from `git status --short`.
5. Proposes `tags` from the summary's key nouns.
6. Shows the full entry for confirmation.
7. On approval, appends the JSON line to `.harness/memory/observations.jsonl`.

The entry's `source` is always `"manual"` — distinguishes user-curated notes from auto-captured ones.

## Auto-capture via `PreCompaction`

Claude Code fires the `PreCompaction` hook when the conversation's context window is about to be compacted. We use this as a natural "save point": the hook injects an instruction telling Claude to pick the 3 most important items from the session and append them to `observations.jsonl` before the compaction discards them.

The hook itself does no summarization — that requires an LLM, which we already have (Claude is right there). The hook is just the prompt orchestrator. Claude does the actual `echo '<json>' >> observations.jsonl` calls.

The auto-captured entries are tagged `"source": "session"` to distinguish them from `/remember` entries.

## Token economics

Memory recall adds **~1-3K tokens** to session startup (the `additionalContext` block).

- **Empty memory file** → zero tokens; the hook emits nothing.
- **Small memory file** (1-5 entries) → a few hundred tokens.
- **Active project** (10+ entries spanning multiple features) → up to ~2-3K tokens for the top-10 filtered recall.

Net savings only materialize on **multi-session work on the same feature**. A one-shot project with no prior sessions sees only cost, not benefit. That's an honest tradeoff: the layer is designed for the case where you're going to open Claude Code on the same project 10+ times, not for one-off chats.

## Privacy

By default, `.harness/memory/` is **NOT** in `.gitignore`. Reasoning:

- For teams, the memory wall is a shared artifact — everyone benefits from prior decisions/failures.
- The contents are summaries (not raw transcripts), so sensitive prompt content doesn't leak.
- The schema has no secrets fields — entries are short, prose-level descriptions.

Solo developers who prefer local-only memory can uncomment the `.harness/memory/` line in the harness's shipped `.gitignore`.

If you want per-file granularity (commit `conventions.md` but ignore `observations.jsonl`, or vice versa), edit `.gitignore` accordingly.

## What it is NOT

Explicit non-features so you can calibrate expectations:

- **Not a cloud service.** No backend, no API, no account. Just files on disk.
- **Not a vector database.** Scoring is feature + recency. No embeddings, no semantic search.
- **Not auto-learning.** The memory only grows when (a) the user invokes `/remember`, or (b) Claude runs the `PreCompaction`-prompted append. There is no background process scanning the conversation.
- **Not a transcript log.** Entries are summaries, not raw messages. A single decision is one line; a 2-hour design discussion that produced 1 decision = 1 line.
- **Not a replacement for `constitution.md` / `CLAUDE.md`.** Those are stable rules and project identity. The memory layer is volatile context — what's been tried, what's been chosen, what's been ruled out.

## Comparison to mem0 / claude-mem

| Property | mem0 | claude-mem | CCC-MAGI memory |
|----------|------|------------|---------------------|
| Storage | Cloud (managed) or self-hosted vector DB | Local SQLite + embeddings | Plain files (`.jsonl` + `.md`) |
| Retrieval | Vector similarity | Hybrid (keyword + vector) | Feature + recency scoring |
| Auto-capture | Background heuristics | Per-message inference | PreCompaction-prompted (LLM does the summarization) |
| Network | Yes (managed) / Yes (self-host) | No | No |
| Dependencies | Python + cloud / DB | Node.js + sqlite + embedding model | `jq` + `bash` |
| Setup cost | Account / DB provisioning | npm install + model download | Zero (hooks already shipped) |
| Schema control | Library-defined | Library-defined | User-readable JSONL — grep-able, hand-editable |
| Lock-in | Yes | Partial | None (just text files) |

See `harness-2026-deep-comparison.md` for the longer-form comparison of CCC-MAGI vs. mem0 / claude-mem / Cursor Rules / etc.

The design tradeoff: we accept weaker retrieval (no semantic search) to keep the layer dependency-free, security-trivial, and version-controllable.
