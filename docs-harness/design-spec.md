# Harness Design Spec

This document is the **architectural rationale** for the harness. It explains *why* the harness is shaped the way it is — the operating model, the load-bearing invariants, and the blind spots that motivated the design.

Operational details (how each stage works step-by-step) live in `outcome/skills/<skill>/SKILL.md`. Rules and identity live in `outcome/constitution.md`. Workflow conventions live in `outcome/CLAUDE.md`. This file is the meta-layer that explains why all of that is structured the way it is.

---

## 0. What this document is for

The harness encodes a small number of opinionated choices about how an AI-assisted workflow should be run:

- A human owns intent; AI never overrides it.
- Every code change passes a different-model audit before commit.
- The thing a non-technical person reads (the spec) is separate from the thing engineers read (the implementation notes).
- Real-human verification is mandatory, not optional.
- Specs and code stay in sync, mechanically enforced.

This document explains the rationale for each of those choices, plus the secondary structures (lanes, stages, scenario IDs, agent roles) that follow from them.

A contributor — human or AI — who understands the rationale can extend the harness without breaking it. A contributor who only reads the operational docs will eventually rationalize past an invariant that exists for a non-obvious reason. This file is the defense against that.

---

## 1. The operating model

The harness organizes work like a small company.

### 1.1 Roles

```
CEO (the human user)
  - Defines intent (happy paths, edge-case behavior)
  - Makes business / user-impact decisions
  - Defines project identity (constitution.md Section 2 — who we serve, what we don't do, compliance, performance floors)
  - Runs smoke tests on the actual product
  - Watches production telemetry
  - Has final say when models disagree

Tech Lead (Main Claude + auditor model)
  - Discovers edge cases with the CEO
  - Decides implementation approaches
  - Writes code (Main Claude)
  - Cross-checks via a different model (auditor)

Junior Reviewers (subagents, mechanical rule enforcement only)
  - frontend-reviewer / backend-reviewer / security-reviewer / ...
  - Read the diff, cite the rule, report violations
  - Never exercise judgment

Junior Programmer (subagent)
  - test-fixer — writes tests, fixes failing ones
  - Fresh context, doesn't know what the implementer thought
```

### 1.2 Who decides what

| Decision class | Owner | Examples |
|----------------|-------|----------|
| Intent / scope / business trade-offs | **CEO only** | "What should this feature do?" |
| Implementation approach | **Tech Lead only** | "Which library? Which pattern?" |
| Rule conformance | **Junior reviewer (mechanical)** | "Does the diff break a documented rule?" |
| Test correctness | **Auditor (judgment)** | "Did the fix actually fix it?" |

### 1.3 What the CEO does NOT do

- Read code (the harness exists so the CEO can ship without reading code)
- Make technical choices (library X vs library Y is Tech Lead territory)
- Justify intent (the CEO's word *is* intent)

### 1.4 What the Tech Lead does NOT do

- Question CEO intent at later stages (paraphrase to confirm — never to challenge)
- Reverse CEO decisions
- Ask the CEO technical questions ("hook or context API?" — translate to user impact instead)

### 1.5 Why this model

LLMs default to "helpful assistant" behavior — they want to please. That collapses the role boundary: the model proposes intent, evaluates its own intent, then judges its own output. Bias compounds across the loop. Explicit role separation prevents this:

- The CEO holds intent → the LLM cannot drift the intent.
- The auditor (different model) judges output → the implementer cannot grade its own work.
- Junior reviewers enforce rules mechanically → no judgment-shaped escape hatch.

The cost is some upfront ceremony. The benefit is a workflow that doesn't accumulate hidden drift across iterations.

---

## 2. The load-bearing invariant: cross-model audit

**Every code change passes a different-model audit before commit.** No exceptions by lane or surface. (See `constitution.md § 1`.)

### 2.1 Why "different model" specifically

Same-model self-audit reliably misses what same-model implementation rationalized. The same priors that generated the code generate the audit. Switching models (Claude → Codex, or vice versa) gets you a reviewer with different priors who catches different mistakes.

### 2.2 Why "every change," not just "important ones"

"This change is too small to audit" is the precise failure mode the invariant prevents. Small changes accumulate. Model-bias drift is per-change, not per-line. The cost of running the audit on a trivial change is small (Quick mode runs in seconds); the cost of skipping is unbounded (silent drift surfaces months later).

### 2.3 Audit intensity scales with change size

| Lane | Audit shape |
|------|-------------|
| Full workflow (new feature / audit-mode) | Full review across stages 1–6 |
| Stability-fix | Full review at stages 5 & 6 |
| Trivial-change | Quick mode (BLOCKING-only — security holes, data loss, defects only) |

Audit-exempt changes: pure docs, pure comments, pure formatting, pure tooling. Everything else passes audit.

### 2.4 Single-engine fallback

If `auditor_model = None` (the user can't run a second model), the audit step still runs — but uses a fresh-context invocation of the same model. The bias-cancellation guarantee weakens; the discipline of a second look survives. Strictly worse than two-model; strictly better than no audit.

---

## 3. The two-file feature spec model

Every feature has up to two docs:

1. **`{{spec_dir}}<name>.md`** — the **CEO spec**. Plain language. The CEO signs off on it; the CEO reads it end-to-end at smoke time. Tech terms are categorically banned.
2. **`{{implementation_dir}}<name>-implementation.md`** — the **manager's notes**. Tech detail. Routing tables, state keys, library versions, scenario→test maps, audit-delta ledgers. The Tech Lead and junior reviewers read it; the CEO doesn't have to.

### 3.1 Why two files

When CEO content and manager content live in one file:

- The CEO can't read their own spec (it's full of tech jargon they don't understand).
- The manager can't write the file freely (every paragraph has to be defensible in plain language).
- Drift compounds: the manager updates tech detail; the CEO doesn't know the user-facing behavior changed.

Separating them:

- The CEO spec stays scannable and signoffable by a non-engineer.
- The implementation notes can carry every routing table, RLS policy, and test-binding the harness needs.
- Drift between the two surfaces is detectable mechanically (every spec change must touch the right file in the same commit — `CLAUDE.md § Doc-in-sync responsibility`).

### 3.2 The plain-language rule

The CEO spec is **banned from these categorical content types** (translate to behavior instead):

- Library / framework names
- Code identifiers (hook / function / store names)
- File paths
- RPC / function / table / column names
- Payload shapes (JSON field lists)
- Migration timestamps
- SDK error type names
- HTTP status codes as primary verbs
- Test file paths and test descriptions
- Query key constants

**The shape test:** if a non-engineer reading the sentence aloud would stumble, the sentence belongs in the implementation file. Translate to outcome ("nothing about the user reaches the device before the gate is passed"), not mechanism ("the RPC returns only `{state, reason, dormancy_required}`").

### 3.3 Audit-delta ledgers belong in the implementation file

When `/audit-spec` produces deltas (code-vs-spec reconciliation), the ledger goes in `{{implementation_dir}}<name>-implementation.md`, never in the CEO spec. By definition the ledger tracks how code matches spec — that is manager-domain content.

---

## 4. The 9-stage workflow

Every full-lane change passes through nine stages:

1. **Draft / as-built spec** — paraphrase CEO intent, run edge-case sweep, or reverse-engineer existing code.
2. **Finalize spec** — mark FINALIZED, final auditor cross-check.
3. **Design schema** — only if `backend_db_type` is configured.
4. **Write execution plan** — per-file checklist, library-version verification.
5. **Implement per plan** — mechanical reviewer chain + auditor judgment.
6. **Auto tests** — test-fixer subagent + four-axis auditor audit.
7. **CEO smoke test** — real human runs the application manually.
8. **Commit & push** — Conventional Commits, doc-in-sync check, only push if both Stage 6 + Stage 7 passed.
9. **Watch after release** — observe telemetry for 24h.

(Stage details live in `outcome/skills/<skill>/SKILL.md`.)

### 4.1 Why nine stages

Fewer stages save time but lose enforcement points. Each stage is a gate that catches a different class of failure:

- Stage 2 catches sloppy hand-offs from Stage 1.
- Stage 4 catches false library-API assumptions (high-trap-libraries) before any code is written — a previously un-audited blind spot in early versions of the harness.
- Stage 6 catches assertion-loosening / test-skipping / scenario-coverage gaps.
- Stage 7 catches "AI thinks it works, actually doesn't" — a category that no LLM audit reliably catches.
- Stage 9 catches drift between testing and production usage.

### 4.2 Why this order, no reordering

Stages don't compose freely. Spec drives schema; schema drives plan; plan drives implementation; implementation drives tests. Reordering breaks the chain. A stage may be **skipped** via an explicit lane (stability-fix skips 1–3; trivial-change condenses 4–5), but never **reordered**.

### 4.3 Stage 6's fourth axis — spec-vs-reality match

Stage 6 historically had three axes (test legitimacy, scenario coverage, fix correctness). A fourth axis was added after a real incident: the implementer had Stage 5 approved by the auditor, then quietly edited a spec sentence during deploy, and the now-incorrect spec sentence drove the CEO's smoke test wrong. The Stage 5 auditor never saw the spec edit (it audited the implementation diff); Stage 7 ran against a spec that no longer matched code. Adding a fourth axis at Stage 6 catches this drift before the CEO reads the spec to drive smoke.

The axis is narrow: it flags sentences asserting user-observable behavior the code provably doesn't deliver, or guarantees the code doesn't enforce. It does NOT police plain-language imprecision — the spec is supposed to omit mechanism; that's the two-file model's whole point.

---

## 5. The three lanes

Three lanes for three change shapes:

| Lane | When | Stages |
|------|------|--------|
| **Full workflow** | New feature / intent change / schema change / new dependency | All 9 |
| **Stability-fix** | Bug fix; intent unchanged, no new surface, no schema change | Skip 1–3; failing test mandatory before fix |
| **Trivial-change** | <20 LOC, no new surface, no schema change, no intent change | Skip 1–3; condensed 4–5; auditor Quick mode |

### 5.1 Why three, not "as needed"

"As needed" means the implementer decides what level of scrutiny their own change deserves. That's self-grading. Three named lanes with explicit entry criteria force the conversation: which lane is this, and why?

The Tech Lead infers the lane from the change shape; the CEO confirms. Never auto-switches mid-flow — if the lane was wrong, the CEO re-classifies.

### 5.2 The stability-fix invariant — failing test FIRST

A stability-fix change MUST author a failing test before the fix. The test is confirmed to fail on the broken code; then the fix lands; then the test passes. The reason: a "fix" without a corresponding test that the bug fails is not a fix, it's a guess. The harness mechanically enforces this at `/implement` Step 0 and `/test-fix` Step 0.

### 5.3 Trivial-change's escape hatch

Trivial-change uses auditor Quick mode (BLOCKING-only). If the auditor's Quick audit surfaces non-trivial concerns, that's a signal the lane is wrong — the change is misclassified. The harness surfaces this to the CEO for re-classification rather than silently flagging the concerns as advisory and shipping.

---

## 6. Auditor opinion classification

Auditor findings are classified by intensity:

| Class | Handling | Examples |
|-------|----------|----------|
| **BLOCKING** | Must resolve. Pushback escalates to CEO. | Security holes; data loss; spec violations; race conditions; outright defects. |
| **STRONG** | Accept, or push back with explicit reasoning. | Better patterns exist; maintenance concerns; convention violations. |
| **ADVISORY** | Free choice. Usually accepted but skippable. | Style; naming; small improvements. |

The verdict comes back as a structured `verdict: APPROVE` / `REQUEST CHANGES` plus `critical[]` and `suggestions[]` arrays (see `outcome/AGENTS.md § Verdict output`). `REQUEST CHANGES` halts the flow until resolved.

### 6.1 CEO escalation pattern

When the auditor disagrees with the CEO on a BLOCKING item:

```
Manager: "Auditor disagreement on [item]:
  - Auditor view: A (reasoning: ...)
  - CEO view: B (reasoning: ...)

  Impact:
  - User-result impact: yes/no
  - Cost / maintenance impact: yes/no
  - Security / risk trade-off: yes/no

  CEO decision needed."
```

The CEO decides. Reasoning lands in the spec's `## Decision history` regardless of which side wins.

Exception: Universal Core items (`constitution.md § 1`) are not overridable, even by direct CEO instruction. If the auditor's finding maps to a Universal Core item, the instruction must be reformulated; it cannot be carried out as-stated.

---

## 7. CEO vs Tech Lead decision criteria

A decision goes to the CEO if any of these is true:

1. **User-result impact** — the user sees something different, behavior changes.
2. **Cost / maintenance impact** — new library, new external service, new infra.
3. **Security / risk trade-off** — "X makes it faster but weakens Y."

If none of those, the Tech Lead decides autonomously and records the reasoning in code comments or the implementation file.

### 7.1 The self-check before asking

Before asking the CEO anything:

- Would the user notice the difference?
- Can the CEO meaningfully compare the options (without becoming an engineer)?
- Is "I don't know" a defensible CEO answer?

Three "no"s = don't ask. Decide internally, document the reasoning.

### 7.2 Good question vs bad question

| ❌ Bad (CEO can't answer) | ✅ Good (translated to user result) |
|---------------------------|-------------------------------------|
| "useState or useReducer?" | Don't ask. Tech Lead's call. |
| "OR or AND in this access predicate?" | Don't ask. Tech Lead's call. |
| "Should we cache chat messages aggressively?" | "Option A: chat opens slow but works offline. Option B: chat opens fast but needs network. Which UX?" |

---

## 8. Junior subagent roles — mechanical only

Junior reviewers (`frontend-reviewer`, `backend-reviewer`, `security-reviewer`) and the junior programmer (`test-fixer`) do **mechanical work only**:

- **Reviewers**: read the diff, look up the rule, report violations. Never propose new rules, evaluate business logic, or exercise judgment.
- **Programmer (test-fixer)**: writes/edits test code from fresh context. Doesn't know what the implementer believed; can't be biased by their reasoning. Writes within hard rules (never `.skip`, never loosen an assertion, etc.).

### 8.1 Why mechanical-only

Judgment in junior agents creates a second judge that competes with the auditor. That defeats the bias-cancellation invariant. The auditor is the judgment layer; junior agents are the rule-enforcement layer. Each layer has a clean job. Mixing them muddies the audit chain.

### 8.2 Subagent invocation is mechanical too

Path-based triggers: `client_code_paths` matches → `frontend-reviewer` fires. `backend_code_paths` matches → `backend-reviewer` fires. Specific predicates → `security-reviewer` fires. The implementer doesn't pick which reviewer runs; the diff picks.

If the implementer could pick, "this diff doesn't need a security review" becomes an escape hatch. Mechanical selection closes it.

---

## 9. Scenario classification — every edge case gets a category

Every edge-case scenario in the CEO spec carries one of two classifications:

- **[Required automated test]** — data correctness, security/permission, business logic, error handling, user data protection.
- **[Smoke test only]** — UI / animation / device-integration / timing-sensitive; cost of automating exceeds value.

### 9.1 Why classify

Without classification, every scenario implicitly becomes "automate everything" (overhead) or "skip the automated test if it feels hard" (drift). Explicit classification per scenario forces the conversation: is this thing automate-able with reasonable effort, and is it the kind of failure that needs an automated catcher? CEO confirms each classification (not silently assigned by the LLM).

### 9.2 Scenario-ID-to-test mapping

Every automated test carries a `// Verifies scenario X.Y` comment at the top:

```
// Verifies scenario 3.4 — <scenario name from spec>
test('<test name>', async () => { ... })
```

The comment is the source-of-truth binding. The implementation file's `## Scenario → automated test map` section is the human-facing lookup convenience. The CEO spec carries the classification only, never the test ID — file paths in the CEO spec violate the two-file model.

### 9.3 Why this matters months later

When the error tracker pings a regression six months from now, the failing test maps to a scenario ID, the scenario ID maps to a CEO-spec section that defines the expected behavior, and `git blame` of the test maps to the commit that introduced the regression. The chain is fast and unambiguous; without scenario IDs it's an archaeological dig.

---

## 10. Anti-flag rules — telling the auditor what to ignore

Projects accumulate deliberate conventions that look like issues to an outside reviewer. `Pressable` is the project standard; `TouchableOpacity` is banned. `(SELECT auth.uid())` is the project pattern; bare `auth.uid()` is wrong. Etc.

Without an anti-flag list, the auditor wastes signal on every false positive. The harness ships an empty anti-flag list in `AGENTS.md`; `/init` seeds a few examples based on the detected tech stack; `/add-anti-flag` grows the list as the project develops conventions.

### 10.1 Why this is a separate mechanism

Anti-flag rules are NOT the same as the audit's checklist. The checklist tells the auditor what to look for. The anti-flag list tells the auditor what to NOT flag. Both are necessary — the auditor must know what's a violation AND what looks like a violation but isn't.

---

## 11. Constitution as the immovable layer

The three-layer governance structure:

```
Constitution (Section 1: Universal Core)
  ↓ cannot be overridden by anyone, including CEO
CLAUDE.md (STRONG principles + operational guide)
  ↓ overridable by CEO with reasoning recorded
spec / rule sources (per-feature, per-area)
  ↓ refined per scenario
code
```

### 11.1 Why a constitution at all

CLAUDE.md is operational and grows over time. As CLAUDE.md grows, the load-bearing invariants get diluted in the operational detail. A separate constitution keeps the invariants small (~5 items), prominent (loaded first by every agent), and immune to silent revision via CLAUDE.md edits.

### 11.2 What goes in the constitution

Five items, shipped with the harness, cannot be removed:

1. Cross-model audit is mandatory.
2. Data ownership red line — user data doesn't leak into logs/errors/cache/cross-user responses.
3. CEO has final authority, EXCEPT on Universal Core.
4. Real-human smoke test is mandatory.
5. Spec and reality stay in sync.

Section 2 (project identity — filled at `/init`) and Section 3 (project-specific red lines — grows over time) are user-owned. Section 1 is harness-owned and immovable.

---

## 12. Blind spots this design closed

Earlier versions of an AI-workflow harness left these gaps:

| Blind spot | How this design closes it |
|------------|---------------------------|
| Stage 4 (planning) was un-audited | Auditor judgment audit at Stage 4 |
| UI / feature stability-fixes shipped without cross-model review | Stability-fix lane runs full audit at Stages 5 & 6 |
| Smoke-test failures patched without test-first verification | Stability-fix Stage 0 mechanically checks for a failing test before the fix |
| Trivial changes shipped without audit at all | Trivial-change lane runs Quick auditor audit |
| Tests passed but didn't tie to spec | Mandatory `// Verifies scenario X.Y` comment |
| CEO spec mixed with implementation detail | Two-file model |
| Manager would "just make the test pass" by loosening | Fresh-context `test-fixer` with hard rules + four-axis auditor audit |
| Spec edits during deploy went unaudited | Stage 6's fourth axis (spec-vs-reality match) |
| Implementer self-grading "is this reviewer needed?" | Mechanical path-based reviewer triggers |
| Auditor opinions treated as suggestions | Verdict parsed from exit code, not prose |
| CEO told "this is too risky" with no decision frame | CEO escalation pattern (Section 6.1 here) |

Each row was once a real incident that surfaced as a bug after the fact. The design changes are the response to those incidents, not speculative future-proofing.

---

## 13. What this design is not

- **Not a build system.** The harness orchestrates conversation, audit, and commit gates. It doesn't replace your build tool.
- **Not a project boilerplate.** Tech stack, file structure, and code conventions are project-specific. The harness wraps them; it doesn't impose them.
- **Not an enterprise governance suite.** No RBAC, no audit log signing, no compliance attestations. (Those are reasonable extensions on top, not part of the core.)
- **Not a substitute for engineering judgment.** Every rule in the harness can be overridden by the CEO (except Universal Core items). The harness's job is to make sure each override is conscious.

---

## 14. Where everything else lives

| You need | Look here |
|----------|-----------|
| Project identity, what we are/aren't | `outcome/constitution.md § Section 2` |
| Universal Core invariants (immovable) | `outcome/constitution.md § Section 1` |
| Stage-by-stage operating procedure | `outcome/skills/<skill>/SKILL.md` |
| Workflow overview, lanes, doc-in-sync | `outcome/CLAUDE.md` |
| Auditor verdict format, anti-flag rules | `outcome/AGENTS.md` |
| Junior agent definitions + plugin template | `outcome/agents/` |
| CLI integration (hooks, MCP config) | `outcome/cli-configs/` |
| How to install the harness in a project | `adoption-playbook.md` (this directory) |
| Lessons from real-world use | `retrospective-notes.md` (this directory) |
| Slot definitions (all 30+) | `outcome/constitution.md § Slot registry` |

---

## 15. Change history

```
2026-05: v1 — initial generic-harness spec, extracted and abstracted from the original project-specific spec.
```
