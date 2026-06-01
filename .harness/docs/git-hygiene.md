# Harness Hygiene (git policy) — detail

> **Reference for `CLAUDE.md § Harness Hygiene`.** Loaded on demand when touching git ignore rules, file tracking, or onboarding teammates. The compact lists in CLAUDE.md are the load-bearing version; this file is the design rationale + self-policing + solo-dev variant.

## The philosophy

**CCC-MAGI = "butler in your project"**. The harness lives in your project to serve you, but the line between "team-shared infrastructure" and "personal runtime state" is **load-bearing for git hygiene**. Both must be committed correctly — wrong policy on either side breaks team collaboration or pollutes shared history.

## Committed to git (team-shared)

Everyone on the team uses the same harness setup. Inconsistency here causes "works on my machine" pain:

- `constitution.md` — project's WHAT (Sections 1+2+3). Slot values define project identity.
- `CLAUDE.md` — workflow + lanes + operating principles. Team contract.
- `AGENTS.md` — universal AI-tool project context + auditor (MAGI) brief.
- `CCC_MAGI_README.md` / `CCC_MAGI_LICENSE` — harness self-documentation.
- `.harness/skills/` — all stage skills. Team uses same skill set.
- `.harness/agents/` — reviewer + test-fixer agent definitions.
- `.harness/scripts/` — hook scripts (deterministic enforcement layer).
- `.harness/docs/` — runtime reference docs (this file's neighborhood).
- `.harness/state/install.json` — the 16/5 L0 slot answers. **Especially critical**: team must agree on project identity.
- `.harness/memory/conventions.md` — long-form project conventions (rules everyone follows).
- `.claude/settings.json` — Claude Code hook wiring. Enforcement consistency.
- `.codex/config.toml` + `.codex/hooks.json` — Codex CLI configuration.
- `docs-harness/` — design rationale. Useful onboarding reference for teammates.

## Gitignored (personal / runtime / regenerable)

Per-developer state. Sharing these creates merge conflict noise or pollutes audit signal:

- `.harness/memory/observations.jsonl` — your personal AI session notes (each dev has own).
- `.harness/memory/decision-log.md` — your personal CEO decisions (each dev has own).
- `.harness/audits/` — runtime audit verdict logs (regenerated each audit; merge-conflict source).
- `.harness/state/auditor-approvals/` — per-feature/per-stage verdict JSON (regenerable).
- `.harness/state/test-fix/` — test-fixer attempt logs (transient).
- `.harness/state/workflow-checkpoints/` — your session progress cards (per-developer).
- `.harness/state/_active.json` — currently-active feature pointer.
- `.harness/state/shipped-hashes.json` — install-time content-hash registry (regenerated per install).
- `.harness/state/auditor.env` — per-machine secrets / model ID overrides.
- `.claude/commands/` — auto-generated slash-command shims (derived from skills).
- `.ccc-magi-temp/` / `old_version_harness/` — installer transient artifacts.

## Self-policing

If you find any of the **gitignored** paths above tracked by git (`git ls-files | grep ...`), it's a hygiene break. Recover with:

```bash
git rm --cached -r <path>
git commit -m "chore: gitignore CCC-MAGI runtime artifacts"
```

If you find a **committed** path missing from git (e.g., `.harness/skills/` is `.gitignore`d), team alignment is at risk. Add it back to git so collaborators stay in sync.

## Trade-off acknowledged

This split deviates from a pure "harness as invisible tool" philosophy. CCC-MAGI is **visible in your repo** — teammates see `constitution.md` and `.harness/skills/` in their clone. The benefit (team-shared identity + deterministic enforcement) outweighs the cost (~30 harness files visible in repo). If you're a solo developer and want the harness fully invisible, you can locally `.gitignore` everything except the harness's slot output (`docs/features/*.md`) — but you lose easy onboarding for any future collaborator.
