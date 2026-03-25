---
name: wf-branch-workflow
description: Use when starting multi-file changes that don't require worktree isolation — feature additions, module refactors, new pages/entities. Triggers include 2+ files changing, new routes or menus, API integrations, any task where you'd normally run generate_entity_code.sh or scaffold code. Enforces branch + plan discipline without worktree overhead.
---

# Branch Workflow

## Overview

Enforce plan-first discipline for multi-file work that doesn't need worktree isolation. **No code changes without a branch and an approved plan.**

**Core principle:** "Not complex enough for worktree" is NOT an excuse to skip ALL discipline.

## When to Use

- Task changes 2+ files
- Adding new pages, entities, routes, or menus
- API integrations with multiple endpoints
- Any scaffolding or code generation
- Module-level refactoring

**Do NOT use for:** Single-file fixes, typo corrections, config tweaks, documentation-only changes.

**Need worktree isolation?** Use `wf-worktree-workflow` instead.

## The Flow

```
Git Check ──▶ Classify ──▶ Plan (main) ──gate──▶ Branch ──▶ Build ──▶ Verify ──▶ Present
```

## Pre-flight Checklist

**BLOCKING — complete every item in order. No skipping.**

### Phase 0: Git State Check (MANDATORY FIRST STEP)

Run this BEFORE anything else — even before exploring the codebase:

```bash
git branch --show-current && git status --short
```

**Do NOT assume you know the current branch.** Other sessions or the user may have switched branches since your last turn. Verify, then proceed.

### Phase 0.1: Gate Check

```bash
bash <skill-base-dir>/scripts/workflow-gate.sh check <plan-name>
```

The skill loader provides the base directory path. Use it to resolve the script.

- **All checks pass** → skip to Phase 3 (Build). Plan and branch already exist.
- **Any check fails** → the script tells you exactly what's missing. Fix each item in order (Phase 0.5 → Phase 1 → Phase 2) until the gate passes.

**No Edit/Write calls to `src/` files until this gate returns exit code 0.**

### Phase 0.5: Classify

1. Count files that will change. If 2+ → this skill applies.
2. Is worktree needed? If yes → use `wf-worktree-workflow`. If no → continue here.

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

### Phase 1: Plan (on main, BEFORE branching)

3. Read project AGENTS.md for conventions (naming, `.sisyphus/` structure, commit style).
4. Create design doc: `.sisyphus/designs/{plan-name}-design.md`
   - Problem statement, approach, affected files, API summary
   - **MUST include "Interface Dependencies" section listing all APIs with `[CONFIRMED]` status**
5. Create work plan: `.sisyphus/plans/{plan-name}.md`
   - Task breakdown with checkboxes
   - Branch name: `feature/{plan-name}`
   - Base branch + commit hash
   - Commit strategy
6. **STOP. Present plan to user. Wait for explicit approval.**

### Phase 2: Branch + Commit Plan

7. `git checkout -b feature/{plan-name}`
8. Commit plan artifacts: `git add .sisyphus/ && git commit -m "plan({domain}): {plan-name}"`

### Phase 3: Build (feature branch only)

9. All edits on the feature branch — never switch back to main
10. Track progress with TodoWrite
11. Run `pnpm check:ci` (or project CI command) after completing implementation

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

### Phase 4: Present

12. Show summary of changes to user
13. Do NOT push or create PR without explicit request

## Red Flags — STOP Immediately

| Thought                                               | Reality                                                             |
| ----------------------------------------------------- | ------------------------------------------------------------------- |
| "I know which branch I'm on from the last turn"       | You don't. Other sessions or user may have switched. Always check.  |
| "User asked to implement, so I'll just start coding"  | Implementation request ≠ skip planning. Plan first.                 |
| "Not complex enough for worktree, so skip everything" | Branch workflow exists for exactly this case. Use it.               |
| "More efficient to just do it"                        | Efficiency without discipline = rework. Plan takes 5 min.           |
| "I'll create the branch after I make the changes"     | Branch BEFORE changes. Uncommitted work on main = violation.        |
| "The user seems impatient"                            | Impatience doesn't override the checklist. Present plan quickly.    |
| "It's just scaffolding, templates handle it"          | Scaffolding + customization = multi-file change. Plan it.           |
| "I already know the codebase pattern"                 | Knowing the pattern doesn't mean skip the plan. Plans catch gaps.   |
| "Let me explore first, then decide"                   | Exploration is fine. But once you decide to implement → plan first. |
| "The API should exist, user mentioned the path"       | Mentioned ≠ documented. Verify or ask. Never assume.                |
| "The interface is probably similar to the others"     | Every interface must be independently verified. No guessing.        |

## Quick Reference

| Step          | Where  | Action                               |
| ------------- | ------ | ------------------------------------ |
| Classify task | —      | Count files, pick workflow           |
| Create design | main   | `.sisyphus/designs/{name}-design.md` |
| Create plan   | main   | `.sisyphus/plans/{name}.md`          |
| Human gate    | main   | Present plan, wait for approval      |
| Create branch | main   | `git checkout -b feature/{name}`     |
| Commit plan   | branch | Commit `.sisyphus/` artifacts        |
| Implement     | branch | Code, test, track with todos         |
| Verify        | branch | Run CI gate command                  |
| Present       | branch | Show changes, await instructions     |

## AGENTS.md Setup

For strongest enforcement, copy the decision tree template into your project's AGENTS.md:

```
<skill-source-dir>/../AGENTS_MD_TEMPLATE.md
```

This is optional — the skill works standalone — but projects with the template get an extra layer of reinforcement.

## Common Mistakes

**Making changes on main then "moving" to a branch** — The branch must exist BEFORE any code changes. If you already have uncommitted changes on main, stash them, create the branch, then unstash.

**Skipping the design doc for "simple" features** — If it changes 2+ files, it's not simple enough to skip. A minimal design doc (5 lines) is still required.

**Treating plan approval as optional** — "Present plan to user" means STOP and WAIT. Do not proceed until the user says yes.

**Creating design docs with unverified APIs** — If user mentions an API path but no documentation exists for it, you MUST ask for docs before creating any design. "User mentioned it" is not the same as "I have verified it".
