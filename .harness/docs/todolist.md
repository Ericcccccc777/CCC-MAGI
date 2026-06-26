# Project Todolist — schema & mechanism

> The todolist is CCC-MAGI's durable answer to **"where is this project at — what
> have we built, what are we building, what do we want to build next?"** It is
> **function-grouped**, not a flat checklist: a project is split into FUNCTIONS
> (capability areas / features), and each function holds ITEMS that are
> `done` / `doing` / `todo`.

## Why function-grouped (not a flat list)

A real project has many functions in flight at once — auth half-done, search
being built, billing only sketched. A flat list flattens that structure away.
Grouping by function preserves the shape the CEO actually thinks in: *"how far
along is each part of my product?"* The CCC 灵动岛 dashboard renders each
function as a column/card with its own done/doing/todo board.

## File

`.harness/state/todolist.json` — **committed to git** (team-shared project state,
like `.harness/state/install.json`), because the todolist is the project's
durable roadmap/ledger that the whole team — and the CCC 灵动岛 dashboard — should
see, not per-developer resume state. Created on demand by
`scripts/todolist-write.sh --init`, or backfilled by the updater for projects
that predate the feature.

> Solo devs who'd rather keep it local can gitignore `.harness/state/todolist.json`;
> the dashboard reads it off disk either way, so ignoring it only affects team sharing.

## Schema (v1)

```json
{
  "schema_version": 1,
  "project": "<project name, from install.json>",
  "created_at": "<ISO-8601>",
  "updated_at": "<ISO-8601>",
  "functions": [
    {
      "id": "auth",                      // kebab-case slug; usually the feature slug
      "title": "用户登录",                // human display name
      "description": "邮箱 + OAuth 登录",  // optional one-liner (null if absent)
      "status": "in-progress",           // planned | in-progress | done | abandoned
      "linked_feature": "auth",          // docs/features/<slug>.md, or null
      "created_at": "<ISO>",
      "updated_at": "<ISO>",
      "items": [
        {
          "id": "auth-1",                // stable: <fn-id>-<seq>, never reused
          "text": "邮箱密码登录",
          "status": "done",             // todo | doing | done
          "source": "spec",             // manual|spec|plan|research|ai-suggested|backfill
          "note": null,                  // optional
          "created_at": "<ISO>",
          "updated_at": "<ISO>"
        }
      ]
    }
  ]
}
```

### Field semantics

| Field | Meaning |
|---|---|
| `function.status` | Roll-up of the function. **Auto-derived** from items on every item change, EXCEPT `abandoned` which is sticky (hand-set, never auto-cleared). Derivation: all items `done` → `done`; any item `doing`/`done` → `in-progress`; else → `planned`. |
| `function.linked_feature` | When set, ties the function to a `docs/features/<slug>.md` spec + its workflow checkpoint, so the dashboard can cross-link to the workflow page. |
| `item.status` | `todo` = wanted, not started · `doing` = in progress · `done` = shipped/finished. |
| `item.source` | Provenance, so the dashboard can show *why* an item exists and the AI can be conservative about what it auto-adds. `ai-suggested` = proposed by MAGI after a plan/research, accepted by CEO. `backfill` = seeded by the updater from pre-existing checkpoints. |

## Writer — `scripts/todolist-write.sh`

Single source of truth for the schema (mirrors `checkpoint-write.sh`). Atomic
(tmp + rename), idempotent where it can be, jq-based. Operations:

| Operation | Purpose |
|---|---|
| `--init [--project <name>]` | Create the file if missing (no-op if present). |
| `--add-function --fn-id <slug> --fn-title <text> [--fn-desc] [--linked-feature] [--fn-status]` | Add/update a function group. |
| `--add-item --fn-id <slug> --item-text <text> [--item-status] [--source] [--item-note]` | Add an item; auto-creates the function if absent; **prints the new item id**. |
| `--set-item-status --fn-id --item-id --item-status` | Change an item's status; re-derives function status. |
| `--set-function-status --fn-id --fn-status` | Set function status explicitly (use for `abandoned`). |
| `--derive-function-status --fn-id` | Recompute one function's status from its items. |
| `--remove-item --fn-id --item-id` / `--remove-function --fn-id` | Delete. |
| `--list` | Print the whole todolist JSON to stdout (dashboards / AI read this). |

## Who writes it

- **`/todolist` skill** — human-facing view + edits, and the AI-suggestion flow.
- **Workflow stages** — after `/execution-plan` and `/implement`, MAGI proposes
  candidate items and (on CEO yes) appends them; `/commit` can flip items to `done`.
  MAGI **suggests**, never silently mutates the CEO's todolist.
- **The updater** — backfills functions/items from existing `workflow-checkpoints/`
  and `docs/features/` when updating a project that predates this feature.

## Who reads it

- **`/todolist`** renders it as a function-grouped board for the CEO.
- **CCC 灵动岛 dashboard** (`?view=dashboard` → 待办 page) polls `.harness/state/todolist.json`
  and visualizes each function as a categorized done/doing/todo board.

## Relationship to workflow checkpoints

`workflow-checkpoints/<feature>.json` tracks **one feature's 9-stage progress**
(transient; archived at commit). The todolist tracks **the whole project's
functions over its lifetime** (durable). A function's `linked_feature` connects
the two: the checkpoint answers *"what stage is this feature in right now"*, the
todolist answers *"what has this project built and what's left"*.
