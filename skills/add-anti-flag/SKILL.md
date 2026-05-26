---
name: add-anti-flag
description: Append an anti-flag rule to AGENTS.md so the auditor stops flagging a project-specific convention as a false positive. Use when an audit produced a finding that's actually a deliberate project decision (not a bug). Trigger when the user invokes /add-anti-flag, says "this is a false positive don't flag", "add an anti-flag rule", "auditor is wrong about X", or similar suppress-the-finding intent.
allowed-tools: Read, Edit, Bash(date:*), Bash(grep:*)
argument-hint: <text describing the convention being flagged incorrectly>
---

# /add-anti-flag

Grow the L2 anti-flag rules in `AGENTS.md` over time. Each new rule tells the auditor (MAGI / `{{auditor_model}}`) that a specific project-specific convention LOOKS like an issue but is deliberately how this project does it — don't flag it as a finding.

> *Companion to `/add-constitution-clause`. Anti-flag rules are area-level conventions; red lines are project-wide identity. Most "this is fine, stop flagging it" content belongs here, not in the constitution.*

## Language Awareness

This skill's instructions are in English. When you talk to the user (asking the criteria questions, proposing the rule, confirming), use the user's OS locale language. See `CLAUDE.md § Language Awareness`. The text written INTO `AGENTS.md` stays verbatim per what the user approves; do not translate user-entered convention content.

## What this skill produces

A modified `AGENTS.md` with one new anti-flag bullet appended to the `## Anti-flag rules — do NOT flag these as issues` section. The `### Architecture posture (default, applies to all projects)` sub-section stays untouched.

---

## Step 0 — Pre-flight

1. Verify `AGENTS.md` exists at project root. If missing, fail with:

   ```
   AGENTS.md not found — run /init first.
   ```

   Halt the skill.

2. Read `AGENTS.md` fully (Read tool).

3. Locate the anti-flag rules section. Look for either:

   - The `{{anti_flag_rules}}` placeholder (early project, no anti-flag rules yet), OR
   - Already-rendered bullet rules under `## Anti-flag rules — do NOT flag these as issues` and before `### Architecture posture (default, applies to all projects)`.

   If neither is present, surface the issue and halt — the AGENTS.md structure has been edited beyond what this skill can safely modify.

---

## Step 1 — Understand the convention

1. Parse `$ARGUMENTS` as the convention description.

2. If `$ARGUMENTS` is empty, ask:

   ```
   What convention is the auditor incorrectly flagging? Describe:
     - What X is (the correct pattern in THIS project)
     - What Y is (the alternative the auditor keeps suggesting)
     - Why X is right for this project
   ```

   **Wait for user response before continuing.**

---

## Step 2 — Validate this is actually project-specific

Anti-flag rules are for **project-specific conventions** that look universally wrong but are actually right for this project. Walk the user through the 3 criteria:

```
Before adding, confirm:

  1. Is this convention SPECIFIC to this project, not a universal best
     practice that just happens to be ignored here?
     (If it's a universal best practice, the auditor is right; fix the code,
     don't suppress the warning.)
     Example fail: "Don't flag missing try/catch" (universal best practice — fix the code)
     Example pass: "Don't suggest TypeScript — this project deliberately stays
                   plain JS for zero-build static deploy"

  2. Is the auditor's suggestion (Y) actually WRONG for this project,
     not just suboptimal?
     (If Y is also OK, just slightly preferred elsewhere, don't add a rule —
     the auditor's advisory is fine to ignore case-by-case.)
     Example fail: "Don't suggest extracting helper functions" (Y is fine,
                   just not always needed — case-by-case judgment is OK)
     Example pass: "Don't suggest CDN libs — every JS file must be in this
                   repo, no external deps allowed"

  3. Does this rule have a documented reason that future-you will agree
     with in 6 months?
     (Reason should be a constraint or trade-off, not a passing whim.)

Does your proposed anti-flag rule meet all three criteria?
  [y] yes — proceed
  [n] no — reconsider; cancel
  [explain] help me judge

Wait for user response before continuing.
```

Branch:

- `[y]` → proceed to Step 3.
- `[n]` → abort silently; write nothing.
- `[explain]` → ask which criterion the user is unsure about, walk through it with them, then re-present y/n. Loop until `[y]` or `[n]`.

---

## Step 3 — Format the rule

Use the default anti-flag rule format per AGENTS.md's template:

```markdown
- **<X> is correct, <Y> is BANNED.**
  Don't suggest switching to Y. (Reason: <why this project chose X>)
```

Propose the formatted rule to the user with their content filled in:

```
Proposed anti-flag rule to append to AGENTS.md:

  - **<convention X> is correct, <alternative Y> is BANNED.**
    Don't suggest switching to Y. (Reason: <reason>)

Approve?
  [a] approve as proposed
  [b] modify (tell me what to change)
  [c] cancel

Wait for user response before continuing.
```

Branch:

- `[a]` → proceed to Step 4.
- `[b]` → accept user revisions to X, Y, or Reason; re-show the proposal; loop until `[a]` or `[c]`.
- `[c]` → abort silently; write nothing.

---

## Step 4 — Apply edit

Use the Edit tool to append the new rule to the anti-flag section in `AGENTS.md`.

Placement rules:

- If the `{{anti_flag_rules}}` placeholder is still present in the section → **replace** the placeholder with the new rule (becomes the first rule).
- If `{{anti_flag_rules}}` has already been replaced with rendered content (one or more bulleted rules) → **append** the new rule after the last existing rule, maintaining the bulleted list format. Place the new rule consistently AFTER existing user-added rules.

Do NOT touch:

- The `### Architecture posture (default, applies to all projects)` sub-section — that's the stack-agnostic default, shipped with the harness and not user-grown.
- Any other part of `AGENTS.md` (the auditor identity preamble, `## Your role`, `## Doc-in-sync verification`, `## Verdict output`, etc.).

This skill writes to the anti-flag bullet list ONLY.

---

## Step 5 — Wrap up

Display to the user (in their locale):

```
✓ Anti-flag rule appended to AGENTS.md.

The auditor (MAGI / {{auditor_model}}) will skip this finding in future audits.

  - <X> is correct, <Y> is BANNED.

If a future audit still flags this, two reasons:
  1. The rule wording doesn't catch the pattern — refine via re-running /add-anti-flag with clearer X/Y/Reason
  2. The flagged code doesn't match the rule's convention — the finding may be valid

Commit when ready (use /commit).
```

---

## Rules

- **Never bypass the 3-criteria validation** (Step 2). Universal best practices and case-by-case advisories don't belong in anti-flag rules.
- **Never edit the Architecture posture sub-section.** It is stack-agnostic default content shipped with the harness; user-added rules go in the upper anti-flag list.
- **Never commit or push from this skill.** Edits land as working-tree changes. The user commits via `/commit` when ready.
- **Never touch other parts of `AGENTS.md`** beyond the anti-flag bullet list. Identity preamble, role, verdict schema, etc. are out of scope.
- **Never translate user-entered convention content.** Write verbatim what the user approved at Step 3.

---

## Trust contract

- This skill modifies **exactly one file**: `AGENTS.md`.
- It writes to the anti-flag bullet list section only; Architecture posture and all other sections stay untouched.
- If the user cancels at any confirmation step, nothing is written.
- The skill makes no assumptions about which audits produced the finding — it captures the convention the user describes, no investigation of past audits.

---

## Completion criteria

`/add-anti-flag` is complete when:

- Step 0 has run (pre-flight checks pass; anti-flag section located)
- Step 1 has captured the convention description
- Step 2 has been answered `[y]` (or cancelled — in which case nothing else runs)
- Step 3 has been approved by the user (or cancelled)
- Step 4 has appended the new rule to the anti-flag bullet list
- Step 5 has displayed the wrap-up message
