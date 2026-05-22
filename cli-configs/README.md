# CLI Integration Layer (`outcome/cli-configs/`)

This directory holds the **per-CLI integration configs** — the hooks, permissions, and runtime settings that each CLI (Claude Code, Codex) needs to actually load this harness.

## Why this is split per-CLI

Each CLI has its own config format and conventions:

| CLI | Config files | Format |
|-----|-------------|--------|
| Claude Code | `.claude/settings.json` | JSON |
| Codex | `.codex/config.toml`, `.codex/hooks.json` | TOML + JSON |

The **content** (hook semantics, permission intents) is largely shared. The **format** is per-CLI. In Round 1 of harness cleanup we keep them as separate templates; in Round 2 the plan is a single "settings spec" + adapters that render each CLI's format. For now: 3 files, separately maintained.

## What's in here

```
cli-configs/
├── README.md                 ← this file
├── claude/
│   └── settings.json         ← Claude Code settings template
└── codex/
    ├── config.toml           ← Codex model + MCP servers config
    └── hooks.json            ← Codex hook config (typically same shape as claude/)
```

## Installation flow

When `/init` runs in a user's project:

1. Reads slot values (`{{auditor_model_id}}`, `{{junior_reviewers}}`, etc.) from `constitution.md` registry
2. Renders the templates above with slot values filled in
3. Writes them to the user's project at:
   - `.claude/settings.json`
   - `.codex/config.toml`
   - `.codex/hooks.json`
4. Creates `.harness/scripts/` directory with the project's hook scripts (typecheck / lint-bans / cycles / format / post-migration / auditor-gate). **These scripts are project-specific** — the harness ships templates / examples in `outcome/cli-configs/scripts-template/` (TBD in Round 2); the user customizes them based on their stack.

## What was removed from the original

The harness's source files (`harness/claude/settings.json`, `harness/codex/config.toml`, `harness/codex/hooks.json`) contained:

- **User-personal telemetry hooks** (CCC PreToolUse / Stop / Notification with `sessionId=2 port=52301` and HTTP calls to localhost) → REMOVED. That was the original author's local dev tooling, not part of the harness.
- **User-personal statusLine** (pointing to `/var/folders/...` temp file) → REMOVED.
- **Supabase MCP permissions and server URL** (with a specific project_ref) → REMOVED, replaced with commented example in `codex/config.toml`.
- **Specific model name `gpt-5.5`** → slot-ified as `{{auditor_model_id}}`.

## Required hook scripts

The templates reference these script paths. The harness expects them to exist in the user's project at `.harness/scripts/`:

| Script | Purpose | When invoked |
|--------|---------|--------------|
| `precommit-typecheck.sh` | Block commit on type/syntax errors | PreToolUse on `git commit` |
| `lint-bans.sh` | Block commit on anti-flag pattern hits | PreToolUse on `git commit` |
| `precommit-cycles.sh` | Block commit on dependency cycles (only if `dependency_flow` non-empty) | PreToolUse on `git commit` |
| `format-edit.sh` | Run formatter on edited files | PostToolUse on `Edit` / `Write` |
| `post-migration.sh` | Refresh caches + regenerate types after migration | Manual (referenced in `/db-schema`) |
| `auditor-gate.sh` | Invoke the auditor CLI ({{auditor_model}}) with structured output | Manual (referenced in every audit-gated skill) |

These are **project-specific** — the user fills them with their stack's actual commands (e.g., `tsc --noEmit` for TypeScript, `mypy` for Python, etc.).

## MCP server defaults

The harness ships with:

- **`context7`** (Upstash) — universal docs lookup; high value across stacks
- **`github`** — optional; useful for any project that uses GitHub
- **Project-specific MCPs** — user adds per stack. Examples:
  - Backend MCPs (e.g., Supabase MCP, Postgres MCP, MongoDB MCP) — only if `backend_db_type` configured
  - SaaS MCPs (Stripe, Sentry, etc.) per the project's external integrations

## Permissions philosophy

The `permissions.allow` list controls which MCP tool calls Claude Code may execute without prompting. The harness ships a minimal default — `context7` only. Other MCPs require explicit user opt-in at `/init` to avoid silent over-permissioning.

If you want a different default, edit `claude/settings.json` here before running `/init`.
