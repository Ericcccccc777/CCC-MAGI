---
name: feature-draft
description: This skill should be used when starting a new feature. It produces stage 1 (new-feature mode) of the dual-mode feature workflow — paraphrasing CEO intent, running an edge-case round using the configured `{{edge_case_categories}}`, and a different-model auditor external review — landing a plain-language spec at {{spec_dir}}<name>.md plus an optional implementation notes file. Always use this skill to start a feature rather than writing specs freely, so every feature enters the pipeline with the same shape. Trigger when the user invokes /feature-draft, says "start a new feature", "draft a spec for X", "I want to build <feature>", "let's build <feature>", or similar intent.
argument-hint: [feature-name]
---

# /feature-draft

Drive Stage 1 of the workflow in **new-feature mode**: convert CEO intent into a finalized plain-language spec, with edge cases discovered collaboratively and validated by a different model.

The output is the **two-file model**:

- `{{spec_dir}}<name>.md` — CEO domain. Plain language, no tech terms. Always produced.
- `{{implementation_dir}}<name>-implementation.md` — manager domain. Tech detail. Produced only when the feature warrants it.

## Why this flow

Two layers of validation remove the implementer-grades-own-work bias from intent itself:

1. **Conversation-level (paraphrase + edge-case sweep)** — Main Claude paraphrases the CEO's happy path back to confirm understanding, then walks the categories in `{{edge_case_categories}}` together with the CEO. Edge-case discovery is collaborative; intent decisions stay the CEO's.
2. **Model-level (auditor external review)** — the auditor ({{auditor_model}}) independently reads the consensus spec for missing scenarios, hidden assumptions, and contradictions. Different priors catch things shared-model authorship misses.

CEO has the final word on intent; the auditor flags concerns but cannot override CEO decisions (Constitution § 3).

## Authoritative sources

Load before drafting:

1. **`constitution.md`** — project identity (Section 2) + universal core (Section 1); shapes acceptable feature scope
2. **Root `CLAUDE.md`** — two-file model, lane definitions
3. **i18n convention** — anything user-visible needs translation entries for all locales in `{{supported_locales}}`
4. **`{{rule_sources}}`** — scoped rule files that may constrain this feature's design
5. **Existing files under `{{spec_dir}}`** — to stay consistent with prior CEO-spec shape

The CEO spec must NOT pull in tech-term language from prior implementation notes during Stage 1. Tech detail belongs in the implementation file, written later.

## Invocation

- Typical: `/feature-draft <feature-name>` (e.g., `/feature-draft messaging`)
- `$ARGUMENTS` becomes the filename (`{{spec_dir}}$ARGUMENTS.md`) and the feature folder name (under `{{feature_folder_pattern}}`).

If `$ARGUMENTS` is missing, ask the user. Do not guess.

## Pre-stage check

Before Step 1, run a 30-second pre-flight:

1. `git status` — clean? If uncommitted changes exist, surface them and ask: commit first, stash, or proceed (and accept noise).
2. Existing `{{spec_dir}}<name>.md` — does it already exist? If yes, ask whether this is a redo (delete and start over), an audit (`/audit-spec <name>` instead), or an add-on to a finalized spec.
3. State recap to user: "Pre-stage clear. Lane: Full workflow (new feature). Proceeding with Stage 1 in new-feature mode. Anything to adjust before we start?"

Do not proceed without an explicit go-ahead.

## Step 1 — CEO happy path + paraphrase

Ask the CEO for the happy path in one sentence-or-paragraph, plain language (the example below uses a generic scenario; adapt to the actual feature):

> "Users open the app, type a phone number, get a code, type the code, and they're in."

If the CEO doesn't know the happy path, offer **2–3 generic patterns** ("for a feature like this, common shapes are: A, B, C — pick or describe your own"), let the CEO choose or modify, and document that the CEO selected from offered patterns (this stays in `## Decision history`).

Then **paraphrase** back: "I'm hearing X. Did I get that right?" Wait for confirmation or correction. Do not infer past what the CEO said.

> **Language mode reminder:** `{{language_mode}}`. If `plain` (default), every question is phrased so a non-engineer can answer. If `professional`, technical vocabulary is allowed in CEO-facing prompts.

## Step 2 — Edge-case round

Walk all categories listed in `{{edge_case_categories}}`. For each, raise 3–5 concrete scenarios that **could** apply to this feature, then ask the CEO which behaviors apply and how each should resolve. Keep questions in plain language; refuse to ask the CEO tech-flavored questions ("useState vs useReducer?" — never; "how should the app behave if the user double-taps the submit button?" — yes).

**Default categories** (these ship with the harness; the user can edit `{{edge_case_categories}}` at /init or via `/constitution-edit` to add domain-specific ones):

1. **Input validation** — empty, too long, special characters, wrong format
2. **Network / external dependency** — disconnected, slow, mid-failure, timeout, third-party down
3. **Concurrency** — same action attempted twice, two devices at once, race conditions
4. **Permission / authentication** — not logged in, no permission, expired session, blocked, anonymous vs authenticated
5. **Lifecycle** — app force-quit, backgrounded, returned, mid-screen-transition
6. **Data state** — none, too many, corrupted, stale, fresh vs cached
7. **User mistake / abuse** — wrong order, repeating the same action, intentional misuse
8. **Domain / market specifics** — fill in at /init; covers norms, expectations, regulatory nuances unique to your domain

Question shape:

> "[Network / external dependency] If the user starts entering an OTP and their network drops mid-submit, options:
>
> a. Show 'connection failed', let them tap retry
> b. Auto-retry up to 3 times silently, then show error
> c. Treat as fatal, return them to the previous screen
>
> Which fits the experience you want?"

Move category by category. Skip categories that don't apply (e.g., concurrency rarely matters for a static welcome screen). Do not ask category-spanning questions; keep them tight.

## Step 3 — Write spec v1

After all applicable categories are walked, surface to the CEO a one-paragraph recap of the consensus (happy path + the edge-case behaviors decided) and ask: "Anything to add, change, or revisit before I draft the spec?"

**Wait for user response before continuing.**

Then write `{{spec_dir}}<name>.md` using the template below. This is **plain language only** — no library names, no code identifiers, no file paths.

```markdown
# Feature: <Feature Name>

## Status: DRAFT <YYYY-MM-DD>

## 1. What this feature is for

One paragraph, plain language: who uses it, what value it delivers.

## 2. Happy path

### 2.1 <Scenario name in plain language>

When the user does X, the system does Y, and the screen shows Z.

### 2.2 <Other scenario>

...

## 3. Edge-case behavior

### 3.1 <Situation in plain language>

#### Behavior (CEO sign-off)

- When the user does X
- The system does Y (different from happy path because ...)
- The user sees Z

#### Classification

[Required automated test] or [Smoke test only]

(Test IDs are NOT recorded in the CEO spec. After Stage 6 the resolved IDs land in `{{implementation_dir}}<feature>-implementation.md` § "Scenario → automated test map". The source-of-truth scenario↔test binding is the `// Verifies scenario X.Y` comment at the top of each test file.)

#### Smoke test procedure

**Reproduce:**

1. ...
2. ...

**Pass criteria:**

- ...

**Failure signals:**

- ...

### 3.2 <next scenario>

...

## 4. Who can use this

- Who has access (anonymous, signed-in, specific role)
- What conditions must be met
- When access is blocked

## 5. External dependencies (plain language)

- Which outside services this relies on — described in plain terms
- What happens when an external dependency fails

## 6. Deferred / unresolved

- Decisions intentionally postponed, with the reason

## 7. Out of scope

- What this feature explicitly does not cover

## 8. Decision history

- One line per significant decision: what + why (plain language)

## 9. (Audit mode only — leave empty in new-feature mode) Code vs spec delta
```

**Scenario classification rule:**

- **Required automated test** if the scenario hinges on data correctness, security/permission, business logic, error handling, or user data protection.
- **Smoke test only** if it's UI / animation / device-integration / timing-sensitive and the cost of automating outweighs the value.

Classification is **CEO-confirmed**, not silently assigned by Main Claude.

If the feature has tech detail worth recording (routing, components, state, access-control policies, library decisions, i18n keys), also write `{{implementation_dir}}<name>-implementation.md`. For a simple feature, skip it. Use this shape:

```markdown
# <Feature> — Implementation Notes

**Spec:** {{spec_dir}}<name>.md (canonical, CEO domain)
**This file:** technical detail, manager domain.

## Routing contract

...

## UI surface

...

## Data requirements

...

## External dependencies

<library + version + functions used>

## i18n

<key-by-key table covering all of {{supported_locales}}>

## Boundary contracts

<interfaces with other features>

## File locations

<code-location map per {{feature_folder_pattern}}>
```

Surface both files to the CEO before invoking the auditor.

## Step 4 — Auditor external review

Run the auditor gate on the CEO spec with the spec-tuned adversarial preset (`.harness/scripts/auditor-prompts/adversarial-spec.md`). The preset wraps the focus text below with skeptical-review framing and a spec-shaped attack surface (ambiguous user paths, undefined error states, silent state transitions, multi-user races, undocumented dependencies, PII gaps, lifecycle/offline gaps).

```bash
AUDITOR_GATE_PRESET=adversarial-spec \
AUDITOR_GATE_TARGET_LABEL="<feature> Stage 1 new-feature spec" \
bash .harness/scripts/auditor-gate.sh review <feature> 1 \
  "Review this Stage 1 (new-feature mode) spec. Main Claude and the CEO have walked an edge-case round through {{edge_case_categories}}; the spec reflects their consensus. Your job is the external-model layer. Beyond the preset's spec attack surface, also weigh: subtle scenarios within the categories that were missed (e.g., the spec covers 'network drop mid-OTP' but not 'network drop after OTP accepted, before session lands'); concerns outside the configured categories (domain norms specific to this project per constitution.md Section 2 — Project Identity; business-logic contradictions; cross-feature implications); spec-internal contradictions between sections. Do NOT flag: writing style, section ordering, suggestions to extend scope beyond declared, opinions on technical architecture (the spec is intentionally tech-term-free). Stay in plain-language territory." \
  {{spec_dir}}<feature>.md
```

Read the gate's exit code:

- **Exit 0 (PASS / CONCERNS / WAIVED)** — surface any advisory items to the CEO. For CONCERNS, also surface the logged warning path (`.harness/audits/concerns-*.json`) so the CEO weighs it before commit. For WAIVED, surface the `waiver_reason`. Stage 1 is one round closer to done. Proceed to Step 5.
- **Exit 2 (FAIL)** — surface every blocking item verbatim. Proceed to Step 5.
- **Exit 1 (script error / Universal Core WAIVED rejected / missing waiver_reason / legacy verdict)** — surface stderr, halt.

## Step 5 — CEO answers, spec v2

For each auditor finding, present to the CEO:

> "{{auditor_model}} flagged: [verbatim quote of the finding].
>
> Three resolutions:
> a. Accept and update the spec (here's the proposed change)
> b. Reject and document why (the concern is real but acceptable for our context)
> c. Defer to a future round (mark as known limitation)
>
> Which?"

CEO chooses. Update the spec. Repeat for each finding.

If the CEO disagrees with the auditor on something marked CRITICAL, follow the **CEO escalation pattern** (Constitution § 3):

> "Auditor disagreement on [item]:
>
> - Auditor view: A (reasoning: ...)
> - CEO view: B (reasoning: ...)
>   User-result impact: [yes/no]
>   Cost / maintenance impact: [yes/no]
>   Security / risk trade-off: [yes/no]
>
> CEO decision overrides; documenting the reasoning in `## Decision history`. (Note: per Constitution § 3, CEO cannot override Universal Core items — if the auditor's finding maps to a Section 1 item, reformulation is required.)"

CEO decides; the decision goes into `## Decision history` regardless of which side wins.

## Step 6 — Run another auditor round if needed

Re-run the auditor gate after each spec revision. Stage 1 is **finalized** when:

1. The auditor's most recent round returns no new BLOCKING / STRONG findings, AND
2. CEO declares "OK, proceed."

Round count is unbounded — CEO has stop authority. The gate is the structural defense against premature finalization.

## Step 7 — Hand off to Stage 2

Once finalized:

- Surface to the CEO: "Stage 1 complete. CEO spec at `{{spec_dir}}<feature>.md`; implementation notes at `{{implementation_dir}}<feature>-implementation.md` (or 'not produced — feature simple enough')."
- Recommend: "Run `/spec-finalize <feature>` to mark FINALIZED with a final auditor cross-check."

Do not advance to Stage 2 silently — CEO triggers it.

## Trust contract

- **CEO owns intent.** Tech Lead paraphrases, surfaces options, runs the edge-case sweep, and writes the spec — but every behavior in the spec is CEO-confirmed.
- **Plain language is non-negotiable in the CEO file.** Tech terms (library names, code identifiers, framework jargon) belong in the implementation file or the code.
- **Auditor review is unconditional.** No skipping because "the spec looks fine" or "the feature is small." (Constitution § 1.)
- **Verdict is parsed from the gate's exit code**, not interpreted from prose.
- **CEO escalation has a fixed shape** so auditor disagreements are surfaced uniformly.

## Anti-patterns the skill blocks

- **Tech-term creep into the CEO spec.** Catch on review; rewrite as plain language.
- **Main Claude inferring past CEO intent.** If the CEO didn't say it, it's not in the spec — surface as a question instead.
- **Skipping the edge-case sweep "because the feature is small."** All applicable categories are walked; categories that don't apply produce no questions, but the walk is mandatory.
- **Silent classification of scenarios.** Each scenario's [Required automated test] vs [Smoke test only] tag is CEO-confirmed.
- **Bundling implementation detail into the CEO file.** The implementation file is where it lives.
- **Treating the auditor as advisory at Stage 1.** BLOCKING/STRONG items must be surfaced and resolved (accept / reject-with-reason / defer); ADVISORY items can pass.

## Completion criteria

Stage 1 in new-feature mode is complete when:

- `{{spec_dir}}<feature>.md` exists with every template section present (the CEO spec does NOT carry test IDs — that index lives in the implementation file's "Scenario → automated test map" once Stage 6 lands)
- `{{implementation_dir}}<feature>-implementation.md` exists when the feature warrants it (CEO and Tech Lead agree it does), or is explicitly skipped. If present, it may carry an empty "Scenario → automated test map" stub at this stage; the map fills in at Stage 6.
- The CEO spec is plain language end-to-end (no tech terms, no test file paths)
- Every scenario is classified [Required automated test] or [Smoke test only] with CEO sign-off
- The auditor's most recent round returned no new BLOCKING / STRONG findings
- CEO has declared "OK, proceed"
- The next step is `/spec-finalize <feature>`
