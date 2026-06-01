# Two-file feature spec model — detail

> **Reference for `CLAUDE.md § Two-file feature spec model`.** Loaded on demand when writing or auditing specs. The compact rule in CLAUDE.md is the load-bearing version; this file is the full ban-list + EARS reference + migration guidance.

## The two files

- `{{spec_dir}}<name>.md` — **CEO domain.** Plain language, no tech terms. Happy path, edge-case behaviors, scenario classification (`[Required automated test]` / `[Smoke test only]`), smoke-test procedures. CEO signs off; CEO is the only one who reads this end-to-end at smoke-test time. **Categorical list of tech terms that must NEVER appear here** (translate to behavior instead): framework / library names, hook / function names, store / state names, router / navigation APIs, RPC / function / table / column names, payload shapes (JSON field lists), file paths, migration timestamps, SDK error type names, HTTP status codes as primary verbs, query key constants, **test file paths and test descriptions**. **The shape test:** if a non-engineer reading the sentence aloud would stumble, the sentence belongs in the implementation file. Translate to outcome ("nothing about the user reaches the device before the gate is passed"), not mechanism ("the RPC returns only `{state, reason, dormancy_required}`").

- `{{implementation_dir}}<name>-implementation.md` — **manager domain (optional).** Routing tables, component map, state keys, access-control policies, library + version notes, i18n key index, boundary contracts, **scenario → automated test map**. Tech Lead and reviewers read this; CEO doesn't have to. Simple features may skip this file entirely; complex features typically have a rich one. **All audit-delta ledgers (Stage 1 audit findings, code-vs-spec reconciliation) belong in this file — never in `<name>.md`.** By definition they track how code matches spec, which is manager-domain content. The CEO spec records intent and behavior; the implementation file records how the code currently honors that intent.

## Manager-file functional requirements: EARS notation

Functional requirements in `{{implementation_dir}}<name>-implementation.md` use **EARS notation** (Easy Approach to Requirements Syntax). EARS is structured natural language — each requirement names the trigger and the expected behavior in a testable format.

**Primary pattern** (event-driven — covers ~80% of cases):

```
WHEN [trigger/condition] THE SYSTEM SHALL [expected behavior]
```

Examples:
- `WHEN the user submits the OTP form with a valid code, THE SYSTEM SHALL navigate to home screen within 500ms.`
- `WHEN the upload request returns 401, THE SYSTEM SHALL clear local session and redirect to login.`
- `WHEN a user cancels the upload mid-stream, THE SYSTEM SHALL delete the partial S3 object within 60s.`

**Other EARS variants** (use when the primary pattern doesn't fit):

| Variant | Pattern | When to use |
|---|---|---|
| Ubiquitous | `THE SYSTEM SHALL [behavior]` | Always-true invariant (no trigger) |
| Event-driven (primary) | `WHEN [event] THE SYSTEM SHALL [response]` | Most functional requirements |
| Unwanted behavior | `IF [undesired event] THEN THE SYSTEM SHALL [recovery]` | Error handling, anomaly recovery |
| State-driven | `WHILE [state] THE SYSTEM SHALL [behavior]` | Constraints that hold during a state |
| Optional | `WHERE [feature included] THE SYSTEM SHALL [behavior]` | Behavior gated by a feature flag |

**Why EARS for manager domain:**
- Each `SHALL` clause maps directly to a test assertion. Stage 6 (`/test-fix`) can generate tests from EARS requirements with minimal interpretation.
- All-caps keywords (`WHEN`, `THE SYSTEM SHALL`) scan visually as load-bearing — distinguishes functional requirements from architectural notes / library version notes / scenario→test mappings (which stay as prose).
- Industry standard (AWS Kiro default, NASA / aerospace adoption).

**Where EARS does NOT apply:**
- `{{spec_dir}}<name>.md` (CEO domain). The CEO file stays plain prose — no `SHALL`, no all-caps keywords. The 16-category tech-term ban in the CEO file (see § above) implicitly excludes EARS keywords; this section makes it explicit: **CEO file = no EARS.**
- Manager-file sections OTHER than functional requirements: routing tables, component maps, store keys, RLS policies, library + version notes, i18n key index, boundary contracts, scenario→test maps — these stay as their natural format (tables, lists, prose). EARS is for the **Functional requirements** section only.

**Migration note:** existing manager files with prose-style functional requirements don't need to be retroactively rewritten. New manager files written from this point on should use EARS for the Functional requirements section. Run `/audit-spec <name>` to surface drift — including manager-file requirements that could be promoted to EARS.

The CEO spec is the canonical source of truth. The implementation file is a working notebook.
