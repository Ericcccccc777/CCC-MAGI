---
name: todolist
description: This skill manages the project todolist — a function-grouped work ledger answering "what has this project built, what's being built, what's wanted next". Each function (capability area / feature) holds items that are done / doing / todo. Use it to VIEW the todolist (render a function-grouped board for the CEO), to ADD or UPDATE functions and items, and to run the AI-suggestion flow after a plan or research round. Trigger when the CEO invokes /todolist, or says "看看 todolist / 待办 / 任务清单", "我们做到哪了 / 整体进度", "把 X 加进 todolist / 加个任务", "X 做完了 / X 在做了", "show me the todolist", "what have we built / what's left", "add X to the todolist", "mark X done". Also invoked internally by the workflow after /execution-plan and /implement to propose candidate items.
argument-hint: [view | add | done <what> | ...natural language]
---

# /todolist

Manage the project todolist: a **function-grouped** ledger of work. The project
is split into FUNCTIONS (capability areas / features); each function holds ITEMS
that are `done` / `doing` / `todo`. It is the durable answer to *"where is this
project at?"* — distinct from a single feature's 9-stage checkpoint.

> **Schema & writer reference:** `.harness/docs/todolist.md`. The only way to
> mutate the todolist is via `.harness/scripts/todolist-write.sh` (atomic,
> idempotent, jq-based) — never hand-edit `.harness/state/todolist.json`.

All CEO-facing output follows the session locale (see CLAUDE.md § Language
Awareness). Item/function ids and the JSON stay machine-form.

## Modes

The CEO won't type subcommands — infer the mode from natural language.

### 1. View (default)

When the CEO wants to see the todolist ("看看 todolist", "整体进度", "what's left"):

1. Read state: `bash .harness/scripts/todolist-write.sh --list` (returns JSON;
   `--init` first if you intend to also add something this turn).
2. Render a **function-grouped board** in the CEO's language. One block per
   function, items bucketed by status. Example shape:

```
📋 DemoApp — 项目待办

🔵 用户登录 (进行中)
   ✅ 邮箱密码登录
   ✅ Google OAuth
   ⚪ 忘记密码

⚪ 搜索 (计划中)
   ⚪ 全文搜索

总计: 1 个功能进行中 · 1 个计划中 · 2/4 项已完成
```

Status glyphs: `✅ done · 🔵 doing · ⚪ todo` for items; `✅ done · 🔵 in-progress
· ⚪ planned · 🗑 abandoned` for functions. Keep it scannable; don't dump JSON.

### 2. Add / update (CEO-driven)

Map the CEO's intent to writer calls:

| CEO says | Call |
|---|---|
| "加个功能 X" / "新功能区 X" | `--add-function --fn-id <slug> --fn-title "X"` |
| "X 功能里加一项 Y" / "给 X 加任务 Y" | `--add-item --fn-id <slug> --item-text "Y"` |
| "Y 在做了" | `--set-item-status --fn-id <slug> --item-id <id> --item-status doing` |
| "Y 做完了" | `--set-item-status --fn-id <slug> --item-id <id> --item-status done` |
| "X 这块不做了 / 放弃 X" | `--set-function-status --fn-id <slug> --fn-status abandoned` |
| "删掉 Y" | `--remove-item --fn-id <slug> --item-id <id>` |

Resolution rules:
- **Slug**: derive a kebab-case `fn-id` from the function name; reuse the
  existing one if the CEO names a function already present (match on title).
- **Item id**: the CEO refers to items by description, not id — `--list` first,
  match the text, use that item's `id`. If ambiguous, ask one short question.
- **Source**: CEO-entered items use `--source manual`. Default item status is
  `todo` unless the CEO says it's in progress / done.
- Always echo back the result as a one-line confirmation, then optionally
  re-render the affected function block.

### 3. AI-suggestion flow (after plan / research)

Invoked by the workflow at the end of `/execution-plan` and `/implement`, or
whenever the CEO has just finished planning/research and there are concrete
work items worth recording. **MAGI proposes; the CEO decides. Never silently
write `ai-suggested` items.**

1. From the just-produced plan/spec/research, extract a short list of candidate
   items (the discrete pieces of work), grouped under the relevant function
   (use the feature slug as `fn-id`, `--linked-feature <slug>`).
2. Present them to the CEO for opt-in, in their language:

```
📋 要把这些加进 todolist 吗?(功能:用户登录)
   ⚪ 邮箱密码登录
   ⚪ Google OAuth
   ⚪ 忘记密码流程

回复「都加」/「加 1 和 3」/「不用」即可。
```

3. On CEO confirmation, for each accepted item:
   - ensure the function exists (`--add-function ... --linked-feature <slug>`),
   - `--add-item --fn-id <slug> --item-text "..." --source ai-suggested`
     (status `todo` for future work; `doing` if it's what's being implemented now).
4. Confirm what was added; if the CEO declined, drop it silently — do not nag.

## Status-derivation note

Function status auto-derives from its items on every item change (all done →
`done`; any doing/done → `in-progress`; else `planned`), EXCEPT `abandoned`
which is sticky. So you rarely set function status by hand — only for
`abandoned`, or to correct an override. After bulk item edits you may call
`--derive-function-status --fn-id <slug>` to force a recompute.

## Guardrails

- Never hand-edit `.harness/state/todolist.json` — always go through the writer.
- The todolist is the CEO's. The AI may *suggest* additions; it must not invent
  functions or items the CEO didn't ask for or approve.
- Keep item text in the CEO's domain language (what the work achieves), not
  tech identifiers — same spirit as the CEO spec file.
- This skill is read/advisory + writer-mediated; it makes no judgment calls
  about business logic. It records the CEO's intent, it doesn't decide scope.

## Final message to CEO

After a view: re-offer natural next steps ("想加任务、标记完成、还是看某个功能的细节?").
After an edit: one-line confirmation + the updated function block.
After the suggestion flow: confirm what was added (or note nothing was added).
