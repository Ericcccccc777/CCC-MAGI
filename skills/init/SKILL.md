---
name: init
description: Project configuration. Asks L0 slot questions, fills constitution.md, scaffolds .harness/ + .claude/ + .codex/ in the user's project, and writes the install.json that marks the harness as fully configured. This skill assumes existing-harness detection has already been handled by the bootstrap; it does NOT run detection itself. Works in two modes — interactive (standalone CLI use) and CCC-driven (CCC's HarnessWizard invokes /init programmatically with pre-collected answers). Trigger when the user invokes /init, says "set up the harness", "configure CCC-Harness", "fill the L0 questions", or arrives here from the bootstrap flow (standalone-bootstrap.md or CCC's bundled Step 1 driver).
argument-hint: [--ccc-driven] [--config <yaml>] [--force]
---

# /init

Drive the configuration step of harness setup — what CCC's flow calls "Step 2".

> *Constitutional basis: this skill fills constitution.md (Section 2 — Project Identity) with the user's specific values, then writes `.harness/state/install.json` as the canonical "configured" marker that all other systems (CCC's session-open check, CLAUDE.md's Bootstrap Status Check, the AI-driven detection in `standalone-bootstrap.md`) use to know the harness is ready.*

## Language Awareness

This skill's instructions are in English (more stable + token-efficient). When you ask the 16 L0 questions of the user, ask in their OS locale's language. See `CLAUDE.md § Language Awareness` (detect via `locale` / `$LANG`; default English).

The question templates below are written in English; translate them to the user's locale when actually displaying. Slot VALUES that the user types (project name, description, etc.) get written verbatim to constitution.md — don't translate user-entered content.

## Where this skill sits in the bootstrap flow

```
Existing harness present?
  ↓                          (handled by:)
  Step 1 — Bootstrap         standalone-bootstrap.md  OR  CCC bundled Step 1 driver
  - Detect existing harness
  - 3-option menu (archive / overwrite / decline)
  - Archive or delete other configs
  ↓
  Step 2 — /init (this skill)
  - Project mode detection
  - L0 question flow
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

| Mode | How it's triggered | Behavior |
|------|---------------------|----------|
| **Interactive (default)** | User runs `/init` in CLI | Asks each L0 question; user types answers |
| **CCC-driven** | CCC's HarnessWizard invokes `/init --ccc-driven --config <yaml>` | Reads answers from `<yaml>`; only asks for missing fields or confirmations |
| **Force re-init** | `/init --force` | Overrides the "already configured" guard at Step 0. Re-runs the full flow, overwriting the prior install. |

---

## Step 0 — Precondition check (do not skip)

Before doing anything, check the current state:

```bash
test -f .harness/state/install.json
```

### If install.json EXISTS

Surface to the user (display in user's locale):

```
⚠️  Detected an existing CCC-Harness install:
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

## Step 2 — L0 slot question flow

All L0 slots from `constitution.md` § Slot registry must be filled. Total: **16 L0 slots**.

### Greenfield mode

Ask each L0 question fresh. Group them into thematic blocks to reduce fatigue:

**Convention for every block below**: at the top of each block, tell the user once:
`(Per question: [Enter] = accept default / type a new value / type "skip <Qn>" to skip)`.
Then individual questions DO NOT repeat the "press Enter to accept" reminder. Brief
industry-common examples are inline (in parentheses) to help the user pick.

#### Block A — Identity (4 questions)

```
─── Block A · Project Identity (4 questions) ───────────────────
(Per question: [Enter] = accept default / type a new value / type "skip <Qn>" to skip)

Q1. Project name (default: auto-detected from manifest)
    e.g.: acme-app / blog-site / dev-tool

Q2. One-sentence description (plain language, no jargon)
    e.g.: "team chat app with file sharing" / "B2B SaaS reporting tool"

Q3. Project stage?
    a. early   — just starting, no users yet
    b. beta    — internal testing / small user group
    c. prod    — publicly released, has users
    d. scale   — at scale, operations-mature
    (common: solo projects → usually a; team projects → usually b)

Q4. Target scale
    e.g.: "100 users" / "10k DAU" / "internal company use"
```

#### Block B — Scope + Discipline (3 questions)

```
─── Block B · Scope + Discipline (3 questions) ─────────────────
(Per question: [Enter] = accept default / type a new value / type "skip <Qn>" to skip)

Q5. Team size?
    a. solo    — one developer (default)
    b. small   — 2-5 people
    c. large   — 6+ people

Q6. What is this harness primarily protecting?
    e.g.: stability / security / velocity / compliance

Q7. What is explicitly NOT in the harness's scope?
    e.g.: marketing copy / customer support / legal terms / server ops
    (one item per line)
```

#### Block C — Engine (2 questions)

```
─── Block C · Engine (2 questions) ─────────────────────────────
(Per question: [Enter] = accept default / type a new value / type "skip <Qn>" to skip)

Q8. Single-engine or dual-engine?
    a. Dual-engine (recommended) — Claude writes code; a second model (default: Codex / gpt-5.5) independently audits.
    b. Single-engine             — Only Claude; audit runs as a fresh-context Claude call (fallback).
                                   Simpler but weaker bias-cancellation guarantee.

Q9. Conversation language style?
    a. plain        — plain language by default; AI strips jargon from prompts (recommended)
    b. professional — technical terms allowed
```

#### Block D — Project identity (5 questions — these go to constitution Section 2)

```
─── Block D · Project Identity / Red Lines (5 questions) ───────
(Per question: [Enter] = accept default / type a new value / type "skip <Qn>" to skip)

Q10. Who do you serve? (one sentence)
     e.g.: "independent writers" / "small-business CRM users" / "developers of developer tools"

Q11. What do you deliberately NOT do? (project-identity-level "no")
     e.g.: "Never add collaboration features — this is a single-user tool"
           "Never store user payment data — use Stripe"

Q12. Compliance / legal floors?
     a. GDPR (EU data protection)
     b. HIPAA (US healthcare)
     c. PCI   (payment cards)
     d. none  (no mandatory regulations)
     e. other (please specify)

Q13. Performance floors (non-negotiable)?
     e.g.: "cold start < 2s" / "99.9% availability" / "any user action < 200ms response"
     Type "none" if you don't have one yet.

Q14. Any other "if-violated-this-is-no-longer-this-project" statements?
     (optional)
```

#### Block E — Paths (2 questions, with defaults)

```
─── Block E · Paths (2 questions) ──────────────────────────────
(Per question: [Enter] = accept default / type a new value / type "skip <Qn>" to skip)

Q15. Where should feature spec files live?
     Default: docs/features/
     e.g.: docs/features/ / specs/ / .specs/

Q16. Where should implementation-notes files live?
     Default: docs/features/ (same directory as specs)
     e.g.: docs/features/ / docs/impl/
```

### Brownfield mode

Same questions, but auto-detect defaults before asking:

- **Q1 (project_name)**: scan `package.json:name`, `pyproject.toml:name`, `Cargo.toml:name`, `go.mod`, `composer.json:name` → propose as default
- **Q2 (project_description)**: scan README.md first paragraph → propose
- **Q3 (project_stage)**: heuristic — if git log < 30 commits AND no test files: early; if has tests + CI but no production marker: beta; otherwise: prod (low confidence — confirm)
- **Q5 (team_size)**: count distinct git authors in last 90 days → propose
- Q4, Q6-Q14 must be asked (no reliable auto-detect)

For each auto-detected default, show (in user's locale):
```
Q1. Project name (detected from package.json: "my-app")
    Press Enter to accept, or type a new value:
```

### Confirmation block

After all 16 questions, show the full L0 slot table for confirmation (display in user's locale):

```
About to write the following L0 configuration to constitution.md:

  project_name              : my-app
  project_description       : A note-taking tool for indie writers
  project_stage             : beta
  ...

All correct? Type "yes" to continue, or "no" to re-answer any question:
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

```bash
cat > .harness/state/install.json <<JSON
{
  "installed_at": "<ISO-8601 timestamp>",
  "harness_version": "<harness package version>",
  "mode": "<greenfield|brownfield>",
  "language_mode": "<plain|professional>",
  "auditor_model": "<Codex|None|...>",
  "junior_reviewers_enabled": [<list of enabled reviewer plugin names>],
  "skill_set_version": "<sha-or-timestamp-of-source-skills>"
}
JSON
```

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
✅ CCC-Harness fully configured.

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
