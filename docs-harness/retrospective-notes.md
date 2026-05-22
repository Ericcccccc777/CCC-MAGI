# Retrospective Notes — Patterns Worth Carrying Forward

Lessons learned during real-world harness use, generalized from project-specific incidents. These aren't bugs to fix — they're **patterns to recognize and apply on future feature builds**.

Read this periodically. Re-read it before any non-trivial feature work. Each pattern below has a recognition trigger and a mitigation cost that beats the cost of re-discovering the pattern the hard way.

---

## 1. Prescribe one conservative mechanism, not a list of options

**Pattern:** When the CEO spec or implementation notes describe a foundational mechanism (a defensive cleanup path, a failsafe, a recovery sequence), don't list multiple "viable options" labeled as alternatives. Pick the most conservative one and prescribe it. Optimizations belong in code review or follow-up commits, not in the foundational spec.

**Why this fails when ignored:** A multi-option list invites the auditor to flag subtle gaps in each option, one round at a time. Each option that turns out to have a defect costs an audit round. Listing three "viable options" where two are subtly wrong = two extra audit rounds you didn't need.

**Mitigation:** Prescribe the conservative-default mechanism upfront (e.g., "network-independent clear + verifiable post-condition"). State the post-condition the mechanism must satisfy. If a smarter mechanism exists, propose it during code review where its merits can be evaluated against a known baseline. Don't make the auditor evaluate four alternative mechanisms simultaneously.

**Specific extension — SDK API post-conditions:** When the prescribed mechanism includes an SDK API call, attach a brief note documenting the actual return type and any non-trivial error-mode behavior. Models routinely assume an SDK's API surface — "this returns null on signed-out" — when the actual return is an envelope (`{data, error}`) with non-trivial interactions between fields. Verify against the SDK source, not against the model's recall.

---

## 2. Spec refactors require BOTH terminology grep AND cross-reference trace

**Pattern:** When a foundational spec replaces a named concept (e.g., a unified model replaces "soft" / "hard" variants of a behavior), the refactor isn't complete until two passes have run:

1. **Terminology grep** — `grep -i` for the old terms across all spec files. Catches stale wording.
2. **Cross-reference trace** — manually read every section that cross-references the refactored concept and verify the cross-referenced mechanic against the source spec's current contract. Catches sections that use the correct terminology but describe stale mechanics.

**Why both:** Terminology grep catches surface drift. Behavioral drift hides behind correct-looking words. A section can use the new vocabulary and still describe the old mechanism — grep won't catch it; only re-reading will.

**Cost:**
- Terminology grep: 30 seconds
- Cross-reference trace: ~1 hour for a focused refactor (one or two spec files; ~10 cross-referencing sections)

**Saves:** ~3–5 audit rounds per foundational refactor (each round was historically catching one or two surviving stale references that should have been caught upfront).

---

## 3. "This surface doesn't exist in code" rationales need a verification grep

**Pattern:** When a Stage 4 execution plan marks a step SKIP with the rationale "this surface doesn't exist in code," the skip MUST carry a captured grep (or equivalent search) confirming non-existence. Either record the grep output beside the skip, or keep the step active until the grep runs.

**Why this fails when ignored:** The model's mental model of "what exists in the codebase" can diverge from the actual codebase. "I think it doesn't exist" is not the same as "I grepped and confirmed it doesn't exist." A skip without a grep is a guess; if the surface actually exists, the related spec gap ships uncaught.

**Specific failure pattern:** A planned skip on the assumption that an error-handling component doesn't exist, when in fact a component matching the pattern does exist (under a slightly different name). The spec-vs-code gap then ships and is caught later by audit, costing the rounds that the grep would have prevented.

**Mitigation:** Every SKIP entry citing non-existence carries the grep command + output (or "no match" confirmation) inline. 5 seconds per skip. Catches the gap before any rounds run.

---

## 4. System-wide error contracts need planning-time blast-radius enumeration

**Pattern:** When a plan introduces a system-wide error contract — a sentinel error class, a new HTTP status the global error handler doesn't sweep, a new query state the render switch doesn't handle, any change where existing handlers across the codebase will see a NEW error class — the plan MUST produce a **classification table at planning time, not at implementation time**.

For every reachable consumer site, the table assigns one tag:

| Tag | Meaning |
|-----|---------|
| **exempt-via-meta** | Opt out at construction (e.g., mutation flag). Used when the consumer owns its own error UX. |
| **catch-via-consumer** | Let the gate fire; consuming screen catches and silent-returns. Used when the universal handler is the canonical surface. |
| **catch-in-hook** | Same as catch-via-consumer but the filter lives in the hook's own error callback. |
| **structurally clean** | The consumer's existing typed-error gate already filters the new error class. Document as deliberate. |
| **direct-call (no gate)** | Bypass the gate entirely. Used for background / auto-fired operations where the universal handler would be noise. |

Each row names the consumer site (`file:line`) and the rationale. The implementation notes' "Out-of-scope list" / "Exempt list" sections must map 1:1 to this table.

**Why this fails when ignored:** Without the upfront table, the auditor enumerates the gap one round at a time. Each round catches a subset of consumer sites; total cost scales with site count × audit-round cost. For a system-wide change touching dozens of consumer sites, this is 3–6 audit rounds (hours of compute + reviewer time).

**Cost:**
- Comprehensive sweep at planning time: ~60 minutes
- Audit-round equivalent: 5–6 rounds × 30 min compute + 30 min review = 5–6 hours absorbed

**The pattern generalizes:** Any primitive that changes which path a control-flow boundary takes — new auth-state values the routing switch doesn't case on, new query states the render switch doesn't handle, refetch-on-focus toggles — benefits from the same planning-time classification.

---

## 5. Comprehensive sweep ≠ correctness — also run a post-sweep audit

**Pattern:** After a comprehensive sweep against an auditor finding, run a deliberate cross-check against the spec's enumerated lists at sweep time. The sweep finds *the surface area*; the spec defines *the right decision for each surface*. These are different.

The post-sweep audit catches three classes of residual gap:

1. **Grep miss.** A consumer site that the sweep grep didn't surface (e.g., a hook with a non-obvious name). Mitigation: eyeball cross-reference the spec's named examples against the table rows. Every named example must have a row.

2. **Classification error against an explicit spec carve-out.** A consumer was classified one way during the sweep but the spec explicitly lists it as another. The spec wins. Mitigation: every exempt-from-default classification verifies that the consumer is named in the spec's carve-out list.

3. **State-coupling bug independent of the sweep's pattern.** Optimistic state armed before a mutation that fires through the new gate. If the gate errors, the optimistic state never resets → silent regression elsewhere. Mitigation: at sweep time, also grep for `useRef(false)` / `useState(false)` patterns where the ref/state is flipped to true synchronously before a mutation. Each such "armed flag" needs a non-success reset path.

**Cost:** ~20 minutes adds to a sweep. Catches what would otherwise surface in 1–2 additional audit rounds.

---

## 6. Refactors that move logic between scope levels need a pre-existing-handlers checklist

**Pattern:** When a refactor moves logic between scope levels (hook → screen, screen → shared, sheet → screen, component → page), the move is **NOT** complete until an explicit pre-existing-handlers checklist has been enumerated.

Every behavior the OLD scope handled — every branch in its switch statement, every guard predicate, every error class catch, every conditional render, every prop / state value the old scope handled — must be re-listed and verified as preserved by the NEW scope.

**Why this fails when ignored:** "Comprehensive sweep" enumeration tells you what was **missed** (a consumer that should have a change). It says nothing about what was **lost** (a refactor that dropped a pre-existing behavior). These are different audit axes:

- **Missed** = a site that should have a change but didn't get one.
- **Lost** = a site that got a change which dropped a pre-existing behavior.

Sweeps catch "missed." Pre-existing-handlers checklist catches "lost." Both are needed.

**Cost:** 15–30 minutes per non-trivial refactor. Catches the bug at refactor time, before the WIP commit, before any audit round.

---

## 7. Spec / audit cycles catch correctness, not whether the design itself was warranted

**Pattern:** The audit invariant (Constitution § 1) ensures whatever ships is correct against its design. It does NOT ensure the design itself is warranted. Constitution § STRONG #3 (simplicity over completeness) provides the "is the design too big?" check — but only if someone asks the meta-question at the right moment.

Stage 1 spec and Stage 4 plan are too early for that question — the design hasn't shipped, so its real cost isn't visible. **Manual smoke on real environments is where "is this the right amount of machinery?" becomes visible.** When smoke surfaces "too much," the right move is sometimes to delete the machinery rather than fix it.

### Pattern-recognition triggers

Pause for the meta-question when:

- **Multiple unrelated visual / behavioral issues surface in the same feature area during smoke.** Three unrelated symptoms in one surface area is a smell that the surface is doing too much.
- **The custom infrastructure exceeds the value it delivers.** If a feature ships custom-built primitives where platform-native primitives would suffice (custom toast vs `Alert.alert`; custom modal stack vs platform navigation), the maintenance cost rarely justifies the visual consistency gain.
- **Per-feature components share >80% structure.** When every feature has a `<FeatureNameError>` with the same icon + title + button + onRetry shape, the abstraction is missing — the per-feature components are just glue, and a shared component eliminates them.
- **Custom replacements for platform-native primitives.** "Consistency" arguments for replacing native primitives rarely pencil out for solo-maintainable projects.

### Cost shape

Building the minimal design is usually cheaper than building the ambitious one — sometimes by a factor of 4 or 5. The simplification typically:

- Ships in less time than the ambitious version did
- Has less code surface
- Handles fewer edge cases (because there's less to handle)
- Reads more clearly because there's less to read

The dominant reason to keep this pattern visible is that the cost shape is asymmetric in the simplification's favor. Don't assume an ambitious design is "more thorough"; sometimes it's just more code.

---

## 8. Pre-commit hooks enforce what discipline can't

**Pattern:** Any rule that depends on "the developer will remember to do X" eventually fails. Mechanical enforcement via pre-commit hook is the only durable answer for invariants that must hold across every commit.

Examples worth hook-enforcing:

- **Migration ↔ spec sync.** If a migration touches a table referenced in a CEO spec, the spec must update in the same commit. Pre-commit hook reads `git diff --name-only`, identifies touched tables (from the migration content), and looks for the corresponding spec file in the diff.
- **Spec ↔ code sync.** User-visible behavior changes must update the corresponding CEO spec.
- **Plan-file deletion.** `<feature>-plan.md` cannot survive the commit that ships its implementation.

**Why this fails when ignored:** Without the hook, drift is silent. The first symptom surfaces months later as a misleading spec or an audit finding pointing at code that disagrees with its spec. The hook catches it at commit time — when the fix is one update, not one archaeological dig.

**Cost:** A small shell script per hook. ~30 minutes to author, near-zero to maintain.

---

## 9. Test legitimacy is per-commit, not per-feature

**Pattern:** A test that passes can pass for the wrong reason:

- An assertion was loosened to match buggy code
- A `.skip` (or framework equivalent) was added
- Internal mocks were added so the test no longer exercises real behavior
- Test cases were deleted entirely
- Setup mocks were re-shaped to hide a regression

Stage 6's auditor pass scrutinizes the test-fix diff on this dimension specifically. The `suspicious` flag in the test-fixer's structured report exists to surface these patterns proactively.

**Why this matters:** A passing test is only evidence of correctness if the test would have failed on broken code. The harness's discipline:

- Stability-fix lane mechanically requires a failing test BEFORE the fix.
- Test-fixer's hard rules ban the suspicious modifications above.
- Auditor's Stage 6 Axis 1 (test legitimacy) explicitly looks for them.

Test legitimacy is not a one-time setup; it's per-commit vigilance.

---

## 10. Spec wording outside the diff is still in scope for audit

**Pattern:** During apply/deploy phases, spec text can get edited outside the diff that the Stage 5 auditor reviewed. The Stage 5 auditor only saw implementation changes; the post-Stage-5 spec edits go unaudited by any prior gate.

Stage 7 (CEO smoke test) reads the spec to drive smoke. If a spec sentence no longer matches reality, the smoke test gets driven in the wrong direction. This is where Stage 6's **fourth axis (spec-vs-reality match)** matters: it reads the spec end-to-end (not just the diff) and flags sentences that assert user-observable behavior the code doesn't deliver.

**Why this is narrow:** The axis is NOT about plain-language imprecision. The spec is intentionally non-mechanical. Flag a sentence ONLY when:

- It asserts a user-observable behavior the code provably doesn't deliver, OR
- It asserts a guarantee the code doesn't enforce.

Do NOT flag wording that omits implementation mechanism — the spec is supposed to omit it. Do NOT suggest the spec become more technical so the audit is mechanically easier — that inverts the two-file model.

**The exemplar this axis was written for:** a spec sentence asserting a user recovery path ("a retry of the action picks up where it left off") when the user's session was already revoked and they cannot re-invoke. That's behavioral drift the CEO would design the smoke test around. Stage 6's fourth axis catches it.

---

## How to use this file

- Before a non-trivial feature build, skim the section headers.
- When a pattern recognition trigger fires (multiple unrelated symptoms in one surface area; sweep is about to declare done; refactor is moving logic between scope levels), open this file and read the relevant section.
- When you discover a new pattern worth carrying forward, add it here with: pattern name, when it surfaces, mitigation cost, what it saves. Keep entries concrete enough to apply on the next build.

---

## Change history

```
2026-05: v1 — initial generalized retrospective, extracted and abstracted from the original project-specific incident log.
```
