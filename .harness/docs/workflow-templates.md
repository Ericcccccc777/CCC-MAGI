# Workflow templates — schema & mechanism

> CCC-MAGI's answer to **"the 9-stage pipeline fits a full-stack app, but it's awkward for a frontend / library / ML / content project."** Instead of one hardcoded pipeline, the workflow is a **template** chosen per project type, customizable per project, and rendered live in the CCC dashboard.

## Two-level model

- **Templates** — named, ordered lists of **stages**, one per project type. Files: `.harness/workflows/templates/<id>.json`. Registry: `.harness/workflows/index.json`.
- **Abstract slots** — three stages are *roles*, not fixed steps: `VERIFY-GATE`, `HUMAN-REVIEW`, `WATCH`. Each template binds them to a type-appropriate concrete stage. The original "DB schema / localhost smoke / error-tracker watch" are just the **full-stack bindings** of these slots; a frontend project binds VERIFY-GATE to visual-regression, WATCH to Web Vitals, etc.
- **Lanes** stay orthogonal — Full / Stability-fix / Trivial are an *intensity axis* applied WITHIN any template (they skip `lanes:["full"]` stages and dial auditor intensity), exactly as before.

## The 6 templates (+ trivial lane)

| id | for | what's distinct |
|---|---|---|
| `full-stack` | backend + DB web app | the original 9 stages, verbatim (default) |
| `frontend` | SPA / marketing site | drops DB schema; verify = visual-regression + a11y + perf budget; watch = Web Vitals |
| `mobile` | iOS/Android | platform-guidelines + permissions; human review = beta build; store review + staged rollout + crash watch |
| `library` | lib / CLI / SDK | spec = API contract; semver check; docs+changelog; human review = consumer dry-run; publish |
| `data-ml` | ML / eval-driven | schema = dataset versioning; implement = train+track; verify = eval gate; human = eval-dashboard review; watch = drift |
| `content` | articles / docs | spec = brief+outline (Diátaxis); implement = edit ladder; verify = fact-check; human = editorial review |

## Stage shape

Each stage in a template's `stages` array (schema documented in `index.json § stage_schema`):
`{ n, id, title, skill, slot, lanes, optional_if, desc }` — `skill` is the skill to invoke (or `null` for guidance/manual stages), `slot` is the abstract slot it binds (or `null`), `lanes` limits which lanes run it (omit = all).

## Active selection

`.harness/state/workflow-template.json` — **committed to git** (team-shared project workflow, like `install.json` / `todolist.json`):

```json
{ "schema_version": 1, "template_id": "frontend", "recommended_id": "frontend",
  "chosen_at": "<ISO>", "customized": false, "customizations": [], "stages": null }
```

- `customized:false` → the dashboard/skills read the canonical `templates/<template_id>.json`.
- `customized:true` → `stages` holds the user's full resolved ordered stage list; `customizations` records the `{op,stage,detail}` edits.
- **Absent file** → project is on `full-stack` by default (backward compatible; nothing breaks for pre-template projects).

## Who writes / reads it

- **`/workflow-template` skill** — recommends (from repo signals), confirms in one question, customizes (skip/reorder/add), persists. Invoked during `/init` (Step 3.5) and anytime later.
- **CCC dashboard** — `WorkflowPage` reads `workflow-template.json` (+ the template file) and renders the data-driven stage list, the active template name, and any customizations.
- **Checkpoints** — `workflow-checkpoints/<feature>.json`'s `current_stage` (a number) now indexes the **active template's** `stages[].n`. `checkpoint-write.sh` is unchanged; only the meaning of the number is template-relative.

## Customization guardrails (Universal Core)

Per `constitution.md § Section 1`, customization can NOT:
- remove the `HUMAN-REVIEW`-bound stage (§1.4 human smoke test),
- remove `spec-audit` or the implement-time cross-model audit (§1.1),
- reorder `commit` before the `VERIFY-GATE` or `HUMAN-REVIEW` stage.

The `/workflow-template` skill enforces these and explains the nearest allowed alternative when a request hits a guardrail.

## Recommendation, not gating

Detection ranks templates from repo signals (manifests, layout, disambiguating deps) and *recommends* the top one with a one-question confirm + full override — the GitHub starter-workflows pattern. CCC-MAGI never forces a template.
