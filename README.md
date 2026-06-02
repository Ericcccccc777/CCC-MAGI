# CCC-MAGI

> **An AI-coding harness that turns vibe coding into a maintainable project.**
> Cross-model audit on every change · plain-language specs · persistent memory across sessions · 7-position MAGI AI team · 20 natural-language skills · drop-in to any codebase.

**Read in your language**: **English** (this section) · [简体中文](#ccc-magi-中文版)

---

## What CCC-MAGI is, in one paragraph

When you let an AI write code, the AI is happy to give you 1000 lines of plausible-looking work in five minutes. Three weeks later, you can't tell which lines were carefully designed and which were guessed. You can't tell if the spec in your head still matches the code on disk. You can't tell which "fix" actually fixed anything. **CCC-MAGI is the harness that fixes this.** It sits in your project, talks to your AI CLI (Claude Code, Codex, etc.), and forces every change through a workflow: write a plain-language spec, get it audited by a *different* model, plan the files, implement, run tests, smoke-test by hand, commit. The discipline that a senior engineer would impose, but never has to be remembered — the harness enforces it mechanically.

It works the same way whether you're a hobbyist building your first side project, a solo professional shipping a SaaS, or a small team trying to keep three contributors' AI-generated code from contradicting each other.

---

## Who CCC-MAGI is for

| If you are... | What CCC-MAGI gives you |
|---|---|
| **Vibe-coding beginner** — you discovered Claude Code last month and your project is starting to feel like a haunted house | A safety net. Specs get written before code. A second AI reviews every change. You can't accidentally commit a 1000-line "improvement" without a smoke test. |
| **Creator who wants something stable** — you can read code but you're not a full-time engineer | Engineering discipline that doesn't depend on you remembering it. The hooks fire automatically; the constitution enforces project identity even after compaction. |
| **Solo professional** — you ship for a living and want AI to multiply you, not bury you | Cross-model audit (Claude × Codex) cancels single-model bias. Persistent memory means "what did we decide about auth last month" is one question, not a code-archaeology dig. |
| **Team of 2-5 doing vibe coding** — multiple contributors, shared codebase, AI everywhere | A shared constitution every teammate's AI reads first. Conventions stay aligned. Bug fixes have mandatory failing tests. Plan files are deleted at commit. |
| **Brownfield project that has outgrown casual AI use** — you have working code but no spec discipline | `/audit-spec` reverse-engineers the current code into a spec, then surfaces the deltas between what you *think* it does and what it *actually* does. Brownfield onboarding is a first-class path, not an afterthought. |

If you fit any of the above, you're the audience.

---

## Why it exists

Most AI-coding harnesses (BMAD, SpecKit, OpenSpec, etc.) are excellent but ship project-coupled — BMAD assumes React Native, SpecKit assumes GitHub Issues, etc. You can't lift their conventions into a Python backend or a Swift app.

CCC-MAGI extracts the universal mechanics — the parts that work regardless of language, framework, or team size — and packages them as a slot-driven template:

- **Cross-model audit** as a load-bearing invariant (not an optional layer)
- **Two-file feature spec model** (CEO domain in plain language; manager domain with tech detail in EARS notation)
- **Lane-aware workflow** (full / stability-fix / trivial — same flow, different gate intensity)
- **Three-tier persistent memory** (working scratchpad / 30-day recall / archive) — survives `/clear`, compaction, days off
- **MAGI 7-position AI team** (Core / Verdict / Planner / Programmer / Tester / Reviewer / Archivist) — clearly named roles, clear authority
- **Mechanical junior reviewers** (rules cite source docs, never invent rules)
- **Real-human smoke test as a contract** (AI's "done" doesn't count — Constitution § 1.4)
- **Spec-and-code drift detection** (`/audit-spec` reverse-engineers reality, surfaces deltas)
- **Natural-language interface** (you don't memorize slash commands — say what you want, the AI translates)

All of it filled in for **your** project's specifics via a one-time `/init` (5 questions in Simple mode, 16 in Pro mode).

---

## What it feels like in use

CCC-MAGI is **conversational, not CLI-driven**. You almost never type slash commands. Example dialogue:

```
You: "I want to build a user login feature"

MAGI Core: "Got it — I'll start Stage 1 (spec draft). First, let me
            paraphrase what I heard..."
            (silently invokes /feature-draft user-login)
            (walks paraphrase + 8 edge-case categories with live progress: 🔍 4/8)
            (writes docs/features/user-login.md)

MAGI Core: "✅ Spec is ready. You can:
              👉 'continue'  — I'll run the final audit
              👉 'show me'    — read the spec aloud
              👉 'change X'   — redo with new input
              👉 'drop it'    — abandon the feature"

You: "continue"

MAGI Core: "Calling MAGI Verdict (Codex) for cross-model audit..."
            (verdict PASS, risk 3)
            "Stage 2 done. Design the database (Stage 3) or jump straight
             to execution plan (Stage 4)?"

You: "continue"

MAGI Core: "This touches user tables, so Stage 3 first..."
            (writes migration, audited)
            "Stage 3 done. Move to execution plan?"

You: "continue"

MAGI Core: (writes per-file plan, surfaces in Claude Code's TodoWrite sidebar)
           "📋 Plan written — 8 files to change. Quick sanity check:
              👉 'OK' — start coding
              👉 'change X' — modify plan"

You: "OK"

MAGI Core: (Stage 5: implements, TodoWrite ticks live ▶→✅ per file)
           "✅ Stage 5 done. Move to tests?"

(...all the way through Stage 8 commit — never a slash command typed...)
```

**Natural-language trigger table**: see `CLAUDE.md § MAGI Core's Natural-Language Intent Translation` for the full "you say X → I do Y" cheat-sheet.
**Sole exception**: Stage 7 (CEO manual smoke test) is **never** auto-invoked — the constitution requires a human verify with their own hands.

---

## Key features (the complete current list)

### Workflow & quality gates

- **9-stage workflow**: draft → finalize → schema (optional) → plan → implement → test → smoke → commit → watch
- **3 lanes**: full (new feature) / stability-fix (bug fix with mandatory failing test) / trivial (<20 LOC)
- **Cross-model audit** at every gate (Claude ↔ Codex by default; single-model fresh-context fallback)
- **EARS notation** for functional requirements in the manager spec — directly mappable to test assertions
- **CEO smoke test** mandated by Constitution § 1.4 — AI cannot mark "done" without human verification
- **Spec-vs-reality drift detection** via `/audit-spec` (fresh-context subagent re-derives the spec from code)

### MAGI 7-position AI team

A clearly named team with clearly assigned authority:

- **MAGI Core** — orchestrator (your primary CLI). Talks to you, dispatches the workflow
- **MAGI Verdict** — cross-model auditor (default: Codex). Independent judgment authority — not under MAGI Core's chain of command
- **MAGI Planner / Programmer / Tester** — MAGI Core in matching workflow stage (mode switch, not separate processes)
- **MAGI Reviewer** — mechanical junior reviewers (backend / frontend / security / test-fixer). Cite rules, never invent
- **MAGI Archivist** — memory hook services (SessionStart / PreCompaction)

### 20 natural-language skills

You usually trigger these by saying what you want, not by typing slash commands:

| Skill | What it does |
|---|---|
| `/init` | First-time project configuration — Simple (5 questions, ~3 min) or Pro mode (16 questions, ~15 min) |
| `/feature-draft` | Stage 1 (new feature) — paraphrase intent + 8 edge-case categories + spec |
| `/audit-spec` | Stage 1 (audit existing code) — fresh subagent reverse-engineers as-built spec |
| `/spec-finalize` | Stage 2 — auditor cross-checks integration consistency |
| `/db-schema` | Stage 3 — schema design (skip if no backend) |
| `/execution-plan` | Stage 4 — per-file checklist + plan-time audit |
| `/implement` | Stage 5 — junior reviewers (mechanical) + cross-model audit |
| `/test-fix` | Stage 6 — test-fixer subagent + legitimacy audit |
| `/commit` | Stage 8 — Conventional Commits + plan-file deletion |
| `/next` | Workflow wayfinder — "where am I, what should I do?" |
| `/pickup` | Resume in-progress feature across sessions / devices / days |
| `/abandon` | Mark feature dead, archive checkpoint |
| `/handoff` | Generate rich 5-slot session snapshot at ~95% context budget |
| `/offload` | Spawn fresh-context subagent for a sub-task at ~75% budget |
| `/recall` | JIT memory fetch (manifest → body on demand) |
| `/remember` | Save an observation / decision / failure for future sessions |
| `/constitution-edit` | Edit Section 2 / Section 3 of constitution.md (with Sync Impact Report) |
| `/add-constitution-clause` | Add a project-wide red line to Section 3 |
| `/add-anti-flag` | Suppress an auditor false positive in AGENTS.md |
| `/uninstall` | Clean removal (with optional restore of prior harness) |

### Three-tier persistent memory

Cross-session memory survives `/clear`, compaction, multi-day breaks:

| Tier | Location | Purpose | At SessionStart |
|---|---|---|---|
| **1 — Working** | `.harness/state/scratchpad.md` | Current objective / last+next step / blockers (≤500 tokens, rewritten every turn) | ✅ Always read |
| **2 — Recall** | `.harness/memory/sessions/recall/*.jsonl` | Last 30 days of decisions / failures / snapshots | ✅ Manifest only (~500–1000 tokens), bodies on demand |
| **3 — Archive** | `.harness/memory/sessions/archive/<YYYY-MM>.jsonl` | Older entries, cold storage | ❌ Only via `/recall --deep <query>` |

Bounded SessionStart cost (~1–1.5K tokens regardless of project age). Hard caps prevent "fetch everything to be safe" drift.

### Locale-aware UX (i18n)

The harness detects your OS locale at session start. Internal files stay in English (token-efficient, model-friendly); user-facing prompts, menus, status reports translate automatically to `zh_CN` / `zh_TW` / `ja_JP` / `ko_KR` / other locales. Code identifiers, file paths, frontmatter never translated.

### Three-section constitution that survives harness upgrades

`constitution.md` has three layered sections:

- **Section 1 — Universal Core** (harness-guaranteed, never editable by `/constitution-edit`): cross-model audit, data ownership, CEO final authority, mandatory smoke test, spec-reality sync
- **Section 2 — Project Identity** (filled by `/init`): tech stack, scale target, primary concern, out-of-scope, edge-case categories, etc.
- **Section 3 — Project Red Lines** (grown over time via `/add-constitution-clause`): your accumulated absolute rules

When you upgrade CCC-MAGI, Section 1 may change (carefully, with migration notes); Section 2 and 3 are yours and are preserved verbatim.

### Tested CLI matrix

| Primary CLI | Auditor | Status |
|---|---|---|
| Claude Code | Codex CLI | ✅ **Tier 1** (end-to-end tested) |
| Codex CLI | Claude Code | ✅ **Tier 1** (roles reversed) |
| Single CLI (fallback) | Same model, fresh context | ⚠️ Tier 2 — works, but bias-cancellation weakens |
| Cursor / Cline / Aider / Gemini | Whatever's installed | ⚠️ Tier 3 — skills work as docs; hooks may not fire |

---

## Platform support

| Platform | Installer (`npx`) | CCC-MAGI hooks | Status |
|---|---|---|---|
| macOS (Apple Silicon / Intel) | ✅ native | ✅ all hooks fire | **Tier 1** — fully tested |
| Linux (Ubuntu / Debian / RHEL / Fedora / Arch) | ✅ native | ✅ all hooks fire | **Tier 1** — fully tested |
| Windows 10/11 + WSL2 (Ubuntu) | ✅ via WSL | ✅ all hooks fire | **Tier 1** — same as Linux |
| Windows 10/11 + Git for Windows, from Git Bash | ✅ native | ✅ all hooks fire | **Tier 1** — full support |
| Windows 10/11 + Git for Windows, from PowerShell/cmd | ✅ auto-detects Git Bash (v0.10.2+) | ⚠️ hooks need Claude Code launched from Git Bash | **Tier 2** — install works, hooks limited |
| Windows 10/11 without Git for Windows | ❌ installer guides you to install it | ❌ | **Tier 3** — `winget install Git.Git` and retry |

**Recommendation by user type:**

- **macOS / Linux**: just install and go.
- **Windows (no Linux background)**: install Git for Windows (free, includes bash) — `winget install Git.Git`. Then you can run `npx create-ccc-magi@latest` from PowerShell, cmd, OR Git Bash — bash is auto-discovered. For full hooks support, launch Claude Code from Git Bash.
- **Windows with Linux comfort**: WSL2 + Ubuntu — `wsl --install -d Ubuntu`. Full Linux parity.

CCC-MAGI inherits its platform matrix from Claude Code itself. Anywhere Claude Code runs, CCC-MAGI can run, provided a POSIX shell is reachable for hook execution.

---

## Step 0: Install prerequisites (5-10 min, one-time)

Before you run `npx create-ccc-magi@latest`, install these on your machine. **The installer fails fast if any hard prereq is missing** — better to install them up front than to hit errors mid-install.

### What you need

| Tool | Why | Hard prereq? |
|---|---|---|
| **git** | clone CCC-MAGI from GitHub; harness uses git for checkpoints | ✅ required |
| **bash 3.2+** | run install-into.sh and harness hooks | ✅ required (macOS/Linux native; Windows via Git for Windows) |
| **jq** | JSON parsing in hooks + auditor verdict handling | ✅ required (`install-into.sh` fails fast if missing) |
| **Node.js ≥ 18** | for `npx` itself | ✅ required |
| **Claude Code** OR **Codex CLI** | the AI you'll actually talk to | ✅ at least one (both = Tier 1 cross-model audit) |

### macOS

```bash
# 1. Homebrew (skip if you already have it)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. git (most Macs have it; if not, brew fixes it)
brew install git

# 3. jq + Node.js
brew install jq node

# 4. Claude Code (primary CLI)
npm install -g @anthropic-ai/claude-code

# 5. Codex CLI (recommended auditor for Tier 1 cross-model audit)
npm install -g @openai/codex
```

### Windows 10/11 (PowerShell)

```powershell
# 1. Git for Windows (includes bash that v0.10.2+ installer auto-discovers)
winget install Git.Git

# 2. jq
winget install jqlang.jq

# 3. Node.js LTS
winget install OpenJS.NodeJS.LTS

# 4. Claude Code
npm install -g @anthropic-ai/claude-code

# 5. Codex CLI (optional but recommended)
npm install -g @openai/codex
```

**Important**: after install, **close and re-open PowerShell** so the new PATH entries take effect.

### Linux (Ubuntu / Debian)

```bash
sudo apt update
sudo apt install -y git jq nodejs npm
sudo npm install -g @anthropic-ai/claude-code
sudo npm install -g @openai/codex   # optional
```

For RHEL / Fedora / Arch: swap `apt install` for `yum install` / `dnf install` / `pacman -S` accordingly.

### Mainland China tips

- **npm slow / timeout?** Switch to Taobao mirror:
  ```bash
  npm config set registry https://registry.npmmirror.com
  ```
- **GitHub clone slow / timing out?** You'll likely need a VPN. CCC-MAGI's installer clones from GitHub, so reliable GitHub access is required.
- **Claude Code / Codex CLI login** may require VPN depending on your account type / region.

### Verify everything is ready

```bash
git --version       # any
jq --version        # 1.5+
node --version      # v18+
claude --version    # any (if Claude Code installed)
codex --version     # any (if Codex CLI installed)
```

If all print versions without "command not found", you're ready for `npx create-ccc-magi@latest`.

> After install, the harness's Phase 1 environment check (`.harness/scripts/env-check.sh`) runs on your first chat with Claude Code, confirming everything is wired up correctly.

---

## Quick start

### Path A — Via npx installer (recommended)

```bash
cd /path/to/your/project
npx create-ccc-magi@latest
```

This downloads the harness, places files in canonical locations, sets script permissions, and tells you to open your AI CLI. Use `--dry-run` to preview without writing anything, or `--force` to overwrite existing CCC-MAGI files.

Then open Claude Code:

```bash
claude
```

Claude reads `CLAUDE.md`, sees the **Bootstrap Status Check** block at the top, sees `.harness/state/install.json` doesn't exist → reads `.harness/scripts/standalone-bootstrap.md` → walks you through detection of any existing harness configs + 3-option menu + `/init` configuration.

### Path B — Manual install (advanced)

If you need full control over file placement:

```bash
cd /path/to/your/project
git clone https://github.com/Ericcccccc777/CCC-MAGI.git .ccc-magi-temp
cd .ccc-magi-temp

# Move root files
mv constitution.md CLAUDE.md AGENTS.md ../

# Move directories to .harness/ subpaths
mkdir -p ../.harness
mv skills agents scripts ../.harness/

# Move CLI configs
mkdir -p ../.claude ../.codex
mv cli-configs/claude/settings.json ../.claude/
mv cli-configs/codex/config.toml cli-configs/codex/hooks.json ../.codex/

# Move docs and metadata
mv docs-harness ../
mv cli-configs/README.md ../docs-harness/cli-configs-README.md
mv .gitignore ../   # if you don't already have one
mv README.md ../CCC_MAGI_README.md
mv LICENSE ../CCC_MAGI_LICENSE

# Clean up + permissions
cd ..
rm -rf .ccc-magi-temp
chmod +x .harness/scripts/*.sh
```

Then open Claude Code as in Path A.

> **Strongly recommend Path A unless you have a specific reason.** The npx installer does exactly this layout for you and adds safety checks.

### Path C — Via CCC (Claude Code Controller)

If you use CCC as your desktop session manager:

1. Open CCC, "new session", select your project folder
2. Click the "Harness" button in the session view
3. Click "Environment Detection" → confirm token usage warning
4. CCC handles everything (terminal spawn + driver injection + git pull + `/init` invocation)

See `docs-harness/ccc-step1-driver-template.md` for the CCC integration spec.

### Path D — Via Anthropic Plugin Marketplace (when available)

CCC-MAGI includes a `.claude-plugin/plugin.json` manifest. Once submitted to and accepted by the Anthropic `claude-community` marketplace:

```bash
/plugin marketplace add anthropics/claude-plugins-community
/plugin install @claude-community/ccc-magi
```

**Note**: plugin-only installation ships skills + commands; the full project-level harness (constitution.md, `.harness/state/`, slot rendering) still requires `install-into.sh` or `npx create-ccc-magi`.

---

## Team collaboration & git policy

CCC-MAGI ships a careful split between team-shared and personal files. The shipped `.gitignore` already encodes this — you usually don't have to think about it.

**Committed (visible in repo, every teammate sees the same):**

- `constitution.md` — project identity
- `CLAUDE.md` + `AGENTS.md` — workflow + AI tool context
- `.harness/skills/` + `.harness/agents/` + `.harness/scripts/` — the harness machinery
- `.harness/state/install.json` — answers to the onboarding questions
- `.harness/memory/conventions.md` — long-form project conventions
- `.claude/settings.json` + `.codex/config.toml` — hook wiring

**Gitignored (yours alone, never shared):**

- `.harness/memory/observations.jsonl` + `.harness/memory/decision-log.md` — your AI session notes
- `.harness/audits/` + `.harness/state/auditor-approvals/` — runtime verdict logs
- `.harness/state/workflow-checkpoints/` — your session progress cards
- `.harness/state/shipped-hashes.json` — install-time hash registry

**Why this split** — Cline / Spec-Kit / BMAD / Continue / Roo all commit their harness files wholesale, leading to merge conflicts every time someone re-installs at a different version. Aider gitignores everything, losing team alignment. CCC-MAGI's middle path: commit the **identity + tools + rules**, gitignore the **session + verdicts + progress**.

---

## What CCC-MAGI is NOT

- **Not a build system.** It orchestrates conversation, audit, and commit gates. It does not replace `npm run build`, `make`, or your CI pipeline.
- **Not a project boilerplate.** Tech stack, file structure, and code conventions are yours.
- **Not an enterprise governance suite (yet).** No RBAC, no audit-log signing, no compliance attestations. Those are on the enterprise roadmap, not in v0.9.
- **Not a substitute for engineering judgment.** Every rule (except 5 Universal Core items) can be overridden by you with reasoning recorded.

---

## Documentation map

| File | Purpose |
|---|---|
| `README.md` (this file) | What CCC-MAGI is, who it's for, how to install |
| `constitution.md` | Project identity (filled by `/init`) + 5 universal core items |
| `CLAUDE.md` | Workflow rules, lane definitions, doc-in-sync, tool map |
| `AGENTS.md` | Universal project context (AGENTS.md ecosystem standard) + auditor (MAGI) brief + anti-flag rules |
| `docs-harness/README.md` | Index of the framework's own design docs |
| `docs-harness/design-spec.md` | Architectural rationale |
| `docs-harness/adoption-playbook.md` | Step-by-step install guide (greenfield + brownfield + standalone + CCC paths) |
| `docs-harness/context-architecture-v2.md` | 3-tier memory + budget management design |
| `docs-harness/memory-layer.md` | Persistent memory implementation |
| `docs-harness/retrospective-notes.md` | Generalized LLM-workflow patterns worth carrying forward |
| `docs-harness/ccc-step1-driver-template.md` | Integration template for the CCC Step 1 driver |

---

## Roadmap

### v0.9 (current — dogfooded)

- All 20 skills shipped
- 3-tier memory architecture (Tier 1 scratchpad + Tier 2 recall + Tier 3 archive)
- MAGI 7-position team
- Simple / Pro onboarding modes
- Session resume via workflow checkpoints
- Claude Code + Codex CLI Tier-1 tested
- Anthropic plugin marketplace manifest ready (submission pending)

### v1.0 (next — small-team collaboration polish)

- Team-aware decision log (multi-author attribution)
- Conflict-aware checkpoint merging (when two teammates resume the same feature on different machines)
- Per-teammate audit-history visibility
- Shared "team convention" memory tier (cross-developer recall)
- Team onboarding flow (`/init --join-team` reads existing project constitution and skips identity questions)

### v1.x — enterprise multi-user (in development)

- RBAC for skill invocation (e.g., only Tech Leads can run `/constitution-edit`)
- Signed audit logs (tamper-evident verdict history)
- Compliance attestation hooks (SOC 2 / ISO 27001 friendly)
- Centralized harness-version policy (org-wide pinning, controlled rollout)
- Observability layer: token / cost / gate-pass-rate dashboard
- Cross-project memory federation (with project-scoped redaction)

### Beyond

- Parallel agents + worktree isolation
- Tech-stack starter presets (Next.js / Django / Go / Rust / Swift / Kotlin)
- AGENTS.md root-of-truth mode (Linux Foundation standard compat)
- Plugin marketplace integration (post-acceptance)

---

## Status

**v0.9.0** — feature-complete MVP, dogfooded internally, undergoing pre-1.0 stabilization. Standalone install path fully functional. Tested end-to-end on macOS + Claude Code + Codex CLI. Suitable for solo and small-team adoption; enterprise multi-user features are in the v1.x track.

---

## License

Apache License 2.0 — see [`LICENSE`](./LICENSE).

---

## Contributing

This is a young project. PRs welcome especially for:

- Tech-stack-specific anti-flag rule starter packs (Next.js, Django, Go, Rust, Swift, Kotlin)
- Junior reviewer plugin examples for non-frontend domains (CI/CD, IaC, infrastructure)
- CCC bundled Step 1 driver implementation (CCC team)
- Translation of user-facing prompts beyond `zh-Hans` / `en` / `ko` / `ja`
- Tested adapters for Cursor / Cline / Aider / Gemini CLI

Repo: <https://github.com/Ericcccccc777/CCC-MAGI>

---
---

# CCC-MAGI (中文版)

> **一个让 vibe coding 变成可维护项目的 AI 编程框架。**
> 每次改动跨模型审计 · 大白话需求文档 · 持久化跨会话记忆 · 7 位 MAGI AI 团队 · 20 个自然语言技能 · 任意代码仓库即装即用。

**切换语言**: [English](#ccc-magi) · **简体中文** (当前)

---

## 一段话讲清楚 CCC-MAGI 是什么

让 AI 写代码很爽 —— 5 分钟出 1000 行看着挺像样的东西。三周后你已经分不清哪些是认真设计的、哪些是猜的；分不清你脑子里的需求还和硬盘上的代码对得上；分不清哪个"修复"真的修复了。**CCC-MAGI 就是来解决这件事的框架。** 它装进你的项目里，跟你的 AI CLI（Claude Code、Codex 等）对话，把每一次改动强制走完整流程：写大白话需求 → 让**不同模型**审一遍 → 列文件计划 → 实现 → 跑测试 → 人肉冒烟测试 → 提交。一位资深工程师该有的纪律，不需要你记 —— 框架机械地执行。

不管你是搭第一个副业项目的新手、独立专业开发者、还是 3-5 人的小团队希望多个贡献者的 AI 代码别互相打架，工作方式完全一样。

---

## 谁应该用 CCC-MAGI

| 如果你是... | CCC-MAGI 提供给你 |
|---|---|
| **Vibe coding 新手** —— 上个月刚发现 Claude Code，项目开始像一栋鬼屋 | 安全网。代码之前先有需求文档；每次改动有第二个 AI 复审；不会一不小心提交 1000 行没冒烟测试的"优化" |
| **想做稳定项目的创作者** —— 读得懂代码但不是全职工程师 | 不依赖你记忆的工程纪律。Hook 自动触发；宪法在 compaction 后依然守住项目身份 |
| **个人专业开发者** —— 靠出货吃饭，想让 AI 放大你而不是埋葬你 | 跨模型审计（Claude × Codex）抵消单模型偏见。持久化记忆 = "上个月 auth 模块我们怎么定的"是一个问题，不是一次代码考古 |
| **2-5 人的小团队搞 vibe coding** —— 多个贡献者，共享代码库，到处都是 AI | 一份共享宪法，所有人的 AI 都先读它。约定保持一致。Bug 修复必须先有失败测试。计划文件在提交时自动删除 |
| **已经长出规模的小项目** —— 有能跑的代码，但没需求纪律 | `/audit-spec` 反向把当前代码逆推成需求文档，然后摆出"你以为它做什么" vs "它实际做什么"的差异。Brownfield 上手是一等公民流程，不是事后补丁 |

只要你属于以上任一类，你就是目标人群。

---

## 为什么有 CCC-MAGI

主流 AI 编程框架（BMAD、SpecKit、OpenSpec 等）都很好，但**和项目深度绑定** —— BMAD 假设 React Native；SpecKit 假设你用 GitHub Issues。这些约定搬不进 Python 后端或 Swift app。

CCC-MAGI 抽取的是**通用机制** —— 跟语言、框架、团队规模无关的那部分 —— 并以 slot 驱动模板的形式打包：

- **跨模型审计**作为承重的不变量（不是可选层）
- **两文件需求模型**（CEO 域用大白话；管理者域用 EARS 语法 + 技术细节）
- **三 lane 工作流**（full / stability-fix / trivial —— 同一流程，不同 gate 强度）
- **三层持久化记忆**（工作笔记 / 30 天 recall / 归档）—— 跨 `/clear`、compaction、几天休息后依然在
- **MAGI 7 位 AI 团队**（Core / Verdict / Planner / Programmer / Tester / Reviewer / Archivist）—— 角色清楚、职权清楚
- **机械化的初级评审**（规则引用源文档，从不自创）
- **人类冒烟测试作为契约**（AI 说的"完成"不算 —— 宪法 § 1.4）
- **Spec / 代码漂移检测**（`/audit-spec` 反向把现实推回需求，呈现 delta）
- **自然语言入口**（不用记斜杠命令 —— 说你想要啥，AI 自己翻译）

所有这些通过一次性 `/init` 填入**你**项目的具体值（Simple 模式 5 个问题，Pro 模式 16 个问题）。

---

## 实际使用体感

CCC-MAGI **以对话为主，不是命令行式的**。你几乎不需要敲斜杠命令。示例对话：

```
你: 「我想做一个用户登录功能」

MAGI Core: 「好的，我来启动 Stage 1（起草需求）。先复述我理解到的...」
            (静默调用 /feature-draft user-login)
            (走完 paraphrase + 8 类 edge case，实时进度：🔍 4/8)
            (写出 docs/features/user-login.md)

MAGI Core: 「✅ 需求写好了。可以做：
              👉 「继续」 —— 我做最终审查
              👉 「看一下」 —— 把需求念给你听
              👉 「改一下 X」 —— 重做
              👉 「放弃」」

你: 「继续」

MAGI Core: 「调 MAGI Verdict（Codex）做跨模型审计...」
            (verdict PASS, risk 3)
            「Stage 2 完成。要做数据库设计（Stage 3）还是直接做执行计划（Stage 4）？」

你: 「继续」

MAGI Core: 「这个功能涉及用户表，先做 Stage 3...」
            (写出 migration，被审计通过)
            「Stage 3 完成。要继续做执行计划吗？」

你: 「继续」

MAGI Core: (写出每文件计划，在 Claude Code 的 TodoWrite 侧栏显示)
           「📋 计划写好了，要改 8 个文件。快速过一下：
              👉 「OK」 —— 开始编程
              👉 「改一下 X」 —— 修改计划」

你: 「OK」

MAGI Core: (Stage 5：实现，TodoWrite 逐文件 ▶ → ✅)
           「✅ Stage 5 完成。要继续做测试吗？」

（...一直到 Stage 8 commit，全程没敲过一个斜杠命令...）
```

**自然语言触发器速查表**：见 `CLAUDE.md § MAGI Core's Natural-Language Intent Translation`。
**唯一例外**：Stage 7（CEO 手工冒烟测试）**永远不会**被 AI 自动跑 —— 宪法要求人类亲自验证。

---

## 核心功能（完整当前列表）

### 工作流 & 质量 gate

- **9 个 stage**：起草 → 终稿 → 数据库（可选）→ 计划 → 实现 → 测试 → 冒烟 → 提交 → 观察
- **3 个 lane**：full（新功能）/ stability-fix（必须先写失败测试的 bug 修）/ trivial（< 20 行）
- **跨模型审计**在每个 gate 触发（默认 Claude ↔ Codex；单模型 fresh-context 兜底）
- **EARS 语法**用于管理者文档的功能需求 —— 可直接映射成测试断言
- **CEO 冒烟测试**由宪法 § 1.4 强制 —— AI 不能在没有人类验证的情况下标记"完成"
- **Spec vs 现实漂移检测**通过 `/audit-spec`（fresh-context 子 agent 从代码反推需求）

### MAGI 7 位 AI 团队

清晰命名、清晰职权的团队：

- **MAGI Core** —— 编排者（你的主 CLI）。跟你对话，调度工作流
- **MAGI Verdict** —— 跨模型审计员（默认 Codex）。独立判决权 —— 不在 MAGI Core 指挥链下
- **MAGI Planner / Programmer / Tester** —— 对应 stage 的 MAGI Core（模式切换，不是独立进程）
- **MAGI Reviewer** —— 机械化的初级评审（backend / frontend / security / test-fixer）。引规则，不自创
- **MAGI Archivist** —— 记忆 hook 服务（SessionStart / PreCompaction）

### 20 个自然语言 skill

通常你只说意图，不用敲斜杠：

| Skill | 作用 |
|---|---|
| `/init` | 首次配置 —— Simple（5 问，约 3 分钟）或 Pro 模式（16 问，约 15 分钟） |
| `/feature-draft` | Stage 1（新功能）—— paraphrase + 8 类 edge case + 写需求 |
| `/audit-spec` | Stage 1（审现有代码）—— fresh-context 子 agent 反推 as-built 需求 |
| `/spec-finalize` | Stage 2 —— auditor 交叉检查集成一致性 |
| `/db-schema` | Stage 3 —— 数据库设计（无后端跳过） |
| `/execution-plan` | Stage 4 —— 每文件 checklist + 计划阶段审计 |
| `/implement` | Stage 5 —— 初级评审（机械化）+ 跨模型审计 |
| `/test-fix` | Stage 6 —— test-fixer 子 agent + 合法性审计 |
| `/commit` | Stage 8 —— Conventional Commits + 计划文件删除 |
| `/next` | 工作流定位器 —— "我在哪？下一步该干啥？" |
| `/pickup` | 跨 session / 跨设备 / 跨天接续在进 feature |
| `/abandon` | 标记 feature 死亡，归档 checkpoint |
| `/handoff` | 约 95% context 预算时生成丰富的 5 槽 session 快照 |
| `/offload` | 约 75% 预算时 spawn fresh-context 子 agent 做子任务 |
| `/recall` | 按需取记忆（manifest → 按需取 body） |
| `/remember` | 保存 observation / 决策 / 失败给未来 session |
| `/constitution-edit` | 编辑 constitution.md 的 Section 2 / 3（带 Sync Impact Report） |
| `/add-constitution-clause` | 给 Section 3 加项目级红线 |
| `/add-anti-flag` | 抑制 auditor 假阳性（写进 AGENTS.md） |
| `/uninstall` | 干净卸载（可选恢复先前 harness） |

### 三层持久化记忆

跨 session 记忆能扛 `/clear`、compaction、多天休息：

| 层级 | 位置 | 用途 | SessionStart 加载 |
|---|---|---|---|
| **1 — 工作** | `.harness/state/scratchpad.md` | 当前目标 / 上一步 + 下一步 / 阻塞（≤500 token，每轮重写） | ✅ 始终读取 |
| **2 — Recall** | `.harness/memory/sessions/recall/*.jsonl` | 最近 30 天的决策 / 失败 / 快照 | ✅ 仅 manifest（约 500-1000 token），body 按需 |
| **3 — Archive** | `.harness/memory/sessions/archive/<YYYY-MM>.jsonl` | 更早的条目，冷存储 | ❌ 仅通过 `/recall --deep <query>` |

SessionStart 成本有界（约 1-1.5K token，不随项目年龄增长）。硬上限阻止 "保险起见拉全部" 的漂移。

### Locale 感知 UX（i18n）

框架在 session 启动时检测 OS locale。内部文件保持英文（token 友好、模型友好）；用户面对的提示、菜单、状态报告自动翻译到 `zh_CN` / `zh_TW` / `ja_JP` / `ko_KR` / 其他 locale。代码标识符、文件路径、frontmatter 永不翻译。

### 三段式宪法（跨 harness 升级保留）

`constitution.md` 三层结构：

- **Section 1 —— 通用核心**（harness 保证，`/constitution-edit` 不可改）：跨模型审计、数据归属、CEO 最终权威、强制冒烟测试、spec/现实同步
- **Section 2 —— 项目身份**（`/init` 填）：技术栈、规模目标、首要关注点、out-of-scope、edge case 分类等
- **Section 3 —— 项目红线**（通过 `/add-constitution-clause` 增长）：你逐步累积的绝对规则

升级 CCC-MAGI 时，Section 1 可能变（小心带迁移说明）；Section 2 和 3 是你的，原样保留。

### 已测 CLI 矩阵

| 主 CLI | 审计员 | 状态 |
|---|---|---|
| Claude Code | Codex CLI | ✅ **Tier 1**（端到端测试） |
| Codex CLI | Claude Code | ✅ **Tier 1**（角色互换） |
| 单 CLI 兜底 | 同模型 fresh context | ⚠️ Tier 2 —— 能跑，但去偏弱 |
| Cursor / Cline / Aider / Gemini | 看本机有啥 | ⚠️ Tier 3 —— skill 当文档用；hook 可能不触发 |

---

## 平台支持

| 平台 | 安装器（`npx`） | CCC-MAGI hook | 状态 |
|---|---|---|---|
| macOS（Apple Silicon / Intel） | ✅ 原生 | ✅ 所有 hook 触发 | **Tier 1** —— 充分测试 |
| Linux（Ubuntu / Debian / RHEL / Fedora / Arch） | ✅ 原生 | ✅ 所有 hook 触发 | **Tier 1** —— 充分测试 |
| Windows 10/11 + WSL2（Ubuntu） | ✅ 通过 WSL | ✅ 所有 hook 触发 | **Tier 1** —— 同 Linux |
| Windows 10/11 + Git for Windows，从 Git Bash 启动 | ✅ 原生 | ✅ 所有 hook 触发 | **Tier 1** —— 完整支持 |
| Windows 10/11 + Git for Windows，从 PowerShell/cmd 启动 | ✅ 自动检测 Git Bash（v0.10.2+） | ⚠️ hook 需从 Git Bash 启动 Claude Code | **Tier 2** —— 装能装，hook 受限 |
| Windows 10/11 未装 Git for Windows | ❌ 安装器会引导你装 | ❌ | **Tier 3** —— `winget install Git.Git` 后重试 |

**按用户类型推荐：**

- **macOS / Linux**：装上就用
- **Windows（无 Linux 背景）**：装 Git for Windows（免费，含 bash）—— `winget install Git.Git`。装好后 PowerShell / cmd / Git Bash 都能跑 `npx create-ccc-magi@latest`，bash 自动发现。如果要 hook 完整工作，从 Git Bash 启动 Claude Code
- **Windows（有 Linux 经验）**：WSL2 + Ubuntu —— `wsl --install -d Ubuntu`，完整 Linux parity

CCC-MAGI 继承 Claude Code 的平台矩阵。只要 Claude Code 能跑、有可达的 POSIX shell，CCC-MAGI 就能跑。

---

## 第 0 步：环境准备（5-10 分钟，一次性）

在跑 `npx create-ccc-magi@latest` **之前**，先把下面这些装好。**任何硬依赖缺失，installer 会立刻报错退出** —— 提前装好比中途撞错好得多。

### 你需要装的东西

| 工具 | 用途 | 硬依赖？ |
|---|---|---|
| **git** | 从 GitHub 拉 CCC-MAGI；harness 用 git 做 checkpoint | ✅ 必须 |
| **bash 3.2+** | 跑 install-into.sh + harness hooks | ✅ 必须（macOS/Linux 原生；Windows 装 Git for Windows 自带） |
| **jq** | hook 里解析 JSON + 处理审计 verdict | ✅ 必须（`install-into.sh` 缺它直接报错退出） |
| **Node.js ≥ 18** | `npx` 自己需要 | ✅ 必须 |
| **Claude Code** 或 **Codex CLI** | 你实际对话的 AI | ✅ 至少装一个（两个都装 = Tier 1 跨模型审计） |

### macOS

```bash
# 1. Homebrew（已装可跳过）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. git（多数 Mac 已有；没有的话 brew 装）
brew install git

# 3. jq + Node.js
brew install jq node

# 4. Claude Code（主 CLI）
npm install -g @anthropic-ai/claude-code

# 5. Codex CLI（推荐 —— 跟 Claude 配对做跨模型审计 Tier 1）
npm install -g @openai/codex
```

### Windows 10/11（PowerShell 跑）

```powershell
# 1. Git for Windows（含 bash，v0.10.2+ installer 会自动找到）
winget install Git.Git

# 2. jq
winget install jqlang.jq

# 3. Node.js LTS
winget install OpenJS.NodeJS.LTS

# 4. Claude Code
npm install -g @anthropic-ai/claude-code

# 5. Codex CLI（可选但推荐）
npm install -g @openai/codex
```

**重要**：装完后**关掉 PowerShell 再打开**，新的 PATH 才生效。

### Linux（Ubuntu / Debian）

```bash
sudo apt update
sudo apt install -y git jq nodejs npm
sudo npm install -g @anthropic-ai/claude-code
sudo npm install -g @openai/codex   # 可选
```

RHEL / Fedora / Arch：把 `apt install` 换成 `yum install` / `dnf install` / `pacman -S`。

### 中国大陆用户提示

- **npm 慢或超时？** 切换淘宝镜像：
  ```bash
  npm config set registry https://registry.npmmirror.com
  ```
- **GitHub clone 慢或超时？** 大概率需要 VPN。CCC-MAGI 的 installer 是从 GitHub clone 的，所以必须能稳定访问 GitHub
- **Claude Code / Codex CLI 登录**可能需要 VPN，看你账号类型 / 地区

### 验证准备就绪

```bash
git --version       # 任何版本
jq --version        # 1.5+
node --version      # v18+
claude --version    # 任何（如果装了 Claude Code）
codex --version     # 任何（如果装了 Codex CLI）
```

如果上面 5 条都正常打印版本（没有 "command not found"），就可以跑 `npx create-ccc-magi@latest` 了。

> 装完 CCC-MAGI 后，第一次跟 Claude Code 对话时，harness 的 Phase 1 环境检查（`.harness/scripts/env-check.sh`）会自动跑一遍，确认所有依赖都正确连上。

---

## 快速开始

### 路径 A —— 通过 npx 安装器（推荐）

```bash
cd /path/to/your/project
npx create-ccc-magi@latest
```

会下载框架、把文件放到规范位置、设置脚本权限、提示你打开 AI CLI。`--dry-run` 预览；`--force` 覆盖现有 CCC-MAGI 文件。

然后打开 Claude Code：

```bash
claude
```

Claude 读 `CLAUDE.md`，看到顶部的 **Bootstrap Status Check** 块，发现 `.harness/state/install.json` 不存在 → 读 `.harness/scripts/standalone-bootstrap.md` → 引导你检测现有 harness 配置 + 3 选项菜单 + `/init` 配置。

### 路径 B —— 手动安装（进阶）

需要完全控制文件位置时：

```bash
cd /path/to/your/project
git clone https://github.com/Ericcccccc777/CCC-MAGI.git .ccc-magi-temp
cd .ccc-magi-temp

# 顶层文件
mv constitution.md CLAUDE.md AGENTS.md ../

# 目录到 .harness/
mkdir -p ../.harness
mv skills agents scripts ../.harness/

# CLI 配置
mkdir -p ../.claude ../.codex
mv cli-configs/claude/settings.json ../.claude/
mv cli-configs/codex/config.toml cli-configs/codex/hooks.json ../.codex/

# 文档和元数据
mv docs-harness ../
mv cli-configs/README.md ../docs-harness/cli-configs-README.md
mv .gitignore ../   # 如果已有自己的，需手动合并
mv README.md ../CCC_MAGI_README.md
mv LICENSE ../CCC_MAGI_LICENSE

# 清理 + 权限
cd ..
rm -rf .ccc-magi-temp
chmod +x .harness/scripts/*.sh
```

然后按路径 A 打开 Claude Code。

> **强烈建议用路径 A，除非有特殊原因**。npx 安装器做的就是上面这套布局，并加了安全检查。

### 路径 C —— 通过 CCC（Claude Code Controller）

如果你用 CCC 作为桌面 session 管理器：

1. 打开 CCC，"new session"，选你的项目文件夹
2. session 视图里点 "Harness" 按钮
3. 点 "Environment Detection" → 确认 token 使用警告
4. CCC 全权处理（终端 spawn + driver 注入 + git pull + `/init` 调用）

集成规范见 `docs-harness/ccc-step1-driver-template.md`。

### 路径 D —— 通过 Anthropic Plugin Marketplace（可用时）

CCC-MAGI 自带 `.claude-plugin/plugin.json` manifest。一旦被 Anthropic `claude-community` marketplace 接受：

```bash
/plugin marketplace add anthropics/claude-plugins-community
/plugin install @claude-community/ccc-magi
```

**注意**：plugin-only 安装只交付 skill + command；完整的项目级 harness（constitution.md、`.harness/state/`、slot 渲染）仍需 `install-into.sh` 或 `npx create-ccc-magi`。

---

## 团队协作 & git 策略

CCC-MAGI 仔细划分了 team-shared 和个人文件。出厂的 `.gitignore` 已编码这套策略 —— 你通常不用想。

**进 git（仓库里可见，所有队友看到一样）：**

- `constitution.md` —— 项目身份
- `CLAUDE.md` + `AGENTS.md` —— 工作流 + AI 工具 context
- `.harness/skills/` + `.harness/agents/` + `.harness/scripts/` —— 框架机器
- `.harness/state/install.json` —— 入职问题的答案
- `.harness/memory/conventions.md` —— 长文项目约定
- `.claude/settings.json` + `.codex/config.toml` —— hook 接线

**.gitignore（只属于你，从不共享）：**

- `.harness/memory/observations.jsonl` + `.harness/memory/decision-log.md` —— 你的 AI session 笔记
- `.harness/audits/` + `.harness/state/auditor-approvals/` —— 运行时审计判决日志
- `.harness/state/workflow-checkpoints/` —— 你的 session 进度卡
- `.harness/state/shipped-hashes.json` —— 安装时哈希注册表

**为何如此划分** —— Cline / Spec-Kit / BMAD / Continue / Roo 把 harness 文件一股脑全提交，导致每次有人在不同版本重装就出 merge 冲突。Aider 全 gitignore，丢了团队对齐。CCC-MAGI 走中间路：**身份 + 工具 + 规则**进 git，**session + 判决 + 进度**进 gitignore。

---

## CCC-MAGI 不是什么

- **不是构建系统**。它编排对话、审计、提交 gate；不替代 `npm run build`、`make` 或 CI pipeline
- **不是项目脚手架**。技术栈、文件结构、代码约定是你的
- **暂时不是企业治理套件**。无 RBAC、无审计日志签名、无合规证明 —— 这些在企业 roadmap 上，v0.9 没有
- **不是工程判断的替代品**。除 5 条 Universal Core 外，所有规则都可被你 override（带理由记录）

---

## 文档地图

| 文件 | 用途 |
|---|---|
| `README.md`（本文） | CCC-MAGI 是什么、谁该用、怎么装 |
| `constitution.md` | 项目身份（`/init` 填）+ 5 条通用核心 |
| `CLAUDE.md` | 工作流规则、lane 定义、doc 同步、工具地图 |
| `AGENTS.md` | 通用项目 context（AGENTS.md 生态标准）+ auditor (MAGI) 简报 + 反假阳性规则 |
| `docs-harness/README.md` | 框架自身设计文档索引 |
| `docs-harness/design-spec.md` | 架构理由 |
| `docs-harness/adoption-playbook.md` | 安装详细流程（greenfield + brownfield + standalone + CCC 各路径） |
| `docs-harness/context-architecture-v2.md` | 三层记忆 + 预算管理设计 |
| `docs-harness/memory-layer.md` | 持久化记忆实现 |
| `docs-harness/retrospective-notes.md` | 可复用的 LLM 工作流通用模式 |
| `docs-harness/ccc-step1-driver-template.md` | CCC Step 1 driver 集成模板 |

---

## Roadmap

### v0.9（当前 —— 已 dogfood）

- 20 个 skill 全部交付
- 三层记忆架构（Tier 1 scratchpad + Tier 2 recall + Tier 3 archive）
- MAGI 7 位团队
- Simple / Pro 入职模式
- 通过 workflow checkpoint 实现 session 恢复
- Claude Code + Codex CLI Tier-1 测试
- Anthropic plugin marketplace manifest 就绪（待提交）

### v1.0（下一版 —— 小团队协作优化）

- 团队感知决策日志（多作者归属）
- 冲突感知的 checkpoint 合并（两个队友在不同机器接同一 feature 时）
- 队友间审计历史可见性
- 共享"团队约定"记忆层（跨开发者 recall）
- 团队入职流程（`/init --join-team` 读已有项目宪法，跳过身份问题）

### v1.x —— 企业多人（开发中）

- 技能调用 RBAC（例如只有 Tech Lead 能跑 `/constitution-edit`）
- 签名审计日志（防篡改的判决历史）
- 合规证明 hook（SOC 2 / ISO 27001 友好）
- 集中化 harness 版本策略（组织级 pin、受控发布）
- 可观测性层：token / 成本 / gate 通过率 dashboard
- 跨项目记忆联邦（带项目级脱敏）

### 更远

- 并行 agent + worktree 隔离
- 技术栈起步预设（Next.js / Django / Go / Rust / Swift / Kotlin）
- AGENTS.md root-of-truth 模式（Linux Foundation 标准兼容）
- Plugin marketplace 集成（被接受后）

---

## 当前状态

**v0.9.0** —— 功能完整的 MVP，内部 dogfooded，正在 1.0 前稳定化。Standalone 安装路径完全可用。在 macOS + Claude Code + Codex CLI 上端到端测试。适合个人和小团队采用；企业多人功能在 v1.x 轨道上。

---

## License

Apache License 2.0 —— 见 [`LICENSE`](./LICENSE)。

---

## 贡献

这是一个年轻项目。特别欢迎 PR：

- 技术栈相关的反假阳性规则起步包（Next.js、Django、Go、Rust、Swift、Kotlin）
- 非前端领域的初级评审插件示例（CI/CD、IaC、基础设施）
- CCC 捆绑的 Step 1 driver 实现（CCC 团队）
- `zh-Hans` / `en` / `ko` / `ja` 以外的用户面向提示翻译
- Cursor / Cline / Aider / Gemini CLI 的测试适配器

仓库：<https://github.com/Ericcccccc777/CCC-MAGI>
