# `.harness/scripts/` — Starter Templates + Bootstrap Driver

This directory holds:

1. **Shell-script templates** that get copied into the user's project at `/init` time (target: `.harness/scripts/`). Each script is a **starter** — the user customizes the parts marked `# CUSTOMIZE:` based on their stack.

2. **Standalone bootstrap driver** (`standalone-bootstrap.md`) — an AI-instruction file that runs when the user has cloned CCC-MAGI from GitHub directly (no CCC), the first time they open a CLI in the project.

## File inventory

| File | Type | Used by | What it does | Required? |
|------|------|---------|--------------|-----------|
| `bootstrap-check.sh` | Shell hook | Claude/Codex `UserPromptSubmit` event | Fires on every user prompt. If `.harness/state/install.json` is missing AND `.harness/` is present, injects a directive telling Claude to read `standalone-bootstrap.md` and run the bootstrap flow BEFORE responding. Exits silently if install.json exists. | **Yes — load-bearing** |
| `standalone-bootstrap.md` | AI driver | CLAUDE.md Bootstrap Status Check + `bootstrap-check.sh` hook | Detects existing harness configs (using AI semantic judgment), presents 3-option menu, archives/deletes other configs, then invokes /init | **Yes — standalone path** |
| `auditor-gate.sh` | Shell | every audit-gated skill | Invokes the auditor CLI ({{auditor_model}}), parses JSON verdict, returns exit code 0 (PASS / CONCERNS / WAIVED — all advance) / 2 (FAIL — halt) / 1 (script error, Universal Core WAIVED rejected, missing waiver_reason, or legacy verdict). CONCERNS verdicts are logged to `.harness/audits/concerns-*.json`; WAIVED verdicts to `.harness/audits/waivers-*.json`. | **Yes — core** |
| `precommit-typecheck.sh` | Shell | Claude/Codex hooks (PreToolUse `git commit`) | Runs the project's typecheck before commit | Yes, customize per stack |
| `lint-bans.sh` | Shell | Claude/Codex hooks (PreToolUse `git commit`) | Greps staged diff for anti-flag patterns | Yes if `{{anti_flag_rules}}` non-empty |
| `precommit-cycles.sh` | Shell | Claude/Codex hooks (PreToolUse `git commit`) | Runs dependency-cycle check | Optional — only if `{{dependency_flow}}` is non-empty |
| `format-edit.sh` | Shell | Claude/Codex hooks (PostToolUse Edit\|Write) | Runs the project's formatter on the edited file | Yes, customize per stack |
| `post-migration.sh` | Shell | `/db-schema` skill (manual invocation) | Backend cache refresh + typed-bindings regeneration | Only if `{{backend_db_type}}` configured |
| `memory-recall.sh` | Shell hook | Claude/Codex `SessionStart` event | Reads `.harness/memory/observations.jsonl`, scores entries by relevance to the current git branch's feature, injects top-N entries into Claude's `additionalContext`. Silent no-op when memory file is missing or empty. | Yes if memory layer in use |
| `memory-snapshot.sh` | Shell hook | Claude/Codex `PreCompaction` event | Injects an instruction telling Claude to summarize the session's key decisions into `.harness/memory/observations.jsonl` BEFORE context compaction proceeds. Creates the memory directory/file on first run. | Yes if memory layer in use |
| `budget-monitor.sh` | Shell hook | Claude/Codex `UserPromptSubmit` event | Reads `transcript_path` from hook input, estimates token usage (bytes / 4), emits advisory `additionalContext` at 50% / 75% / 90% of `CCC_CONTEXT_BUDGET` (default 200000) instructing Claude to prefer cheaper models for subagents, skip Explore-type research, recommend `/compact`. Silent under 50%. Advisory-only — Claude Code doesn't expose runtime model switching to hooks. | Yes (P1.6) |

## Why no harness-detect.sh anymore

Earlier versions had a `harness-detect.sh` shell script for detecting existing harness installations. It's been **removed** in favor of AI-driven detection inside `standalone-bootstrap.md` (and a parallel CCC-bundled driver on the CCC side).

Reasons:
- Shell-based detection can only match canonical markers (e.g., `.bmad-core/`, `.cursorrules`). Real-world projects often have ad-hoc AI config files (`agent.md`, `agent/harness.md`, etc.) that no static rule catches.
- AI can read file contents and make semantic judgments about what's harness-related.
- One uniform mechanism (AI judgment + user confirmation) is simpler than maintaining two layers (shell strict-match + AI fallback).
- See `CCC_harness_flow.md` § decision 1 for the architectural rationale.

## Bash / POSIX only (for shell scripts)

All shell scripts target **bash on macOS and Linux**. The harness-detect.sh removal also removed the last `declare -A` (bash 4+) dependency, so the remaining scripts are bash 3.2 compatible (macOS default).

## Customization pattern

Each shell script has a `# CUSTOMIZE:` block near the top. Edit that block, leave the rest alone:

```bash
# CUSTOMIZE: pick your stack's typecheck command
# Examples:
#   TypeScript:    COMMAND=(npx tsc --noEmit)
#   Python+mypy:   COMMAND=(mypy .)
#   Go:            COMMAND=(go vet ./...)
COMMAND=(npx tsc --noEmit)
```

`/init` may pre-fill some `CUSTOMIZE` blocks based on detected `tech_stack` — but you're always free to override.

## Permissions

After copying to your project, make sure shell scripts are executable:

```bash
chmod +x .harness/scripts/*.sh
```

`/init` does this automatically.

## Failure mode

If a shell script fails (non-zero exit), the calling hook / skill halts. This is by design — broken hooks are infinitely better than silent skipping.

If you want to temporarily disable a hook, edit `.claude/settings.json` (or `.codex/hooks.json`) to remove the entry, OR make the script `exit 0` early. **Do not delete the script** — other skills may reference it.

For `standalone-bootstrap.md`: this file is read by AI, not executed. If you want to disable standalone-bootstrap behavior, edit the Bootstrap Status Check block at the top of `CLAUDE.md` to remove the "read standalone-bootstrap.md" instruction. (Not recommended — without it, new users get no guidance on existing-harness handling.)
