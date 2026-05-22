---
name: audit-spec
description: This skill should be used when starting an audit of an existing feature. Trigger it when the user invokes /audit-spec, says "audit feature X", "verify the auth feature", "check what the [feature] code actually does", or wants to reverse-engineer an existing implementation. It is Stage 1 in audit mode of the dual-mode feature workflow. The CEO walks the same intent rounds as new-feature mode (paraphrase + {{edge_case_categories}} sweep + auditor external review) to produce the *intended* spec, THEN a fresh general-purpose subagent (clean context, MCP access if configured) reads the codebase + live state and produces an as-built reading; Main Claude diffs intent vs as-built and surfaces deltas; the CEO decides each delta. Output is the two-file model (CEO + implementation) plus a Section 9 delta list that becomes Stage 3+ work.
argument-hint: [feature-name]
---

# /audit-spec

Drive Stage 1 of the workflow in **audit mode**: produce a finalized canonical spec for an existing feature, plus a delta list that drives Stage 3+ work to bring the code into alignment.

The output is the same **two-file model** as new-feature mode:

- `{{spec_dir}}<name>.md` — CEO domain. Plain language, no tech terms. Section 9 (Delta) is populated with deltas the CEO chose to act on.
- `{{implementation_dir}}<name>-implementation.md` — manager domain. Tech detail, when the feature warrants it.

Plus a frozen as-built snapshot at `.harness/audits/<name>-as-built-<YYYY-MM-DD>.md` that records what the code did at audit time.

## Why this flow

Audit mode lands on the same finalized two-file spec as new-feature mode, but it adds an extra reconciliation phase between intent and code. Without it, you have two failure modes:

- **Intent-only** (skip code) — spec ships with drift unaddressed; the bug surfaces at Stage 7 smoke test or post-launch.
- **Code-only** (skip intent rounds) — spec inherits whatever drift the code already has; the audit anchors on a stale implementation.

So the flow is **intent first, code second, reconcile third**. CEO intent grounds the spec; fresh-context code analysis surfaces deltas; CEO decides each delta.

Three layers of independence remove implementer-grades-own-work bias from the audit:

1. **Conversation-level** (paraphrase + edge-case sweep) for intent — same as new-feature mode.
2. **Context-level** (fresh subagent reading code + live state) for as-built — the subagent has no prior conversation, no anchoring on the existing canonical spec.
3. **Model-level** (auditor) twice — once on the consensus intent spec, once optionally on the as-built reading.

## Authoritative sources

1. **Root `CLAUDE.md`** — workflow modes, two-file model, lane definitions
2. **`constitution.md`** — Universal Core + project identity, both shape the intended behavior
3. **`{{rule_sources}}`** — any scoped rule docs that constrain this feature
4. **The code surface** — discovered in Step 6, read in Step 7

The intent rounds (Steps 1–5) **must not** read the existing canonical spec or any policy doc that describes the feature's intended behavior. Those represent prior intent, not necessarily the right intent today; we want the CEO to re-state intent freshly.

The as-built subagent (Step 7) **must not** read `{{spec_dir}}<feature>.md` or any other policy doc. It documents reality, not intent.

## Invocation

- Typical: `/audit-spec <feature-name>` (e.g., `/audit-spec auth`)
- `$ARGUMENTS` identifies the feature being audited.

If `$ARGUMENTS` is missing, ask. Do not guess.

## Pre-stage check

Before Step 1:

1. `git status` — clean? If uncommitted changes exist, surface them and ask.
2. Existing `{{spec_dir}}<name>.md` — if it exists, note its date and Status. We do not read it during intent rounds, but we'll diff against it at the end.
3. State recap to user: "Pre-stage clear. Lane: Full workflow (audit). Intent rounds first; then code analysis; then delta reconciliation. Anything to adjust before we start?"

Do not proceed without an explicit go-ahead.

## Steps 1–5 — Intent rounds (same shape as new-feature mode)

Run the new-feature-mode flow exactly as described in `feature-draft` SKILL.md, with one twist: do not read the existing `{{spec_dir}}<feature>.md` even if it exists.

- **Step 1 — CEO happy path + paraphrase.** What does the CEO believe the feature should do? Plain language, no tech terms.
- **Step 2 — Edge-case round.** Walk all applicable categories from `{{edge_case_categories}}`. 3–5 questions per category; CEO decides each behavior.
- **Step 3 — Write spec v1.** Use the same template as new-feature mode. Write to `{{spec_dir}}<feature>.md` with Status: `DRAFT (audit, intent phase) <YYYY-MM-DD>`. Section 9 ("Code vs spec delta") is left empty for now — populated at Step 9.
- **Step 4 — Auditor external review on the intent spec.** Same gate as new-feature mode, with the spec-tuned adversarial preset:

  ```bash
  AUDITOR_GATE_PRESET=adversarial-spec \
  AUDITOR_GATE_TARGET_LABEL="<feature> Stage 1 audit intent spec" \
  bash .harness/scripts/auditor-gate.sh review <feature> 1-audit-intent \
    "Review this Stage 1 (audit-mode, intent phase) spec for the `<feature>` feature. Main Claude and CEO have just walked an edge-case round through {{edge_case_categories}} to capture *intended* behavior; the code itself has not yet been read. Your job is the external-model layer on intent. Beyond the preset's spec attack surface, also weigh: subtle scenarios within the categories the CEO and Main Claude missed; concerns outside the configured categories (domain-specific norms per constitution.md Section 2 — Project Identity; cross-feature implications); spec-internal contradictions. Do NOT flag: anything that requires reading the codebase to evaluate (that's the next phase); writing style; section ordering; suggestions to extend scope. Stay in plain-language territory; the spec is intentionally tech-term-free." \
    {{spec_dir}}<feature>.md
  ```

- **Step 5 — Iterate to consensus.** Same shape as new-feature Step 5: surface auditor findings, CEO chooses accept/reject/defer per item, update spec, re-run the gate. Stage 1 intent phase is finalized when the auditor returns no new BLOCKING/STRONG and the CEO declares "OK on intent — let's read the code."

At this point the spec is the **intended** state. Status line still reads `DRAFT (audit, intent phase) <date>` — not yet finalized.

## Step 6 — Spawn discovery subagent (code surface)

Spawn a fresh `general-purpose` subagent via the Task tool. Give it this prompt:

```
You are doing Stage 1 (audit mode, code-discovery phase) for the `<feature>` feature.
Your context starts fresh. You have no prior conversation about this feature.

DO NOT read any of these:
- {{spec_dir}}<feature>.md
- {{implementation_dir}}<feature>-implementation.md
- any other {{spec_dir}}*.md
- any policy doc from {{rule_sources}} describing this feature

Those represent intent. We want the as-built read to describe reality independently.

Your task: produce a candidate path list of files / folders that constitute the
audit surface for `<feature>`. Discovery rules:

1. ALWAYS include `{{feature_folder_pattern}}<feature>/**` (recursive).

2. CROSS-FEATURE IMPORTS — grep for files outside `{{feature_folder_pattern}}<feature>/`
   that import from this feature's public surface. They use the feature's surface;
   they may belong in the audit.

3. BACKEND FUNCTION NAME MATCHES — if `{{backend_code_paths}}` is configured,
   list backend functions / endpoints whose names match the feature's keywords.
   Justify why each belongs.

4. MIGRATION MATCHES — if `{{migration_dir}}` is configured: migrations whose
   filename or content references the feature's primary tables (use `grep -l`).

5. ENTRY-POINT / ROUTE MATCHES — any router / entry files referencing this feature's screens.

6. RELATED-FEATURE FOLDERS — adjacent feature folders that share concerns by name;
   tag as "related-feature candidate, user may scope in or out."

7. LIVE BACKEND PROBES (if the project has a configured database MCP or equivalent
   read-only access):
   - List tables + columns
   - List deployed functions / endpoints
   - List applied migrations
   - For auth-shaped features: note auth-provider config (rate limits, OTP TTL,
     MFA flags) — these aren't visible in code but matter for reality.

Return a structured path list with one-line rationale per path:

  [Path] — [why included] — [confidence: certain | likely | candidate]

Group by category (feature folder / cross-feature consumers / backend functions
/ migrations / routes / related-feature candidates / live-state notes).

Do not write the as-built yet. Do not read the existing canonical spec. Just
return the candidate surface list.
```

Surface the subagent's path list verbatim to the CEO. Get explicit confirmation:

> "The discovery subagent suggests this surface. Anything to add, remove, or reclassify (especially related-feature candidates)?"

Wait for confirmation. Do not proceed with an unverified path list.

## Step 7 — Spawn as-built subagent (write the as-built)

Spawn a **fresh** `general-purpose` subagent (separate from the discovery one) with the confirmed path list, the discovery subagent's MCP findings, and instructions to write the as-built. Use this prompt:

```
Confirmed audit surface:
- <path 1> — <rationale>
- <path 2> — <rationale>
- ...

Live-state probes already gathered:
- <e.g., "Auth provider sms_otp_exp = 180s, MFA TOTP enroll/verify both false">

Now produce the as-built reading.

Read every file on the confirmed list. Use the configured backend MCP (if any)
to verify live state (column types, deployed function versions, access-control
policies, etc.). Cite file:line for every documented behavior.

Output as a single markdown document using this template:

  # Feature: <feature> (As-built)
  ## Status: AS-BUILT DRAFT <YYYY-MM-DD>
  ## Summary
  ## User stories
    Phrase as "As a <role>, I can <action> because <code path>." Cite file:line.
  ## Scope
    ### In scope ### Out of scope (boundaries)
  ## UI surface
  ## Data requirements
    Tables, RPCs, functions exercised. Cite migration file:line and
    function file:line. Include client-side caches. MCP confirmations noted.
  ## Access and permissions
    Auth state requirements, access-control policies, function JWT verification,
    service-role usage. Cite file:line.
  ## External dependencies
  ## Live config
    Anything from MCP probes that affects behavior but isn't in the repo.
  ## i18n
    String keys present in code; spot-check coverage across {{supported_locales}}.
  ## Error and empty states
  ## Rate limiting / abuse defenses
  ## Behaviors not fitting the template (anomalies / drift / extras)
    Anything the code does that doesn't fit cleanly above. Be explicit:
    "This exists at file:line; CEO may want to verify whether it should remain."
  ## Implementation map
    File-by-file: what each file contributes. One short sentence per file.

For every documented behavior, cite file:line. If something is ambiguous from
reading the code (a flag, a magic constant, a branch whose intent isn't clear),
mark explicitly:

  [AMBIGUOUS — code shows X at file:line; intent unclear from code alone]

If a section doesn't apply, mark `[NOT APPLICABLE]` with one sentence why.

Do NOT infer intent. If the code does Z, document Z exists; do not assume Z is
"supposed to" do anything beyond what's coded. Do not silently fill in what
you'd expect to find.

Write the file directly to `.harness/audits/<feature>-as-built-<YYYY-MM-DD>.md`.
Use today's date.

Return only a confirmation message ("As-built written to <path>") plus a
brief list of any [AMBIGUOUS] or [NOT APPLICABLE] markers placed.
```

When the subagent returns, verify the file was written and is non-empty.

## Step 8 — (Optional) Auditor review on the as-built

The load-bearing auditor pass is on the intent spec at Step 4. An additional pass on the as-built is recommended for large or complex features — it catches incorrect citations, missing user-facing behaviors, and code-vs-doc contradictions. CEO can opt in/out.

If running, use the code-shaped adversarial preset:

```bash
AUDITOR_GATE_PRESET=adversarial \
AUDITOR_GATE_TARGET_LABEL="<feature> Stage 1 audit as-built reading" \
bash .harness/scripts/auditor-gate.sh review <feature> 1-audit-asbuilt \
  "Review this as-built reading for the `<feature>` feature. The author was a fresh-context Main Claude subagent with backend MCP access; you have neither prior conversation nor MCP. Your job is to catch what same-model authorship may miss. Beyond the preset's attack surface, weigh: incorrect file:line citations; missing user-facing behaviors visible in the cited code but undocumented; unfounded assumptions ('this is gated on X' — is the gate actually enforced where claimed?); contradictions between the cited code and the as-built description. Do NOT flag: project-convention choices per {{anti_flag_rules}}, formatting, naming, or suggestions for additional sections beyond the template. Stay scoped to whether the as-built accurately describes what the cited code does." \
  ".harness/audits/<feature>-as-built-<date>.md"
```

Surface findings to the CEO, who decides whether the as-built needs corrections before Step 9.

## Step 9 — Diff: intent vs as-built

Now Main Claude reads BOTH:

- `{{spec_dir}}<feature>.md` (the intent spec, Status: DRAFT (audit, intent phase))
- `.harness/audits/<feature>-as-built-<date>.md` (the as-built)

Surface the diff to the CEO using this format:

```
Analysis complete. Comparing the intended spec with what the code does:

✅ Matching scenarios:
- 2.1, 2.2, 2.3
- 3.1, 3.2, 3.4

⚠️ Differences found (CEO decision needed):

Δ 1: [Scenario X — name in plain language]
  Intent: A
  Code:   B
  Which side wins?

Δ 2: [Scenario Y]
  Intent: A
  Code:   missing entirely
  Implement, or revise intent?

🆕 In code, not in intent:
- Code does X at file:line — not described in the intended spec
- Add to spec? Remove from code? Out of scope?
```

For each delta, ask the CEO to choose one of four resolutions:

- **a. Keep code, add to intent spec** — code is right, intent missed it
- **b. Keep intent, modify code** — intent is right, code is wrong (Stage 3+ work)
- **c. Both change** — neither side is right, define a new behavior (Stage 3+ work)
- **d. Out of scope** — defer; record as known limitation

## Step 10 — Integrate decisions into spec v2

For each delta:

- (a) — append the missing scenario to the appropriate section, classify [Required automated test] / [Smoke test only], add CEO-confirmed smoke procedure where applicable.
- (b), (c) — append to Section 9 (Code vs spec delta) with action item ("Stage 3+ work: scenario X.Y needs implementation change").
- (d) — append to Section 6 (Deferred / unresolved) with reason.

Update Status to `FINALIZED <YYYY-MM-DD>` once the integration is done.

## Step 11 — Optional: implementation file

If the feature warrants tech detail (routing, components, access-control policies, library decisions, i18n keys), produce `{{implementation_dir}}<feature>-implementation.md` based on the as-built reading. Same shape as new-feature mode. Skip for simple features.

## Step 12 — Auditor final pass on integrated spec

After deltas are resolved, run a final auditor pass on the integrated CEO spec with the spec-tuned adversarial preset:

```bash
AUDITOR_GATE_PRESET=adversarial-spec \
AUDITOR_GATE_TARGET_LABEL="<feature> Stage 1 audit finalized integrated spec" \
bash .harness/scripts/auditor-gate.sh review <feature> 1-audit-final \
  "Review this finalized audit-mode spec. The intent phase has been auditor-reviewed already; this final pass is on the integrated spec after delta reconciliation with the as-built code reading. Beyond the preset's spec attack surface, focus on: contradictions introduced by the integration (e.g., a code-derived scenario added in section 3.X conflicts with happy path 2.Y); Section 9 deltas that should have been integrated into the main spec instead of left as a delta; missing scenarios surfaced by the as-built that didn't make it into either the spec or Section 9. Do NOT flag: writing style; section ordering; suggestions to extend scope; opinions on technical architecture (the spec is plain-language). Stay scoped to integration consistency." \
  {{spec_dir}}<feature>.md
```

Iterate as needed. Stage 1 audit is finalized when the auditor returns no new BLOCKING/STRONG and the CEO declares "OK, proceed."

## Step 13 — Hand off

Surface to the CEO:

- **CEO spec:** `{{spec_dir}}<feature>.md` (FINALIZED, Section 9 lists deltas to act on)
- **Implementation notes:** `{{implementation_dir}}<feature>-implementation.md` (if produced)
- **Frozen as-built snapshot:** `.harness/audits/<feature>-as-built-<date>.md` (record of code state at audit time; not maintained going forward)
- **Recommended next step:** "If Section 9 has any (b) or (c) deltas, run `/spec-finalize <feature>` then proceed to `/db-schema` (if schema affected AND `backend_db_type` is configured) or `/execution-plan` (if code-only) to bring the code into alignment. If Section 9 is empty, the audit served as a documentation pass and you can stop here."

## Trust contract

- **Intent rounds run before code reading.** Reverse the order and the CEO anchors on existing implementation drift.
- **The intent-phase subagent does not read existing specs.** Anchoring on a stale intent spec defeats the audit.
- **The as-built subagent does not read existing specs.** Anchoring on intent defeats the as-built reading.
- **Auditor on intent is unconditional** (Step 4). Auditor on as-built is optional but recommended for complex features.
- **CEO decides each delta.** Tech Lead presents options and reasoning; CEO chooses (a/b/c/d).
- **Section 9 is the bridge to Stage 3+ work.** A non-empty Section 9 means the audit produced action items.

## Anti-patterns the skill blocks

- **Reading the existing spec during intent rounds.** Intent rounds re-state intent; no anchoring.
- **Letting the as-built subagent see the canonical spec.** Same reason.
- **Skipping the auditor pass on the intent spec.** That pass is the cross-model audit invariant for Stage 1 (Constitution § 1).
- **Silently choosing a delta resolution.** Each (a/b/c/d) is CEO-confirmed.
- **Treating the as-built as the final spec.** It's a frozen snapshot; the CEO spec is canonical.
- **Cross-feature folder auto-inclusion.** Surface as a candidate; CEO decides scope.

## Completion criteria

Stage 1 in audit mode is complete when:

- `{{spec_dir}}<feature>.md` exists with `## Status: FINALIZED <YYYY-MM-DD>`, every section populated. The CEO spec does NOT carry test IDs — that index lives in the implementation file's "Scenario → automated test map" section. Audit-delta ledgers also live in the implementation file, never in the CEO spec.
- `{{implementation_dir}}<feature>-implementation.md` exists when warranted, or is explicitly skipped. When present, it carries (a) the audit-delta ledger that this skill produces and (b) the "Scenario → automated test map" section (may be empty / TBD if the feature has no automated tests yet; fills in at Stage 6).
- `.harness/audits/<feature>-as-built-<date>.md` exists as a frozen reference
- Every delta has an explicit CEO decision (a/b/c/d) recorded
- The auditor's final pass returned no new BLOCKING/STRONG findings
- CEO has declared "OK, proceed"
- The next step is `/spec-finalize <feature>` (formality), then `/db-schema` or `/execution-plan` if Section 9 has actionable deltas
