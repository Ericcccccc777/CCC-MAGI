# CCC Step 1 Driver — Template

This file is a **template / reference** for the Step 1 driver that CCC (Claude Code Controller) should bundle in its application package.

It is NOT part of the runtime CCC-Harness installed in a user's project. It lives in the CCC-Harness GitHub repo's `docs-harness/` as a reference for the CCC team to copy + adapt into the CCC app bundle.

---

## Where it should live in CCC

```
<CCC project root>/
└── packages/app/resources/
    └── harness-step1-driver.md          ← copy this file's content here
```

This path is a suggestion; the actual location is at CCC's discretion. What matters is that CCC's `SessionManager` (or equivalent) can read this file and inject its contents as a prompt into the spawned AI CLI session.

---

## How CCC uses this driver

```
User clicks "Environment Detection" in CCC's HarnessWizard
   ↓
HarnessWizard sends IPC: HARNESS_STEP1_RUN { sessionPath: "/path/to/user/project" }
   ↓
Main process:
  1. Read packages/app/resources/harness-step1-driver.md
  2. Open new terminal at sessionPath
  3. Launch user's preferred AI CLI (claude / codex / ...)
  4. Inject the driver content as initial prompt
  5. Monitor stdout for "✓ Task complete, close terminal"
   ↓
Driver runs (AI reads driver, walks user through detection + 3-option menu + git pull)
   ↓
On completion marker detected, close terminal
   ↓
HarnessWizard transitions to Step 2 state
```

---

## Driver content (copy below into the CCC bundle's driver file)

```markdown
# CCC Bundled Step 1 Driver

You are an AI assistant invoked by CCC (Claude Code Controller) to perform Step 1 of harness installation: **detect any existing harness configurations in this project + present a 3-option menu to the user + (optionally) pull CCC-Harness from GitHub**.

**You are running inside a CCC-spawned terminal.** Behaviors specific to this environment:

- After completing your task, output the exact string `✓ Task complete, close terminal` on its own line. CCC monitors stdout for this; matching it triggers terminal close.
- You can assume `git`, `bash`, and the user's chosen AI CLI tooling are available in PATH.
- Do NOT prompt the user to "press any key" or other terminal-ish UX — CCC's GUI is also visible; user can scroll back if needed.

## Language Awareness

This driver is written in English (stable + token-efficient). When you talk to the user, talk in their OS locale's language. Detect at session start:

```bash
locale 2>/dev/null | head -1 | sed 's/LANG=//' | sed 's/\..*//'
```

Common locales: `en_*` → English; `zh_*` → 简体/繁體中文; `ja_*` → 日本語; `ko_*` → 한국어. Default English on failure.

User-facing menus and prompts in this driver are templates — translate when displaying. The completion markers (`✓ Task complete, close terminal` / `✗ Task cancelled, close terminal`) are byte-exact and NEVER translated (CCC parses them).

---

## Step A — Scan for existing harness configurations

(Same detection logic as `outcome/scripts/standalone-bootstrap.md` Step A. Refer to that file as the canonical source; the layers are:)

- Layer 1: Known harness markers (BMAD, SpecKit, OpenSpec, Cursor rules, Cline rules, etc.)
- Layer 2: Canonical AI config files, case-insensitive (CLAUDE.md / AGENTS.md / AGENT.md and variants)
- Layer 3: AI-shaped directories (agent/, agents/, ai/, prompts/, skills/, rules/, instructions/, harness/, workflow/)
- Layer 4: Suspicious markdown at project root (excluding README/LICENSE/CHANGELOG/etc., AND excluding anything in Layer 5)
- Layer 5: CCC-Harness owned files — ALWAYS filter out, surface separately in 🟢 section. In CCC mode (this driver), CCC-Harness should NOT yet be present since this driver runs BEFORE git clone. But on a re-run (e.g., user previously clicked Environment Detection then closed without finishing), the partial install may have placed our files; recognize them by name + signature:
  - `constitution.md` + signature `SLOT REGISTRY`
  - `CLAUDE.md` + signature `Bootstrap Status Check`
  - `AGENTS.md` + signature `Auditor Instructions (for Sam / Codex)`
  - `.harness/`, `.claude/`, `.codex/`, `docs-harness/` directories
  - `CCC_HARNESS_README.md`, `CCC_HARNESS_LICENSE`
- Layer 6: User's original files backed up by us — pattern `*.pre-ccc-harness` (or `*.pre-ccc-harness.<timestamp>`). Content is the user's, filename is ours. Surface separately in 🟡 section; do NOT include in the 3-option menu set.

Use `Glob` + `Read` tools to scan. Read first 80 lines of suspicious candidates to make semantic judgments.

## Step B — Present findings and confirm

(Same as standalone-bootstrap.md Step B — refer to it for the canonical output template, including the 5-category grouping: 📕/📗/📘 numbered askable items, ✅ confirmed unrelated, 🟢 CCC-Harness self, 🟡 user's backed-up originals.)

Critical rules:
- Numbered list (1, 2, 3...) ONLY for 📕/📗/📘 items the user actually decides on.
- 🟢 and 🟡 sections are informational — show them so the user understands what's there, but they are NOT in the editable set.
- Loop user confirmation until "done".

### Special case: empty confirmed set

If after the user's responses the confirmed-harness list is **empty** (user marked all candidates as "not harness", or said "none" upfront), there is nothing to archive or delete. **Skip Step C and Step D entirely; jump directly to Step E** (git clone CCC-Harness + then invoke /init for Step 2 configuration).

Acknowledge this to the user before jumping (translate to user's locale per Language Awareness):

```
You confirmed there are no existing harness files to handle.
Proceeding directly to install stage (pull CCC-Harness + configure).
```

Then proceed to Step E. The git clone runs unconditionally; the only thing skipped is the archive/delete action (which has nothing to act on).

## Step C — Present 3-option menu

Display this menu to the user (translate to user's locale per Language Awareness; the template below is English-canonical):

```
How would you like to handle these harness files?

  [1] Take over + archive (recommended ★)
      → Create old_version_harness/ directory at project root
      → Move the confirmed files / directories above into it
      → Then pull CCC-Harness from GitHub
      → On completion, proceed to Step 2 configuration

  [2] Take over + delete
      → Delete the confirmed files / directories above
      → Then pull CCC-Harness from GitHub
      → On completion, proceed to Step 2 configuration
      → Warning: deletion is irreversible

  [3] Decline CCC-Harness
      → Close terminal
      → CCC window will show a "Declined — rerun?" button
      → No files in your project will be modified

Enter 1 / 2 / 3:
```

## Step D — Execute the chosen option

### Option 1 (Archive)

1. Confirm with user.
2. `mkdir old_version_harness && mv <files...> old_version_harness/`
3. Write `old_version_harness/README.md` documenting the archive.
4. Proceed to Step E (git pull).

### Option 2 (Delete)

1. Show explicit warning + require typed `DELETE` confirmation.
2. `rm -rf <files...>`
3. Proceed to Step E.

### Option 3 (Decline)

1. Acknowledge to the user (translate to user's locale):
   ```
   OK — CCC-Harness will not be installed this time.
   ```
2. Output the **decline marker** (NOT the success marker — these are different so CCC can route correctly):
   ```
   ✗ Task cancelled, close terminal
   ```
   Note the leading `✗` (U+2717 BALLOT X) instead of `✓` (U+2713 CHECK MARK). CCC monitors stdout for both markers and routes to different UI states.
3. Halt. CCC closes the terminal; HarnessWizard transitions to "Declined — rerun?" state.

## Step E — Pull CCC-Harness from GitHub

**Reached if**: user picked option 1 or 2 in Step C, OR confirmed-set was empty (Step B special case).

```bash
# CUSTOMIZE THIS COMMAND when CCC-Harness is published.
# Placeholder — actual repo URL/method TBD per CCC_harness_flow.md decision 2 (deferred to Round 3).
git clone https://github.com/<OWNER>/CCC-Harness.git .ccc-harness-temp
```

Then move the cloned contents into the right project locations (mirror of /init Step 4 file mappings):

- `.ccc-harness-temp/constitution.md` → `./constitution.md`
- `.ccc-harness-temp/CLAUDE.md` → `./CLAUDE.md`
- `.ccc-harness-temp/AGENTS.md` → `./AGENTS.md`
- `.ccc-harness-temp/skills/*` → `.harness/skills/`
- `.ccc-harness-temp/agents/*` → `.harness/agents/` (filtered)
- `.ccc-harness-temp/scripts/*` → `.harness/scripts/` (with chmod +x on .sh)
- `.ccc-harness-temp/cli-configs/claude/settings.json` → `.claude/settings.json`
- `.ccc-harness-temp/cli-configs/codex/*` → `.codex/`
- `.ccc-harness-temp/docs-harness/*` → `./docs-harness/`

Clean up:
```bash
rm -rf .ccc-harness-temp
```

Verify the install:
- `constitution.md` exists at project root
- `.harness/scripts/auditor-gate.sh` exists and is executable
- `.harness/scripts/standalone-bootstrap.md` exists

If any verification fails, report it to the user with the specific failure; do NOT emit the completion marker (let CCC's terminal stay open so user can investigate).

## Step F — Output completion marker

**Two possible markers — pick based on outcome:**

### After successful Step E (user picked 1 or 2 and install completed):
```
✓ Task complete, close terminal
```
(Leading `✓` = U+2713 CHECK MARK)

### After Step D Option 3 (user declined):
```
✗ Task cancelled, close terminal
```
(Leading `✗` = U+2717 BALLOT X)

These are the EXACT strings. No variations, no prefixes, no suffixes. Must be on its own line.

CCC monitors stdout for **either** marker:
- Matches `✓ Task complete, close terminal` → terminal closes; HarnessWizard transitions to "Step 1 complete" → enables "Step 2" button
- Matches `✗ Task cancelled, close terminal` → terminal closes; HarnessWizard transitions to "Declined — rerun?" state

Per CCC_harness_flow.md decision 4, the two markers exist specifically so CCC can route to the correct UI state from stdout alone, without filesystem post-checks.

## Completion criteria for Step 1

Step 1 is complete when ALL of the following are true:

1. Detection has surfaced findings to the user (Step B loop completed with "done")
2. User has explicitly picked option 1, 2, or 3 (Step C)
3. The chosen option's action has executed (Step D + E if applicable)
4. One of the two markers has been emitted on its own line (Step F):
   - `✓ Task complete, close terminal` on options 1/2 success path
   - `✗ Task cancelled, close terminal` on option 3 (decline) path

**The completion marker is the contract between this driver and CCC.** Without ANY marker, CCC will hold the terminal open indefinitely. Emitting the WRONG marker will route CCC's UI to the wrong state.

---

## Rules you MUST follow

(Same as standalone-bootstrap.md "Rules you MUST follow" section.)

- Never skip the user-confirmation loops
- Never delete files under option 1 (move only)
- Never execute option 2 without typed DELETE confirmation
- Never improvise the 3-option menu text
- Never skip emitting the completion marker — CCC depends on it
- Never emit `✓` marker on Option 3 (decline) — that would route CCC to "Step 1 complete" instead of "Declined". Emit `✗` instead.
```

---

## What CCC needs to provide alongside this driver

For this driver to work, CCC must:

1. **Bundle this `.md` file** in its app resources
2. **Spawn a terminal** at the user's session path
3. **Launch the chosen AI CLI** in that terminal (existing CCC capability via `SessionManager.launchInteractive()`)
4. **Inject this driver's content as the initial prompt** (new capability — currently CCC doesn't do prompt injection at session start; needs new IPC channel and main-process handler)
5. **Monitor terminal stdout** for the completion marker `✓ Task complete, close terminal` and close the terminal when matched
6. **Transition HarnessWizard UI state** based on Step 1 outcome (success → enable Step 2 button; declined → show "Rerun" button)

Per `CCC_harness_flow.md` § 9.2, this maps to:
- New file: `<CCC>/packages/app/resources/harness-step1-driver.md`
- Updated `<CCC>/packages/app/src/main/SessionManager.ts` — add prompt injection capability
- Updated `<CCC>/packages/app/src/shared/ipc-channels.ts` — add `HARNESS_STEP1_RUN` channel
- Updated `<CCC>/packages/app/src/renderer/src/components/HarnessWizard.tsx` — enable the previously-dormant flow

---

## Difference vs standalone-bootstrap.md

| Aspect | This driver (CCC-bundled) | standalone-bootstrap.md (in CCC-Harness) |
|--------|---------------------------|-------------------------------------------|
| Where bundled | CCC app package | CCC-Harness GitHub repo |
| Triggered by | CCC UI button | CLAUDE.md Bootstrap Status Check block |
| Includes git clone? | **Yes** (Step E pulls CCC-Harness) | No (CCC-Harness already cloned by user manually) |
| Completion marker | **Required** (CCC closes terminal on match) | Optional (no terminal to close in standalone) |
| Option 3 behavior | Closes terminal + CCC shows "declined" UI | AI continues working in same CLI session |

---

## Version

```
2026-05-21 v1 — initial template; CCC team copies into bundle
```
