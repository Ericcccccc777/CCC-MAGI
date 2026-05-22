# create-ccc-harness

Install [CCC-Harness](https://github.com/<OWNER>/CCC-Harness) into a project. One command.

```bash
cd /path/to/your/project
npx create-ccc-harness@latest
```

That's it. The installer downloads the harness, places files in canonical locations, sets script permissions, and tells you to open your AI CLI.

After install, open Claude Code (or Codex CLI) in the project. The harness's AI-driven bootstrap takes over and walks you through:
- Detecting any existing harness configs (BMAD / Cursor / etc.)
- 3-option menu (archive / overwrite / decline)
- Project configuration via 16 plain-language questions

## Options

| Flag | Effect |
|------|--------|
| `--dry-run` | Print what would be installed; don't write anything |
| `--force` | Overwrite existing CCC-Harness files; also bypasses git-clean check |
| `--ref <tag>` | Install a specific harness version (default: `main`) |
| `--help` | Show usage |

## What gets installed

```
your-project/
├── constitution.md               ← placeholder (filled by /init in next step)
├── CLAUDE.md                     ← workflow rules + Bootstrap Status Check at top
├── AGENTS.md                     ← auditor role contract
├── CCC_HARNESS_README.md         ← harness's own README (your project's README is untouched)
├── CCC_HARNESS_LICENSE           ← harness's MIT license (your project's LICENSE is untouched)
├── .harness/
│   ├── skills/                   ← 9 stage skills (feature-draft, audit-spec, ..., init)
│   ├── agents/                   ← 3 starter reviewers (frontend / backend / security) + 1 junior programmer (test-fixer) + template
│   ├── scripts/                  ← shell scripts (auditor-gate.sh, hooks) + standalone-bootstrap.md
│   └── state/                    ← created by /init (not by this installer); will hold install.json after configuration
├── .claude/settings.json         ← Claude Code hooks + permissions
├── .codex/
│   ├── config.toml               ← Codex CLI config
│   └── hooks.json                ← Codex hooks
└── docs-harness/                 ← framework design rationale (5 docs)
```

The installer **preserves** your existing `README.md` and `LICENSE` (the harness's are renamed to `CCC_HARNESS_*` to avoid collision).

If you already have `constitution.md`, `CLAUDE.md`, `AGENTS.md`, or `.harness/` from a prior CCC-Harness install, the installer skips them by default. Use `--force` to overwrite.

## Requirements

- **git** (the installer uses `git clone --depth 1` to download)
- **node >= 18** (for the npx invocation itself)
- The target directory should be a git repo (`git init` first; the installer warns otherwise)
- The working tree should be clean (uncommitted changes trigger a warning; `--force` overrides)

## Post-install

Open Claude Code in the directory:

```bash
claude
```

Claude reads `CLAUDE.md`, sees the `Bootstrap Status Check` block at the top, sees `.harness/state/install.json` doesn't exist → invokes the bootstrap flow from `.harness/scripts/standalone-bootstrap.md`.

From there it's interactive:
1. AI scans for existing harness configs (BMAD, Cursor, ad-hoc CLAUDE.md / agent.md, etc.)
2. AI lists candidates + asks you to confirm
3. AI presents the 3-option menu
4. If you pick archive or overwrite, AI archives/deletes the other configs and invokes `/init`
5. `/init` asks 16 plain-language questions, fills `constitution.md`, writes `install.json`

Total time: 5–15 minutes for a fresh project.

## What this installer does NOT do

- **Does NOT run the 3-option menu itself.** That happens inside the AI CLI after install, because the menu requires AI judgment to identify ad-hoc harness configs (e.g., a project with `agent/harness.md` that isn't a known framework).
- **Does NOT configure project-specific values.** `/init` does that (16 questions, post-install).
- **Does NOT alter your project's package.json, .gitignore, build configs, etc.** It only places harness files in dedicated locations.

## Troubleshooting

**"git is not installed"** — install git via your package manager (`brew install git` on macOS).

**"Current directory is not a git repository"** — run `git init` first, or use `--force` to install anyway.

**"Working tree has uncommitted changes"** — commit/stash your changes, or use `--force`.

**Clone failed** — verify the harness repo URL in `bin.js` is published and reachable. (Pre-publish: the URL is a placeholder; see `_TODO_PRE_PUBLISH` in `package.json`.)

**Files already exist** — by default the installer preserves existing CCC-Harness files. Use `--force` to overwrite.

## License

MIT — see `LICENSE` (same as the CCC-Harness repo itself).

## Repo

Source: https://github.com/<OWNER>/CCC-Harness (this `installer/` subdirectory)  
Harness it installs: https://github.com/<OWNER>/CCC-Harness (the repo root)

> Pre-publish decision: installer ships as a subdirectory of the harness repo, so a single `git clone` gets both. The installer's `package.json` `repository.url` reflects this. If the installer is later split into a separate npm package repo, update both this README and `package.json` consistently.

## Version

0.1.0-mvp — Round 3 MVP stub. The git clone URL in `bin.js` is currently a placeholder (`<OWNER>` literal). Update it pre-publish per the `_TODO_PRE_PUBLISH` checklist in `package.json`.
