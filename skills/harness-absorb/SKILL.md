---
name: harness-absorb
description: |
  Read an existing project's prior AI-harness (old CLAUDE.md / .cursor rules / copilot-instructions / a foreign constitution / BMAD / SpecKit, etc.), understand it, and MERGE its content INTO CCC-MAGI — faithfully preserving the user's existing rules and identity ("做加法 / absorb-and-merge"), instead of discarding it. Produces a confirmable "understanding card + diff" and stages the result for /init.

  Trigger when:
  - The standalone bootstrap (or CCC's bundled Step 1 driver) Step C option [1] "take over + absorb-and-merge" is chosen
  - The user says "把我现有的规则并进来" / "吸收老配置" / "absorb my existing harness" / "merge my old rules" / "keep my old CLAUDE.md rules" / "기존 설정 흡수"
  - /init is run on a brownfield project that still has a prior harness and the user wants its content carried forward

  This skill NEVER overrides constitution.md Section 1 (Universal Core). It only READS the old harness and STAGES values; nothing is written to constitution.md / AGENTS.md until the user confirms the diff and /init renders.
argument-hint: [--files "<path> <path> ...">] [--ccc-driven]
---

# /harness-absorb

Carry an existing project's harness FORWARD into CCC-MAGI, rather than archiving-and-forgetting it. The contract: **read → extract → classify → map → present a confirmable diff → stage to `.harness/state/_absorb-draft.json`** for `/init` to consume. The user's original files are still archived to `old_version_harness/` by the bootstrap *after* a successful absorb (the archive safety net is never removed).

> *Constitutional basis: this skill helps fill constitution.md Section 2 (identity) + Section 3 (red lines) and AGENTS.md anti-flag rules from the user's PRIOR harness. It is bounded by `constitution.md § Section 1` — Universal Core items can never be overridden by absorbed content.*

## Language Awareness

Instructions here are English (stable + token-efficient). Talk to the user in their OS locale (see `CLAUDE.md § Language Awareness`; detect via `locale` / `$LANG`; default English). **Absorbed user content keeps its original language** — do NOT translate the user's own rules/identity statements when carrying them forward; they are user content, not harness text.

## Input

A list of confirmed harness files/dirs. Normally passed by the bootstrap driver (the set the user confirmed in Step B). If invoked directly without `--files`, re-derive the candidate set the same way `standalone-bootstrap.md § Step A` does, then confirm with the user before reading.

---

## Step 1 — Read (with protection)

Read each confirmed file/dir. Guardrails so a huge or junk harness can't blow up context or pollute the constitution:

- **Per-file cap**: if a file exceeds ~400 lines, read the first 400 + last 40 lines and mark it `[truncated]`. Note the truncation in provenance.
- **Skip** binary files, lockfiles, and anything > ~200 KB. Note them as `[skipped: too large / binary]`.
- **Directories** (e.g., `.cursor/rules/`, `agents/`, `rules/`): read each `.md` / `.mdc` one level deep.
- **De-duplicate**: if the same rule appears in multiple sources, absorb once and list all sources.

Never echo whole files back to the user — you are extracting, not transcribing.

## Step 2 — Extract + classify

Pull out only **meaningful, durable** content (ignore boilerplate, tool-install steps, and generic LLM etiquette). Classify each extracted item into a CCC-MAGI destination:

| Old content type | CCC-MAGI destination |
|---|---|
| Identity statements (who we serve, what we deliberately don't do, compliance / performance floors) | constitution **Section 2** identity slots — `project_audience`, `project_non_goals`, `project_compliance`, `project_performance_floor`, `project_identity_other` |
| Project-wide ABSOLUTE red lines (violating it ⇒ "not this project anymore") | constitution **Section 3** → `project_red_lines` |
| "Never / always / forbidden"-style coding constraints | **AGENTS.md** → `anti_flag_rules` |
| Domain / area-specific coding rules (Cursor rules, style sections of copilot-instructions) | `rule_sources` index + land in the matching rule file |
| Project facts (tech stack, repo structure, test command, folders) | L1 slots — `tech_stack`, `repo_structure`, `test_framework`, `test_runner_command`, `feature_folder_pattern`, `client_code_paths`, `backend_code_paths`, `backend_db_type` … — **merge with /init's existing auto-detect** |
| Foreign workflow config (BMAD / SpecKit stage definitions, custom pipelines) | **Informational only** — CCC-MAGI has its own workflow; do NOT import the pipeline. Extract only project facts from it. |

**Section 3 bar is high** (per `constitution.md § Section 3`): promote a rule to red line only if it is project-wide AND absolute AND identity-changing. When unsure, route to `anti_flag_rules` or `rule_sources`, not Section 3.

Summarize each item to a **short line** (one sentence) — never paste paragraphs into the constitution.

## Step 3 — Conflict resolution + Universal Core guardrail

- **Absorbed vs auto-detected** (e.g., old harness says stack is "Vue" but manifests say "React"): keep BOTH in the diff, present side by side, let the user pick. Default-highlight the auto-detected (ground-truth-from-code) value.
- **Universal Core guardrail (HARD)**: an absorbed rule may **never** weaken `constitution.md § Section 1`. If the old harness says things like "skip tests", "no code review needed", "AI can self-approve", "don't bother with the audit", "push without smoke test" — **do NOT absorb it**. List it in a dedicated `⚠️ conflicts with Universal Core — ignored` group with a one-line reason. These items are reported, never staged.

## Step 4 — Present the understanding card + confirmable diff

Show ONE structured card, grouped by destination, in the user's locale. Every line is editable: the user can `accept` / `rewrite` / `drop` each. Use plain language (CEO-readable, no tech-term dumps).

```
为了把你现有的配置完整带过来,我读了你的旧 harness,下面是我准备并入 CCC-MAGI 的内容
—— 你逐条看一下,可以说「第N条改成…」「第N条删掉」「漏了X」:

🧭 项目身份(→ 宪法 Section 2)
   1. 服务对象:<…>                              [来源: CLAUDE.md.pre-ccc-magi]
   2. 明确不做:<…>                              [来源: copilot-instructions.md]

🚩 项目红线(→ 宪法 Section 3,最高优先级、不可破)
   3. <…>                                        [来源: 旧 constitution]

🛑 Anti-flag 规则(→ AGENTS.md,审计时不报这些)
   4. <…>                                        [来源: .cursor/rules/style.mdc]

📚 领域规则(→ rule_sources)
   5. <…>                                        [来源: .cursor/rules/api.mdc]

🧱 项目事实(与我从代码里自动探测的结果合并)
   6. 技术栈:React(✅ 代码探测) ⟷ Vue(旧 harness)— 我按代码选了 React,对吗?

⚠️ 与 CCC 不可破底线冲突 —— 已忽略(不会并入)
   • "跳过测试即可直接提交" — 与 Universal Core §1.4 人工冒烟冲突
   • "AI 可自行通过审查"   — 与 Universal Core §1.1 强制跨模型审计冲突

这些对吗?逐条说改动,或说「都对/继续」。
```

- For fixed-choice confirmations (conflict picks, accept-all), use the `AskUserQuestion` tool (per `skills/init/SKILL.md` presentation rule: fixed options → AskUserQuestion; free text → plain Q&A).
- Loop until the user says "都对 / continue / done". Apply every edit before staging.

## Step 5 — Stage to `_absorb-draft.json`

After confirmation, write the staged result to `.harness/state/_absorb-draft.json` (atomic: write tmp + rename). `/init` consumes it (pre-fills slots, skips already-confirmed questions) and **deletes it** afterward. This file is gitignored (transient, like `_active.json`).

```json
{
  "schema_version": 1,
  "absorbed_at": "<ISO-8601>",
  "absorbed_from": ["CLAUDE.md.pre-ccc-magi", ".cursor/rules/", "copilot-instructions.md"],
  "slots": {
    "project_audience": "<confirmed value or omit>",
    "project_non_goals": ["..."],
    "tech_stack": "<confirmed>",
    "...": "only slots the user confirmed; omit the rest"
  },
  "section3_red_lines": ["<confirmed red line>", "..."],
  "anti_flag_rules": ["<confirmed rule>", "..."],
  "rule_sources": [{"path": "<rule file>", "summary": "<one line>"}],
  "skipped_conflicts": [
    {"text": "<offending rule>", "reason": "conflicts with Universal Core §1.4"}
  ]
}
```

Only stage what the user **confirmed**. Omit anything dropped. Conflicts go in `skipped_conflicts` (for the `install.json` provenance record), never in `slots` / `section3_red_lines` / `anti_flag_rules`.

## Idempotency

If `install.json` already exists and its `absorption.absorbed_from` already lists a file, do NOT re-absorb it — show "已吸收过 (already absorbed)" for that source and skip. This lets a re-run (e.g., the user deleted `install.json` to reconfigure) avoid duplicating content.

## Output / handoff

When `_absorb-draft.json` is written and confirmed, return control to the caller:
- **From bootstrap option [1]**: tell the bootstrap to archive the originals to `old_version_harness/`, then proceed to Step E (env-check) / Step F (`/init`). `/init` will read `_absorb-draft.json`.
- **From direct `/init` invocation**: `/init` continues at its Step 1.5 understanding card with the staged values already merged.

## Rules you MUST follow

- **Never write to constitution.md / AGENTS.md directly.** This skill only READS and STAGES; `/init` renders.
- **Never absorb anything that weakens Universal Core.** Report it under conflicts; never stage it.
- **Never delete the user's original files.** Archiving is the bootstrap's job (option 1 = move to `old_version_harness/`), and only AFTER a successful absorb+confirm.
- **Never translate absorbed user content.** Preserve original wording + language.
- **Never paste whole files** into the card or the constitution — extract to short lines.
- **Never advance past the diff without explicit user confirmation.**
