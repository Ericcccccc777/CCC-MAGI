---
name: init
description: |
  Project configuration. Fills constitution.md, scaffolds .harness/ + .claude/ + .codex/, writes install.json (the "configured" marker). Supports two onboarding modes:
  - **Simple** (5 questions, ~3 min) — defaults for 11 slots; great for solo / hackathon / side project
  - **Pro** (16 questions, ~15 min) — full identity contract for serious + team projects
  
  After description is captured, runs a **suggestion engine** that pre-fills sensible defaults for remaining slots based on what the user just described.
  
  Trigger when the user:
  - Invokes /init, /init --simple, /init --pro, /init --upgrade-to-pro
  - Says "set up the harness" / "配置 CCC-MAGI" / "harness 설치"
  - Says "I want to upgrade to pro mode" / "升级到专业版" / "切到专业模式" / "现在我想答完所有问题" / "プロモードに切り替える" / "프로 모드로 업그레이드" → invoke `/init --upgrade-to-pro`
  - Arrives from the bootstrap flow (standalone-bootstrap.md or CCC's bundled Step 1 driver)
argument-hint: [--simple | --pro | --upgrade-to-pro] [--ccc-driven] [--config <yaml>] [--force]
---

# /init

Drive the configuration step of harness setup — what CCC's flow calls "Step 2".

> *Constitutional basis: this skill fills constitution.md (Section 2 — Project Identity) with the user's specific values, then writes `.harness/state/install.json` as the canonical "configured" marker that all other systems (CCC's session-open check, CLAUDE.md's Bootstrap Status Check, the AI-driven detection in `standalone-bootstrap.md`) use to know the harness is ready.*

## Language Awareness

This skill's instructions are in English (more stable + token-efficient). When you ask the 16 L0 questions of the user, ask in their OS locale's language. See `CLAUDE.md § Language Awareness` (detect via `locale` / `$LANG`; default English).

The question templates below are written in English; translate them to the user's locale when actually displaying. Slot VALUES that the user types (project name, description, etc.) get written verbatim to constitution.md — don't translate user-entered content.

**TodoWrite items**: if you use the TodoWrite tool to track your /init progress (Step 0 / Step 1 / etc.), **write the `content` field in the user's OS locale**, not in English. The TodoWrite list is shown to the user — keeping it in English while the user is conversing in Chinese / Japanese / Korean breaks the locale contract. Internal field names (`status`, `activeForm`) stay as-is; only the user-readable `content` translates.

## Where this skill sits in the bootstrap flow

```
Existing harness present?
  ↓                          (handled by:)
  Step 1 — Bootstrap         standalone-bootstrap.md  OR  CCC bundled Step 1 driver
  - Detect existing harness
  - 4-option menu (absorb-and-merge / archive only / delete / skip)
  - Absorb (carry old rules forward via harness-absorb) or archive/delete other configs
  ↓
  Step 2 — /init (this skill)
  - Project mode detection
  - Project understanding card (analyze → present → confirm)   ← Step 1.5
  - L0 question flow (only asks what wasn't already confirmed)
  - Slot filling
  - Template rendering
  - Validation
  - Write install.json  ← single canonical "configured" marker
  ↓
  Harness fully usable
```

**This skill does NOT run detection.** If you arrive here and detection hasn't happened, you may be in one of these states:

- **Standalone user who jumped straight to `/init` skipping bootstrap** → that's their choice; warn but proceed
- **CCC-driven invocation** → CCC already ran detection in Step 1; skip detection
- **Force re-init (`--force`)** → user explicitly wants to reconfigure; skip detection

## What this skill produces

```
<project-root>/
├── constitution.md          ← filled with L0 slot values
├── CLAUDE.md                ← references constitution; bootstrap header intact
├── AGENTS.md                ← auditor context, anti-flag rules placeholder
├── .harness/
│   ├── skills/              ← copied from outcome/skills/
│   ├── agents/              ← copied from outcome/agents/ (filtered by enabled plugins)
│   ├── scripts/             ← copied from outcome/scripts/, chmod +x
│   ├── state/
│   │   └── install.json     ← ★ written at Step 5 — completion marker
│   └── audits/              ← empty, for /audit-spec snapshots
├── .claude/
│   └── settings.json        ← from outcome/cli-configs/claude/settings.json
├── .codex/
│   ├── config.toml          ← from outcome/cli-configs/codex/config.toml
│   └── hooks.json           ← from outcome/cli-configs/codex/hooks.json
└── docs/features/           ← empty (or {{spec_dir}} per user choice)
```

## Modes

| Mode | How it's triggered | What it asks | Time | Defaults |
|------|---------------------|----|----|----|
| **Simple (default)** | `/init` or `/init --simple` | **5 questions** (identity essentials + audit + tests) | ~3 min | 11 slots get smart defaults from description + auto-detect |
| **Pro** | `/init --pro` or user picks Pro at the mode prompt | **16 questions** (full identity contract) | ~15 min | 0 — every L0 slot explicitly answered |
| **Upgrade Simple → Pro** | `/init --upgrade-to-pro` or user says "升级到专业版"/"upgrade to pro" | The **11 questions Simple skipped** (5 already-answered ones stay) | ~10 min | Reads existing install.json; appends instead of overwriting |
| **CCC-driven** | CCC's HarnessWizard invokes `/init --ccc-driven --config <yaml>` | Reads answers from `<yaml>`; only asks for missing fields | varies | per yaml |
| **Force re-init** | `/init --force` | Bypasses "already configured" guard; re-runs full Simple or Pro flow | 3-15 min | overwrites prior install |

### Picking mode at run time

When `/init` is invoked WITHOUT explicit `--simple` / `--pro` flag, **ask the user once at the very start** (in their OS locale):

```
─── Choose onboarding mode ─────────────────────────────────────

Welcome to CCC-MAGI. Pick how thorough you want the setup:

  [1] Simple  — 5 questions, ~3 minutes
                Smart defaults for everything else. Great for:
                  • Solo / side projects
                  • Hackathons / weekend hacks
                  • "Just want to try it"
                You can upgrade to Pro later anytime.

  [2] Pro     — 16 questions, ~15 minutes
                Full project identity contract. Great for:
                  • Team projects (3+ devs)
                  • Long-term maintenance projects
                  • Compliance-sensitive work (GDPR / HIPAA / PCI)
                  • Anything you'll explain to a stakeholder later

> 
```

If user says "1" / "simple" / "简单" / "シンプル" → Simple mode.
If user says "2" / "pro" / "professional" / "专业" / "プロ" → Pro mode.
If user picks Simple, remind once at the end: *"You can upgrade to Pro anytime by saying 'upgrade to pro' or running `/init --upgrade-to-pro`."*

---

## Step 0 — Precondition check (do not skip)

Before doing anything, check the current state:

```bash
test -f .harness/state/install.json
```

### If install.json EXISTS

Surface to the user (display in user's locale):

```
⚠️  Detected an existing CCC-MAGI install:
  - .harness/state/install.json (written <date>)
  - mode: <greenfield|brownfield>
  - version: <version>

What do you want?
  [1] Cancel — keep current install
  [2] Re-configure — re-run /init from scratch (existing constitution.md will be overwritten)
  [3] Edit a single slot — abort /init, use /constitution-edit instead

Please enter 1 / 2 / 3:
```

- 1 → exit cleanly
- 2 → continue (or require `--force` flag, depending on safety preference; default: ask user to confirm)
- 3 → exit; remind user about `/constitution-edit`

### If install.json DOES NOT EXIST but `.harness/` is present

This is a **partial install** (interrupted previous /init OR bootstrap-only state).

```
⚠️  .harness/ exists but install.json is missing.
This means either:
  (a) A previous /init was interrupted partway through
  (b) Bootstrap ran but /init has not yet been invoked

Recommended action: clean restart.

Continue anyway and overwrite partial state? [yes / clean / abort]
  yes    — proceed, treat existing files as scratch
  clean  — rm -rf .harness/, constitution.md (placeholder), then proceed fresh
  abort  — stop, let me investigate manually
```

Wait for user response. **Restart policy** (per CCC_harness_flow.md decision 6): no Resume; clean state then re-run.

### If neither exists (clean state)

Proceed to Step 1.

---

## Step 1 — Detect project shape (greenfield vs brownfield)

Check the project root:

```
Greenfield indicators:
- No source files (no src/, app/, lib/, etc.)
- No package manifest (no package.json, pyproject.toml, go.mod, Cargo.toml)
- No git history beyond initial commit
- Empty or near-empty directory

Brownfield indicators:
- Source code present
- One or more manifests
- Git log with multiple commits
- Existing tooling configs (tsconfig.json, .eslintrc, etc.)
```

Compute a confidence score; if ambiguous, ask the user (display in user's locale):

```
Detected project state: <greenfield | brownfield | uncertain>
Reason: <one-line>

Is this correct?
  [1] Yes (proceed as <detected>)
  [2] No, let me choose:
      a. greenfield — brand new project, starting from scratch
      b. brownfield — existing project with code; scan existing structure

Enter 1 / 2a / 2b:
```

Record the result as `project_mode`. The Step 2 question flow uses different defaults per mode.

---

## Step 1.5 — Project understanding card (analyze → present → confirm, BEFORE asking)

> **Why**: a mature project shouldn't be asked things we can already infer from the code, or things the user already wrote in their prior harness. Show what we know first; confirm; then ask only the gaps. This is the "先分析 → 列理解 → 确认 → 再追问" UX.

1. **Gather what's already known**:
   - Run the brownfield auto-detect (Step 2 § Brownfield-mode adjustments + Step 3 L1 auto-detect): `project_name`, `project_description`, `project_stage`, `team_size`, `tech_stack`, `repo_structure`, `test_framework`, `test_runner_command`, `feature_folder_pattern`, client/backend paths, `backend_db_type`.
   - **If `.harness/state/_absorb-draft.json` exists** (the user picked bootstrap option [1] absorb-and-merge), load it and MERGE its confirmed `slots` + `section3_red_lines` + `anti_flag_rules` + `rule_sources` on top of auto-detect. The absorb skill already had the user confirm these — carry them as `confirmed`.
2. **Present ONE understanding card** (user's locale, plain language):
   ```
   为了给你更好的体验,我先了解了一下你的项目,下面是我理解到的 —— 你看看对不对:

   📦 项目:<project_name> · <project_description>
   🧱 技术栈:<tech_stack>     🗂 结构:<repo_structure>     🧪 测试:<test_framework + command>
   🎯 我推测它主要在意:<primary_concern 猜测>
   🧭 从你原来的 harness 读到、已准备并入(若有):
       • <红线 / anti-flag / 身份 摘要,逐条带来源>
   ⚠️ 与 CCC 不可破底线冲突、已忽略(若有):<列出>

   这些理解对吗?可以逐条说「第N条改成…」「删掉第N条」「漏了X」。没问题就说「对 / 继续」。
   ```
3. **Apply corrections.** Mark every value the user confirms here as `confirmed` — Step 2 will NOT re-ask these.
4. **Greenfield degrade**: if little can be inferred (greenfield, no absorb draft), collapse the card to a single line — "I'll start it like this: `<defaults>`. OK?" — confirm and move on. Never make a near-empty project sit through the full card.

After confirmation, consume + delete `_absorb-draft.json` (its content is now reflected in confirmed slots and will be rendered into constitution.md / AGENTS.md at Step 4).

---

## Step 2 — L0 slot question flow

The slot inventory and ordering live in `constitution.md` § Slot registry (17 L0 slots — Block A through Block E below). What changes between modes is **how many of those 17 get explicitly asked vs defaulted**.

> **Skip already-confirmed slots (from Step 1.5).** Any slot the user confirmed on the understanding card — whether auto-detected from the code or absorbed from a prior harness — is already final. Do NOT re-ask it; carry it through and show it as ✓ confirmed in the final confirmation block. Mode (Simple/Pro) still governs which of the **remaining** slots get asked vs defaulted. On a mature project with a rich absorbed harness, this can shrink Simple's 5 questions and Pro's 16 down to just the few that genuinely couldn't be inferred.

### Question inventory (full Pro mode = 16 asked + 1 auto)

| # | Slot | Block | Mode coverage | Default if skipped (Simple mode) |
|---|---|---|---|---|
| Q1 | `project_name` | A | Simple + Pro | auto-detect from manifest |
| Q2 | `project_description` | A | **Simple + Pro** (always) | — (required, no default) |
| Q3 | `project_stage` | A | Pro only | `early` |
| Q4 | `project_scale_target` | A | Pro only | "small / personal" (from description) |
| Q5 | `team_size` | B | Simple + Pro | `solo` |
| Q6 | `primary_concern` | B | Pro only | inferred from description (keyword extract) |
| Q7 | `out_of_scope_items` | B | Pro only | `[]` (empty) |
| Q8 | `auditor_model` | C | Simple + Pro | (asked; see CLI detection below) |
| Q9 | `language_mode` | C | Pro only | `plain` |
| Q10 | `project_audience` | D | Pro only | "general users of {{project_name}}" |
| Q11 | `project_non_goals` | D | Pro only | `[]` (empty) |
| Q12 | `project_compliance` | D | Pro only | `none` |
| Q13 | `project_performance_floor` | D | Pro only | "no formal floor yet" |
| Q14 | `project_identity_other` | D | Pro only | `[]` (empty) |
| Q15 | `spec_dir` | E | Pro only | `docs/features/` |
| Q16 | `implementation_dir` | E | Pro only | `docs/features/` |
| L1.test | `test_required` | — | Simple + Pro | `true` |

**Simple mode = 5 asked**: Q1 + Q2 + Q5 + Q8 + L1.test (test_required)  
**Pro mode = 16 asked**: all 16 above  
**Upgrade Simple→Pro = 11 asked**: everything except the 5 Simple already covered

---

### Step 2A — Suggestion engine (fires after Q2 — description capture)

After the user answers Q2 (`project_description`), pause the question flow and run a **suggestion engine** before continuing:

> **Internal prompt** (do NOT show to user — runs in your head before the next question): *"Based on the project description '<their answer>', what are sensible default values for: project_stage, project_scale_target, primary_concern, project_audience, project_non_goals, project_compliance, project_performance_floor? Give 2-3 concrete options for each. Mark the most likely with ⭐."*

Generate the suggestions in **one pass** (all slots at once — saves tokens and reveals AI's understanding consistency to user).

Then for each subsequent question (Q3-Q16), present the question + show the suggestion.

#### Presentation rule (HARD — for UX consistency)

**For multi-choice questions** (Pattern A below; the labeled option lists in Pattern B; the menus in Simple mode Q3/Q4/Q5; the 3-option auditor menu in Step 2C; `[Y]/[n]` confirmations):

→ **Use Claude Code's `AskUserQuestion` tool**, not plain-text `[1] [2] [3]` prompts.

`AskUserQuestion` renders an interactive arrow-key menu — significantly better UX for non-technical CEOs than asking them to type letters or numbers (no typo risk, language-independent, visual feedback, accessible). The text examples below (e.g., `[a] early  [b] beta ...`) describe the **content** of options, not the literal rendering.

**For free-text questions** (Pattern B's "[E] write your own" branch; Pattern C's free-form input; the project_description Q2 which has no fixed options):

→ Plain text Q&A is correct — the user is typing, not picking.

**Why this matters**: CCC-MAGI's audience includes non-technical founders. The arrow-key menu lets them scan options and pick without touching letters. Without this rule, AI behavior is inconsistent across sessions (real bug observed in v0.10.2 testing: same `/init` flow rendered as text on macOS vs interactive menus on Windows). Make every session feel like the Windows session did.

#### Pattern A — Fixed-options question (multiple choice with highlighted default)

```
Q3. Project stage?
    Based on your description, I'd guess: ⭐ early
    
    [a] early   — just starting, no users yet               ⭐ suggested
    [b] beta    — internal testing / small user group
    [c] prod    — publicly released, has users
    [d] scale   — at scale, operations-mature
    > [Enter to accept ⭐ / type a-d for different / type "?" for why]
```

If user types `?`, show the reasoning: *"You said '<description>' — the words 'just starting' / 'side project' / similar suggest pre-launch state. If users are already using it, pick beta or prod."*

#### Pattern B — Open-ended question (3-5 example values + free input)

```
Q6. What is this harness primarily protecting?
    Based on your description, the most likely concerns are:
    
    [A] data integrity (no lost messages / files)
    [B] real-time sync reliability (multi-device consistency)
    [C] user privacy (chat content stays private)
    [D] velocity (ship features fast)              ← uncommon for this kind of project
    [E] write your own
    
    Can pick multiple (e.g., "A+B") or single. > 
```

User picks letters, types free text, or combinations like `A+C`.

#### Pattern C — Confirmatory question (suggested value pre-filled, edit if needed)

```
Q10. Who do you serve? (one sentence)
     ⭐ Suggested based on description: 
       "remote engineering teams at 5-50 person companies"
     
     > [Enter to accept / type your own]
```

### Step 2B — Simple mode (5 questions)

After mode pick = Simple, run only the 5 essential questions, but still run the suggestion engine after Q2.

Display in user's locale:

```
─── Simple Setup · 5 questions, ~3 minutes ─────────────────────

Q1/5. Project name
      Detected from manifest: "my-app"
      > [Enter to accept / type new]

Q2/5. One-sentence project description (plain language, no jargon)
      e.g.: "team chat app with file sharing for remote engineers"
      > 

[Suggestion engine runs here — produces defaults for the 11 skipped slots]

Q3/5. Team size?
      Based on description, suggesting: ⭐ small (2-5 people)
      [a] solo  [b] small ⭐  [c] large
      > 

Q4/5. Auto-write tests when implementing features?
      [Y] Yes (recommended — MAGI Tester runs at Stage 6)
      [n] No  (skip Stage 6 entirely)
      > 

Q5/5. Cross-model auditor (MAGI Verdict)?
      [CLI detection results here — see Step 2C below]
      > 

✓ Done. 11 other slots set to smart defaults. Run /init --upgrade-to-pro 
  anytime (or say "upgrade to pro") to answer them properly.
```

### Step 2C — CLI detection for the auditor question (Q5/Q8)

Run this detection logic before asking the auditor question:

```bash
HAS_CLAUDE=$(command -v claude >/dev/null && echo yes || echo no)
HAS_CODEX=$(command -v codex >/dev/null && echo yes || echo no)
HAS_GEMINI=$(command -v gemini >/dev/null && echo yes || echo no)
CURRENT_CLI=  # detect parent process — likely claude or codex
```

Branch on results:

**Branch 1 — Both Claude + Codex installed** (Tier 1 ideal):
```
You have both Claude Code and Codex CLI. Pick auditor:
  [1] ⭐ Codex review (use Codex CLI as auditor, default gpt-5.5)
  [2] Same model (current writer also reviews, fresh context)
  [3] Skip audit entirely (⚠️ violates Universal Core — NOT recommended)
> 
```

**Branch 2 — Only your current CLI installed**:
```
You're using Claude Code. Codex CLI is not installed.
  [1] Install Codex CLI now, then use Codex review (default gpt-5.5)
      (1 command — opens https://github.com/openai/codex)
  [2] Same model (current writer also reviews, fresh context)
  [3] Skip audit entirely (⚠️ NOT recommended)
> 
```

**Branch 3 — Some other CLI** (Cursor / Cline / Aider / Gemini / etc.):
```
You're using <detected CLI>. Note: CCC-MAGI is Tier-3 tested on this CLI 
(some hooks may not fire — see README § CLI compatibility).

  [1] Same model (current writer also reviews, fresh context)
  [2] Install Codex CLI as auditor (Codex review, default gpt-5.5)
  [3] Skip audit (⚠️ NOT recommended)
> 
```

For Simple mode: limit to options [1] and [2]; don't show "skip audit" (Universal Core compliance).

### Step 2D — Pro mode (16 questions)

After mode pick = Pro, ask all 16 questions, organized in 5 thematic blocks. The suggestion engine STILL runs after Q2 and pre-fills defaults for Q3-Q16 (user can accept, edit, or override).

**Convention for every Pro-mode block**: at top of each block, tell user once:
`(Per question: [Enter] = accept ⭐ suggestion / type new value / type "skip <Qn>" / type "?" for reasoning)`

#### Block A — Identity (Q1-Q4)
- Q1 project_name — auto-detected default
- Q2 project_description — ALWAYS asked, NO default (triggers suggestion engine)
- Q3 project_stage — choice a/b/c/d, suggestion highlighted
- Q4 project_scale_target — open-ended with 3-5 example suggestions

#### Block B — Scope + Discipline (Q5-Q7)
- Q5 team_size — solo/small/large, suggestion based on git activity (brownfield) or description (greenfield)
- Q6 primary_concern — open-ended with letter-coded suggestion list
- Q7 out_of_scope_items — open-ended with examples from description's negative space

#### Block C — Engine (Q8-Q9)
- Q8 auditor_model — CLI-detected, branches per Step 2C above
- Q9 language_mode — plain/professional, default plain

#### Block D — Project identity / Red lines (Q10-Q14, → constitution Section 2)
- Q10 project_audience — confirmatory pattern (suggestion pre-filled)
- Q11 project_non_goals — open-ended with description-derived examples
- Q12 project_compliance — GDPR/HIPAA/PCI/none/other, suggestion based on `project_audience` keywords
- Q13 project_performance_floor — open-ended with example latencies
- Q14 project_identity_other — OPTIONAL, can skip with empty

#### Block E — Paths (Q15-Q16)
- Q15 spec_dir — default `docs/features/`
- Q16 implementation_dir — default `docs/features/`

### Step 2E — Upgrade mode (Simple → Pro)

If invoked via `/init --upgrade-to-pro` or natural language ("升级到专业版" / "upgrade to pro" / etc.):

1. Read existing `.harness/state/install.json`
2. Identify which 5 slots are already answered (Q1, Q2, Q5, Q8, test_required)
3. Re-run the suggestion engine on the existing `project_description` to produce fresh defaults for the 11 skipped slots
4. Walk through Q3, Q4, Q6, Q7, Q9, Q10, Q11, Q12, Q13, Q14, Q15, Q16 in that order
5. Update install.json with `"mode": "pro"` and `"upgraded_from_simple_at": "<timestamp>"` fields
6. Update constitution.md Section 2 with new identity slots

Don't overwrite the 5 existing answers unless user explicitly says so.

### Brownfield-mode adjustments (regardless of Simple/Pro)

In brownfield mode, auto-detect defaults from the codebase BEFORE asking:

- **Q1 (project_name)**: scan `package.json:name`, `pyproject.toml:name`, `Cargo.toml:name`, `go.mod`, `composer.json:name`
- **Q2 (project_description)**: scan README.md first paragraph
- **Q3 (project_stage)**: heuristic — git log < 30 commits AND no test files → early; has tests + CI but no prod marker → beta; otherwise → prod (low confidence — confirm)
- **Q5 (team_size)**: count distinct git authors in last 90 days

For each auto-detected default, show:
```
Q1. Project name (detected from package.json: "my-app")
    Press Enter to accept, or type new value:
```

### Confirmation block (after all questions in the chosen mode)

Display the full L0 slot table for confirmation (user's locale). Highlight:
- ✓ values user explicitly answered
- 🤖 values from suggestion engine (accepted by user)
- ⚙️ values defaulted (Simple mode skipped slots)
- 🔍 values auto-detected (brownfield)

```
About to write the following configuration to constitution.md:

  project_name              : my-app                  🔍 detected
  project_description       : "..."                    ✓ user
  project_stage             : early                    ⚙️ default (Simple mode)
  team_size                 : small                    🤖 suggested + accepted
  ...

All correct? Type "yes" to continue, "no" to re-answer specific Q#:
```

---

## Step 3 — L1 slot auto-detect + ask

L1 slots (see constitution.md § Slot registry) fill on-demand. At /init we resolve the ones that affect installation:

- `tech_stack` → AUTO scan manifests; CONFIRM
- `test_framework` → AUTO scan dev deps (jest / vitest / pytest / etc.); CONFIRM
- `test_runner_command` → AUTO from package.json scripts or framework default
- `feature_folder_pattern` → AUTO scan fs (src/features/ / app/ / lib/ / pages/); CONFIRM
- `client_code_paths` → derived from feature_folder_pattern + repo layout
- `backend_code_paths` → AUTO scan (supabase/ / api/ / server/ / functions/); OPTIONAL
- `backend_db_type` → derived from backend_code_paths (postgres-via-supabase / postgres-raw / mongodb / sqlite / none); OPTIONAL
- `migration_dir` → derived from backend_db_type
- `rls_auth_function` → derived from backend_db_type (Postgres+Supabase → `(SELECT auth.uid())`; others: OPTIONAL)
- `error_tracker` → ASK
- `release_lanes` → DEFAULT to `[git-push]`; ASK if more (OTA / staged env)
- `supported_locales` → DEFAULT `["zh-Hans", "en", "ko"]`; ASK
- `high_trap_libraries` → seed from detected stack (e.g., RN+Expo → FlashList, Expo SDK; Next.js → Next-specific)
- `junior_reviewers` → derived from tech_stack (frontend-reviewer if client; backend-reviewer if backend; security-reviewer always)
- `pii_columns` → DEFAULT `[phone, email, name, address, payment]`; ASK
- `auditor_model_id` → DEFAULT `gpt-5.5` from slot registry; **auto-fill, not asked**. User can change later via `/constitution-edit`. Filled whenever `auditor_model != None` (i.e., dual-engine).

L2 slots (`anti_flag_rules`, `project_red_lines`) start empty.

---

## Step 3.5 — Recommend the workflow template

Before rendering, pick the project's workflow shape. Invoke the **`workflow-template`** skill (`.harness/skills/workflow-template/SKILL.md`) in `--recommend` mode: it detects the project type from repo signals (reuse the `tech_stack` / paths already auto-detected above), recommends the best-fit of the 6 templates, confirms in ONE question (never gates), allows skip/reorder/add customization, and persists `.harness/state/workflow-template.json`.

- Greenfield with no strong signals → recommend `full-stack` (the default) and move on.
- If the user defers, leave the file absent — the project runs on `full-stack` by default and can switch later via `/workflow-template`.
- Universal Core gates (cross-model audit, human smoke test) survive any template choice — the skill enforces this.

---

## Step 4 — Render templates

For each file in the harness package, produce the rendered version with double-brace placeholders replaced.

### Render rules

(In the rules below, `<NAME>` is a stand-in for any registered slot name like `project_name`, `spec_dir`, etc. The literal template syntax in the harness files uses double curly braces: `{` `{` `<NAME>` `}` `}`. We split it here so this documentation block isn't itself misread as a slot reference.)

- A bare double-braced slot reference → the string value of the slot, unmodified
- A double-braced slot reference followed by a literal suffix → string value + literal suffix (no space)
- Slot values containing characters that need escaping in their target file format: shell-escape for bash files; JSON-escape for `.json` files; TOML-string-escape for `.toml`.

### File mappings

| Source (in harness package) | Destination (in user project) |
|------------------------------|--------------------------------|
| `constitution.md` | project root |
| `CLAUDE.md` | project root |
| `AGENTS.md` | project root |
| `skills/*` (all 9 skills) | `.harness/skills/` |
| `agents/_template/` + `README.md` | `.harness/agents/_template/` |
| `agents/<reviewer>.md` (enabled ones) | `.harness/agents/<reviewer>.md` |
| `scripts/*.sh` + `scripts/standalone-bootstrap.md` + `scripts/README.md` | `.harness/scripts/` (sh files chmod +x; md files copied as-is) |
| `cli-configs/claude/settings.json` | `.claude/settings.json` |
| `cli-configs/codex/config.toml` | `.codex/config.toml` |
| `cli-configs/codex/hooks.json` | `.codex/hooks.json` |
| `docs-harness/*` (5 files) | `docs-harness/` (project root) |

Junior-reviewer filtering: agents/backend-reviewer.md is copied **only if** `backend_db_type` is non-empty. agents/frontend-reviewer.md is copied **only if** `client_code_paths` is non-empty. Other agents always copy.

Skill filtering: skills/db-schema/ is copied **only if** `backend_db_type` is non-empty.

Create empty dirs: `.harness/state/`, `.harness/audits/`, `{{spec_dir}}` (if absent).

**Important**: the Bootstrap Status Check block at the top of `CLAUDE.md` MUST be preserved verbatim during rendering. It is the load-bearing trigger for standalone bootstrap on future sessions.

---

## Step 5 — Permissions + completion marker (write install.json LAST)

### Make scripts executable

```bash
chmod +x .harness/scripts/*.sh
```

### Configure auditor CLI env (optional)

Write to `.harness/state/auditor.env` for shell sourcing.

If `auditor_model = Codex`:
```
AUDITOR_CLI=codex
AUDITOR_MODEL_ID={{auditor_model_id}}
```

If `auditor_model = None` (single-engine fallback):
```
AUDITOR_CLI=claude
```

### Write install.json (★ THIS IS THE COMPLETION MARKER ★)

**This must be the LAST file write in Step 5.** It signals "harness is fully configured" to every other system:

- CCC's session-open check (CCC_harness_flow.md § 5.2)
- CLAUDE.md's Bootstrap Status Check (each session start)
- The AI-driven detection in `standalone-bootstrap.md` (which checks `install.json` before deciding whether to run bootstrap)

If Step 6 validation fails, `install.json` should still be written (the install IS done, validation surfaces issues to fix). Only if a Step 4 file write FAILS should install.json NOT be written.

**MUST contain COMPLETE slot state** — every L0 and resolved L1 slot value gets recorded. This lets downstream skills (/feature-draft, /resume, /constitution-edit, etc.) read project state without re-reading constitution.md and re-parsing slots. The full schema:

> **Schema version 3** (was 2): adds the `absorption` block (prior-harness provenance). **Migration**: a pre-existing v2 `install.json` has no `absorption` key — readers MUST treat a missing `absorption` as `{ "absorbed_from": [] }` and never error on it. No rewrite of old files is required.

```bash
cat > .harness/state/install.json <<JSON
{
  "schema_version": 3,

  "installed_at": "<ISO-8601 timestamp, e.g., 2026-05-28T10:00:00Z>",
  "harness_version": "<package version, e.g., 0.9.0>",
  "skill_set_version": "<sha-or-timestamp-of-source-skills, optional>",

  "onboarding": {
    "mode": "<simple|pro>",
    "upgraded_from_simple_at": "<ISO timestamp, only set if Simple → Pro upgrade happened>",
    "questions_asked": [<list of Q-numbers actually answered, e.g., [1, 2, 3, 5, 8] for Simple mode>],
    "questions_defaulted": [<list of Q-numbers using smart defaults, e.g., [4, 6, 7, 9, ...]>]
  },

  "project_mode": "<greenfield|brownfield>",

  "absorption": {
    "_comment": "Provenance of any prior-harness content absorbed at takeover (bootstrap option 1, via harness-absorb). Absent or empty absorbed_from if nothing was absorbed.",
    "absorbed_from":    [<list of source files/dirs, e.g., ["CLAUDE.md.pre-ccc-magi", ".cursor/rules/", "copilot-instructions.md"]>],
    "absorbed_at":      "<ISO-8601, or null>",
    "carried_forward":  {"section2_identity": N, "section3_red_lines": N, "anti_flag_rules": N, "rule_sources": N, "slots": N},
    "skipped_conflicts": [<rules NOT absorbed because they'd weaken Universal Core, each {"text": "...", "reason": "..."}>]
  },

  "slots": {
    "_comment": "All L0 + resolved L1 slot values. Source: constitution.md § Slot registry. Every key here should match a slot name in that registry.",

    "project_name":              "<value>",
    "project_description":       "<value>",
    "project_stage":             "<early|beta|prod|scale>",
    "project_scale_target":      "<value>",
    "team_size":                 "<solo|small|large>",
    "primary_concern":           "<value>",
    "out_of_scope_items":        [<list>],
    "auditor_model":             "<Codex|Claude|None|...>",
    "auditor_model_id":          "<e.g., gpt-5.5>",
    "language_mode":             "<plain|professional>",
    "spec_dir":                  "<e.g., docs/features/>",
    "implementation_dir":        "<e.g., docs/features/>",

    "project_audience":          "<value>",
    "project_non_goals":         [<list>],
    "project_compliance":        "<GDPR|HIPAA|PCI|none|other>",
    "project_performance_floor": "<value>",
    "project_identity_other":    [<list>],

    "tech_stack":                "<value, AUTO from manifests>",
    "repo_structure":            "<value, AUTO from fs scan>",
    "dependency_flow":           "<value, AUTO or OPTIONAL>",
    "release_lanes":             [<list, e.g., ["git-push"]>],
    "backend_change_lane":       "<value, OPTIONAL>",
    "error_tracker":             "<Sentry|Bugsnag|none|other>",
    "test_required":             true|false,
    "junior_reviewers":          [<list, e.g., ["frontend-reviewer", "backend-reviewer", "security-reviewer"]>],
    "rule_sources":              [<list, starts empty>],
    "supported_locales":         [<list, e.g., ["zh-Hans", "en", "ko"]>],
    "edge_case_categories":      [<list of 8 categories, defaults + user additions>],
    "test_framework":            "<jest|vitest|pytest|none|auto>",
    "test_runner_command":       "<e.g., npm test>",
    "feature_folder_pattern":    "<value>",
    "client_code_paths":         [<list>],
    "backend_code_paths":        [<list>],
    "backend_db_type":           "<postgres|mysql|mongodb|none|other>",
    "high_trap_libraries":       [<list of libraries needing context7 version check>],
    "migration_dir":             "<value, only if backend_db_type set>",
    "pii_columns":               [<list, e.g., ["phone", "email", "name", "address", "payment"]>],
    "rls_auth_function":         "<value, only if backend supports>",

    "_comment_l2": "L2 (grow-over-time) slots are tracked separately — anti_flag_rules in AGENTS.md, project_red_lines in constitution.md § 3. Not duplicated here."
  },

  "environment": {
    "_comment": "Snapshot of env-check.json content at /init time. Useful for /audit and /resume to know what tier was active.",
    "platform":           "<darwin|linux|windows-wsl|windows-git-bash|unknown>",
    "tier":               "<1-claude-codex|2-single-claude|3-other|0-none>",
    "ai_clis_installed":  {"claude": true|false, "codex": true|false, "gemini": true|false}
  },

  "magi_system": {
    "_comment": "Records which models back which MAGI positions. Lets downstream skills know who's playing what.",
    "core_cli":         "<claude|codex|cursor|...>",
    "verdict_cli":      "<codex|claude|gemini|none>",
    "verdict_model_id": "<gpt-5.5|claude-sonnet-4-6|...>"
  },

  "render_status": {
    "_comment": "Which files were rendered + their slot count + any per-file warnings. Helps /constitution-edit and re-installs know what to touch.",
    "constitution.md":  {"slots_filled": N, "warnings": []},
    "CLAUDE.md":        {"slots_filled": N, "warnings": []},
    "AGENTS.md":        {"slots_filled": N, "warnings": []}
  }
}
JSON
```

**Why the verbose schema**: Simple mode hides 11 questions from the user but still WRITES their default values to install.json. This way `/feature-draft` doesn't have to re-derive "what's my project_audience" — it just reads it. Sparse install.json (the v0.8.x format) forced every downstream skill to re-parse constitution.md, which is fragile.

**Upgrade path**: When `/init --upgrade-to-pro` is invoked, **don't overwrite** the existing JSON wholesale. Read it, update only the slots that got new answers, set `onboarding.upgraded_from_simple_at`, and write back.

---

## Step 6 — Validate the install

Run smoke checks (each prints ✅ or ❌):

1. **No unfilled L0 slots** — `grep -rn "{{" constitution.md` should return only L1/L2 references (in the registry comment block), not unfilled L0 substitutions.
2. **All scripts exist + executable** — `for f in .harness/scripts/*.sh; do [ -x "$f" ] && echo ✅; done`
3. **JSON files parse** — `python3 -c "import json; json.load(open('.claude/settings.json'))"` etc.
4. **TOML files parse** — basic structural check (`grep "^\[" .codex/config.toml`)
5. **`install.json` exists and parses** — proves Step 5 completed.
6. **CLAUDE.md still has Bootstrap Status Check block** — sanity check that rendering didn't strip the safety header.
7. **standalone-bootstrap.md exists** at `.harness/scripts/standalone-bootstrap.md` — proves the standalone path is intact.

If any check fails, report it but DO NOT auto-rollback. Tell the user the specific failure + how to fix.

---

## Step 7 — Next steps prompt

Display in user's locale:

```
✅ CCC-MAGI fully configured.

Suggested next steps:

  • Review what was written to constitution.md at the top to confirm it's correct
    (to adjust any L0 slot, run /constitution-edit)
  • For a new feature: /feature-draft <name>
  • To audit an existing feature: /audit-spec <name>
  • To change an existing feature: /audit-spec <name>, then act on the Section 9 deltas

Docs:
  • constitution.md          — project constitution (immovable Universal Core + project identity)
  • CLAUDE.md                — workflow operating manual
  • AGENTS.md                — auditor role contract
  • docs-harness/README.md   — entry point to framework meta-docs
```

**If running in CCC-driven mode**, additionally emit the terminal-close marker on its own line:

```
✓ Task complete, close terminal
```

This is the signal CCC's terminal monitor watches for. In interactive mode, do NOT emit this marker — the user is staying in the same CLI session.

---

## CCC-driven mode

When invoked with `--ccc-driven --config <yaml-path>`:

1. Read the YAML config. Expected schema:
   ```yaml
   slots:
     project_name: my-app
     project_description: ...
     ...
   choices:
     project_mode: greenfield | brownfield
     reviewers_enabled: [frontend, backend, security]
   ```

   Note: `existing_harness_action` is NOT in this YAML anymore — CCC's Step 1 driver has already handled it before /init was invoked.

2. Validate the config covers all required L0 slots. If missing any, exit with structured error (CCC will collect what's missing and re-invoke).

3. Skip every interactive prompt — use config values directly.

4. At end of Step 6 (validation), emit a structured JSON report to stdout (for CCC to parse):
   ```json
   {
     "status": "success" | "error",
     "validation_results": [
       {"check": "no_unfilled_l0_slots", "passed": true},
       ...
     ],
     "next_actions": ["/feature-draft <name>", "/audit-spec <name>"]
   }
   ```

5. Emit the terminal-close marker on its own line:
   ```
   ✓ Task complete, close terminal
   ```

---

## Error recovery (Restart policy)

Per CCC_harness_flow.md decision 6, /init does NOT support Resume. If anything goes wrong:

1. **User can abort at any prompt** — type `abort` (or Ctrl-C). Whatever partial state exists is left as-is for the user to manually clean up.
2. **Step 4 file-write failure** — surface the specific failure; do NOT write install.json; leave the user in a "partially installed but no install.json" state.
3. **Next time the user runs /init**, Step 0's "partial install" branch detects this and offers `clean` to wipe and start over.

There is intentionally no auto-rollback. Manual clean-up + restart is simpler than partial-state recovery.

---

## Trust contract

- **`/init` never silently modifies files outside its declared output**. Every file write is enumerated in Step 4's file mapping table.
- **Detection of existing harness is NOT this skill's job** — bootstrap (standalone-bootstrap.md or CCC Step 1 driver) handles it.
- **L0 slots are mandatory**. The skill cannot complete with any L0 slot unfilled.
- **`install.json` is the single canonical "configured" marker**. No other file plays this role.
- **Validation in Step 6 is informational, not gating**. Validation failures surface issues; they do NOT roll back install.json.
- **Bootstrap header in CLAUDE.md is preserved verbatim during rendering** — load-bearing for future sessions.

---

## Anti-patterns the skill blocks

- **Running detection inside /init** → bootstrap handles it; don't duplicate
- **Skipping L0 question if user "doesn't know"** → "I don't know" is a valid answer; the slot gets a placeholder + a note in `## Decision history` so the auditor can flag it for revisit
- **Auto-detecting answers without confirmation** → every brownfield auto-detect requires explicit user confirmation before becoming the slot value
- **Filling slots in CLAUDE.md / AGENTS.md without filling constitution.md first** → constitution is the single source; the rest reference it
- **Writing install.json before Step 4 completes** → install.json must reflect a complete install, not a partial one
- **Stripping the Bootstrap Status Check block from CLAUDE.md during rendering** → would break next-session standalone bootstrap

---

## Completion criteria

`/init` is complete when:

- Step 0 has run (precondition check; either clean state or user-confirmed re-init)
- Step 1 has run (project mode determined)
- Step 2-3 have run (all L0 + relevant L1 slots filled)
- Step 4 has run (all template files written to their destinations)
- Step 5 has run (scripts executable, `install.json` written, auditor env configured)
- Step 6 validation has run (and either all passed, or user has explicitly accepted any failures)
- User has seen Step 7's next-steps prompt
- **In CCC-driven mode**: the terminal-close marker has been emitted on its own line
