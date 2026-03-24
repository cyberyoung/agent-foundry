---
name: wf-bugfix
description: Use when fixing a bug — any size, any number of files. Enforces the failing-test-first discipline, prevents skipping steps. Triggers include bug reports, runtime errors, incorrect behavior, UI display issues, or any task where existing functionality is broken.
---

# Bug Fix Workflow

## Overview

Enforce disciplined bug fixing: failing test → minimal fix → prevention assessment. **No code fix without a failing test first.**

## When to Use

- Any bug report or broken behavior
- Runtime errors, UI display issues, incorrect data
- Regression from a recent change
- Single-file or multi-file fixes alike

**If multi-file:** also load `wf-branch-workflow` for branch + plan discipline. This skill handles the fix process within whatever branch workflow you're using.

## The Flow

```
Reproduce ──gate──▶ Failing Test ──gate──▶ Fix ──gate──▶ Prevent ──▶ Done
```

## Phase 1: Reproduce

1. Understand the bug — read the report, screenshot, or error message
2. Identify the affected code — find the component/function/module
3. Describe the root cause in one sentence before proceeding

**Gate: Can you explain WHY it's broken? If not, keep investigating.**

## Phase 2: Failing Test

Write a test that:
- Reproduces the exact bug scenario
- **Fails** with the current code
- Will **pass** once the fix is applied

Run the test and confirm it fails:

```bash
pnpm vitest run <test-file>
```

### If the failing test is hard to write

Sometimes a direct failing test is impractical (component not exported, requires full modal rendering, complex async timing, etc.). In this case:

1. **Stop and explain to the user** — describe why a failing test is hard, what the obstacle is
2. **Propose alternatives** — regression test for the fix logic, integration test at a higher level, or extracting the component for testability
3. **Wait for user decision** — the user chooses: adjust approach, skip test for this case, or find another way

**Never silently skip the test and jump to fixing.**

## Phase 3: Fix

1. Implement the minimal fix — change only what's needed to make the failing test pass
2. Run the test again and confirm it passes:

```bash
pnpm vitest run <test-file>
```

3. Do NOT add features, refactor surrounding code, or update rules at this stage

**Gate: The previously failing test must now pass. If it doesn't, keep fixing.**

## Phase 4: Prevention Assessment

Evaluate whether the bug pattern needs systemic prevention:

| Question | If yes |
|----------|--------|
| Could a lint rule or CI check catch this? | Propose adding it |
| Is this a common pattern others might repeat? | Propose a rule in AGENTS.md (anti-pattern or coding convention) |
| Does an existing rule already cover this? | Document which rule — no new rule needed |
| Is this a one-off mistake? | No new rule needed — the test is sufficient prevention |

**Document your conclusion** — even if the answer is "no new rule needed, existing coverage is sufficient."

**Important: Only update rules/conventions AFTER the fix is verified by tests. Never update rules based on an unverified fix.**

## Red Flags — STOP Immediately

| Thought | Reality |
|---------|---------|
| "I know the fix, let me just do it quickly" | Failing test first. No exceptions. |
| "The test is hard to write, I'll skip it" | Explain to user and get approval. Never skip silently. |
| "Let me fix first, then write a regression test" | That's backwards. Test proves the bug exists before you fix it. |
| "I'll also clean up the surrounding code" | Minimal fix only. Refactoring is a separate task. |
| "I should add a rule to prevent this" | Only after the fix is verified. Rules based on unverified fixes are premature. |
| "The fix works in my head, no need to run the test" | Run the test. Always. |
