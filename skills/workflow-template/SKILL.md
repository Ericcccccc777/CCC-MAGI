---
name: workflow-template
description: |
  Pick, customize, and persist the project's WORKFLOW TEMPLATE. CCC-MAGI ships 6 modular templates (full-stack / frontend / mobile / library / data-ml / content) plus the trivial lane. This skill detects the project type from repo signals, RECOMMENDS the best-fit template (one-question confirm, never gates), lets the user skip/reorder/add stages, and persists the result to `.harness/state/workflow-template.json`. The CCC dashboard renders whatever is persisted.

  Trigger when:
  - During /init onboarding, after slots are filled (recommend the template)
  - The user says "换工作流" / "改流程" / "选模板" / "switch workflow" / "change my workflow" / "pick a workflow template" / "customize the stages" / "워크플로 변경"
  - The user asks "这个项目该走什么流程" / "what workflow fits this project"
argument-hint: [--recommend | --set <id> | --customize | --show] [--ccc-driven]
---

# /workflow-template

Choose the workflow shape that fits THIS project, instead of forcing the full-stack 9-stage pipeline on everything. Templates are data at `.harness/workflows/` (registry `index.json` + one file per template under `templates/`). The active selection lives at `.harness/state/workflow-template.json`.

> *Constitutional basis: customization is bounded by `constitution.md § Section 1`. The cross-model audit (spec-audit + the audit gates) and the human smoke test (the HUMAN-REVIEW slot stage) are Universal Core — they CANNOT be removed or reordered after commit, by any template choice or customization.*

## Language Awareness

Instructions are English; talk to the user in their OS locale (see `CLAUDE.md § Language Awareness`). Template ids (`frontend`, `full-stack`) and stage ids are machine identifiers — never translate them; translate titles/descriptions when displaying.

## Modes

| Mode | Trigger | Does |
|------|---------|------|
| `--recommend` (default) | /init onboarding; user has no template yet | Detect type → recommend → one-question confirm → persist |
| `--set <id>` | user names a template | Switch to that template, persist |
| `--customize` | user wants to tweak | Walk skip/reorder/add against the active template, persist |
| `--show` | "what's my workflow" | Print the active template's stages (resolved) |

## Step 1 — Detect the project type (for --recommend)

Read `.harness/workflows/index.json`. For each template, score its `detect` signals against the repo:

- Manifests: `package.json` deps/scripts/`bin`, `pyproject.toml`, `Cargo.toml` (`[lib]`), `go.mod`, `pubspec.yaml`, `Package.swift`, `*.xcodeproj`, `android/`
- Layout: presence of `src/` components vs `server/`/`api/`/`supabase/`, `index.html`, `*.ipynb`, `dvc.yaml`, `mkdocs.yml`/`docusaurus.config`, a docs/content-dominant tree
- Deps that disambiguate: a DB driver/ORM → full-stack; react/vue/svelte + no server → frontend; torch/sklearn/mlflow → data-ml; expo/react-native/flutter → mobile

Pick the highest-scoring template as the recommendation; keep the runner-up for the menu. Reuse the auto-detected `tech_stack` slot if `/init` already computed it.

## Step 2 — Recommend (one-question confirm, NEVER gate)

Show the recommendation + let the user override (use `AskUserQuestion`; per init's presentation rule, fixed options → AskUserQuestion). Display in the user's locale:

```
这个项目看起来是「前端 / SPA」。我建议用 Frontend 工作流:
  跳过 DB schema,加上视觉回归 + 无障碍 + 性能预算三道关,发布后看 Web Vitals。

用这个,还是换一个?
  [1] Frontend(推荐 ★)   [2] Full-stack   [3] 其它(我列全部 6 个)   [4] 我要自己调
```

If the user picks "customize", go to Step 3. Otherwise persist the chosen template (Step 4) and you're done.

## Step 3 — Customize (skip / reorder / add)

Load the chosen template's `stages`. Let the user, in plain language:

- **Skip** a stage → mark it removed
- **Reorder** stages → change the order
- **Add** a stage → insert another template's stage, or a free-form stage `{id,title,desc}` with no skill

**Guardrails (HARD — enforce, explain if the user asks to violate):**

1. The stage bound to **`HUMAN-REVIEW`** (the human smoke test) can NOT be removed — Universal Core §1.4. (Trivial lane may still skip it for pure copy changes; that's the lane, not a template edit.)
2. The **`spec-audit`** stage and the cross-model audit at implement can NOT be removed — Universal Core §1.1.
3. **`commit`** can NOT run before the `VERIFY-GATE` stage or the `HUMAN-REVIEW` stage. Reorders that violate this are rejected.
4. Stages tagged `lanes:["full"]` are already auto-skipped in stability-fix / trivial lanes — don't double-encode that as a customization.

If a requested edit hits a guardrail, explain plainly (e.g., "人工冒烟是不可去掉的底线,但 trivial 改动那条车道本来就会跳过它") and offer the nearest allowed alternative.

## Step 4 — Persist

Write `.harness/state/workflow-template.json` (atomic: tmp + rename). Schema:

```json
{
  "schema_version": 1,
  "template_id": "frontend",
  "recommended_id": "frontend",
  "chosen_at": "<ISO-8601>",
  "customized": false,
  "customizations": [],
  "stages": null
}
```

- `template_id` — the chosen template; the dashboard/skills read `templates/<template_id>.json` for the canonical stages.
- `customized` / `customizations` — set `true` + a list of `{op:"skip|reorder|add", stage:"<id>", detail:"..."}` if the user tweaked.
- `stages` — when `customized` is true, the FULL resolved ordered stage list (same shape as a template's `stages`) so the dashboard renders the user's exact flow without re-deriving. When `customized` is false, leave `null` (dashboard falls back to the template file).

This file is committed to git (team-shared project workflow, like `install.json` / `todolist.json`).

## Backward compatibility

- If `.harness/state/workflow-template.json` is ABSENT, the project is on the **`full-stack`** template by default (the original 9 stages). Nothing breaks for projects that predate this feature; `/workflow-template --recommend` can be run anytime to switch.
- Checkpoints keep using `current_stage` (a number) — it now indexes into the active template's `stages` (`n`), so a project on `frontend` at `current_stage:7` is at "Accessibility gate". `checkpoint-write.sh` is unchanged; only the meaning of the number is template-relative.

## Output / handoff

- From `/init`: after persisting, tell the user their workflow in one line and continue the install.
- Standalone: print the resolved stage list (`--show` format) and stop.
