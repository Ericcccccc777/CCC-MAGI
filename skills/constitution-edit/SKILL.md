---
name: constitution-edit
description: Edit the project constitution.md and update its Sync Impact Report. Use when the user wants to add, modify, or remove a principle in Section 2 (Project Identity), Section 3 (Project Red Lines), or the slot registry. CANNOT modify Section 1 (Universal Core) — those are harness-guaranteed invariants that no edit can remove. Generates a versioned Sync Impact Report at the top of constitution.md.
allowed-tools: Read, Edit, Bash(date:*), Bash(grep:*), Bash(git diff:*), Bash(git status:*)
argument-hint: <description of the change>
---

# /constitution-edit

Edit `constitution.md` Section 2 (Project Identity), Section 3 (Project Red Lines), or the slot registry, and prepend a versioned Sync Impact Report HTML comment that documents the change.

> *Spec-Kit-pattern audit trail. The Sync Impact Report turns ad-hoc constitution edits into versioned, semver-bumped, auditable changes — without burdening the file with full history (that's what `git log` is for).*

## Language Awareness

This skill's instructions are in English. When you talk to the user (proposing the change, asking for confirmations, summarizing results), use the user's OS locale language. See `CLAUDE.md § Language Awareness`. The text written INTO `constitution.md` stays verbatim per what the user approves; do not translate user-entered content.

## What this skill produces

A modified `constitution.md` with:

1. The approved edit applied to Section 2, Section 3, or the slot registry.
2. A Sync Impact Report HTML comment prepended at the top of the file, immediately after the title heading and before the existing file-description comment. Format:

```html
<!-- Sync Impact Report
Version: <old> → <new> (<MAJOR|MINOR|PATCH> — <short description>)
Modified items:
  - <section name> — <what changed>
  - <section name> — <what changed>
Templates needing update:
  - <file path> — <status: ✅ updated / ⚠ pending review / N/A>
Generated: <ISO 8601 UTC timestamp>
-->
```

Only one Sync Impact Report block lives in the file at a time — the most recent one. Prior versions live in `git log`.

## Semver rules

- **MAJOR** — removes or substantively changes a principle that was already in Section 2 / Section 3 / slot registry
- **MINOR** — adds a new principle to Section 2 / Section 3, or adds a new slot to the registry
- **PATCH** — wording / clarification / typo / non-semantic refactor

If multiple changes apply in one `/constitution-edit` invocation, take the highest applicable bump.

If no prior Sync Impact Report block exists in `constitution.md`, treat the current state as version `1.0.0`.

---

## Step 0 — Pre-flight

1. Verify `constitution.md` exists at project root:

   ```bash
   test -f constitution.md
   ```

   If missing, fail with the message:

   ```
   constitution.md not found — run /init first.
   ```

   Halt the skill.

2. Read `constitution.md` fully (Read tool).

3. Extract the current version from any existing Sync Impact Report block at the top:

   ```bash
   grep -m1 -oE 'Version: [0-9]+\.[0-9]+\.[0-9]+ →' constitution.md
   ```

   If no Sync Impact Report block exists, treat the current state as `1.0.0`.

---

## Step 1 — Understand the change

1. Parse `$ARGUMENTS` as the change description (free text from the user).

2. If `$ARGUMENTS` is empty, ask the user:

   ```
   What do you want to change in the constitution? Examples:
     - "add a red line about no third-party trackers"
     - "reword the audience to mention enterprises"
     - "add a slot for retry-policy"
   ```

   **Wait for user response before continuing.**

3. Identify which section(s) the change will affect:

   - **Section 1 (Universal Core)** → REJECT with the message below and halt:

     ```
     /constitution-edit cannot modify Section 1 (Universal Core). These are harness-guaranteed invariants that no project edit can remove. If you want to ADD a new project-level red line, use Section 3 instead.

     If you genuinely need a constitutional change at the harness level, modify outcome/constitution.md directly in the harness source — but understand that doing so changes the harness itself, not your project.
     ```

   - **Section 2 (Project Identity)** → proceed
   - **Section 3 (Project Red Lines)** → proceed
   - **Slot registry** (the HTML comment block at the top of `constitution.md`) → proceed

---

## Step 2 — Propose the edit

1. Based on the change description, propose the EXACT text to add / modify / remove.

2. Format the proposal as a diff-style preview, in the user's locale:

   ```
   Proposed change to <section>:

   <diff-style preview: -old / +new>

   Type:
     [a] approve as proposed
     [b] modify (tell me what to change)
     [c] cancel
   ```

3. **Wait for user response before continuing.**

   - `[a]` → proceed to Step 3
   - `[b]` → accept the user's revisions; re-show the proposal; loop until `[a]` or `[c]`
   - `[c]` → abort silently; write nothing

---

## Step 3 — Determine semver bump

Auto-detect the bump type from the approved change:

| Change shape | Proposed bump |
|--------------|---------------|
| Adding new content (new principle / new slot) | MINOR |
| Removing existing content | MAJOR |
| Substantively rewording existing content (meaning changes) | MAJOR |
| Typo / clarification / non-semantic rewording | PATCH |

Show to the user:

```
Bump type: <type>. Override?
  [Enter] accept
  [m] major
  [n] minor
  [p] patch
```

**Wait for user response before continuing.**

Compute the new version from the old one (`X.Y.Z`):

- MAJOR → `(X+1).0.0`
- MINOR → `X.(Y+1).0`
- PATCH → `X.Y.(Z+1)`

---

## Step 4 — Apply the edit

Use the Edit tool to apply the approved change from Step 2 to `constitution.md`. This is the content edit only; the Sync Impact Report block is prepended later in Step 7.

---

## Step 5 — Detect affected templates

For each affected slot or principle, identify downstream files that may need review:

1. **If a slot was added or changed**: search for `{{<slot_name>}}` references across the running scope (the harness installation root — typically the project root containing `constitution.md`, `CLAUDE.md`, `AGENTS.md`, and `.harness/`):

   ```bash
   grep -rln "{{<slot_name>}}" .
   ```

   Capture matching file paths.

2. **If a Section 2 or Section 3 principle was added**: identify SKILL.md files that consume constitution rules. Heuristic — any SKILL.md referencing `constitution.md` in its body:

   ```bash
   grep -rln "constitution.md" .harness/skills/ 2>/dev/null
   ```

   Mark them as needing review.

If no affected templates can be confidently identified, list:

```
(none detected — review SKILL.md files manually if change is structural)
```

---

## Step 6 — Generate Sync Impact Report block

Build the report block. Use `date -u +%Y-%m-%dT%H:%M:%SZ` for the timestamp:

```html
<!-- Sync Impact Report
Version: <old> → <new> (<bump> — <one-line description>)
Modified items:
  - <section> — <what changed>
Templates needing update:
  - <file path> — <status>
Generated: <ISO 8601 UTC timestamp>
-->
```

Status values for "Templates needing update":

- `✅ updated` — only used if the skill itself edited the template (this skill does NOT auto-edit templates; reserved for future use)
- `⚠ pending review` — default for any detected template
- `N/A` — no templates affected

---

## Step 7 — Prepend to constitution.md

1. If an existing Sync Impact Report block already lives at the top of `constitution.md` (immediately after the title heading), **REPLACE** it with the new block. Do not preserve historic blocks in the file — `git log` is the audit trail.

2. Otherwise, **INSERT** the new block immediately after the title line (`# <project> — Constitution`) and before the next content (typically the existing file-description HTML comment).

Use the Edit tool. After writing, read back and show the top 30 lines of `constitution.md` to the user for visual confirmation.

---

## Step 8 — Wrap up

Display to the user (in their locale):

```
✓ Constitution updated to version <new>.

Sync Impact Report prepended to constitution.md.

Affected templates (if any) marked ⚠ pending review:
  - <file1>
  - <file2>

Next steps:
  1. Review and update marked templates as needed.
  2. Commit when ready (use /commit).
```

If no templates were detected, omit the "Affected templates" list and replace with:

```
No downstream templates detected as affected.
```

---

## Rules / Anti-patterns

- **Never edit Section 1 (Universal Core)** — reject at Step 1 with the explicit message.
- **Never auto-edit downstream templates** — only mark them ⚠ for human review. Auto-modification risks silent corruption.
- **Never skip the user confirmation at Step 2** — the proposed edit must be approved before it lands.
- **Never preserve historic Sync Impact Report blocks** in `constitution.md` — exactly one block always; `git log` carries the history.
- **Never run `git commit` or `git push` from this skill** — edits land as working-tree changes. The user commits via `/commit` when ready.
- **Never translate user-entered constitution content** — write verbatim what the user approved at Step 2.

---

## Trust contract

- This skill modifies **exactly one file**: `constitution.md`.
- It never reads, modifies, or deletes any other project file (it MAY read SKILL.md files in Step 5 detection, but does not write to them).
- Section 1 of `constitution.md` is treated as read-only by this skill.
- If the user cancels at Step 2, nothing is written.
- The Sync Impact Report is always prepended fresh — only one block at a time in the file.

---

## Completion criteria

`/constitution-edit` is complete when:

- Step 0 has run (pre-flight checks pass)
- Step 1 has run (change identified and section confirmed; Section 1 attempts rejected)
- Step 2 has been approved by the user (or cancelled — in which case nothing else runs)
- Step 3 has determined the new semver version
- Step 4 has applied the content edit
- Step 5 has detected affected templates (or determined none)
- Step 6 has built the Sync Impact Report block
- Step 7 has prepended the block to `constitution.md` and shown the result to the user
- Step 8 has displayed the wrap-up message
