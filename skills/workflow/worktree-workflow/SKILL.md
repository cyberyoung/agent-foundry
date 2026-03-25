---
name: wf-worktree-workflow
description: Use when about to create a git worktree for feature work, before running git worktree add. Enforces plan-first workflow with mandatory gates. Triggers include multi-file changes, feature branches, worktree setup, or any task requiring a design doc or plan.
---

# Worktree Workflow

## Overview

Enforce plan-first → gate → move → worktree isolation for multi-file feature work. All planning happens on main FIRST, then artifacts physically move to the worktree.

**Core principle:** No `git worktree add` without a reviewed plan on main.

## When to Use

- Multi-file feature needing a plan or design doc
- About to run `git worktree add`
- Task says "use worktree" or "isolated development"

**Do NOT use for:** Single-file fixes, typo corrections, config changes.

## The Flow

```
Plan (main) ──gate──▶ Start (main→wt) ──gate──▶ Build (wt) ──▶ Ship (wt)
```

## Pre-flight Checklist

**BLOCKING — complete every item in order. No skipping.**

### Phase 0: Git State Check (MANDATORY FIRST STEP)

Run this BEFORE anything else — even before exploring the codebase:

```bash
git branch --show-current && git status --short && git worktree list
```

**Do NOT assume you know the current branch or worktree.** Other sessions or the user may have switched branches since your last turn. Verify, then proceed.

### Phase 0.9: Interface Dependency Verification (MANDATORY before Plan)

**If the task involves ANY API calls — STOP here and verify BEFORE creating design/plan docs.**

For every API path mentioned in user requirements:

1. Mark as `[CONFIRMED]` or `[PENDING]`
2. For each `[PENDING]`:
   - Search project codebase for existing calls
   - Check if user provided documentation
   - If NOT found → **STOP IMMEDIATELY**, ask user for documentation
3. **Decision point**:
   - ALL `[CONFIRMED]` → proceed to Phase 1
   - ANY `[PENDING]` → **DO NOT create design/plan**, ask user first

**Hard rules:**

- ❌ Do NOT create design documents based on assumed interfaces
- ❌ Do NOT guess request/response formats from similar endpoints
- ✅ Ask user for every missing interface document
- ✅ Only proceed when ALL interfaces are verified

### Phase 1: Plan on MAIN

Read project AGENTS.md `GIT WORKFLOW` section for project-specific conventions (naming, plan template path, `.sisyphus/` structure).

1. Create design doc in **main repo** planning directory
   - **MUST include "Interface Dependencies" section listing all APIs with `[CONFIRMED]` status**
2. Create work plan in **main repo** planning directory — MUST include:
   - Branch name
   - Base branch + commit hash
   - Worktree path
   - Commit strategy
   - Merge method
3. **STOP. Present plan to user. Wait for approval.**

### Phase 2: Start (main → worktree)

4. `git worktree add ../{path} -b {branch} {base}`
5. `mv` (NOT cp) planning artifacts from main to worktree
6. Verify: main has ZERO plan-specific files
7. Verify: worktree has ALL planning artifacts

### Phase 3: Build (worktree only)

8. All edits in worktree — never touch main
9. Install deps, verify clean baseline

#### Subagent Verification Protocol (MANDATORY when delegating)

When delegating tasks to subagents during Build phase:

1. **Integration seam check** — After parallel tasks complete, identify every integration point (component A imports B, page uses shared component, etc.) and verify each is actually connected, not stubbed/no-op
2. **Core function audit** — For each subagent deliverable, Read the top 3 most important functions and confirm they contain real logic, not placeholders like `void x; void y`
3. **Interaction test mandate** — Every user-facing interaction (click, submit, navigate) in the plan's deliverables MUST have a corresponding test case. Test plan must list these explicitly before writing tests.
4. **Deduplication check** — `grep -h '^export' <all new files> | sort` to find duplicate exports (same name or same value). Merge duplicates into the shared module, other files import from it.
5. **Cross-file alignment** — Verify all new files are consistent:
   - If a shared module defines a constant/type, other files MUST import it (no local redefinition)
   - Same concept uses same naming across all files (not `PHASE_MAP` in types.ts and `phases` in modal)
   - No orphan imports (importing from shared module but actually using a local copy)

**Red flags**:

- Subagent reports "0 errors, all tests pass" but you haven't Read any delivered source code → VIOLATION
- New file has `export const` for something already exported by the shared types file → VIOLATION

#### Bugfix Closure Rule

Every bugfix MUST include TWO deliverables:

1. **Failing test first, then fix** — reproduce the bug with a test that fails before any implementation change, then fix the code until the test passes
2. **Prevention assessment** — evaluate whether the bug pattern needs a new rule in AGENTS.md, workflow skill, or check:ci. Document conclusion (even if "no new rule needed — existing rule X covers it")

#### Route Permission Check (MANDATORY when adding/modifying routes or page operations)

If the changeset includes new or modified routes (`src/routes/`) or page operations (`_operations` / `engName`):

1. For each `_operations` entry with an `engName`, verify a matching `action` exists in the corresponding route file (`src/routes/{domain}.tsx`)
2. For each new `action` in a route file, verify it is consumed by an `_operations` `engName` in the page component
3. Missing matches → fix before proceeding. Non-admin users will get invisible buttons or 403 errors.

## Red Flags — STOP Immediately

| Thought                                         | Reality                                                            |
| ----------------------------------------------- | ------------------------------------------------------------------ |
| "I know which branch/worktree I'm on"           | You don't. Other sessions or user may have switched. Always check. |
| "Let me create the worktree first, plan later"  | Plan FIRST. Always.                                                |
| "I'll write the design doc in the worktree"     | Design doc starts on main, moves via `mv`.                         |
| "Need to create PR early"                       | PR comes AFTER worktree setup with proper plan.                    |
| "User said urgent"                              | Urgency does not override the checklist.                           |
| "I'll add the plan file later"                  | Later never comes. Plan before `git worktree add`.                 |
| "I can cp instead of mv"                        | `mv` only. Single source of truth.                                 |
| "I already know what to do, skip planning"      | Plans catch gaps you don't see. Write it.                          |
| "The API should exist, user mentioned the path" | Mentioned ≠ documented. Verify or ask. Never assume.               |
| "The interface is probably similar to others"   | Every interface must be independently verified.                    |

## AGENTS.md Setup

For strongest enforcement, copy the decision tree template into your project's AGENTS.md:

```
<skill-source-dir>/../AGENTS_MD_TEMPLATE.md
```

This is optional — the skill works standalone — but projects with the template get an extra layer of reinforcement.

## Common Mistakes

**Creating artifacts directly in worktree** — Design docs and plans must originate on main, then `mv` to worktree. This ensures the human gate happens before code isolation begins.

**Skipping the human gate** — "Present plan, wait for approval" is not optional. Even if the user says "go ahead", the plan must exist and be shown first.

**Using `cp` instead of `mv`** — Copies create divergent sources of truth. Only `mv`.

**Creating design docs with unverified APIs** — If user mentions an API path but no documentation exists for it, you MUST ask for docs before creating any design. "User mentioned it" is not the same as "I have verified it".

## Quick Reference

| Step            | Where    | Command               |
| --------------- | -------- | --------------------- |
| Create design   | main     | Write to planning dir |
| Create plan     | main     | Write to planning dir |
| Human gate      | main     | Present and wait      |
| Create worktree | main     | `git worktree add`    |
| Move artifacts  | main→wt  | `mv` planning files   |
| Verify main     | main     | No plan files remain  |
| All dev work    | worktree | Code, test, commit    |
