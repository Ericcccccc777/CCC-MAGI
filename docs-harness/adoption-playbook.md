# Harness Adoption Playbook

Step-by-step guide for installing the harness in a project. Works for greenfield (new project) and brownfield (existing project) scenarios, via two installation paths.

> **`/init` is the fast path.** Once the harness is on disk and the bootstrap has run, `/init` asks you the questions in Phase 1 here and fills the slots automatically. This playbook is the full manual flow — useful when `/init` doesn't fit your situation, or when you want to understand what `/init` is doing under the hood.

## File layout overview

CCC-Harness ships TWO root-level "AI context" files plus the project constitution:

| File | Read by | Contains |
|---|---|---|
| `AGENTS.md` | Codex / Cursor / Cline / Aider / Gemini CLI / Devin / etc. | Universal project context + auditor brief |
| `CLAUDE.md` | Claude Code only (others ignore) | Claude-specific workflow, Bootstrap, Language Awareness |
| `constitution.md` | Every AI agent (per § preamble) | Universal Core (5 invariants) + Project Identity + Red Lines + Slot Registry |

If you use Claude Code, both `CLAUDE.md` and `AGENTS.md` are read by Claude — Claude Code natively reads `CLAUDE.md` and CCC's setup instructs it to also read `AGENTS.md` for project context.

If you use Codex / Cursor / Cline / Aider, those tools read `AGENTS.md` natively. The `CLAUDE.md` file is also present but those tools ignore it.

This dual setup means: any AI tool coming to the project gets the right context without manual configuration.

## Two installation paths

The harness supports two install paths. Pick whichever fits your setup:

### Path A — Through CCC (desktop wrapper)

If you use **CCC (Claude Code Controller)** as your desktop session manager:

1. Open CCC, click "new session", pick your project folder.
2. In the session view, click the "Harness" button.
3. In the HarnessWizard window, click "Environment Detection".
4. Confirm token usage warning → CCC opens a terminal at your session path with your AI CLI running.
5. The AI walks you through:
   - **Step 1** (Bootstrap): detect existing harness configs, present 3-option menu, archive/delete other configs, **pull CCC-Harness from GitHub** to your project.
   - **Step 2** (`/init`): fill 16 L0 questions, write `.harness/state/install.json`.
6. CCC HarnessWizard shows ✅ Step 1 / ✅ Step 2 / ✅ All configuration complete.

CCC users do NOT need to manually clone CCC-Harness — Step 1 pulls it for you. See `CCC_harness_flow.md` (in this repo) for the full spec.

### Path B — Standalone (no CCC)

If you DON'T use CCC, or want full manual control:

1. `git clone <CCC-Harness-repo> .ccc-harness-temp` in your project (you do this yourself).
2. Move contents into the right locations (see Step 1.1 below for the file mapping).
3. Open your AI CLI (`claude` or `codex`) at the project root.
4. The CLI reads `CLAUDE.md`, sees the **Bootstrap Status Check** block, sees `.harness/state/install.json` doesn't exist → AI reads `.harness/scripts/standalone-bootstrap.md` and walks you through:
   - Detection + 3-option menu (same as CCC's Step 1, minus the git clone — you did that)
   - If you pick 1/2: invoke `/init` for Step 2 (L0 filling)
   - If you pick 3: AI continues working without harness this session; re-prompts next session

This playbook below documents Path B in detail. Path A is the same flow but with CCC's GUI driving terminal spawning + monitoring.

---

## Phase 0 — Preconditions

Before starting:

- [ ] You have a project (or are about to create one) with a git repo initialized.
- [ ] Working tree is clean (`git status` clean).
- [ ] You have a CLI installed (Claude Code, Codex, or both — single-engine mode works with one).
- [ ] You've decided whether this will be **greenfield** (new project, no existing code) or **brownfield** (existing code that the harness will wrap).
- [ ] You've skimmed `constitution.md` and `CLAUDE.md` so you know what you're signing up for.

### Recommended branch

For brownfield adoption, work on a dedicated branch so it's easy to back out:

```bash
git checkout -b feat/install-harness
```

For greenfield, install directly on `main`.

---

## Phase 1 — Install harness templates + fill slots

**Goal:** the harness's template files land in your project, and project-specific values get filled into the slot registry.

### Step 1.1 — Copy the harness

Copy the contents of `outcome/` from the harness package into your project root (or a known subdirectory; the convention is the project root):

```
your-project/
├── constitution.md           ← from outcome/constitution.md
├── CLAUDE.md                 ← from outcome/CLAUDE.md
├── AGENTS.md                 ← from outcome/AGENTS.md
├── skills/                   ← from outcome/skills/
├── agents/                   ← from outcome/agents/
└── .harness/                 ← created by the install (scripts/, state/)
    └── scripts/              ← copy from outcome/cli-configs/scripts-template/
```

Plus CLI configs into their canonical locations:

```
.claude/settings.json         ← from outcome/cli-configs/claude/settings.json
.codex/config.toml            ← from outcome/cli-configs/codex/config.toml
.codex/hooks.json             ← from outcome/cli-configs/codex/hooks.json
```

### Step 1.2 — Fill the L0 slots

Open `constitution.md` and the slot registry block at the top. Fill every L0 slot. The harness can't run with unfilled L0 slots — that's the entire point of L0.

L0 slots, in plain language:

| Slot | Question for you |
|------|------------------|
| `project_name` | What's this project called? |
| `project_description` | One sentence, no jargon — what does this do? |
| `project_stage` | early / beta / prod / scale — where are you now? |
| `project_scale_target` | What scale are you building toward? |
| `team_size` | solo / small / large |
| `primary_concern` | What is this harness primarily protecting? (stability / speed / security / ...) |
| `out_of_scope_items` | What should the harness NOT keep harping on? |
| `auditor_model` | Display name of the second model (default Codex; None = single-engine) |
| `language_mode` | plain (default) or professional — affects how prompts are phrased to you |
| `spec_dir` | Where feature specs live (default `docs/features/`) |
| `implementation_dir` | Where implementation notes live (default same as spec_dir) |

Then the L0 constitution-identity slots (Section 2 of constitution.md):

| Slot | Question |
|------|----------|
| `project_audience` | Who do we serve? (one sentence) |
| `project_non_goals` | What do we deliberately NOT do? |
| `project_compliance` | Compliance / legal floors (GDPR / HIPAA / PCI / none / other) |
| `project_performance_floor` | Performance floors that can't be crossed |
| `project_identity_other` | Other "if-violated-it's-not-this-project-anymore" statements |

### Step 1.3 — Fill the L1 slots as you go

L1 slots are answered at the appropriate stage. Some can be auto-detected from manifests (`package.json`, `pyproject.toml`, etc.):

- `tech_stack` — auto-detect from manifests
- `repo_structure` — auto-detect from filesystem, confirm with you
- `test_framework` — auto-detect from dependencies, confirm
- `test_runner_command` — auto-detect from scripts, confirm

Other L1 slots need you to answer when relevant:

- `release_lanes` — default `[git-push]`; you can add OTA / staged environments
- `backend_db_type` — leave empty if no backend (db-schema skill skips entirely)
- `error_tracker` — Sentry / Bugsnag / none / other
- `test_required` — true (default) or false
- `junior_reviewers` — which plugins to enable (see `outcome/agents/README.md`)
- `dependency_flow` — optional; leave blank if no enforcement
- `supported_locales` — default `["zh-Hans", "en", "ko"]`; adjust to your project
- `high_trap_libraries` — libraries to force `context7` verification on
- `feature_folder_pattern`, `client_code_paths`, `backend_code_paths` — per your repo layout

L2 slots (anti-flag rules, project red lines) start empty and grow over time. Don't fill them now.

### Step 1.4 — Customize the example agents

The harness ships 4 example agents in `agents/` (`frontend-reviewer`, `backend-reviewer`, `security-reviewer`, `test-fixer`). Each has `example: true` in its frontmatter. Decide:

- Keep `frontend-reviewer` if your project has client-side code
- Keep `backend-reviewer` if `backend_db_type` is configured (it auto-skips otherwise)
- Keep `security-reviewer` if your project touches PII or auth
- Keep `test-fixer` if `test_required = true`

Replace the project-specific checklist categories in each kept agent with rules from your `{{rule_sources}}`. The structure stays; the content swaps.

Add your own junior reviewer plugins by copying `agents/_template/junior-agent-template.md`. Register the new agent in the `junior_reviewers` slot.

### Step 1.5 — Customize the CLI hook scripts

The harness's `claude/settings.json` and `codex/hooks.json` reference these scripts at `.harness/scripts/`:

- `precommit-typecheck.sh` — your stack's typecheck (e.g., `tsc --noEmit`, `mypy`, `cargo check`)
- `lint-bans.sh` — grep for your anti-flag patterns from `AGENTS.md`
- `precommit-cycles.sh` — your dependency-cycle check (e.g., `madge --circular src/`); skip if `dependency_flow` is empty
- `format-edit.sh` — your formatter (e.g., `prettier --write`, `black`, `gofmt`)
- `post-migration.sh` — only if `backend_db_type` is configured (refresh schema cache + regenerate typed bindings)
- `auditor-gate.sh` — invokes the auditor CLI with structured output; the harness ships a reference implementation in `outcome/cli-configs/scripts-template/`

### Step 1.6 — Commit Phase 1

```bash
git add constitution.md CLAUDE.md AGENTS.md skills/ agents/ .claude/ .codex/ .harness/
git commit -m "feat(harness): install workflow harness

- Add constitution, workflow rules, agent definitions
- Configure cross-model audit (auditor: {{auditor_model}})
- Hook scripts at .harness/scripts/ customized for stack
- Two-file feature spec model active

See constitution.md and CLAUDE.md for design rationale."
```

---

## Phase 2 — First feature as dogfood

**Goal:** run a real feature through the harness end-to-end. The first run validates the install AND surfaces gaps before they compound.

### Greenfield path

1. Pick the simplest meaningful feature (e.g., "user can sign in").
2. Run `/feature-draft <name>`.
3. Walk Stage 1 with the harness paraphrasing your intent and running edge-case sweeps.
4. Continue through stages 2 → 8.
5. Smoke-test the feature on a real environment (Stage 7).
6. Commit.

### Brownfield path

1. Pick a feature that already has code but no spec (or stale spec).
2. Run `/audit-spec <name>`.
3. Walk the intent rounds, then let the harness's fresh-context subagent read the code and produce an as-built reading.
4. Resolve each delta (code-vs-spec) with the harness's a/b/c/d decision framing.
5. Continue through stages 3+ if Section 9 has actionable deltas.
6. Smoke-test.
7. Commit.

### What to watch for during Phase 2

- **The CEO spec accidentally carrying tech jargon.** Stage 2's plain-language check should catch this, but it's worth watching during Stage 1.
- **The audit gate not firing.** Confirm `.harness/scripts/auditor-gate.sh` actually invokes your auditor model.
- **Lane misclassification.** A "trivial" change that should have been stability-fix; a "stability-fix" that turned out to need spec changes.
- **Subagent invocation gaps.** A frontend change that didn't trigger `frontend-reviewer` (means your `client_code_paths` slot is wrong).

If any of these happen, halt and fix the config before continuing.

---

## Phase 3 — Gradual adoption (brownfield only)

After Phase 2, the brownfield project has one feature in the new spec model and many features still in the old shape (or no shape at all).

Adopt remaining features in priority order. Suggested order:

1. **Highest-risk features first** — auth, payments, anything touching PII. These benefit most from the harness's audit invariant.
2. **Most-edited features second** — anything where you find yourself making changes weekly. The harness pays for itself fastest here.
3. **Foundational features third** — features other features depend on. Improving them improves everything downstream.
4. **Low-risk leaf features last** — simple settings screens, static content. The harness's overhead may exceed the value here.

Each feature is one `/audit-spec <name>` invocation. The harness handles the rest.

Optional: track progress in `.harness/audit-progress.md`:

```markdown
# Feature Audit Progress

## Done
- [x] auth (2026-MM-DD)

## In Progress
- [ ] chat

## Backlog
- [ ] sell
- [ ] feed
...
```

---

## Tuning

### Tuning budget pressure

CCC-Harness includes a budget-pressure hook (P1.6) that emits advisory warnings as the session context fills up. The threshold is 200,000 tokens by default — the Opus historical baseline.

If you're using a 1M-context model variant, raise the budget so the hook doesn't fire prematurely:

```bash
export CCC_CONTEXT_BUDGET=1000000  # add to ~/.zprofile or ~/.bashrc
```

Below 50% of budget: hook is silent (zero token overhead).
At 50-89%: advisory `additionalContext` (~200 tokens) suggesting model downgrade for subagents + narrower reads.
At 90%+: stronger advisory + recommendation that the user run `/compact`.

---

## Troubleshooting

### Q: A skill keeps invoking my old CLI's CLAUDE.md location

Your `.claude/settings.json` or `AGENTS.md` reference may be stale. Check `outcome/cli-configs/README.md § Required hook scripts` for the canonical paths the harness expects.

### Q: My CEO spec keeps drifting into tech jargon

You may have skipped Stage 2 or the auditor's plain-language check isn't firing. Re-run `/spec-finalize <name>` — Stage 2 explicitly scans for tech-term creep and halts on each match.

### Q: The audit chain takes forever

Audit cost scales with diff size, not change importance. If a feature change is too large for any reasonable audit, split it into smaller commits. The lane system exists partly to encourage this.

If the auditor model is genuinely too slow for your iteration speed, consider:

- Switching to a faster auditor model (smaller, faster variant of the same family).
- Single-engine fallback (`auditor_model = None`) — weaker bias-cancellation, but viable for early-stage solo work.
- Skipping audit on a per-commit basis is **not an option** (Constitution § 1).

### Q: Lane classification is wrong, the harness wants to drag a 5-line change through full workflow

If the change has no intent change AND no schema change AND no new dependency AND <20 LOC, it's trivial-change. Tell the harness explicitly during pre-stage: "this is a trivial-change."

### Q: Smoke test feels like overhead for tiny UI tweaks

Trivial-change skips Stage 7 for pure copy / text / translation changes. Spot-check on device for any logic change. If you find yourself wanting to skip Stage 7 for a logic change, that's a signal the change isn't actually trivial.

### Q: I want to bypass the auditor for an emergency hotfix

You don't bypass — you use the stability-fix lane with auditor Quick mode if it's truly small, or accept the full audit cost if it's not. Constitution § 1 isn't negotiable for emergencies. The discipline is the entire point.

(If your project is in such a fragile state that hotfixes need to ship unaudited, the hotfix isn't the problem — the underlying stability is. Fix that, not the harness.)

### Q: My team doesn't have a second model for cross-model audit

Set `auditor_model = None` to enable single-engine fallback. Fresh-context invocation of the same model still catches a class of errors (the implementer's contextual blind spots) — it just doesn't catch model-prior blind spots. Better than no audit; worse than two-model.

### Q: I want to extend the harness with my own stage / agent / skill

- New agent: copy `agents/_template/junior-agent-template.md`, fill in, register in `junior_reviewers` slot.
- New skill: copy an existing `skills/<skill>/SKILL.md` as a template, follow the shape.
- New stage: this is a non-trivial extension — read `design-spec.md` first to understand why there are 9 stages, then propose changes via the harness's own flow (yes, dogfood your harness on the harness).

---

## Time estimates

```
Phase 0 (preconditions):    5–15 min
Phase 1 (install + slots):  30–60 min  (longer for brownfield with deep customization)
Phase 2 (first feature):    2–4 hours  (first run is slowest; later features run faster)
Phase 3 (gradual adoption): per-feature, asynchronous, on your own schedule
```

The full Phase 0 → 2 install is typically a single afternoon for a solo developer on a clean project.

---

## Submitting to Anthropic Plugin Marketplace

CCC-Harness ships a plugin manifest at `.claude-plugin/plugin.json` so it can be submitted to Anthropic's `claude-community` marketplace.

### Process (manual, external)

1. **Verify the manifest is current**: bump `version` in `outcome/.claude-plugin/plugin.json` to match the new release
2. **Tag the release**: `git tag v0.X.Y && git push --tags`
3. **Fork** `anthropics/claude-plugins-community` on GitHub
4. **Add CCC-Harness** to their `marketplace.json` (or whatever submission format they use at submission time — check current docs)
5. **Open a PR** with the addition
6. **Wait for Anthropic review** (typically 1-2 weeks per their docs)
7. **Once merged**, users can install via `/plugin install @claude-community/ccc-harness`

### Trade-off note

Plugin-only installation gives users the skills (e.g., `/feature-draft`, `/audit-spec`) globally — but NOT the constitution.md, slot registry, or `.harness/state/install.json` (those require per-project installation).

For full CCC-Harness experience: `install-into.sh` or `npx create-ccc-harness` remains the recommended primary path. The plugin marketplace is the "I want the skills, not the discipline" lightweight option.
