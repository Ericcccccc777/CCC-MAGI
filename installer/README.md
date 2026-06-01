# create-ccc-magi

Install [CCC-MAGI v0.10.1](https://github.com/Ericcccccc777/CCC-MAGI) into a project. One command.

```bash
cd /path/to/your/project
npx create-ccc-magi@latest
```

That's it. The installer downloads the harness from GitHub, places files in canonical locations, sets script permissions, and tells you to open your AI CLI.

After install, open Claude Code (or Codex CLI) in the project. The harness's **two-phase bootstrap** takes over:

- **Phase 1 — Environment check (~30 seconds, conversational)**  
  MAGI Core greets you and detects what's installed (git, jq, claude, codex). Anything missing → walks you through install conversationally (brew / vendored binary / manual options).

- **Phase 2 — Project deployment (~3-15 minutes, conversational)**  
  Pick Simple (5 questions, smart defaults) or Pro (16 questions, full identity contract). Can upgrade Simple → Pro anytime later by saying "升级到专业版" / "upgrade to pro".

## Options

| Flag | Effect |
|------|--------|
| `--dry-run`, `-n` | Print what would be installed; don't write anything |
| `--force`, `-f` | Overwrite existing CCC-MAGI files; bypasses git-clean check |
| `--force-load-bearing` | Also overwrite `constitution.md` / `CLAUDE.md` / `AGENTS.md` (use carefully — wipes your project identity) |
| `--ref <tag>` | Install a specific harness version (default: `main`) |
| `--version` | Print this installer's version |
| `--help`, `-h` | Show usage |

## Platform support

| Platform | Status |
|---|---|
| macOS (Apple Silicon / Intel) | ✅ Tier 1 |
| Linux (Ubuntu / Debian / RHEL / Arch) | ✅ Tier 1 |
| Windows 10/11 + WSL2 (Ubuntu) | ✅ Tier 1 — recommended |
| Windows 10/11 + Git for Windows (Git Bash) | ⚠️ Tier 2 — community-tested |
| Windows native (cmd / PowerShell only) | ❌ install Git for Windows first |

CCC-MAGI inherits its platform matrix from Anthropic Claude Code. Anywhere Claude Code runs, CCC-MAGI can run (provided a POSIX shell is reachable for hook execution).

**Windows quick-start:**
```powershell
winget install Git.Git
# OR for a full Linux experience:
wsl --install -d Ubuntu
```

## What gets installed

```
your-project/
├── constitution.md               ← project identity placeholder (filled by /init)
├── CLAUDE.md                     ← workflow rules + two-phase Bootstrap Status Check
├── AGENTS.md                     ← MAGI System (7 positions) + auditor brief
├── CCC_MAGI_README.md            ← harness's own README (your README is preserved)
├── CCC_MAGI_LICENSE              ← harness's Apache 2.0 license (your LICENSE preserved)
├── .harness/
│   ├── skills/                   ← 16 stage skills (feature-draft, audit-spec, ..., resume, abandon)
│   ├── agents/                   ← 4 reviewer agents (backend / frontend / security / test-fixer)
│   ├── scripts/                  ← 15 shell scripts (hooks, helpers, env-check, checkpoint-write...)
│   └── state/                    ← created at runtime (install.json, env-check.json, checkpoints...)
├── .claude/settings.json         ← Claude Code 5-hook chain + permissions
├── .codex/
│   ├── config.toml               ← Codex CLI config
│   └── hooks.json                ← Codex hooks
└── docs-harness/                 ← framework design rationale (6 docs)
```

The installer **preserves** your existing `README.md` and `LICENSE`. The harness's are renamed to `CCC_MAGI_*` to avoid collision.

## Git-clean check

By default, the installer refuses to run if your target directory has uncommitted changes — installing on a dirty tree mixes harness files with your in-progress edits. Either:

```bash
git stash         # set aside, install, then git stash pop
# — or —
git commit -am "wip" # commit, then install
# — or —
npx create-ccc-magi@latest --force   # override
```

## Requirements

- **git** (for cloning CCC-MAGI from GitHub at install time)
- **bash** (for executing install-into.sh; Mac/Linux native, Windows via Git Bash or WSL)
- **node >= 18** (for npx itself)
- Target directory should be a git repository (`git init` first)

Note: **jq is installed conversationally** during Phase 1 environment check by MAGI Core (not by this installer). The installer doesn't gate on jq presence — that's the harness's job at first interaction.

## Post-install

```bash
cd /path/to/your/project
claude   # or: codex
```

Claude Code reads `CLAUDE.md`, sees the **Bootstrap Status Check** block at the top, notices `.harness/state/install.json` doesn't exist → walks you through:
1. Phase 1 — env check (with conversational jq install if missing)
2. Phase 2 — Simple or Pro project deployment

Total time: 5–15 minutes for a fresh project.

## What this installer does NOT do

- **Does NOT install jq for you.** That's Phase 1's conversational job inside MAGI Core. The installer just gets the harness files in place.
- **Does NOT alter your project's `package.json`, `.gitignore`, build configs, etc.** It only places harness files in dedicated locations.
- **Does NOT run `/init` itself.** That's Phase 2 of the bootstrap, executed inside Claude Code with full conversational control.

## Troubleshooting

**"git is not installed"** — install git via your package manager (`brew install git` on macOS, `winget install Git.Git` on Windows).

**"bash is not installed"** — on Windows, install Git for Windows (`winget install Git.Git`) — it includes Git Bash.

**"Current directory is not a git repository"** — run `git init` first, or use `--force` to install anyway.

**"Working tree has uncommitted changes"** — commit/stash your changes, or use `--force`.

**Clone failed** — verify network connectivity. For private forks, use `--ref <branch-or-tag>` to target a reference your local credentials can reach.

**Files already exist** — by default the installer preserves existing CCC-MAGI files (content-hash registry detects user customizations). Use `--force` to overwrite, `--force-load-bearing` to also overwrite `constitution.md` / `CLAUDE.md` / `AGENTS.md`.

## License

Apache-2.0

## Repo

Source: https://github.com/Ericcccccc777/CCC-MAGI

## Version

0.9.0 — MAGI 7-position AI team system + Simple/Pro onboarding modes + feature-aware session resume + two-phase conversational bootstrap. See [CHANGELOG](https://github.com/Ericcccccc777/CCC-MAGI/releases) on the main repo for details.
