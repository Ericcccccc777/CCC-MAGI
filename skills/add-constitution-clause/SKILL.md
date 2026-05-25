---
name: add-constitution-clause
description: Append a new project-specific red line to constitution.md § Section 3. Use when the user wants to add a project-wide, absolute, identity-changing rule. The skill validates the rule meets the 3 promotion criteria (project-wide / absolute / identity-changing) and refuses to add area-specific or contextual rules. Trigger when the user invokes /add-constitution-clause, says "add a red line", "add a project rule", "promote this to constitution", or similar identity-rule intent.
allowed-tools: Read, Edit, Bash(date:*), Bash(grep:*)
argument-hint: <text of the new red line>
---

# /add-constitution-clause

Append a new project-specific red line to `constitution.md § Section 3 — Project-specific red lines`. Smaller surface than `/constitution-edit` (which also handles Section 2 and the slot registry); this skill only writes to Section 3.

> *Spec-Kit-pattern audit trail. The Sync Impact Report turns ad-hoc constitution edits into versioned, semver-bumped, auditable changes.*

## Language Awareness

This skill's instructions are in English. When you talk to the user (asking the criteria questions, proposing the clause, confirming), use the user's OS locale language. See `CLAUDE.md § Language Awareness`. The text written INTO `constitution.md` stays verbatim per what the user approves; do not translate user-entered content.

## What this skill produces

A modified `constitution.md` with:

1. A new numbered clause appended to Section 3 (Project-specific red lines).
2. A Sync Impact Report HTML comment regenerated at the top of the file documenting the new clause.

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

## Step 1 — Understand the rule

1. Parse `$ARGUMENTS` as the proposed red line text.

2. If `$ARGUMENTS` is empty, ask:

   ```
   What's the red line you want to add? Describe the constraint in one or two sentences.
   ```

   **Wait for user response before continuing.**

---

## Step 2 — Validate against the 3 promotion criteria

The constitution.md § Section 3 prelude lists 3 promotion criteria. A rule should only be promoted to Section 3 if it meets ALL THREE:

- Project-wide scope (NOT area-specific)
- Absolute (no exceptions, no lane override)
- Identity-changing (violating it makes this no longer this project)

Walk the user through these checks. Display:

```
Before adding to Section 3, confirm this rule meets all THREE criteria:

  1. PROJECT-WIDE SCOPE — does this rule apply across the whole project?
     (Area-specific rules belong in rule sources or scoped CLAUDE.md, not here.)
     Example fail: "All React components must use TypeScript" (area-specific to frontend)
     Example pass: "PII must never be sent to client without RLS gating" (project-wide)

  2. ABSOLUTE — does this rule admit ZERO exceptions?
     (Rules with lane overrides or "unless X" carve-outs belong in operating
     principles, not red lines.)
     Example fail: "Tests required, except trivial-lane" (has lane exception)
     Example pass: "No third-party trackers in production" (absolute)

  3. IDENTITY-CHANGING — would violating this rule mean this is no longer
     THIS project?
     (Rules that are merely "preferences" or "best practices" don't qualify.)
     Example fail: "Use 2-space indent" (style preference, not identity)
     Example pass: "No user data leaves the EU" (identity for an EU-only product)

Does your proposed rule meet ALL three criteria?
  [y] yes — proceed
  [n] no — let me reconsider; cancel this skill
  [explain] tell me which criterion(ia) you're unsure about, I'll help judge

Wait for user response before continuing.
```

Branch:

- `[y]` → proceed to Step 3.
- `[n]` → abort silently; write nothing.
- `[explain]` → ask which criterion the user is unsure about, walk through it with them in plain language, then re-present the y/n choice. Loop until `[y]` or `[n]`.

---

## Step 3 — Format the clause

Format the user's text as a numbered Section 3 clause. Convention:

```markdown
### N. <short title in title case>

<one-paragraph rule statement>
```

Where `N` is the next available number in Section 3. Read `constitution.md` to find the highest existing clause number under `## Section 3 — Project-specific red lines` (look for `### N.` headings); increment by 1. If Section 3 has no existing clauses yet (still holds the `{{project_red_lines}}` placeholder or is empty after the prelude), use `N = 1`.

Propose a short title in title case derived from the rule text (Tech Lead chooses a reasonable phrase). Show the formatted version to the user:

```
Proposed clause to append to Section 3:

  ### <N>. <title>

  <text>

Approve?
  [a] approve as proposed
  [b] modify (tell me what to change)
  [c] cancel

Wait for user response before continuing.
```

Branch:

- `[a]` → proceed to Step 4.
- `[b]` → accept user revisions to title and/or body; re-show the proposal; loop until `[a]` or `[c]`.
- `[c]` → abort silently; write nothing.

---

## Step 4 — Apply edit

Use the Edit tool to append the new clause to `## Section 3 — Project-specific red lines` in `constitution.md`.

Placement rules:

- If the `{{project_red_lines}}` placeholder is still present in Section 3 (early project, Section 3 has no clauses yet), **replace** the placeholder with the new clause.
- If `{{project_red_lines}}` has already been replaced with rendered content (one or more `### N.` clauses), **append** the new clause AFTER the last existing clause.

Do NOT touch:

- The Section 3 prelude (the `> Starts empty…` blockquote and the 3-criteria bullet list).
- Section 1 (Universal Core) — harness-guaranteed, read-only.
- Section 2 (Project Identity) — out of scope for this skill (use `/constitution-edit` for Section 2 changes).
- The slot registry HTML comment.

---

## Step 5 — Generate Sync Impact Report

Identical machinery to `/constitution-edit`. Compute bump = MINOR (this skill always adds new content). Compute new version from old (`X.Y.Z` → `X.(Y+1).0`).

Build the report block. Use `date -u +%Y-%m-%dT%H:%M:%SZ` for the timestamp:

```html
<!-- Sync Impact Report
Version: <old> → <new> (MINOR — add Section 3 clause #N: <title>)
Modified items:
  - Section 3 — added clause #N: <title>
Templates needing update:
  - <any files referencing {{project_red_lines}}>
Generated: <ISO 8601 UTC>
-->
```

If no other files reference `{{project_red_lines}}`, write `Templates needing update:` followed by `  - N/A`.

Placement:

- If an existing Sync Impact Report block already lives at the top of `constitution.md` (immediately after the title heading), **REPLACE** it with the new block. Only one block lives in the file at a time — `git log` is the audit trail.
- Otherwise, **INSERT** the new block immediately after the title line (`# <project> — Constitution`) and before the next content.

---

## Step 6 — Wrap up

Display to the user (in their locale):

```
✓ Constitution updated to version <new>.

New clause #N appended to Section 3:
  "<title>"

Sync Impact Report regenerated at top of constitution.md.

Next steps:
  1. Commit when ready (use /commit).
  2. If this clause has implications for existing code, audit with /audit-spec.
```

---

## Rules

- **Never edit Section 1 or Section 2.** Use `/constitution-edit` for Section 2 changes; Section 1 is harness-guaranteed and cannot be edited by any skill.
- **Never skip the 3-criteria validation in Step 2.** A rule that fails any one of project-wide / absolute / identity-changing belongs elsewhere (operating principles, rule sources, anti-flag rules), not in Section 3.
- **Never commit or push from this skill.** Edits land as working-tree changes. The user commits via `/commit` when ready.
- **Always regenerate the Sync Impact Report** (consistency with `/constitution-edit` — Section 3 edits are versioned changes).
- **Never translate user-entered clause content.** Write verbatim what the user approved at Step 3.

---

## Trust contract

- This skill modifies **exactly one file**: `constitution.md`.
- It only writes to Section 3 and the Sync Impact Report block; Sections 1, 2, the slot registry, and the prelude of Section 3 stay untouched.
- If the user cancels at any confirmation step, nothing is written.
- The Sync Impact Report is always regenerated fresh — only one block at a time in the file.

---

## Completion criteria

`/add-constitution-clause` is complete when:

- Step 0 has run (pre-flight checks pass)
- Step 1 has captured the proposed rule text
- Step 2 has been answered `[y]` (or cancelled — in which case nothing else runs)
- Step 3 has been approved by the user (or cancelled)
- Step 4 has appended the new clause to Section 3
- Step 5 has regenerated the Sync Impact Report at the top of `constitution.md`
- Step 6 has displayed the wrap-up message
