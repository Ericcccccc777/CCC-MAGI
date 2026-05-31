---
name: offload
description: |
  Spawn a fresh-context subagent to complete a discrete sub-task and return a 1-2K summary. Use when budget pressure (~75%) makes finishing the current sub-task in the main thread risky, but you don't need full session handoff yet.

  Trigger when:
  - Budget-monitor 75% menu surfaces "[2] /offload <task>"
  - User says "把这个交给 subagent / 找个新 context 做 X / spawn agent for X / offload X"
  - You (AI) recognize the main thread context is full but a discrete next sub-task has clean boundaries
allowed-tools: Task, Read, Bash(git status:*)
argument-hint: <task description>
---

# /offload

Subagent isolation as a budget-pressure release valve. Instead of forcing a full session handoff at 75%, you spawn an isolated-context subagent that does a discrete sub-task and returns just its summary. The main thread context grows by ~1-2K tokens instead of by the sub-task's full execution trace.

## When this is the right answer

- Context is ~70-85% and a clean sub-task is next (refactor a file, write a set of tests, search for a pattern across the codebase, generate a script)
- The sub-task has **clear inputs and clear outputs** — easily described in ≤300 chars
- You don't need ongoing dialogue with the user inside the sub-task

## When this is NOT the right answer

- Context >95% → use `/handoff` instead (offload only delays the inevitable)
- Sub-task requires user judgment partway through → can't be isolated
- Sub-task is "improve the whole codebase" → too vague; subagent will burn budget without a clear stop condition
- The work would only cost ~1K tokens anyway → just do it inline

## How it works

You invoke the Task tool with a carefully-scoped prompt. The subagent runs in its own 200K context window, returns a single message back. From the main thread's perspective, the cost is:
- ~500 tokens of subagent prompt
- ~500-2000 tokens of subagent return summary

Total main-thread overhead: typically 1-3K tokens vs. the 10-30K the task would have cost inline.

## Step 1 — Scope the sub-task

Before invoking, you (the AI) write a tight sub-task prompt:

```
Task: <one-sentence description>

Inputs:
- <relevant file paths>
- <constraints>

Outputs:
- <what the subagent should return>
- <format expectations>

Constraints:
- Stay focused on this sub-task only
- Don't open Explore agents recursively
- Report in ≤500 words
```

Ask the user to confirm the scope before invoking (in CEO's locale):

```
─── Offload Plan ─────────────────────────────────

  Sub-task: <description>
  
  Inputs:
    - <list>
  
  Subagent will return:
    - <list>
  
  Expected main-thread overhead: ~1-3K tokens
  Subagent type: general-purpose

Confirm?
  [1] Spawn subagent
  [2] Edit scope
  [3] Cancel (do task inline instead)
```

## Step 2 — Invoke

On `[1]`:

Use the Task tool with:
- `subagent_type: "general-purpose"` (default) OR a specific type if the project has one matching the sub-task (e.g., `test-fixer` for test work, `backend-reviewer` for backend audits)
- A self-contained `prompt` that gives the subagent enough context — it CANNOT see your conversation history
- `description` short summary (3-5 words)

CRITICAL: the prompt must be self-contained. The subagent has no access to:
- Conversation history
- TodoWrite state
- Open files in your main session

So bake in: file paths to read, the specific objective, the success criteria, and any project conventions the subagent needs to know.

## Step 3 — Report back to CEO

Once the subagent returns, summarize in CEO's locale:

```
✓ Offload complete

  Sub-task: <description>
  Subagent verdict: <PASS / CONCERNS / FAIL>
  
  Summary:
    <subagent's return summary, paraphrased to ≤200 chars>
  
  Files modified by subagent:
    <list, or "none">
  
  Main thread overhead: ~<N>K tokens
  
  Next: continue with <next planned action>
```

## Trust contract

- This skill spawns ONE subagent. Multiple offloads in a single turn defeat the purpose.
- The subagent runs without user oversight — only invoke when the scope is clear-cut and the risk is bounded.
- Subagent failures (subagent returns "couldn't do X") are surfaced to CEO; you don't silently retry.

## When you should auto-invoke vs. ask the CEO

- **Auto-invoke** if the user explicitly said `/offload <task>` (clear intent)
- **Ask first** if budget-monitor 75% menu fired and you're proposing offload — show the Step 1 scope plan
- **Don't auto-invoke** mid-task without budget pressure — that's just using a subagent for no reason

## Completion criteria

- Subagent invoked, returned a result, user has seen the Step 3 summary, OR
- Subagent failed or was cancelled at Step 1; control returned to main thread; alternative plan stated
