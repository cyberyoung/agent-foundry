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

## The Flow

```
Branch ──▶ Reproduce ──gate──▶ Plan Review ──gate──▶ Failing Test ──gate──▶ Fix ──gate──▶ Prevent ──▶ Done
```

## Phase 0: Branch

Never fix directly on main — no exceptions, no matter how small.

1. Check current state:

```bash
git branch --show-current && git status --short
```

2. Decide:
   - **On a `fix/` branch** → use it as-is (multiple bugs on one branch is fine)
   - **On main** → create a fix branch: `git checkout -b fix/<bug-name>`
   - **On any other branch** → switch to main first, then create a fix branch: `git checkout main && git checkout -b fix/<bug-name>`

**Gate: You must NOT be on main before any code changes.**

## Phase 0.5: PRD Check

Check if `docs/prds/` has a PRD document for this bug. If not, ask the user to write one first. The PRD is the user's description of the problem — do not write it yourself.

## Phase 1: Reproduce

1. Understand the bug — read the PRD and any additional report, screenshot, or error message
2. Identify the affected code — find the component/function/module
3. Describe the root cause in one sentence before proceeding

**Gate: Can you explain WHY it's broken? If not, keep investigating.**

## Phase 1.5: Plan Review (mandatory)

Before writing any code or tests:

Derive `{name}` from the PRD filename (strip extension), or from the bug name if no PRD exists.

**Provider dispatch (design phase only):**
1. Check if a PRD exists and has a "Workflow Providers" section → use it for `design` phase
2. Otherwise read AGENTS.md "Workflow Providers" table for `design` phase
3. Neither exists → manual

**Provider invocation instructions:**
- Output to `docs/designs/{name}.md`
- Link to PRD in `docs/prds/` if exists

**If provider is a skill name:** Invoke that skill with above instructions.
**If manual:** You are the provider — write the design doc yourself.

**Post-completion verification:**
- File `docs/designs/{name}.md` exists
- Contains: root cause (what's broken and why)
- Contains: fix approach (which files, which lines, what the change looks like)
- Contains: test plan (what tests to write, what they assert, which files)
- Contains: execution order (step-by-step sequence including regression checks)

**Then:** Update `docs/README.md` artifact index. **Present plan to user. Wait for explicit approval.**

**Gate: The user must explicitly approve the plan before you proceed. Do NOT start Phase 2 until the user confirms.** If the user requests changes to the plan, update it and wait for approval again.

This gate exists because:
- Fixing the wrong root cause wastes everyone's time
- The user may have context you don't (e.g., which compType actually triggers the bug)
- Reviewing a plan is cheap; reverting an incorrect fix is expensive

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
| "I know the fix, let me just do it quickly" | Plan review first, then failing test. No exceptions. |
| "The plan is obvious, no need to confirm" | Present it anyway. The user may have context you lack. |
| "The test is hard to write, I'll skip it" | Explain to user and get approval. Never skip silently. |
| "Let me fix first, then write a regression test" | That's backwards. Test proves the bug exists before you fix it. |
| "I'll also clean up the surrounding code" | Minimal fix only. Refactoring is a separate task. |
| "I should add a rule to prevent this" | Only after the fix is verified. Rules based on unverified fixes are premature. |
| "The fix works in my head, no need to run the test" | Run the test. Always. |
| "It's a one-liner, I'll fix it on main" | Not on main. Switch to or create a branch first. |
