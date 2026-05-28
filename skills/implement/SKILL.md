---
name: implement
description: This skill should be used at the end of stage 5 of the feature workflow, after the user has implemented the feature per the execution plan. It mechanically picks the required junior reviewers from `git diff` (no self-assessment), runs them in parallel, and on approval invokes a different-model auditor pass on the full diff. Use this always to close stage 5 — the gate prevents reviewer-skip mistakes and shared-model blind spots. Trigger when the user invokes /implement, says "implement this feature", "write the code per plan", "implementation done", "ready for review", or moves from coding to verification.
argument-hint: [feature-name]
---

# /implement

Drive the close of Stage 5: orchestrate the mechanical review chain on the implementation diff.

Implementation itself is creative coding done with main Claude using the execution plan. This skill takes over once implementation is "done" per the user. Two layers of independence remove the implementer-grades-own-work bias:

1. **Context-level** — junior reviewer subagents (from `{{junior_reviewers}}`) with fresh contexts.
2. **Model-level** — auditor ({{auditor_model}}) audits the full diff for what subagents, sharing model priors, may miss together.

Reviewer selection is **mechanical from the diff**, never self-assessed.

> *Constitutional basis: Constitution § 1 (cross-model audit is mandatory).*

## Authoritative sources

1. `{{spec_dir}}<feature>-plan.md` — the execution plan (Stage 4 artifact)
2. `{{spec_dir}}<feature>.md` — the **CEO spec** (plain language, canonical intent)
3. `{{implementation_dir}}<feature>-implementation.md` — manager-domain notes (when present)
4. `.harness/agents/` — junior reviewer subagent definitions (mechanical rule enforcement only; judgment is the auditor's job)
5. `.harness/scripts/auditor-gate.sh` — the auditor review gate
6. `AGENTS.md` (root) — auditor standing context, including `{{anti_flag_rules}}`
7. Root `CLAUDE.md` § Workflow — Stage 5 flow

## Lane awareness

The auditor audit prompt and depth depend on lane:

- **Full workflow** (default) — full auditor review on the diff (Step 6 below).
- **Stability-fix** — full auditor review at Step 6, plus a **mandatory failing-test-first procedural check at Step 0** (see below). The check halts the skill if the diff contains a fix without a corresponding failing test that was confirmed to fail pre-fix.
- **Trivial-change** — auditor runs in Quick mode (BLOCKING-only): security holes, data loss, outright defects only. No advisory or strong items. Use the Quick prompt in Step 6.

If the lane is unclear, ask the CEO before proceeding.

## Step 0 — Stability-fix lane: failing-test-first enforcement (conditional)

**Run this step only when the lane is stability-fix.** Skip for full workflow and trivial-change.

This step enforces the test-first ordering required by root `CLAUDE.md` § Lanes (stability-fix lane). Without it, a manager can apply a fix and forget the failing test — the precise failure mode this rule exists to prevent.

The procedural sequence the user must have followed before invoking `/implement` on the stability-fix lane:

1. Bug analyzed; root-cause hypothesis written down.
2. **Failing test authored first** — added to a test file per the project's `{{test_framework}}` convention, with a `// Verifies scenario X.Y` comment tying it to a CEO-spec scenario.
3. Test confirmed to fail on the broken (pre-fix) code — the user runs `{{test_runner_command}} <test-path>` and watches it fail.
4. Fix applied to source.
5. Test confirmed to pass on the fixed code.

Then `/implement` is invoked.

The skill verifies steps 2–5 before proceeding to the standard reviewer chain. **Capture the baseline first**:

```bash
BASELINE=<sha>  # last commit before stability-fix work began; ask user once if ambiguous

git diff "$BASELINE" --name-only > /tmp/implement-stab-files.txt
# Use {{test_framework}}'s file pattern to distinguish tests from source:
grep -E '\.test\.(ts|tsx|js|jsx|py|go|rs)$|_test\.(go|py)$|test_.*\.(py)$' /tmp/implement-stab-files.txt > /tmp/implement-stab-tests.txt || true
grep -vE '\.test\.(ts|tsx|js|jsx|py|go|rs)$|_test\.(go|py)$|test_.*\.(py)$' /tmp/implement-stab-files.txt > /tmp/implement-stab-source.txt || true
```

**Mechanical check 1 — diff must include a test file.** If `/tmp/implement-stab-tests.txt` is empty but `/tmp/implement-stab-source.txt` is non-empty, halt:

> "Stability-fix lane requires a failing test written before the fix (per CLAUDE.md § Lanes). The diff contains source changes (`<list>`) but no new or modified test file. Halt — write the failing test first, confirm it fails on the broken code, then re-apply the fix and re-invoke `/implement`. Do NOT proceed to the reviewer chain until the test is in the diff."

**Mechanical check 2 — at least one test in the diff carries `// Verifies scenario X.Y`.** Inspect `git diff "$BASELINE" -- $(cat /tmp/implement-stab-tests.txt)` for the comment pattern. If no test in the diff carries it, halt:

> "Stability-fix lane requires the failing test to reference a CEO-spec scenario via `// Verifies scenario X.Y`. The diff has test changes but none carry the comment. Halt — add the comment to the test that exercises the regression, then re-invoke `/implement`."

**User confirmation — pre-fix failure was observed.** After both mechanical checks pass, ask the user once:

> "Stability-fix procedural confirmation:
>
> - The failing test in this diff (`<test path>::<test name>`) was run against the broken code BEFORE the fix was applied — and it failed?
> - After the fix was applied, that same test passes now?
>
> Both `yes` → proceed to reviewer chain.
> Either `no` → halt; revert the fix locally, run the test, watch it fail, then re-apply the fix and re-invoke `/implement`."

If the user answers `no` to either, halt. Do not proceed.

If the user answers `yes` to both, record the confirmation in the working state and proceed to Step 1.

**Anti-loophole.** "I forgot to write the test but the fix is obvious" is not an exception — write the test now, even after the fact, and confirm it fails on the broken code by reverting the fix locally to a temp branch first. The point of test-first is the _demonstration that the test catches the bug_, not the chronological order. If the user pushes back on this, surface the rule once, then accept the user's override only after they explicitly state "override; recording in commit body."

## Invocation

- Typical: `/implement <feature-name>`
- `$ARGUMENTS` identifies the feature

If `$ARGUMENTS` is not provided, identify from context (recent edits matching `{{feature_folder_pattern}}`, the most recent execution plan). Ask the user if ambiguous.

## Step 1 — Identify the baseline

The diff to review is `git diff <baseline>` where baseline is the commit before Stage 5 implementation began.

Conventions:

- If Stage 3 produced a migration commit, baseline = that commit
- Otherwise baseline = the commit immediately before Stage 5 started (typically the plan commit, or the prior feature's final commit)
- If the working tree has uncommitted changes (Stage 5 changes typically remain uncommitted until `/commit` at Stage 8), they are part of the diff: use `git diff <baseline>` (not `git diff <baseline>..HEAD`)

If the baseline is ambiguous, ask the user: "what's the last commit before you started implementation?" Do not guess.

Capture: `BASELINE=<sha>`.

## Step 2 — Determine touched layers

Inspect:

```bash
git diff --stat $BASELINE > /tmp/implement-diffstat.txt
git diff $BASELINE > /tmp/implement-fulldiff.txt
```

Determine required junior reviewers **mechanically** from path + content. The mapping is defined at /init time based on `{{junior_reviewers}}` and the project's `{{client_code_paths}}` / `{{backend_code_paths}}`. Typical patterns:

- **Frontend reviewer** is required if any path matches `{{client_code_paths}}`.
- **Backend reviewer** is required if any path matches `{{backend_code_paths}}` (skipped entirely on projects without a backend).
- **Security / privacy reviewer** is required when the diff touches auth, access-control, or PII-bearing code. Specific triggers are declared by the security reviewer's subagent definition (e.g., access-control predicate keywords, auth-feature paths, migrations that add columns to PII-bearing tables).

If the diff has no relevant paths, stop and report: "no reviewable changes detected; was implementation actually done?"

Surface to the user the list of required reviewers and the reason each was selected (which path or content match triggered it). The user may not opt out of any selected reviewer — selection is mechanical, but the user confirms the diff baseline and reviewer set looks right before spawn.

**Wait for user response before continuing.**

## Step 3 — Verify version-sensitive APIs

Claude's training data has an effective cutoff and confidently suggests stale APIs for libraries that moved past it. Stage 4 should have flagged version-sensitive decisions with `• verified:` annotations in the plan, but implementation drift happens.

**Spot-check the diff** for uses of libraries in `{{high_trap_libraries}}` that lack a `• verified:` note in `{{spec_dir}}<feature>-plan.md`.

For each unverified use, query `context7` for the relevant library and confirm the call matches the current API. If it doesn't match (a prop that no longer exists, a method signature change, an import path moved), halt and surface to the user — fix before invoking reviewers. If it does match, annotate the plan retroactively with the `• verified:` note.

**Skip** for: language primitives, stable framework patterns, project-internal code, and patterns the codebase already exercises correctly elsewhere — those are stronger evidence than docs.

If `context7` is unreachable or unhelpful for a specific library, do NOT guess. Surface "unverified API in implementation: `<library>` — recommend manual check" and halt.

**Canonical-source escalation.** `context7` is a third-party docs mirror and can be incomplete. If a lookup conclusion would drive a _destructive change_ (removing config, deleting a feature, renaming a field, contradicting working code) or is _negative_ ("X doesn't exist"), `context7` alone is insufficient. Also fetch the canonical source via WebFetch (official docs site or upstream GitHub README), and surface the canonical URL in the report. Treating absence-from-mirror as proof-of-absence is the failure mode this rule prevents. Adding new code based on a lookup needs one source; removing or contradicting working code based on a lookup needs canonical confirmation.

## Step 4 — Spawn junior reviewers in parallel

For each required reviewer, invoke via the Task tool (`subagent_type: "<reviewer>"`).

**Spawn all required reviewers in a single message with multiple Task tool calls** so they run concurrently. Sequential invocation wastes time and lets earlier verdicts color how you frame later prompts.

Construct each reviewer's prompt to include:

- The baseline ref (so they can run `git diff` themselves if they want)
- The relevant subset of paths from `/tmp/implement-diffstat.txt`
- An instruction to read `{{spec_dir}}<feature>.md` and `<feature>-plan.md` for context

Do NOT pass:

- Your own interpretation of the diff
- "I believe this is correct" framing
- Pre-summary of what the diff does (let the reviewer read it themselves)

Pass artifacts and criteria. Not interpretation.

## Step 5 — Surface reviewer verdicts

Read each verdict report verbatim. Do not summarize, filter, or aggregate.

For each reviewer, surface to the user:

- The verdict line (`PASS` / `CONCERNS` / `FAIL` / `BLOCK` / `ESCALATE: <other-reviewer>`)
- Blocking findings (if any)
- Warnings and advisory items (if any)

Branch:

- **Any reviewer returns `FAIL` or `BLOCK`** — halt. Stage 5 is incomplete. The user fixes the flagged issues and re-invokes `/implement`.
- **Any reviewer returns `ESCALATE: <other>`** — verify `<other>` was already in the required-reviewers set. If yes, its verdict is already in this batch; proceed to the next branch. If no, spawn `<other>` now and surface its verdict before proceeding.
- **All required reviewers return `PASS` or `CONCERNS`** — proceed to Step 6. Surface any `CONCERNS` warnings explicitly so the CEO can weigh them before commit.

## Step 6 — Auditor review pass (judgment layer)

Invoke the gate. Pick the prompt by lane.

**Full workflow / Stability-fix lane** — full review with adversarial preset.

The preset (`.harness/scripts/auditor-prompts/adversarial.md`) wraps the focus text below with adversarial-review framing: skepticism stance, attack-surface checklist (auth, data loss, idempotency, races, partial failure, schema drift, observability), and "prefer one strong finding over filler" calibration. The focus text below carries the stage-specific guardrails the preset doesn't know about.

```bash
DIFF_FILE=$(mktemp /tmp/implement-auditor-diff.XXXXXX)
git diff "$BASELINE" > "$DIFF_FILE"

AUDITOR_GATE_PRESET=adversarial \
AUDITOR_GATE_TARGET_LABEL="<feature> Stage 5 implementation diff" \
bash .harness/scripts/auditor-gate.sh review <feature> 5 \
  "Review the implementation diff against the CEO spec at {{spec_dir}}<feature>.md, the implementation notes at {{implementation_dir}}<feature>-implementation.md (if present), and the plan at {{spec_dir}}<feature>-plan.md. Junior reviewers from {{junior_reviewers}} have already approved project-rule conformance — they are mechanical rule reviewers, not judgment. Your job is the judgment layer: catch what shared-model planning + rule-conformance review miss together. Beyond the preset's attack surface, also weigh: alternative approaches that meaningfully reduce risk; hidden assumptions in the implementation.

  **Spec-vs-reality match (mandatory axis).** The CEO spec at {{spec_dir}}<feature>.md is a behavioral document written for the final decision maker (the CEO, who reads it end-to-end at smoke time). It describes what the feature does from a user-facing perspective — what the user sees, what they can do, what happens to their data, what guarantees the product makes. It does NOT describe implementation mechanism, and is BANNED from doing so by CLAUDE.md's two-file model. Your audit must respect that boundary.

  Read the spec end-to-end (not just sections touched by this diff). Flag a sentence ONLY when:
  - It asserts a user-observable behavior the code provably doesn't deliver (timing, atomicity boundary, recovery path the user can actually take, what an attempted action returns, what gets scrubbed / cascaded / revoked from the user's perspective, what the user sees after the action), OR
  - It asserts a guarantee (\"either everything commits or nothing does\", \"the user is signed out on every device\") that the code doesn't enforce.

  Do NOT flag:
  - Plain-language vocabulary that doesn't map 1:1 to a code identifier. If the user-facing meaning is correct, the wording is correct.
  - Sentences that omit implementation mechanism. The CEO spec is supposed to omit mechanism; absence of jargon is not absence of behavior.
  - Wording that could be tightened toward technical precision — that would break the two-file model.

  This axis exists because spec wording often gets touched outside this diff's scope and unaudited behavioral drift compounds silently across rounds. It does NOT exist to police plain-language imprecision.

  Do NOT flag: anti-flag rules in AGENTS.md (already reviewed by junior reviewers), formatting (formatter handles it), naming preferences, refactor opinions, or suggestions for additional test coverage (Stage 6 is for that)." \
  "$DIFF_FILE"
```

**Trivial-change lane** — Quick mode (BLOCKING-only):

```bash
DIFF_FILE=$(mktemp /tmp/implement-auditor-diff.XXXXXX)
git diff "$BASELINE" > "$DIFF_FILE"

bash .harness/scripts/auditor-gate.sh review <feature> 5-trivial \
  "Review this trivial-change diff. Per CLAUDE.md's trivial-change lane, this is < 20 LOC, no new feature surface, no schema change, no new dependency, no intent change. Run in Quick mode: report ONLY items that meet the BLOCKING bar — security holes, data loss, outright defects. Do NOT flag: code style, refactor opportunities, alternative approaches, naming, advisory items, suggestions for additional tests, anything that wouldn't block a normal commit. If you find non-trivial concerns, that's a signal the lane is misclassified — say so explicitly so the user can re-classify; do NOT silently flag them as advisory. If nothing meets BLOCKING, return PASS." \
  "$DIFF_FILE"
```

Read the gate's exit code:

- **Exit 0 (PASS / CONCERNS / WAIVED)** — surface `✓ Stage 5 complete: implementation reviewed by [list of junior reviewers] + {{auditor_model}} cross-model audit.` Mention any advisory items. For CONCERNS, also surface the logged warning path (`.harness/audits/concerns-*.json`) and remind the CEO to review before commit. For WAIVED, surface the `waiver_reason`. Stage 5 complete; user may proceed to `/test-fix <feature>`.
- **Exit 2 (FAIL)** — surface every blocking item from the auditor verbatim, halt. The user addresses, re-invokes `/implement`.
- **Exit 1 (script error / Universal Core WAIVED rejected / missing waiver_reason / legacy verdict)** — surface stderr, halt.

## Trust contract

- **Reviewer selection is mechanical from `git diff`.** Skill has no judgment authority to skip a reviewer "because the diff looks fine."
- **Verdicts are surfaced verbatim.** No "reviewer says it's fine, proceeding."
- **Auditor is unconditional on subagent PASS.** No skipping the audit because "the diff looks clean." (Constitution § 1.)
- **On disagreement** (junior reviewers PASS, auditor FAILs): auditor wins by default. Surface both views; user overrides explicitly if they disagree.
- **Verdict semantics.** The four verdicts are `PASS` (advance silently), `CONCERNS` (advance with logged warning at `.harness/audits/concerns-*.json` for CEO commit-time review), `FAIL` (halt), and `WAIVED` (CEO override only; rejected by the gate if any blocking item cites Universal Core).

## Completion criteria

Stage 5 is complete when:

- Every required junior reviewer returned `PASS` or `CONCERNS` (FAIL halts)
- `.harness/scripts/auditor-gate.sh` returned exit 0 for Stage 5 (`PASS`, `CONCERNS`, or `WAIVED`)
- `.harness/state/auditor-approvals/<feature>-stage5.json` exists with a non-FAIL `verdict`

The user should be able to proceed to `/test-fix <feature>` immediately after.

## Anti-patterns the skill blocks

- Implementer self-assessing whether a reviewer is needed → mechanical from `git diff --stat`
- Implementer rationalizing past a reviewer's FAIL → halt, no auto-proceed
- Skipping the auditor because "junior reviewers already approved" → auditor unconditional
- Treating auditor disagreement as noise → halt, user explicitly overrides if needed
- Sequential reviewer spawn (lets earlier verdicts color later prompts) → all required reviewers in a single parallel batch

---

## Checkpoint + decision-log integration (MAGI Archivist) — including mid-flight

Stage 5 differs from other stages: it can take hours and edit many files. MAGI Archivist tracks progress **at the file level**, not just at stage end. This is what enables `/pickup` to pick up at "5/8 files done" instead of "Stage 5 incomplete".

### At Stage 5 START — declare the file plan

After reading the execution plan but before writing any code:

```bash
TOTAL_FILES=$(grep -cE '^\s*-\s+\`?[^[:space:]\`]+' docs/features/<feature>-plan.md | tr -d ' ')
.harness/scripts/checkpoint-write.sh \
  --feature <feature-slug> \
  --stage 5 \
  --stage-in-progress "$(jq -nc --argjson total "$TOTAL_FILES" '{stage_number:5, files_total:$total, files_done_list:[], files_remaining_list:[], last_action:"Stage 5 started", resume_hint:"Run /implement to begin"}')"
```

### MID-FLIGHT — after each file's Edit/Write completes

```bash
# Call this AFTER every file the implementer fully completes (not on partial edits)
.harness/scripts/checkpoint-write.sh \
  --feature <feature-slug> \
  --file-done <path/to/file>
```

This makes `/pickup` reports show: *"3/8 files done — continue at src/auth/middleware.ts (next)"*.

### At Stage 5 END — close out + audit verdict

After all files complete + reviewer chain + auditor-gate passes:

```bash
.harness/scripts/checkpoint-write.sh \
  --feature <feature-slug> \
  --stage 6 \
  --stage-complete 5 \
  --stage-in-progress 'null' \
  --append-audit "$(jq -c '{stage:5, verdict, risk:.risk_score, at:now|todate}' .harness/state/auditor-approvals/<feature>-stage5.json)"

# Log any escalation or override:
.harness/scripts/decision-log-append.sh \
  --feature <feature-slug> --stage 5 --by "CEO" \
  --decision "<e.g. 'override frontend-reviewer false positive on FlashList ref'>"
```

**Without mid-flight tracking, a crash at file 4/8 makes `/pickup` think Stage 5 hasn't started.**
