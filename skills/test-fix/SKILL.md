---
name: test-fix
description: This skill should be used at stage 6 of the feature workflow, after implementation (stage 5) is complete. It runs the project's test suite ({{test_framework}}), and if any tests fail, spawns a fresh-context `test-fixer` subagent to diagnose and fix (up to 3 iterations), then audits fix legitimacy with a different-model auditor pass. On the stability-fix lane (no prior stage-5 audit) it runs an additional auditor backstop on the entire fix diff, closing the cross-model gap on hotfixes. Use this always after implementation — do not declare stage 5 done without running tests. Skipped entirely if `test_required = false`. Trigger when the user invokes /test-fix, says "write tests for X", "fix the failing test", "run tests", or when moving from implementation to verification.
argument-hint: [feature-name]
---

# /test-fix

Drive Stage 6 of the feature workflow. Three layers of independence remove the implementer-grades-own-work bias:

1. **Context-level independence** — fresh `test-fixer` subagent (junior programmer; writes test code only, no judgment).
2. **Model-level independence (post-fix audit)** — auditor ({{auditor_model}}) audits the test-fix diff on four axes:
   - **Test legitimacy** — assertions / skips / mocks / deletions
   - **Scenario coverage** — every CEO-spec scenario classified `[Required automated test]` has at least one test that references it via the `// Verifies scenario X.Y` comment
   - **Fix correctness** — when source files were modified during the fix loop, do those source changes actually address the failure without introducing new ones
   - **Spec-vs-reality match** — final gate before the CEO smoke test
3. **Model-level independence (stability-fix backstop)** — when the stability-fix lane is detected (no prior Stage 5 auditor audit on this change), an additional auditor audit covers fix correctness on the entire fix diff. Closes the gap where Stages 1–4 are skipped.

> *Constitutional basis: Constitution § 1 (cross-model audit) + § 4 (real-human smoke test follows — this is the final gate before CEO takes over).*

**Skipped entirely if `test_required = false`** — projects can opt out of automated tests at /init; in that case, jump from Stage 5 directly to Stage 7.

## Scenario-ID rule (load-bearing)

Every automated test produced or modified at this stage carries a comment:

```ts
// Verifies scenario 3.4 — <scenario name from spec>
test('<test name>', async () => { ... })
```

The comment ties the test to a scenario ID in `{{spec_dir}}<feature>.md`. Tests without the comment have no audit trail; the auditor's scenario-coverage check catches the gap.

When tests pass and the auditor advances (PASS, CONCERNS, or WAIVED), the resolved test bindings (file path + test name) are recorded in the implementation file's "Scenario → automated test map" section, NOT in the CEO spec.

## Authoritative sources

1. The project's testing convention (`{{test_framework}}`, assertion rules)
2. `{{spec_dir}}<feature>.md` — the **CEO spec** (canonical scenario list + classification)
3. `{{implementation_dir}}<feature>-implementation.md` — manager-domain notes (when present)
4. `{{spec_dir}}<feature>-plan.md` — execution plan (when present; absent on stability-fix lane)
5. `.harness/agents/test-fixer.md` — the subagent definition (junior programmer, mechanical)
6. `.harness/scripts/auditor-gate.sh` — the auditor post-fix audit + diagnostic gate
7. `AGENTS.md` (root) — auditor standing context including `{{anti_flag_rules}}`
8. Root `CLAUDE.md` § Lanes (stability-fix flow) and § Workflow (Stage 6)
9. Scoped rule files governing the touched layers (from `{{rule_sources}}`)

## Identify the active feature

The skill needs `<feature>` for state file paths and to pass the spec/plan to test-fixer.

- If `$ARGUMENTS` is provided, use it as `<feature>`.
- Otherwise, identify the active feature from context (most recently created/edited spec under `{{spec_dir}}`, current implementation focus). If you cannot confidently identify it, ask the user explicitly: "which feature is this test pass for?"

Do not proceed without a confirmed `<feature>` name.

## Step 0 — Stability-fix lane: failing-test-first verification (conditional)

**Run this step only when the lane is stability-fix.** Skip for full workflow and trivial-change.

This step backstops the failing-test-first enforcement that `/implement` runs at its Step 0. It exists in case the user ran `/test-fix` directly (without going through `/implement`) on a stability-fix change.

The procedural sequence required by root `CLAUDE.md` § Lanes (stability-fix) is: bug analyzed → failing test authored → test confirmed failing on broken code → fix applied → test confirmed passing on fixed code. This step verifies a failing test was authored as part of the change, not bolted on after the fix passed.

```bash
ORIGINAL_BASELINE=<the last commit before the stability-fix work began — ask the user>
git diff "$ORIGINAL_BASELINE" --name-only > /tmp/test-fix-stab-files.txt
# Adjust pattern to match {{test_framework}}'s file convention:
grep -E '\.test\.(ts|tsx|js|jsx|py|go|rs)$|_test\.(go|py)$|test_.*\.(py)$' /tmp/test-fix-stab-files.txt > /tmp/test-fix-stab-tests.txt || true
grep -vE '\.test\.(ts|tsx|js|jsx|py|go|rs)$|_test\.(go|py)$|test_.*\.(py)$' /tmp/test-fix-stab-files.txt > /tmp/test-fix-stab-source.txt || true
```

**Mechanical check 1 — diff must include a test file.** If `/tmp/test-fix-stab-tests.txt` is empty but `/tmp/test-fix-stab-source.txt` is non-empty, halt:

> "Stability-fix lane requires a failing test written before the fix (per CLAUDE.md § Lanes). The diff contains source changes but no test changes — the regression has no automated catcher. Halt — write the failing test now (revert the fix to a temp branch first to confirm the test catches the bug), then re-stage and re-invoke `/test-fix`."

**Mechanical check 2 — at least one test in the diff carries `// Verifies scenario X.Y`.** Inspect `git diff "$ORIGINAL_BASELINE" -- $(cat /tmp/test-fix-stab-tests.txt)` for the comment pattern. If no test in the diff carries it, halt:

> "Stability-fix lane requires the failing test to reference a CEO-spec scenario via `// Verifies scenario X.Y`. The diff has test changes but none carry the comment. Halt — add the comment to the test that exercises the regression, then re-invoke `/test-fix`."

**User confirmation — pre-fix failure was observed.** After both mechanical checks pass, ask the user once:

> "Stability-fix procedural confirmation:
>
> - The failing test in this diff (`<test path>::<test name>`) was run against the broken code BEFORE the fix was applied — and it failed?
> - After the fix was applied, that same test passes now?
>
> Both `yes` → proceed to Step 1 (run tests + auditor audit).
> Either `no` → halt; the audit chain assumes test-first; re-do this in the correct order before re-invoking."

If the user answers `yes` to both, proceed. If either `no`, halt. The user may override with explicit reasoning recorded for the commit body — the override does not silently advance.

## Step 1 — Pre-flight

1. Capture baseline: `BASELINE=$(git rev-parse HEAD)`.
2. Run `{{test_runner_command}}` once with no fixing. Capture stderr and pass/fail status.
3. If all tests pass on the first run, skip to **Step 5 — Auditor post-fix audit** with an empty `FIXES_APPLIED`. We still run the audit so any test coverage that was weakened during Stage 5 doesn't slip through.
4. If tests fail, proceed to Step 2.

## Step 2 — Spawn test-fixer subagent

Invoke the `test-fixer` subagent via the Task tool (`subagent_type: "test-fixer"`).

Construct the subagent prompt to include exactly:

- The failing test output verbatim (full stderr from Step 1)
- An instruction to read: `{{spec_dir}}<feature>.md`, `{{spec_dir}}<feature>-plan.md`, the project's testing convention, the relevant scoped rule files
- If `.harness/state/test-fix/<feature>-attempts.json` exists (prior escalation retry), include its contents pretty-printed under the heading: `REJECTED_APPROACHES (from prior test-fixer iterations — these did NOT resolve the failures; do not repeat them, find a different angle):`

**Do NOT include in the prompt:**

- Any text from the main session about why the code "should be" correct
- The implementer's reasoning, framing, or interpretation
- "I believe…" / "this looks right" / any pre-supposition of the answer

Pass artifacts and criteria. Not interpretation.

## Step 3 — Receive and surface the report

Read the test-fixer's structured report **verbatim**. Do not summarize, filter, or rephrase.

Surface to the user:

- The full `FIXES_APPLIED` list, with every entry's `suspicious` flag visible
- `ITERATIONS_USED`
- If `STATUS: ESCALATE` — the `REMAINING_FAILURES` and `HYPOTHESIS` blocks

The user must see what the subagent actually did before any verdict computes.

## Step 4 — Branch on STATUS

- `STATUS: PASS` → Step 5 (auditor post-fix audit)
- `STATUS: ESCALATE` → Step 6 (escalation routing)

## Step 5 — Auditor post-fix audit

Compute the diff and write to a temp file:

```bash
DIFF_FILE=$(mktemp /tmp/test-fix-diff.XXXXXX)
git diff "$BASELINE" > "$DIFF_FILE"
```

`git diff "$BASELINE"` (no `..HEAD`) is working-tree-aware. The `test-fixer` subagent uses Edit, not commit — its changes sit uncommitted. Using `..HEAD` here would diff committed-only and yield an empty file, silently auditing nothing.

Invoke the gate. The prompt covers four axes — test legitimacy, scenario coverage, fix correctness, and spec-vs-reality match:

```bash
bash .harness/scripts/auditor-gate.sh review <feature> 6 \
  "Review the diff produced by Stage 6 test fixing. Tests now pass; you verify four axes.

Axis 1 — Test legitimacy: weakened assertions (exact values replaced with looser matchers, removed assertions, removed test cases, .skip / .only / equivalent left in, new mocks of components / hooks / modules the test was supposed to exercise). If a test now passes only because it asserts less, that is CRITICAL.

Axis 2 — Scenario coverage: read {{spec_dir}}<feature>.md and enumerate every scenario classified [Required automated test]. For each, confirm at least one test in the diff (or already in the repo on a path the diff modifies) carries a '// Verifies scenario X.Y' comment matching it. A [Required automated test] scenario with no covering test is CRITICAL. The resolved test bindings should land in {{implementation_dir}}<feature>-implementation.md's 'Scenario → automated test map' section (NOT in the CEO spec); a [Required automated test] scenario missing a subsection there after Stage 6 is CRITICAL. Also flag CRITICAL if the CEO spec carries any '#### Automated test ID' block or 'scenario-X-Y — <path>/*.test.*' line — that's a workflow violation per CLAUDE.md's two-file model.

Axis 3 — Fix correctness (when source files were modified during the test-fix loop): does the source change actually fix the failure without introducing a new one? Does it contradict the CEO spec? Does it bypass an access-control gate the prior code relied on? If the source change is itself buggy, that is CRITICAL.

Axis 4 — Spec-vs-reality match (mandatory; this is the final gate before smoke). The CEO spec at {{spec_dir}}<feature>.md is a behavioral document written for the final decision maker — the CEO reads it end-to-end at smoke time to drive the manual smoke test. It describes what the feature does from a user-facing perspective: what the user sees, what they can do, what happens to their data, what guarantees the product makes. It does NOT describe implementation mechanism, and is BANNED from doing so by CLAUDE.md's two-file model. Your audit must respect that boundary. Read the spec end-to-end. Flag a sentence ONLY when: (a) it asserts a user-observable behavior the code provably doesn't deliver (timing, atomicity boundary, recovery path the user can actually take, what an attempted action returns, what gets scrubbed or cascaded or revoked from the user's perspective, what the user sees after the action), OR (b) it asserts a guarantee that the code doesn't enforce. Do NOT flag plain-language vocabulary that doesn't map 1:1 to a code identifier. Do NOT flag sentences that omit implementation mechanism. Do NOT flag wording that could be tightened toward technical precision. This axis exists because /implement auditor sees only the implementation diff (which may not include all spec edits) and /test-fix is the last gate before the CEO smoke test. It does NOT exist to police plain-language imprecision.

Do NOT flag: project-convention choices per {{anti_flag_rules}}, formatting, naming, refactor opinions, or suggestions for additional test coverage beyond what the CEO spec lists as [Required automated test]." \
  "$DIFF_FILE"
```

Read the gate's exit code:

- **Exit 0 (PASS / CONCERNS / WAIVED)** — proceed to Step 5b (stability-fix backstop, if applicable). Mention any advisory items. For CONCERNS, also surface the logged warning path (`.harness/audits/concerns-*.json`) and remind the CEO to review before commit. For WAIVED, surface the `waiver_reason`.
- **Exit 2 (FAIL)** — surface every blocking item verbatim. Halt. Stage 6 incomplete. Ask the user how to proceed (re-run test-fixer with the blocking findings as additional guidance, manual fix, or accept the risk and override later at Stage 8).
- **Exit 1 (script error / Universal Core WAIVED rejected / missing waiver_reason / legacy verdict)** — surface stderr, halt. Stage 6 cannot complete without a successful auditor call.

## Step 5b — Stability-fix lane backstop (conditional)

This step closes the cross-model gap on the stability-fix lane. When `/implement` was invoked and produced a Stage 5 auditor approval, fix correctness was already audited there. This backstop fires only when that didn't happen — i.e., the user jumped straight to `/test-fix` without `/implement`.

It fires when:

1. **No prior Stage 5 audit exists** — `.harness/state/auditor-approvals/<feature>-stage5.json` is absent. Presence means `/implement` ran and the auditor already audited the fix on its full diff; running again here would duplicate.

If the prior-audit file exists, skip Step 5b and report `✓ Stage 6 complete: tests pass; auditor post-fix audit (legitimacy + coverage + correctness + spec-vs-reality) advanced.` exactly as the Step 5 PASS path does.

### Determine the original-fix baseline

`$BASELINE` from Step 1 was captured at `/test-fix` start, so it includes only the test-fix loop. The stability fix itself sits before that. Ask the user once:

> "Stability-fix lane detected (no prior `/implement` auditor audit on this change). What's the last commit before you started this fix? (e.g., `HEAD~1`, or a sha)"

Capture as `ORIGINAL_BASELINE`. Do not guess — an incorrect baseline either bloats the diff with unrelated commits (noise) or misses part of the fix (false negatives). If the user is unsure, prompt them to check `git log --oneline` rather than defaulting.

### Run the audit

```bash
STAB_DIFF=$(mktemp /tmp/test-fix-stab-diff.XXXXXX)
git diff "$ORIGINAL_BASELINE" > "$STAB_DIFF"

bash .harness/scripts/auditor-gate.sh review <feature> 6-fix \
  "Stability-fix lane backstop. Stages 1–3 were skipped per CLAUDE.md and /implement was not invoked, so this is the FIRST cross-model audit on this change end-to-end. The diff includes the original fix plus any test-fixer adjustments. Audit fix CORRECTNESS (Step 5 already covered test legitimacy + scenario coverage). Look for: access-control / RLS correctness when {{backend_code_paths}} is touched; auth-context assumptions; anonymous-vs-authenticated path handling; race conditions between async operations; runtime edge cases (null, empty, concurrent, expired-session, signed-out timing, app-backgrounded mid-mutation); source-fix contradictions (does the fix actually address the bug? does it introduce a new failure mode? does it bypass an access-control gate the prior code relied on?); CEO-spec contradictions (read {{spec_dir}}<feature>.md and confirm the fix matches the spec's behavior for the touched scenarios — not just the test). Compare against scoped rule files and the feature spec. Do NOT flag: project conventions in {{anti_flag_rules}}, formatting, naming preferences, refactor opinions, or suggestions for additional test coverage beyond what the CEO spec lists as [Required automated test]." \
  "$STAB_DIFF"
```

The gate writes `.harness/state/auditor-approvals/<feature>-stage6-fix.json`.

Read the gate's exit code:

- **Exit 0 (PASS / CONCERNS / WAIVED)** — surface `✓ Stage 6 complete: tests pass; auditor post-fix audit advanced; stability-fix end-to-end audit advanced.` Mention any advisory items. For CONCERNS, surface the logged warning path (`.harness/audits/concerns-*.json`) and remind the CEO to review before commit. For WAIVED, surface the `waiver_reason`. Stage 6 complete.
- **Exit 2 (FAIL)** — surface every blocking item verbatim. Halt. Stage 6 incomplete. The user addresses (typically by editing the fix, not the tests), then re-invokes `/test-fix`.
- **Exit 1 (script error / Universal Core WAIVED rejected / missing waiver_reason / legacy verdict)** — surface stderr, halt.

## Step 6 — Escalation routing

The test-fixer exhausted 3 iterations without PASS.

### 6a. Persist this attempt

Append to `.harness/state/test-fix/<feature>-attempts.json`. Schema:

```json
{
  "feature": "<feature>",
  "routing_rounds": <integer>,
  "attempts": [
    {
      "spawned_at": "<ISO-8601 timestamp>",
      "fixes_applied": [...],
      "remaining_failures": [...],
      "hypothesis": "..."
    }
  ]
}
```

If the file exists: parse, increment `routing_rounds`, append the new attempt to `attempts`, write back atomically. If not: create with `routing_rounds: 1` and the array containing one entry. Use `mkdir -p .harness/state/test-fix/` if the directory is missing.

### 6b. Auto-fire auditor diagnostic

Invoke the gate in diagnostic mode:

```bash
bash .harness/scripts/auditor-gate.sh diagnostic <feature> \
  "Three test-fixer iterations exhausted; tests still fail. Read the failing test output, the test files, the source files under test, the spec at {{spec_dir}}<feature>.md, and the prior attempts (provided as the artifact). Produce a different-model read: is the spec consistent with what the test asserts? Is there a hidden assumption in the implementation? Is there a fix angle the prior attempts haven't tried? Return ranked hypotheses with concrete next steps." \
  ".harness/state/test-fix/<feature>-attempts.json"
```

The gate writes `.harness/state/auditor-approvals/<feature>-stage6-diagnostic.json`. Surface the hypotheses to the user side-by-side with the test-fixer's `HYPOTHESIS`.

### 6c. Present the routing menu

```
[1] Retry test-fixer — fresh context, with prior attempts included as REJECTED_APPROACHES
[2] Re-examine spec — open {{spec_dir}}<feature>.md (test-fixer hypothesis suggests ambiguity)
[3] Re-examine plan — open {{spec_dir}}<feature>-plan.md (test design may be wrong)
[4] Manual takeover — drop back to interactive Claude with full context dumped
```

Wait for the user's choice. Do not auto-select.

### 6d. Hard retry budget

If `routing_rounds` in the attempts file has reached **2**, only `[4] Manual takeover` is offered. The harness stops offering retry/re-examine after two rounds — past that, the failure mode is human, not algorithmic.

## Trust contract

- **Surface the test-fixer report verbatim.** No "test-fixer says it's fine, proceeding." The user sees `FIXES_APPLIED` in full, including every `suspicious` flag, before any verdict is computed.
- **Auditor post-fix audit is unconditional on PASS.** No skipping the audit because "the diff looks fine." The skill has no judgment authority to bypass the gate.
- **Verdict is parsed deterministically from the gate's exit code.** No prose interpretation. The four verdicts are `PASS` (advance silently), `CONCERNS` (advance with logged warning at `.harness/audits/concerns-*.json` for CEO commit-time review), `FAIL` (halt), and `WAIVED` (CEO override only; rejected by the gate if any blocking item cites Universal Core). Note: in this skill, "PASS" appears in two distinct senses — the **test-fixer's** PASS/FAIL signal (tests passed) and the **auditor's** PASS verdict (one of the four). They are independent; both must be checked.
- **On disagreement** (test-fixer says tests-PASS, auditor says FAIL): auditor wins by default. Surface both views. The user overrides explicitly if they disagree.

## Step 7 — Update implementation file "Scenario → automated test map"

After every applicable auditor pass advances (PASS, CONCERNS, or WAIVED), update `{{implementation_dir}}<feature>-implementation.md`. The map lives in the implementation file, NOT the CEO spec — file paths and test descriptions are manager-domain. For each scenario classified `[Required automated test]` in the CEO spec, ensure the implementation file's "Scenario → automated test map" section has a subsection with the resolved test bindings:

```markdown
### Scenario 3.4 — <scenario name from CEO spec>

- scenario-3-4 — <path>/<test-file> > describe > test name
- scenario-3-4 — <path>/<other-test-file> > ... (if multiple tests cover the scenario)
```

If the implementation file does not yet exist (simple feature), create it with at minimum the header pointer to the CEO spec plus this map section. If the implementation file exists but lacks the map section, append it.

If a scenario is reclassified to `[Smoke test only]` after the fact, remove its subsection from the map.

This closes the spec ↔ test mapping loop and makes regression triage tractable months later. The source-of-truth scenario↔test binding remains the `// Verifies scenario X.Y` comment at the top of each test file; the map is the human-facing lookup convenience.

## Completion criteria

Stage 6 is complete when one of:

- All tests pass AND the auditor post-fix audit advances (`PASS`, `CONCERNS`, or `WAIVED` — Step 5: legitimacy + coverage + correctness + spec-vs-reality) AND, if Step 5b's condition holds, the stability-fix end-to-end audit advances (`PASS`, `CONCERNS`, or `WAIVED`), AND the implementation file's "Scenario → automated test map" has a subsection populated for every `[Required automated test]` scenario in the CEO spec (Step 7). CONCERNS warnings must be surfaced to the CEO before commit.
- The user has explicitly accepted ESCALATE state and chosen `[4] Manual takeover` (Step 6d).

Either outcome must be reported explicitly. No silent advancement to Stage 7 (smoke).

## Anti-patterns the skill blocks

- Implementer rationalizing why a failing test is "wrong" → fresh subagent context
- Implementer mocking internals to make a test pass → test-fixer's hard rules + auditor audit
- Implementer `.skip`-ing a test (or framework equivalent) → suspicious flag + auditor audit
- Loosening an assertion to match buggy code → suspicious flag + auditor audit
- Unbounded iterations on a stuck test → 3-iteration cap → escalation
- Looping forever on retry → 2-routing-round hard limit → manual takeover only
- Skipping the post-fix audit because the diff looks fine → mandatory by skill design
- Stability-fix lane shipping changes with zero cross-model review → Step 5b fires whenever no prior Stage 5 auditor audit exists
- Tests that cover-but-don't-name a scenario → auditor's scenario-coverage axis flags missing `// Verifies scenario X.Y` comments
- Implementation file's "Scenario → automated test map" missing a subsection for any `[Required automated test]` scenario after auditor advances (PASS / CONCERNS / WAIVED) → completion criteria forces the update
