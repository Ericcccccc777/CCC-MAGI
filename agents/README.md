# Junior Agents (`outcome/agents/`)

This directory holds the **junior agents** that the harness's skills spawn at specific workflow stages. Junior agents are **mechanical rule enforcers** (reviewers) or **fresh-context task workers** (programmers) — they do not exercise judgment, propose new patterns, or evaluate business logic.

## Two roles, never mixed

| Role | Verb | Scope | Authority |
|------|------|-------|-----------|
| **Reviewer** | "does this diff violate a documented rule?" | Cites rules; never invents them | Findings must cite a rule source |
| **Programmer** | "make this thing work, within hard rules" | Acts on artifacts (failing test, etc.) | Fresh context, no implementer-bias |

The **core three** roles (Planner / Programmer / Reviewer) at the harness level are played implicitly by main Claude + the auditor model — they don't have their own agent files. See `CLAUDE.md § Subagents — Core three`.

The junior agents in *this* directory are **invoked by skills** (e.g. `/implement` spawns the relevant junior reviewers; `/test-fix` spawns `test-fixer`).

## What ships by default

The harness ships 4 starter examples (all marked `example: true` in frontmatter):

| File | Role | Loaded when |
|------|------|-------------|
| `frontend-reviewer.md` | Reviewer | Always (if project has client code) |
| `backend-reviewer.md` | Reviewer | **Only if `backend_db_type` is configured** (optional plugin) |
| `security-reviewer.md` | Reviewer | Always (auth / PII / access-control surfaces) |
| `test-fixer.md` | Programmer | Always (if `test_required = true`) |

These are **starters, not requirements**. `/init` selects which to enable for your project based on `tech_stack` + `junior_reviewers` slot.

## Adding your own junior agent

1. Copy `_template/junior-agent-template.md` to `outcome/agents/<your-name>.md`
2. Fill in: `name`, `description`, `role` (reviewer | programmer), authority rule sources, checklist sections, finding taxonomy
3. Register it in `{{junior_reviewers}}` slot (via `/init` or by hand-editing `constitution.md`)
4. Add path-trigger rule in `CLAUDE.md § Tool map — Rule-enforcement plugins` so `/implement` knows when to invoke it

## The unified schema all junior agents follow

Every junior agent file matches this shape:

```
---
name: <kebab-case-name>
description: <one paragraph; what it does, when to invoke>
role: reviewer | programmer
tools: [list of tools the agent may use]
model: inherit | <specific>
color: <UI color for the agent's verdicts>
memory: project | fresh
example: true | false        # true if shipped as a starter; false if user-authored
optional: true | false       # only loads when `requires` is satisfied
requires: <slot name>         # e.g. backend_db_type
---

[Body sections]
1. Role statement — what you are
2. Scope (what you do / what you do NOT do)
3. Authoritative rule sources — where findings cite from
4. When invoked — numbered steps
5. Review checklist (reviewers) OR Workflow (programmers)
6. Finding report format OR Return contract
7. Memory protocol
```

See `_template/junior-agent-template.md` for the skeleton with inline guidance.

## Why no Codex `.toml` duplicates?

In the original harness, `claude/agents/*.md` and `codex/agents/*.toml` were near-mirrors (with sync debt). The cleaned harness uses **a single source** (`.md`) — the adapter that converts to Codex's TOML format (or any other CLI's format) lives at `.harness/adapters/` and is built in a later round.

This is the kernel-plus-adapter pattern: write the agent once, render to whichever CLI loads it.
