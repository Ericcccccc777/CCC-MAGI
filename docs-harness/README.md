# Framework Meta-Docs (`outcome/docs-harness/`)

This directory holds the harness's **own design docs** — not project-feature docs (those live at `{{spec_dir}}`), and not operational rules (those live in `CLAUDE.md` / `AGENTS.md`). The files here explain **why** the harness is designed the way it is, and how to adopt it.

## What's in here

| File | Purpose | When to read |
|------|---------|--------------|
| `design-spec.md` | Architectural rationale — the WHY behind the operating model, cross-model audit, two-file spec, lanes, etc. | Onboarding; before extending the harness |
| `adoption-playbook.md` | Step-by-step guide for installing the harness in a new or existing project | When `/init` is too narrow and you want the full playbook |
| `retrospective-notes.md` | Generalized lessons from real-world use (LLM-workflow patterns, sweep methodology, when to delete vs fix) | Periodically; before non-trivial feature work |

## What was removed from the original

The original harness shipped 5 files in this directory totaling 3382 lines. Two were **deleted entirely** in the generic harness:

- **`current-state.md` (1113 lines)** — A snapshot of the *original* project's harness state at one point in time. Becomes obsolete the moment the harness moves forward. For the generic harness, current state is read from the code, not from a doc that drifts. Use `/audit-spec` to produce a fresh as-built reading whenever needed.

- **`double-check.md` (98 lines)** — A checklist of project-specific pitfalls. 95% duplicated content already in `design-spec.md § Scenario classification` and similar sections, and the remaining 5% was tightly coupled to one project's file paths.

The other three files were **kept and generalized** — project-specific examples replaced with abstract pattern descriptions, project terminology replaced with the harness's standard vocabulary, and Korean shorthand translated to English to match the rest of the harness.

## Reading order

If you're new to the harness:

1. **Constitution** (`outcome/constitution.md`) — read first; the universal-core invariants and project identity.
2. **CLAUDE.md** (`outcome/CLAUDE.md`) — the operating manual for day-to-day work.
3. **`design-spec.md`** (this directory) — the architectural rationale behind both files above.
4. **`adoption-playbook.md`** — when ready to install the harness in a project.
5. **`retrospective-notes.md`** — once you've shipped your first feature through the harness.

If you're extending the harness:

1. **`design-spec.md`** — to understand the load-bearing invariants you can't break.
2. **`outcome/agents/README.md`** — for the plugin pattern.
3. **`outcome/skills/<skill>/SKILL.md`** — for examples of how a skill is shaped.

## Why this directory exists at all

The harness's design has nontrivial structure (CEO/manager domain split, cross-model audit invariant, scenario-ID-to-test mapping, lane classification, etc.). Without a single document explaining the **why**, the structure looks arbitrary — and a contributor (human or AI) who doesn't understand the rationale will rationalize past invariants that exist for non-obvious reasons. `design-spec.md` is that document.
