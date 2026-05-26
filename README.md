# CCC-Harness

A generic, project-agnostic harness for AI-driven development workflows. Built to be installed in any codebase (greenfield or brownfield), regardless of language or framework, and to give AI coding assistants (Claude Code, Codex, etc.) the structured discipline they don't have out of the box: cross-model audit on every change, plain-language feature specs, mandatory human smoke tests, and a three-section project constitution that survives harness upgrades.

> **Status**: v1 MVP. Tested on macOS (bash 3.2) + Claude Code + Codex CLI. Standalone install path is fully functional; CCC-driven install path is designed (see `docs-harness/ccc-step1-driver-template.md`) but requires CCC integration work on the CCC side.

---

## Why this exists

Most AI-coding harnesses (BMAD, SpecKit, OpenSpec, etc.) are excellent but ship project-coupled. You can't take BMAD's React Native conventions into a Python backend. You can't drop SpecKit's GitHub Issues integration into a project that doesn't use GitHub.

CCC-Harness extracts the universal mechanics from these patterns:

- **Cross-model audit** as a load-bearing invariant (not an optional layer)
- **Two-file feature spec model** (CEO domain in plain language; manager domain with tech detail)
- **Lane-aware workflow** (full / stability-fix / trivial — same flow, different gate intensity)
- **Mechanical junior reviewers** (rules cite source docs, never invent rules)
- **Real-human smoke test as a contract** (AI's "done" doesn't count)
- **Spec-and-code drift detection** (`/audit-spec` reverse-engineers reality, surfaces deltas)

…and packages them as a slot-driven template that fills in **your** project's specifics via a one-time `/init`.

---

## Prerequisites

Before installing, ensure your system has:

- **git** — required (used by the installer and most harness hooks)
- **bash 3.2+** — macOS default supported; Linux distributions ship 4+ typically
- **jq** — required (used for safe JSON merging of `.claude/settings.json` and `.codex/hooks.json`)

The `install-into.sh` script runs `outcome/scripts/check-prereqs.sh` at the start and provides platform-aware install hints if any hard prereq is missing (Homebrew detection on macOS, `apt` / `yum` / `pacman` hints on Linux). Soft prereqs like `python3` are flagged as warnings only.

---

## Quick start

### Path A — Via npx installer (recommended)

```bash
cd /path/to/your/project
npx create-ccc-harness@latest
```

This downloads the harness, places files in canonical locations, sets script permissions, and tells you to open your AI CLI. Use `--dry-run` to preview without writing anything, or `--force` to overwrite existing CCC-Harness files.

Then open Claude Code:

```bash
claude
```

Claude reads `CLAUDE.md`, sees the **Bootstrap Status Check** block at the top, sees `.harness/state/install.json` doesn't exist → reads `.harness/scripts/standalone-bootstrap.md` → walks you through detection of any existing harness configs + 3-option menu + `/init` configuration.

### Path B — Manual install (advanced)

If you need full control over file placement, do it explicitly (do NOT use a flat `cp -r`, because the harness expects a specific directory layout):

```bash
cd /path/to/your/project
git clone https://github.com/<OWNER>/CCC-Harness.git .ccc-harness-temp
cd .ccc-harness-temp

# Move root files
mv constitution.md CLAUDE.md AGENTS.md ../

# Move directories to .harness/ subpaths (NOT to project root)
mkdir -p ../.harness
mv skills agents scripts ../.harness/

# Move CLI configs to their canonical locations
mkdir -p ../.claude ../.codex
mv cli-configs/claude/settings.json ../.claude/
mv cli-configs/codex/config.toml cli-configs/codex/hooks.json ../.codex/

# Move docs and metadata
mv docs-harness ../
mv cli-configs/README.md ../docs-harness/cli-configs-README.md   # NB: must come AFTER docs-harness move
mv .gitignore ../   # if you don't already have one; otherwise merge manually
mv README.md ../CCC_HARNESS_README.md
mv LICENSE ../CCC_HARNESS_LICENSE

# Clean up + permissions
cd ..
rm -rf .ccc-harness-temp
chmod +x .harness/scripts/*.sh
```

Then open Claude Code as in Path A above. The bootstrap flow will run inside the CLI.

> **Strongly recommend Path A unless you have a specific reason.** The npx installer does exactly this layout for you and adds safety checks (git-repo detection, clean-tree check, dry-run mode).

### Path C — Via CCC (Claude Code Controller)

If you use CCC as your desktop session manager:

1. Open CCC, "new session", select your project folder
2. Click the "Harness" button in the session view
3. Click "Environment Detection" → confirm token usage warning
4. CCC handles everything (terminal spawn + driver injection + git pull + /init invocation)

See `docs-harness/ccc-step1-driver-template.md` for the CCC integration spec.

### Path D — Via Anthropic Plugin Marketplace (future)

CCC-Harness includes a `.claude-plugin/plugin.json` manifest. Once submitted to and accepted by the Anthropic `claude-community` marketplace (manual review process), users will be able to install via:

```bash
/plugin marketplace add anthropics/claude-plugins-community
/plugin install @claude-community/ccc-harness
```

**Note**: plugin-only installation ships skills + commands; the full project-level harness (constitution.md, .harness/state/, slot rendering) still requires `install-into.sh` or `npx create-ccc-harness`. The plugin path is for users who want CCC-Harness's skills available globally across projects without per-project configuration.

Submission status: not yet submitted as of v0.7.

---

## What you get

After `/init` completes, your project has:

```
your-project/
├── constitution.md             ← project identity (filled with your answers to /init)
├── CLAUDE.md                   ← workflow rules (with Bootstrap Status Check at top)
├── AGENTS.md                   ← universal project context (AGENTS.md ecosystem standard) + auditor brief
├── CCC_HARNESS_README.md       ← this file, renamed at install time (your project's README is preserved)
├── CCC_HARNESS_LICENSE         ← MIT license, renamed (your project's LICENSE is preserved)
├── .harness/
│   ├── skills/                 ← /feature-draft, /audit-spec, /implement, /test-fix, /commit, ...
│   ├── agents/                 ← frontend-reviewer, backend-reviewer, security-reviewer, test-fixer
│   ├── scripts/                ← auditor-gate.sh, lint hooks, formatter, standalone-bootstrap.md
│   └── state/install.json      ← "configured" marker (written at end of /init)
├── .claude/settings.json       ← Claude Code hooks + permissions
├── .codex/                     ← Codex CLI config + hooks
└── docs-harness/               ← framework design rationale (read once, not load-bearing daily)
    └── cli-configs-README.md   ← documentation on the CLI integration layer
```

The installer **renames** `README.md` → `CCC_HARNESS_README.md` and `LICENSE` → `CCC_HARNESS_LICENSE` so they don't overwrite your project's existing README / LICENSE.

---

## How it works (the short version)

1. **You have a constitution.** A small file at project root with 5 universal-core invariants (cross-model audit mandatory, data ownership red line, CEO final authority, smoke test mandatory, spec-reality sync) + project identity (who you serve, what you don't do, compliance, performance floors).

2. **You have a workflow with 9 stages.** Spec → finalize → schema (optional) → plan → implement → test → smoke → commit → watch. Each stage has a skill (e.g., `/feature-draft` for stage 1) and a clear hand-off contract.

3. **Three lanes select audit intensity.** Full (new feature), stability-fix (bug fix with mandatory failing test), trivial-change (<20 LOC).

4. **Audit is unconditional.** Every code change passes a different-model audit before commit. No lane exemption, no surface exemption. Single-engine fallback supported if you only have one model.

5. **Slots make it generic.** Every project-specific value (tech stack, paths, language, locales, etc.) lives in `constitution.md`'s slot registry. `/init` fills these once. Skills reference them, never hard-code.

For the full design rationale, see `docs-harness/design-spec.md`.

---

## What this is NOT

- **Not a build system.** The harness orchestrates conversation, audit, and commit gates. It doesn't replace `npm run build` or `make`.
- **Not a project boilerplate.** Tech stack, file structure, and code conventions are yours. The harness wraps them; it doesn't impose them.
- **Not an enterprise governance suite.** No RBAC, no audit-log signing, no compliance attestations. Those are reasonable extensions, not core.
- **Not a substitute for engineering judgment.** Every rule (except 5 universal-core items) can be overridden by you with reasoning recorded.

---

## Documentation map

| File | Purpose |
|------|---------|
| `README.md` (this file) | Quick start, what it is |
| `constitution.md` | Project identity (filled by `/init`) + 5 universal core items |
| `CLAUDE.md` | Workflow rules, lane definitions, doc-in-sync, tool map |
| `AGENTS.md` | Universal project context (AGENTS.md ecosystem standard — read by Codex, Cursor, Cline, Aider, etc.) + auditor (Sam / Codex) role contract + anti-flag rules |
| `docs-harness/README.md` | Index of the framework's own design docs |
| `docs-harness/design-spec.md` | The architectural rationale (why two-file model, why three lanes, etc.) |
| `docs-harness/adoption-playbook.md` | Step-by-step install guide (greenfield + brownfield + standalone + CCC paths) |
| `docs-harness/retrospective-notes.md` | Generalized LLM-workflow patterns worth carrying forward |
| `docs-harness/ccc-step1-driver-template.md` | Integration template for the CCC Step 1 driver |

---

## Compatibility

- **CLIs**: Claude Code (`claude`), Codex CLI (`codex`). Future: Gemini CLI, Cline CLI, others.
- **OS**: macOS, Linux. Windows via WSL.
- **Shell**: bash 3.2+ (macOS default supported).
- **Required tools**: `git`, `jq` (for `auditor-gate.sh`).
- **Auditor models**: Codex (default), Claude (single-engine fallback), or any model with structured-output capability.

---

## License

MIT — see `LICENSE`.

---

## Contributing

This is a young project. PRs welcome especially for:
- Tech-stack-specific anti-flag rule starter packs (Next.js, Django, Go, Rust, Swift, Kotlin)
- Junior reviewer plugin examples for non-frontend domains (CI/CD, IaC, infra)
- CCC bundled Step 1 driver implementation (CCC team)
- Translation of user-facing prompts beyond zh-Hans / en / ko

---

## Project status & roadmap

**v1 MVP (now)**: standalone install path fully functional. CCC integration designed, awaiting CCC team implementation.

**v1.x (next)**: 
- Polish: persistent memory layer (mem0 / Supermemory MCP)
- Parallel agents + worktree isolation
- Tech-stack starter presets

**v2 (later)**:
- AGENTS.md root-of-truth mode (Linux Foundation standard compat)
- Observability layer (token / cost / gate-pass-rate dashboard)
- Plugin marketplace integration (Claude Skills / Codex)
- Resume-mode error recovery
