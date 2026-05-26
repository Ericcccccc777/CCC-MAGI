# Standalone Bootstrap Driver

**You are an AI assistant reading this file because the host project has CCC-MAGI files present but `.harness/state/install.json` does not yet exist.** This means the user cloned CCC-MAGI from GitHub but has not yet run the configuration flow.

Your task: walk the user through the bootstrap. Follow the steps **literally** — do not improvise, do not skip steps, do not change the menu options.

---

## Language Awareness

This driver is written in English (more stable + token-efficient for AI). When you actually TALK to the user, talk in their OS locale's language. See `CLAUDE.md § Language Awareness` for the full detection + translation rule (run `locale` or read `$LANG`; default English on failure).

The user-facing menus and prompts in this driver are templates — translate them to the user's locale when displaying. The two completion markers (`✓ Task complete, close terminal` / `✗ Task cancelled, close terminal`) are byte-exact and NEVER translated.

---

## Mode detection

This driver covers the **standalone path** (user is NOT running through CCC). The flow is nearly identical to the CCC-bundled Step 1 driver, with two differences:

1. There is no CCC GUI to render output into — you talk to the user in the CLI directly.
2. After completion, you do NOT need to close a terminal — you continue working in the same CLI session.

If you can tell from the environment that you ARE running inside CCC (e.g., env var `CCC_SESSION_ID` is set, or stdout is being scraped by CCC), use the **CCC-bundled** Step 1 driver instead — CCC ships its own which is similar but emits the `✓ Task complete, close terminal` marker at the end. This file is for standalone use.

---

## Step A — Scan for existing harness configurations

Look around the project root. You're looking for **anything that looks like AI workflow / agent / rule configuration**, not just canonical files.

### Layer 1 — Known harness markers (high confidence)

Check existence (directories or files):

- `.bmad-core/` `.bmad/` `bmad-method/` — BMAD-METHOD
- `.speckit/` `speckit.yml` `speckit.yaml` — GitHub SpecKit
- `.openspec/` — OpenSpec
- `.superpowers/` — Superpowers
- `.ruflo/` `.claude-flow/` — Claude-Flow / Ruflo
- `.cursorrules` `.cursor/rules/` — Cursor Rules
- `.clinerules` `.clinerules/` — Cline Rules
- `.windsurfrules` — Windsurf Rules
- `.aider.conf.yml` — Aider
- `.github/copilot-instructions.md` — GitHub Copilot

### Layer 2 — Canonical AI config files (case-insensitive)

The user's filesystem may be case-insensitive (macOS default) — match these regardless of case:

- `CLAUDE.md` / `claude.md` / `Claude.md`
- `AGENTS.md` / `agents.md` / `Agents.md`
- `AGENT.md` / `agent.md` / `Agent.md` (singular variant)

### Layer 3 — AI-shaped directories (open them, list `.md` files inside)

For each of these, if the directory exists, list every `.md` file inside (one level deep is enough):

- `agent/` `agents/`
- `ai/`
- `prompts/` `prompt/`
- `skills/` `skill/`
- `rules/` `ai-rules/`
- `instructions/`
- `harness/`
- `workflow/` `workflows/`

### Layer 4 — Suspicious markdown at project root

Any `*.md` file at project root that is NOT one of the obviously-unrelated names below:

- Exclude: `README.md`, `LICENSE.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `NOTES.md` (if it's just personal notes)
- Exclude ALSO: any file in the "Layer 5 — CCC-MAGI owned" list below (don't double-flag)

For each remaining candidate, **read the first 80 lines** and judge:

- Does it contain AI-workflow keywords like "agent", "workflow", "spec", "harness", "Claude", "AI", "prompt", "stage", "step", "skill", "rule"?
- Is it structured like instructions (numbered steps, sections like "When invoked", "Authoritative sources", "Workflow")?
- Or is it just narrative prose / documentation / notes?

### Layer 5 — CCC-MAGI owned (NEVER flag these as "harness to handle")

These files / directories are **part of CCC-MAGI itself** OR were created BY CCC-MAGI. They are NOT user harness configs. Always filter them out of the "candidate" list and surface them separately in a 🟢 informational section.

**Files we install** (identifiable by name + signature):

| Path | Signature to confirm it's ours |
|------|--------------------------------|
| `constitution.md` (case-insensitive) | Contains string `SLOT REGISTRY` near top |
| `CLAUDE.md` (case-insensitive) | Contains string `Bootstrap Status Check` |
| `AGENTS.md` (case-insensitive) | Contains string `Auditor Instructions (for MAGI / Codex)` |
| `CCC_MAGI_README.md` | Renamed by our installer; presence is sufficient |
| `CCC_MAGI_LICENSE` | Same |
| `.gitignore` | Contains string `.harness/state/auditor-approvals/` if installed by us; if user already had one and we merged, treat as theirs |

**Directories we install** (presence alone confirms ours):

| Directory | Notes |
|-----------|-------|
| `.harness/` | Our state + skills + agents + scripts |
| `.claude/` | Our settings.json (Claude Code config) |
| `.codex/` | Our config.toml + hooks.json (Codex CLI config) |
| `docs-harness/` | Our framework design docs |

**Backup files we created during install** (special category — see Layer 6):

| Pattern | What it is |
|---------|------------|
| `*.pre-ccc-magi` | A backup of a USER file that existed before we installed. The CONTENT is the user's; the FILENAME is ours. Surface these in the 🟡 "your original files (backed up)" section instead of either harness category. |
| `*.pre-ccc-magi.<timestamp>` | Same, but a timestamped variant created when a primary backup name was already taken (e.g., re-install). |

**Verification step**: for any file matching a name in the table above, if its signature is also present, mark it 🟢 (ours, do not handle). If a file has the name but signature does NOT match (e.g., user happened to have their own file called `constitution.md` with different content), it falls back to one of the other layers (probably Layer 4 — suspicious markdown).

### Layer 6 — User's original files backed up by us

Distinct from Layers 1-4 (other harnesses) and Layer 5 (CCC-MAGI self): any file matching `*.pre-ccc-magi` (or `*.pre-ccc-magi.<timestamp>`) is the USER's original file content, preserved automatically when we installed our load-bearing files. These should be surfaced to the user in a dedicated 🟡 section so they understand what those files are (and can decide whether to view / restore / delete them).

Do NOT include these in the 3-option menu set (Step C). The 3-option menu is for "what to do with the user's prior harness configs"; the backups are already preserved and need no archive/delete action. If the user later wants to restore one, that's a manual step.

---

## Step B — Present findings and confirm

Show the user a structured summary in **plain language**. Use a numbered list. Group by confidence level using emoji prefixes.

Template (display IN USER'S LOCALE — translate when showing):

```
I scanned your project. Here's what I found, grouped by whether you need to decide on it:

═══════════════════════════════════════════════════════════════
ITEMS NEEDING YOUR DECISION (numbered = possible harness configs)
═══════════════════════════════════════════════════════════════

📕 Known harness (high confidence):
  1. <path> — <reason: matched <known-marker>>
  2. ...

📗 Looks like harness config (medium confidence — I read the contents):
  3. <path> — <reason: contains <keywords>; structured like <pattern>>
  4. ...

📘 Suspicious markdown at project root (low confidence — please confirm):
  5. <path> — <reason: mentioned <keywords> a few times but content looks like <type>>

═══════════════════════════════════════════════════════════════
INFORMATIONAL ONLY (not asking you about these)
═══════════════════════════════════════════════════════════════

✅ Confirmed unrelated (won't ask):
  - README.md, LICENSE.md (standard project docs)

🟢 CCC-MAGI itself (won't ask — these came with the install):
  - constitution.md (contains SLOT REGISTRY signature)
  - CLAUDE.md (contains Bootstrap Status Check signature)
  - AGENTS.md (contains Auditor Instructions section signature)
  - .harness/, .claude/, .codex/, docs-harness/
  - CCC_MAGI_README.md, CCC_MAGI_LICENSE

🟡 Backups of your original files (won't ask — your content was auto-backed-up):
  - CLAUDE.md.pre-ccc-magi  ← contains your original claude.md content
  - (any other .pre-ccc-magi files)
  
  Note: when CCC-MAGI was installed, we overwrote your CLAUDE.md / AGENTS.md / 
  constitution.md files and auto-backed-up your originals with the .pre-ccc-magi 
  suffix. To view your original content: `cat CLAUDE.md.pre-ccc-magi`. 
  To remove the backups when you no longer need them: `rm` manually. 
  Bootstrap will NOT touch these files.

═══════════════════════════════════════════════════════════════

Please tell me which items are NOT actually harness configs. 
Input numbers separated by spaces (example: "3 5").
Or:
  - Type "all" to confirm all numbered items ARE harness configs
  - Type "none" to confirm none of them are harness → skip Steps C/D, jump to Step E (ask whether to start /init Step 2 configuration)
```

**Important**: 🟢 and 🟡 items are NOT in the numbered list — the user cannot make decisions about them; they're informational only. Numbered options apply ONLY to 📕 / 📗 / 📘 categories.

Wait for user response.

After response, **re-list the updated set** (only the ones still classified as harness):

```
Updated harness file list:
  1. <path>
  2. <path>
  ...

Anything missing or incorrect in this list?
  - If nothing's missing, type "done"
  - Otherwise, describe (e.g., "3 is not harness", "missed my-rules/internal.md")
```

**Loop this confirmation until user says "done".** Do not advance to Step C until the user has explicitly confirmed the list.

### Special case: empty confirmed set

If after the user's responses the confirmed-harness list is **empty** (user marked all candidates as "not harness", or said "none" upfront), there is nothing to archive or delete. **Skip Step C and Step D entirely; jump directly to Step E** (invoke /init for Step 2 configuration).

Acknowledge this to the user before jumping (display in user's locale):

```
You confirmed there are no existing harness configs to handle.
Proceeding directly to Step 2 — CCC-MAGI configuration.
```

Then proceed to Step E.

---

## Step C — Present 3-option menu

After user says "done" **AND the confirmed set is non-empty**, present this menu (display in user's locale):

```
How would you like to handle these harness files?

  [1] Take over + archive (recommended ★)
      → Create old_version_harness/ at project root
      → Move the confirmed files/dirs into it
      → Then start CCC-MAGI configuration (/init flow)
      → Lowest risk: your old files are preserved and reviewable anytime

  [2] Take over + delete
      → Permanently delete the confirmed files/dirs
      → CCC-MAGI takes over the project
      → Warning: deletion is not recoverable

  [3] Skip CCC-MAGI this session
      → For this conversation only, treat CCC-MAGI as not present and continue with the user's request
      → On the next CLI session, this prompt will appear again (until the user picks 1/2 or removes CCC-MAGI files manually)

Please enter 1 / 2 / 3:
```

Wait for user response.

---

## Step D — Execute the chosen option

### If user picks 1 (Take over + archive)

1. Confirm with user one more time (display in user's locale):
   ```
   About to run:
     mkdir old_version_harness
     mv <file-1> old_version_harness/
     mv <file-2> old_version_harness/
     ...
   
   Confirm? (yes / no)
   ```
2. If `yes`:
   - Use the `Bash` tool to create `old_version_harness/` and move each confirmed file/dir into it.
   - Write `old_version_harness/README.md` documenting what was moved (file list, date, reason).
3. Proceed to Step E.

### If user picks 2 (Take over + delete)

1. **Show an explicit warning + require typed confirmation** (display in user's locale):
   ```
   ⚠️ You are about to permanently delete the following files / dirs:
     • <path-1>
     • <path-2>
     ...
   
   This cannot be undone (unless you have a git commit to restore from).
   
   To continue, type uppercase "DELETE" exactly (case-sensitive):
   ```
2. If user types exactly `DELETE` (untranslated — accept the literal English word as the safety phrase, even if conversing in another language):
   - Use the `Bash` tool to `rm -rf` each confirmed file/dir.
3. If user types anything else:
   - Abort the delete action; fall back to the 3-option menu.
4. Proceed to Step E.

### If user picks 3 (Skip this session)

1. Acknowledge (display in user's locale):
   ```
   OK, this session won't use CCC-MAGI.
   I'll proceed with your requests normally.
   
   Note: the CCC-MAGI files are still in your project (.harness/, constitution.md, etc.).
   On your next CLI session, I'll ask again whether you want to install.
   To stop being prompted, manually delete the CCC-MAGI files from your project.
   ```
2. **Stop running this bootstrap driver.**
3. Continue the conversation normally — respond to whatever the user actually wants to do.
4. **Do NOT invoke any `.harness/skills/*` skills this session.** Treat them as not present.
5. **Do NOT write `.harness/state/install.json`** — leave it absent so next session re-prompts.
6. **Do NOT output the success marker** — the user is staying in the same CLI session for actual work, so no terminal-close signal is needed in standalone mode.

### If user picks anything else

Repeat the 3-option menu. Do not improvise variants.

---

## Step E — Trigger CCC-MAGI configuration

**Reached if**: user picked 1 or 2 in Step C, OR confirmed-set was empty (Step B special case).

The CCC-MAGI files are now ready, but project-specific values (L0 slots in `constitution.md`) need to be filled. This is what `/init` skill does. Invoke it:

1. Tell the user (display in user's locale; pick the line matching the path that led here):
   ```
   ✓ Step 1 complete (environment cleaned + CCC-MAGI in place).     ← if came from Step C option 1/2
   ✓ Environment is clean — proceeding directly to configuration.       ← if came from Step B empty-set
   
   Next, Step 2: fill in your project's identity (~16 questions, 5-10 minutes).
   
   Start now? 
     yes / Y → invoke /init now
     no  / N → skip this session; bootstrap will re-prompt next session
     skip   → decline CCC-MAGI entirely (treat as Step C option 3)
   ```
2. **If user says yes**: invoke the `/init` skill (`.harness/skills/init/SKILL.md`). The /init skill handles L0 question flow, slot rendering, validation, and writes `install.json`.
3. **If user says no**: do nothing further this session. Surface this explicit notice (display in user's locale):
   ```
   OK, /init configuration will be skipped this session.
   
   ⚠️ Important: because install.json was not written, the bootstrap flow will run AGAIN on your NEXT CLI session
   (re-presenting Step A scan results + Step B confirmation + Step C 3-option menu).
   
   To avoid being prompted next time, you can:
     a. Answer yes now to complete Step 2
     b. Run /init manually later to complete configuration (writes install.json)
     c. If you've decided against CCC-MAGI, manually delete .harness/ and constitution.md, etc.
   ```
   The user keeps a clean partial-install state; per CCC_harness_flow.md decision 6 (Restart policy) this is expected and benign — bootstrap re-fires next session.
4. **If user says skip**: treat exactly like Step C option 3 — decline CCC-MAGI for this session. This branch is most relevant when Step E was reached via Step B's empty-confirmed-set jump (the user never saw the Step C menu and now wants to back out). Acknowledge (display in user's locale):
   ```
   OK, this session won't use CCC-MAGI.
   I'll proceed with your requests normally.
   
   Note: the CCC-MAGI files are still in your project (.harness/, constitution.md, etc.).
   On your next CLI session, I'll ask again whether you want to install.
   To stop being prompted, manually delete the CCC-MAGI files from your project.
   ```
   - **Stop running this bootstrap driver.**
   - Continue the conversation normally — respond to whatever the user actually wants to do.
   - **Do NOT invoke any `.harness/skills/*` skills this session.** Treat them as not present.
   - **Do NOT write `.harness/state/install.json`** — leave it absent so next session re-prompts.
   - **Do NOT output the success marker** — the user is staying in the same CLI session for actual work, so no terminal-close signal is needed in standalone mode.

---

## Completion criteria

The bootstrap is complete when ONE of the following is true:

1. User picked option 3 → conversation continues without harness this session
2. User picked option 1 or 2 AND user declined Step E → environment is cleaned but config not yet filled (next session: bootstrap sees no install.json → re-prompts; CLAUDE.md still has bootstrap block)
3. User picked option 1 or 2 AND completed `/init` → `install.json` exists → fully configured

For case 3 only, output the completion marker on its own line:

```
✓ Task complete, close terminal
```

This marker is for CCC's terminal monitor. In standalone mode CCC isn't watching, but emitting the marker is harmless and keeps the two modes uniform.

---

## Rules you MUST follow

- **Never skip the user-confirmation loops.** Steps B and C require explicit user input each time.
- **Never delete files in option 1.** Option 1 = move (mv), not delete (rm). Files go to `old_version_harness/`.
- **Never execute option 2 without the typed "DELETE" confirmation.** Anything other than exact `DELETE` aborts.
- **Never write `install.json` if the user picked option 3.** The whole point of option 3 is that the user can re-decide next session.
- **Never invoke `.harness/skills/*` skills under option 3.** Pretend they don't exist for this session.
- **Never improvise the 3-option menu text.** Show exactly the wording above so behavior is predictable.
- **Never advance past Step B without user typing "done".** No silent advance.

---

## What this file is NOT

- This is NOT the `/init` skill. /init is a separate skill at `.harness/skills/init/SKILL.md` that handles L0 question flow. This bootstrap calls /init as the final step (under options 1/2).
- This is NOT the CCC-bundled Step 1 driver. CCC ships its own driver in its app bundle. The two drivers are nearly identical in content but differ in completion behavior (CCC closes terminal; standalone continues working in the same CLI).
- This is NOT for re-configuration. If the user wants to change project identity after installation, they use `/constitution-edit`. If they want to start over completely, they delete `.harness/state/install.json` and re-run this bootstrap.
