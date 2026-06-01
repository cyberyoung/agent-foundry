---
name: wf-worktree-workflow
description: Use when about to create a git worktree for feature work, before running git worktree add. Enforces plan-first workflow with mandatory gates. Triggers include multi-file changes, feature branches, worktree setup, or any task requiring a design doc or plan.
---

# Worktree Workflow

## Overview

Enforce plan-first → gate → move → canonical worktree isolation for multi-file
feature work. All planning happens on main FIRST, then artifacts physically move
to `../worktrees/{repo-name}/{slug}`.

**Core principle:** No worktree creation without a reviewed plan on main, and no
automated worktree path outside `../worktrees/{repo-name}/{slug}`.

## Feature Mode

This workflow must explicitly declare a **feature mode** before implementation begins:

- `tdd-feature`
- `standard-feature`

Default fallback is `standard-feature`. Do **not** infer mode from branch name, commit message, or vague wording.

Mode semantics must stay aligned with `wf-branch-workflow`:

- `tdd-feature` → requires failing-test-first evidence and stronger completion proof
- `standard-feature` → does not require failing-test-first, but still requires a successful `pnpm check:task`

## OpenSpec Lifecycle

Feature work that adds a capability, changes behavior, changes architecture, or changes
security / performance semantics must create or reference an OpenSpec change.

If an OpenSpec change exists for the task:

- Plan must declare `OpenSpec Change: <change-id>`.
- Plan must include `## OpenSpec Traceability`.
- Every OpenSpec `#### Scenario:` must map to a task and verification/test.
- Implementation must read `proposal.md`, `design.md`, and `specs/**/spec.md`.
- Implementation must run `openspec validate <change-id> --strict` before coding.
- Final review must check every OpenSpec scenario for implementation and test coverage.
- Completion must archive the change after merge/release or record a deferred-archive reason.

`pnpm check:task --mode <mode>` must include `pnpm check:openspec-traceability`.

## Frontend Interaction Gate

When the task adds or changes modal, drawer, side panel, long-running button,
mutation-driven UI, SSE-driven UI, polling-driven UI, or generated-content UI:

- The design/plan must include `## UI Interaction Matrix`.
- The matrix must list every entry point, initial state, user action, expected UI
  state, loading/disabled state, test coverage, and browser evidence path.
- Tests must cover field visibility by label/role, every entry mode, selection
  persistence, loading/disabled state, and submitted payload.
- Completion requires `docs/evidence/{task}/ui-review.md` with the reviewed routes
  or URLs, entry points, field visibility/layout result, selection persistence,
  loading/disabled result, and screenshot path or explicit reason screenshots are
  unavailable.
- If there is no frontend interaction change, the plan must say
  `N/A: no frontend interaction change`.

## Branch Naming

- Worktree feature work uses `feature/{name}`.
- Bug fixes use the bugfix workflow and `fix/{name}`.
- Urgent production/release fixes use the bugfix workflow and `hotfix/{name}` only when explicitly appropriate.
- Do not invent personal, tool-specific, or ad-hoc branch prefixes without explicit user confirmation.
- Do not create branches or worktrees silently. Before any `git checkout`,
  `git switch`, or `git worktree add -b`, present the current branch, intended
  base branch, proposed branch name, and proposed canonical worktree path to the user.
  Wait for explicit confirmation; the user may edit the branch name or path, and
  those confirmed values are authoritative.

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

Use the primary repo resolver before any baseline or worktree path decision.
The resolver derives `../worktrees/{repo-name}` from the primary repo root and
is the only source for canonical worktree placement.

### Phase 0: Git State Check (MANDATORY FIRST STEP)

Run this BEFORE anything else — even before exploring the codebase:

```bash
git branch --show-current && git status --short && git worktree list
PRIMARY_REPO="$(primary repo resolver result)"
git -C "$PRIMARY_REPO" fetch origin main
```

**Do NOT assume you know the current branch or worktree.** Other sessions or the user may have switched branches since your last turn. Verify, then proceed.

**Do NOT skip the fetch.** Creating a worktree from a stale main is the #1 cause of avoidable merge conflicts.

Use the primary repo resolver from `wf-worktree-cleanup/scripts/worktree-paths.sh`
or the same algorithm: resolve `git rev-parse --path-format=absolute
--git-common-dir`, map it back to the primary checkout, verify it is listed by
`git worktree list --porcelain`, then derive
`../worktrees/{repo-name}` from the primary repo parent.

Baseline safety:

- If the primary repo is on `main` and clean, update it with
  `git -C "$PRIMARY_REPO" merge --ff-only origin/main`.
- If the primary repo is on a feature branch, do not merge `origin/main` into
  that feature branch. Use `origin/main` as the worktree creation baseline or
  stop for human confirmation.
- Never run a main update from an arbitrary linked worktree cwd.

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

### Phase 0.9: PRD Check

Check if `docs/prds/` has a PRD document for this task. If not, ask the user to write one first. The PRD is the user's description of the requirements — do not write it yourself.

### Phase 1: Design (on MAIN)

Derive `{name}` from the PRD filename (strip extension). E.g., `docs/prds/foo.md` → `{name}` = `foo`.

**Provider dispatch:**
1. Check if the PRD has a "Workflow Providers" section → use it for `design` phase
2. Otherwise read AGENTS.md "Workflow Providers" table for `design` phase
3. Neither exists → manual

**Provider invocation instructions:**
- Output to `docs/designs/{name}.md`
- Link to PRD in `docs/prds/`
- Use `docs/PLAN_TEMPLATE.md` as template if available

**If provider is a skill name:** Invoke that skill with above instructions.
**If manual:** You are the provider — write the design doc yourself.

**Post-completion verification:**
- File `docs/designs/{name}.md` exists
- Contains: problem statement, approach, affected files, API summary
- Contains: "Interface Dependencies" section, all APIs marked `[CONFIRMED]`
- Contains: test design section (`## 测试` or `## Test`) — 每个变更块的测试用例和验证点

**Then:** Update `docs/README.md` index. **STOP. Present design to user. Wait for approval.**

### Phase 1.5: Plan (on MAIN)

**Provider dispatch:** Same lookup as Phase 1, but for `plan` phase.

**Provider invocation instructions:**
- Output to `docs/plans/{name}.md`
- Must include: branch name, base branch + commit hash, canonical relative path,
  resolver algorithm, commit strategy, merge method

**If provider is a skill name:** Invoke that skill with above instructions.
**If manual:** You are the provider — write the plan yourself.

**Post-completion verification:**
- File `docs/plans/{name}.md` exists
- Contains: branch name, base branch + commit hash, canonical relative path,
  resolver algorithm, commit strategy, merge method
- Records only `../worktrees/{repo-name}/{slug}` and the resolver algorithm.
  Runtime absolute paths may appear only in session logs or uncommitted runtime
  files.
- Contains: explicit **feature mode** (`tdd-feature` or `standard-feature`)
- If the task changes frontend interaction UI, contains `## UI Interaction Matrix`; otherwise contains `N/A: no frontend interaction change`
- If an OpenSpec change exists, contains `OpenSpec Change: <change-id>` and `## OpenSpec Traceability`

**Then:** Update `docs/README.md` index. **STOP. Present plan to user. Wait for approval.**

### Phase 2: Start (main → worktree)

4. Confirm the exact branch name and canonical worktree path with the user if
   they were not explicitly approved in Phase 1.5. Create the repo bucket first:
   `mkdir -p ../worktrees/{repo-name}`. Then create the worktree at
   `../worktrees/{repo-name}/{slug}` using the confirmed branch name and base.
5. `mv` (NOT cp) planning artifacts from main to worktree
6. Verify: main has ZERO plan-specific files
7. Verify: worktree has ALL planning artifacts

### Phase 2.5: Dependency Bootstrap (worktree only)

Run this immediately after the worktree exists and before any Phase 3
read/edit/build/test work in that worktree.

1. `cd` into the confirmed worktree path.
2. Inspect project signals before choosing a command: `README`, package manager
   lockfiles, dependency manifests, language/framework config, and existing
   scripts.
3. Install dependencies with the project's own toolchain and lockfile:
   - Node: use the lockfile/package manager (`pnpm install --frozen-lockfile`,
     `npm ci`, `yarn install --frozen-lockfile` / `yarn install --immutable`,
     or `bun install --frozen-lockfile`).
   - Python: prefer project tooling (`uv sync`, `poetry install`, or a local
     virtualenv + `pip install -r requirements*.txt`). Never install packages
     globally.
   - Go/Rust/Ruby/Java: use the project-native bootstrap (`go mod download`,
     `cargo fetch`, `bundle install`, `mvn dependency:go-offline`, or the
     repo's Gradle wrapper).
   - Other stacks: follow the checked-in docs/scripts for that project.
4. Verify the dependency bootstrap:
   - install command exits successfully
   - lockfiles are not unexpectedly modified
   - if the repo defines a cheap baseline check, run it now
5. If no dependency install is required, record the reason before moving on.

### Phase 3: Build (worktree only)

#### Working Directory Verification (MANDATORY before every file operation)

Before any Read/Edit/Write/Bash file operation, verify the path belongs to the current environment:

1. **Determine environment**: Am I in a worktree or the main repo? Check `git worktree list` or the session's primary working directory.
2. **Validate path**: Does the target file path fall under the current worktree/repo directory?
3. **Reject cross-environment paths**: If a path points to the main repo while working in a worktree (or vice versa), STOP — rewrite the path for the current environment.
4. **Distrust cached paths**: Absolute paths from earlier in the conversation or from memory may point to the wrong environment. Always reconstruct from the current working directory.

**Hard rule**: The session's primary working directory (shown in gitStatus at conversation start) is the source of truth. All file paths must be under that directory.

**Provider dispatch:** Look up `execute` phase provider (same lookup as Phase 1).

**If provider is a skill name:** Invoke that skill, instruct it to execute `docs/plans/{name}.md`. **传达以下约束：**
- **禁止逐 task 提交** — implementer 不执行 `git commit`，计划中的 "commit" 步骤替换为 "验证"（`pnpm vitest run --changed`）
- **所有变更积累** — 直到整体 review 通过、用户审批后统一提交
- 提交粒度 = 完整功能，不是子任务

After completion, run CI check.

**If manual:**
8. All edits in worktree — never touch main
9. Confirm Phase 2.5 dependency bootstrap is complete
10. **不逐 task 提交** — 积累变更到 Phase 4（Ship）
11. If an upstream skill such as `using-git-worktrees`,
    `executing-plans`, or `subagent-driven-development` asks to create another
    worktree, treat the already-created canonical worktree satisfies isolation
    rule as authoritative. Do not create a second worktree.
12. If an OpenSpec change exists, read its proposal/design/specs and run `openspec validate <change-id> --strict`
12. If frontend interaction UI changed, create/update `docs/evidence/{task}/ui-review.md` and verify every entry in `## UI Interaction Matrix`

Before any completion claim, the task must pass:

```bash
pnpm check:task
```

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

### Phase 4: Ship

**Provider dispatch:** Look up `ship` phase provider (same lookup as Phase 1).

Before entering ship / publish / PR flow, run and pass:

```bash
node scripts/ci/check-task-gate.mjs --gate pre-pr
```

If an OpenSpec change exists, final review must check every scenario listed in
`## OpenSpec Traceability`. After merge or release, archive the change or record
why archive is deferred.

Do not run cleanup from this skill. After the PR is merged and the user confirms
the merged PR details, hand off to `wf-worktree-cleanup`.

**If provider is a skill name:** Invoke that skill to complete the development branch.

**If manual:** Show summary of changes to user. Do NOT push or create PR without explicit request.

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
| "I'll use the path from earlier in the conversation" | Earlier path may point to main repo, not the current worktree. Reconstruct from pwd. |
| "I'll use repo-local `.worktrees/`, repo-local `worktrees/`, a global worktree dir, or a scattered sibling worktree" | Abort. Automated creation is canonical-only: `../worktrees/{repo-name}/{slug}`. |

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
| Create design   | main     | `docs/designs/{name}-design.md` |
| Create plan     | main     | `docs/plans/{name}.md`          |
| Update index    | main     | Update `docs/README.md`         |
| Human gate      | main     | Present and wait                |
| Create worktree | main     | create `../worktrees/{repo-name}/{slug}` from the confirmed branch/base |
| Move artifacts  | main→wt  | `mv` planning files   |
| Install deps    | worktree | Use project language/framework lockfile/tooling |
| Verify main     | main     | No plan files remain  |
| All dev work    | worktree | Code, test, commit    |
