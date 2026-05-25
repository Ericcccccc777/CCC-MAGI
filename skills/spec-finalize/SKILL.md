---
name: spec-finalize
description: This skill should be used at stage 2 of the feature workflow, after stage 1 has landed a CEO-confirmed plain-language spec (via /feature-draft for a new feature or /audit-spec for an existing one). It verifies the two-file model is in shape, every scenario is classified, the spec is plain-language end-to-end, marks the CEO spec FINALIZED, and runs a different-model auditor cross-check focused on integration consistency. Use this always to close stage 2 — spec errors caught here cost much less than spec errors caught during implementation. Trigger when the user invokes /spec-finalize, says "finalize the spec", "mark spec as ready", "stage 2 done", or moves from spec discussion to schema design (or to execution-plan if no backend).
argument-hint: [feature-name]
---

# /spec-finalize

Drive Stage 2 of the feature workflow: confirm Stage 1's output is in shape, mark the CEO spec finalized, and run a final cross-model pass.

Stage 1 already did the heavy lifting (paraphrase + edge-case sweep + {{auditor_model}} review; in audit mode also code reading + delta reconciliation). Stage 2 is largely a formality that prevents premature finalization — it catches sloppy hand-offs from Stage 1.

## Authoritative sources

1. `{{spec_dir}}<feature>.md` — the CEO spec from Stage 1
2. `{{implementation_dir}}<feature>-implementation.md` — the manager-domain notes (when present)
3. `constitution.md` § 5 (Spec and reality stay in sync) — why this stage exists
4. `.harness/scripts/auditor-gate.sh` — the cross-check gate
5. Root `CLAUDE.md` — two-file model, lane definitions
6. `AGENTS.md` (root) — the auditor's standing context

## Invocation

- Typical: `/spec-finalize <feature-name>` (e.g., `/spec-finalize auth`)
- `$ARGUMENTS` identifies the feature; reads `{{spec_dir}}$ARGUMENTS.md`

If `$ARGUMENTS` is missing, identify the active feature from context (most recently created/edited spec under `{{spec_dir}}`). If you cannot confidently identify it, ask explicitly.

## Step 1 — Two-file shape check

Read both:

- `{{spec_dir}}<feature>.md` (must exist; this is the CEO spec)
- `{{implementation_dir}}<feature>-implementation.md` (may or may not exist)

Confirm the CEO spec has all required sections per the spec template:

- Status
- What this feature is for
- Happy path
- Edge-case behavior
- Who can use this
- External dependencies
- Deferred / unresolved
- Out of scope
- Decision history
- Audit-mode delta section (populated only for audits, empty for new-feature mode)

Then confirm:

1. The CEO spec does **not** carry a `## Open questions` section with unanswered numbered items.
2. The implementation file, when present, references the CEO spec at the top (`**Spec:** {{spec_dir}}<feature>.md`).

If shape is wrong, halt and surface the issue:

- Missing section → ask the user to fill it
- Open questions remain → halt; CEO answers, then re-invoke
- CEO spec contains an `#### Automated test ID` block or any `scenario-X-Y — <path>` test-mapping line → halt; the test-ID index is manager-domain and belongs in the implementation file's "Scenario → automated test map" section
- Implementation file missing for a complex feature → recommend producing one (not blocking; CEO can override)

## Step 2 — Plain-language and classification check

Skim the CEO spec for tech-term creep. Categorical bans per Constitution + CLAUDE.md "Two-file feature spec model":

- Library / framework names
- Code identifiers (hook / function / store / state names)
- File paths
- Backend identifiers (RPC / function / table / column names)
- Framework jargon (router / navigation API names, lifecycle terms)
- SDK error type names
- HTTP status codes as primary verbs
- Test file paths and test descriptions (e.g., `scenario-3-X — <path>/*.test.* > describe > test name`)
- Query key constants, payload shapes (JSON field lists), migration timestamps

Surface every match to the CEO with a plain-language replacement suggestion. The CEO confirms the rewrite or rejects ("this term is fine to keep — users see it in the UI"). Don't silently rewrite. Test-ID matches are NOT optional — they relocate to the implementation file's "Scenario → automated test map" section, no CEO confirmation needed.

Confirm every scenario in the Edge-case section has a `Classification` line — `[Required automated test]` or `[Smoke test only]`. If any classification is missing, halt and ask the CEO to classify.

## Step 3 — Mark the CEO spec FINALIZED

When shape is right, plain language is clean, and every scenario is classified, surface the proposed change to the user:

```
Proposing to replace the spec's Status line with:

  ## Status: FINALIZED <YYYY-MM-DD>

This marks Stage 2 closure (auditable). The auditor cross-check at Step 4 follows.

Approve?
  [a] approve
  [b] cancel (return to drafting)
```

**Wait for user response before continuing.**

On approval, replace the Status line with `## Status: FINALIZED <YYYY-MM-DD>` (today's date in ISO format) and write the file back. The FINALIZED line makes Stage 2 closure auditable.

## Step 4 — Auditor final cross-check

Invoke the gate:

```bash
bash .harness/scripts/auditor-gate.sh review <feature> 2 \
  "Review this finalized two-file feature spec. Stage 1 already ran an edge-case round with auditor external review (and in audit mode, an as-built reading and delta reconciliation). Stage 2's job is the final cross-check on the integrated artifact. Look for: spec-internal contradictions between sections (a happy path that contradicts an edge-case behavior, an external-dependency note that contradicts a scenario classification); plain-language hygiene gaps (tech terms that slipped through); scenario classification anomalies (something marked [Smoke test only] that is clearly data-correctness or security-sensitive and should be [Required automated test]); CEO-spec / implementation-notes inconsistency (a routing rule in the implementation file that doesn't match a scenario in the CEO spec); missing scenarios that subsequent Stage 5 implementers would have to invent unilaterally. Do NOT flag: writing style, section ordering, suggestions to extend scope beyond declared, opinions on technical architecture, anything that would have been caught at Stage 1 (we're past that round)." \
  {{spec_dir}}<feature>.md
```

Read the gate's exit code:

- **Exit 0 (PASS / CONCERNS / WAIVED)** — surface `✓ Stage 2 complete: spec FINALIZED; auditor cross-check advanced.` Mention any advisory items. For CONCERNS, also surface the logged warning path (`.harness/audits/concerns-*.json`) and remind the CEO to review before commit. For WAIVED, surface the `waiver_reason`. Recommend the next step (`/db-schema <feature>` if the spec implies data-layer work AND `backend_db_type` is configured, otherwise `/execution-plan <feature>`).
- **Exit 2 (FAIL)** — see Step 5.
- **Exit 1 (script error / Universal Core WAIVED rejected / missing waiver_reason / legacy verdict)** — surface stderr, halt.

## Step 5 — On FAIL

Blocking findings indicate Stage 1 left gaps a reasonable implementer could not resolve unilaterally.

1. Surface every blocking item from the auditor verbatim to the CEO.
2. **Roll back the FINALIZED line.** Replace `## Status: FINALIZED <date>` with `## Status: DRAFT <YYYY-MM-DD> (pending stage-2 fixes)`. The spec is not finalized after all; the rollback prevents stale-status drift.
3. Append the blocking findings to a `## Open questions` section as new numbered items, prefixed with `(from stage-2 auditor review)`. The CEO answers, the spec is updated, the user re-invokes `/spec-finalize`.
4. Halt. No silent advance.

This routes auditor findings back through the same loop the CEO used during Stage 1. The shape stays uniform: there is no separate "auditor feedback resolution" stage.

## Trust contract

- **Auditor is unconditional.** Skill cannot skip the cross-check because "the spec looks fine." (Per Constitution § 1.)
- **Verdict is parsed deterministically from the gate's exit code.** No prose interpretation. The four verdicts are `PASS` (advance silently), `CONCERNS` (advance with logged warning at `.harness/audits/concerns-*.json` for CEO commit-time review), `FAIL` (halt), and `WAIVED` (CEO override only; rejected by the gate if any blocking item cites Universal Core).
- **No silent finalize.** If the auditor returns FAIL, the FINALIZED line comes off — the spec does not retain a stale status.
- **Plain-language audit is enforced at Stage 2** (Step 2). Tech terms in the CEO file are caught here, not at smoke time.
- **Implementation file is optional** — its absence is acceptable for simple features; its presence is checked only for cross-consistency with the CEO spec.

## Completion criteria

Stage 2 is complete when:

- The two-file shape is correct (CEO spec present and well-formed; implementation file present when warranted)
- Every scenario in the Edge-case section is classified (`[Required automated test]` / `[Smoke test only]`)
- The CEO spec is plain language end-to-end
- `## Status: FINALIZED <date>` is present at the top of the CEO spec
- `.harness/scripts/auditor-gate.sh` returned exit 0 (`PASS`, `CONCERNS`, or `WAIVED`)
- `.harness/state/auditor-approvals/<feature>-stage2.json` exists with a non-FAIL `verdict`

Next step: `/db-schema <feature>` (if the spec implies data-layer work AND `backend_db_type` is configured) or `/execution-plan <feature>`.
