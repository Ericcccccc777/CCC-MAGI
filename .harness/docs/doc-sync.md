# Doc-in-sync responsibility — detail

> **Reference for `CLAUDE.md § Doc-in-sync responsibility`.** Loaded on demand at commit time. The compact rule in CLAUDE.md is the load-bearing version; this file is the elaboration on exceptions, cross-feature touches, and drift detection.

## Constitutional basis

> *`./constitution.md § 5` (Spec and reality stay in sync).*

Specs at `{{spec_dir}}<name>.md` are load-bearing only when they match reality. Drift kills them.

## Rule

Any commit that changes a feature's data model, public API, or user-visible behavior MUST update the corresponding `{{spec_dir}}<name>.md` in the same commit. This applies to commits made via any lane — full workflow, stability-fix, or trivial-change. If only the technical surface changes (file split, query refactor with same shape), update `{{implementation_dir}}<name>-implementation.md` instead.

## Exceptions

Stylistic refactors, internal renames, formatting, and bug fixes that preserve external behavior do not require doc updates.

## Cross-feature touches

When a change touches multiple features' surfaces, update the doc for the feature that _owns_ the affected surface, not just the feature you happened to be working in. The owner is whichever feature's spec was the original source of that artifact.

## Plan files are transient

`{{spec_dir}}<name>-plan.md` is the Stage 4 execution checklist. Once the implementation lands at Stage 8, the plan has done its job — delete it as part of the commit that ships the implementation. Stale plan files with un-ticked checkboxes mislead future-you.

## Catching drift

If you suspect a spec has drifted from reality, run `/audit-spec <name>` to produce a fresh as-built reading from code (fresh subagent author; **MAGI Verdict** reviews independently), then iterate to a corrected canonical spec. The audit mechanism IS the maintenance mechanism.
