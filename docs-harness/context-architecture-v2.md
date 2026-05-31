# Context Architecture v2 — CCC-MAGI

> **Status**: Active design (rolled out 2026-05). Supersedes the v1 single-tier observations layer.
> **Audience**: Harness contributors + power users wanting to understand or tune the memory layer.
> **Companion files**: `CLAUDE.md § Memory Calling Rules` (operational), `outcome/scripts/memory-*.sh` (mechanism), individual SKILL.md for `/handoff`, `/recall`, `/offload` (UX).

## 1. The problem v2 solves

v1's `.harness/memory/observations.jsonl` is a single flat append-only file. Three failure modes accumulated:

- **Recency bias squeezes out durable wisdom.** Scoring is `+5 feature-match, +1 within 7 days`. After 6 months of project work, old foundational decisions (e.g., "we don't use Redux, ever") lose the recency bonus and stop being recalled — even though they remain load-bearing rules.
- **Eager injection wastes tokens.** SessionStart injects up to ~2K tokens of recalled entries regardless of whether the user's current task needs them. On unrelated work (refactor, doc edit, off-topic Q&A) this is pure overhead.
- **Binary `consumed` flag for snapshots is brittle.** If session N+1 happens to start on a different feature than session N's snapshot, the snapshot is read-and-consumed for no benefit; when the user returns to the original feature later, the snapshot is gone.

v2 reorganizes memory into a 3-tier (Letta-style) structure with explicit calling rules and just-in-time recall.

## 2. The 3 tiers

```
┌─────────────────────────────────────────────────────────────────┐
│  Tier 1: Working memory  (always in context, ~500 tokens)       │
│  Location: .harness/state/scratchpad.md                         │
│  Lifecycle: AI rewrites every turn (Stop hook); read at         │
│             SessionStart                                         │
│  Stores: current objective / last step / next step / blockers   │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│  Tier 2: Recall memory  (manifest in context, ~500-1000 tokens) │
│  Location: .harness/memory/sessions/recall/                     │
│    ├── observations.jsonl   (PreCompaction + /remember writes)  │
│    └── snapshots.jsonl      (/handoff writes)                   │
│  Lifecycle: ≤ 30 days. Manifest (id+focus+date+feature) at      │
│             SessionStart; body loaded on /recall <id>.          │
│  Stores: recent decisions / session snapshots / observations    │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│  Tier 3: Archival memory  (not in context, on-demand only)      │
│  Location: .harness/memory/sessions/archive/<YYYY-MM>.jsonl     │
│  Lifecycle: Entries older than 30 days migrated by              │
│             memory-archive.sh                                    │
│  Stores: same schema as Tier 2, just cold storage               │
│  Access: /recall --deep <query> (grep-based, no vector DB)      │
└─────────────────────────────────────────────────────────────────┘

╔═════════════════════════════════════════════════════════════════╗
║  Shared (committed to git, team-wide)                           ║
║  ─ .harness/memory/conventions.md   ─ long-form rules           ║
║  ─ .harness/memory/decisions.jsonl  ─ /remember writes here     ║
╚═════════════════════════════════════════════════════════════════╝
```

### Why 3 tiers (not 2, not 4)?

- **Working** keeps multi-step task focus (anti-distraction) — needs to be always available, so it pays the constant 500-token cost.
- **Recall** is the day-to-day memory — needs to be cheap to scan (manifest) but expensive to load (body). 30-day window matches "human working memory" — what you can plausibly remember about a project.
- **Archival** is the institutional memory — pay only when actually queried. Without this tier, recall manifest would grow unbounded; with this tier, manifest stays at 5-15 entries no matter how long the project runs.

A 4th tier (e.g., vector-indexed semantic search) was considered and rejected. Adding a vector DB introduces dependencies (embeddings model, runtime), makes the memory non-grepable, and the empirical gain over grep-based archival recall is small for projects below ~10K total entries. We accept weaker retrieval to preserve the "files-on-disk, no dependencies" property.

## 3. AI calling rules (HARD)

Without explicit calling rules, AI will fetch recall bodies "for completeness" and waste tokens. The rules below are **hard constraints written into CLAUDE.md**, validated at runtime via skill prompts.

### 3.1 Tier 1 (Working / scratchpad)
- **Always read at SessionStart** (no choice).
- **Always rewrite at end of each turn** via Stop hook.
- AI must not "skip" the rewrite — empty scratchpad is acceptable, half-stale is not.

### 3.2 Tier 2 (Recall)

**Manifest is always injected at SessionStart** (zero choice for AI).

**Body fetch via `/recall <id>` triggers ONLY when**:
1. User explicitly references prior context: "之前 / 上次 / 上回 / 我们之前定的 / last time / before / previously"
2. Current task's `feature` tag **exactly matches** a manifest entry's `feature`
3. AI is about to make a decision in an area where a manifest summary indicates a relevant prior decision (overlap, not mere relatedness)

**Hard caps**: ≤ 3 recall body fetches per session.

### 3.3 Tier 3 (Archive)

**No injection at SessionStart** (zero overhead).

**`/recall --deep <query>` triggers ONLY when**:
1. User explicitly asks: "查一下半年前 / search history / older / archive"
2. Current task's `feature` is not present in the recall manifest
3. Code being edited has `git blame` older than 30 days (suggests pre-recall-window logic)

**Hard caps**: ≤ 1 archive search per session.

### 3.4 Prohibitions (also HARD)

- ❌ "For completeness" fetches without one of the triggers above
- ❌ Fetching multiple recall bodies "just in case"
- ❌ Searching archive when user's question is clearly about current work

## 4. Trigger surfaces

| Trigger | Threshold | Action | UX |
|---|---|---|---|
| Budget pressure | 50% | Soft advisory (existing) | `additionalContext` text only |
| Budget pressure | 75% | Firm advisory + offer `/offload <task>` | 4-option menu at end-of-turn |
| Budget pressure | 95% | 3-option menu: `/compact` / `/handoff` / continue | Menu deferred to end-of-turn via Stop hook |
| End-of-turn | Every turn | Scratchpad rewrite | Stop hook fires `scratchpad-update.sh` |
| Session start | Every session | Inject scratchpad + recall manifest + checkpoint | SessionStart hooks fire in order |
| PreCompaction | Auto-compact triggered | Harvest checkpoint+decision-log into snapshot | Deterministic (no LLM call) |

## 5. File layout

```
.harness/
├── memory/
│   ├── conventions.md                 [shared, committed]
│   ├── decisions.jsonl                [shared, committed]
│   └── sessions/                      [personal, gitignored]
│       ├── recall/
│       │   ├── observations.jsonl
│       │   └── snapshots.jsonl
│       └── archive/
│           ├── 2026-04.jsonl
│           └── 2026-05.jsonl
├── state/
│   ├── scratchpad.md                  [personal, gitignored]
│   ├── _handoff-offered/<sid>.flag    [personal, gitignored]
│   └── _handoff-dismissed/<sid>.flag  [personal, gitignored]
└── scripts/
    ├── memory-recall.sh               [modified: manifest mode]
    ├── memory-snapshot.sh             [modified: deterministic harvest]
    ├── memory-archive.sh              [NEW]
    ├── scratchpad-update.sh           [NEW]
    ├── scratchpad-recall.sh           [NEW]
    └── budget-monitor.sh              [modified: 95% menu + token accuracy]

outcome/skills/
├── recall/                            [NEW]
├── handoff/                           [NEW]
└── offload/                           [NEW]
```

## 6. Schemas

### 6.1 Recall manifest entry (in-context, ~80 tokens each)

```
[<id>] feature=<f> kind=<k> date=<YYYY-MM-DD> focus="<≤80 chars>"
```

Example:
```
[SS-2026053001] feature=auth kind=session-snapshot date=2026-05-30 focus="OTP race condition in middleware"
[OBS-2026052901] feature=ui kind=decision date=2026-05-29 focus="Use Tailwind not styled-components"
```

### 6.2 Snapshot entry (Tier 2 body, ~2-3KB)

```json
{
  "id": "SS-2026053001",
  "ts": "2026-05-30T18:30:00Z",
  "kind": "session-snapshot",
  "feature": "auth",
  "focus": "Resolve OTP race condition in middleware",
  "decisions": [
    {"id": "d-001", "rule": "WHEN form submits with code, THE SYSTEM SHALL validate before navigation"}
  ],
  "open_problems": [
    {"id": "p-001", "what": "Concurrent submissions cause double-charge", "blocked_by": "need DB advisory lock"}
  ],
  "next_intent": "Implement advisory lock in src/auth/middleware.ts",
  "files_touched": [
    {"path": "src/auth/middleware.ts", "why": "added validation hook"}
  ],
  "prev_session_id": "SS-2026052801",
  "source": "handoff"
}
```

### 6.3 Observation entry (Tier 2 body, unchanged from v1)

```json
{
  "id": "OBS-2026052901",
  "ts": "...", "kind": "decision|failure|observation",
  "summary": "...", "details": "...",
  "feature": "...", "files": [...], "tags": [...],
  "source": "manual|session"
}
```

Note: `id` is new in v2; old entries get IDs back-filled by `memory-archive.sh` on first run.

### 6.4 Scratchpad (Tier 1)

```markdown
# Working Scratchpad
> Rewritten by AI at end of every turn. Read at SessionStart.

## Current objective
<one sentence>

## Last step taken
<what just finished>

## Next step
<what I plan to do next, before user input>

## Blockers / open questions
- <bullet>
- <bullet>

## Decision-relevant context (optional, ≤3 bullets)
- <bullet>
```

Hard cap: 500 tokens total. If AI's rewrite exceeds this, Stop hook truncates oldest sections.

## 7. Tier upgrade rationale (against 2026 SOTA)

| Component | v1 tier | v2 tier | Why |
|---|---|---|---|
| `memory-recall.sh` | B | A | Manifest-only injection + JIT recall (Anthropic Memory Tool pattern) |
| `memory-snapshot.sh` | C+ | A | Deterministic harvest (no LLM call competing with Sonnet 4.5+ native compaction) |
| Memory layer overall | C | A | Letta 3-tier + decay + agent-driven retrieval |
| Working scratchpad | (none) | A | Manus recitation pattern, anti-drift |
| Tool result clearing | (none) | A | Anthropic clear_tool_uses_20250919, single config line |
| Subagent offload UX | (none) | A | Budget-pressure release valve, Anthropic 90.2% lift pattern |

## 8. Rollout (Phase plan)

- **Phase 0**: Enable `clear_tool_uses_20250919`. ← *single settings line, lowest cost, highest immediate ROI*
- **Phase 1**: This document.
- **Phase 2**: Implement 3-tier file layout + `memory-recall.sh` manifest mode + `/recall` skill + archival cron + AI calling rules in CLAUDE.md.
- **Phase 3**: `/handoff` skill + 95% menu in `budget-monitor.sh` + accurate token accounting (read transcript `usage` instead of byte/4).
- **Phase 4**: `scratchpad.md` + `scratchpad-update.sh` (Stop hook) + `scratchpad-recall.sh` (SessionStart hook).
- **Phase 5**: `/offload` skill + 75% menu option in `budget-monitor.sh`.

## 9. Rollback

Each phase is independently rollback-able:

- **Phase 0**: Remove `"betas"` and `"context_management"` from settings.json.
- **Phase 2**: Move files from `sessions/recall/` back up to `.harness/memory/observations.jsonl`. Restore old `memory-recall.sh`.
- **Phase 3-5**: Remove the corresponding skill + revert the changed hook scripts.

Snapshots / observations / scratchpad are plain text files at all times — none of the changes lock data into a proprietary format. Worst case, rollback recovers by `cat`ing files together.

## 10. Test plan

See `outcome-test-bed/` for the test fixture and `outcome-test-bed/test-runner.sh` for the 8-case test suite (T1-T8) that validates every phase end-to-end.
