---
name: wf-bugfix
description: Use when fixing a bug — any size, any number of files. Enforces the failing-test-first discipline, prevents skipping steps. Triggers include bug reports, runtime errors, incorrect behavior, UI display issues, or any task where existing functionality is broken.
---

# Bug Fix Workflow

## Overview

Enforce disciplined bug fixing: failing test → minimal fix → prevention assessment. **No code fix without a failing test first.**

**Workflow mode:** `mode = bugfix`

This skill is the authoritative entry point for bugfix mode. Bugfix mode always requires:

- failing-test-first evidence
- a defined **target test file**
- a defined **target test command**
- a git-history-backed **root cause timeline** for the affected file(s)
- a successful `pnpm check:task --mode bugfix` before claiming completion

## OpenSpec Lifecycle

Bugfixes are exempt from OpenSpec by default. If a bugfix creates or references
an OpenSpec change, the OpenSpec lifecycle becomes mandatory:

- Plan must declare `OpenSpec Change: <change-id>`.
- Plan must include `## OpenSpec Traceability`.
- Every OpenSpec `#### Scenario:` must map to a task and verification/test.
- Implementation must read `proposal.md`, `design.md`, and `specs/**/spec.md`.
- Implementation must run `openspec validate <change-id> --strict` before coding.
- Final review must check every OpenSpec scenario for implementation and test coverage.
- Completion must archive the change after merge/release or record a deferred-archive reason.

`pnpm check:task --mode bugfix` must include `pnpm check:openspec-traceability`
when an OpenSpec change is present.

## Frontend Interaction Gate

When the bug affects modal, drawer, side panel, long-running button,
mutation-driven UI, SSE-driven UI, polling-driven UI, or generated-content UI:

- The fix plan must list every affected entry point and expected UI state.
- The failing test must reproduce the broken entry mode, not only a helper
  function.
- If the bug is visible or actionable only in the browser, follow
  `wf-ui-browser-verification` for Browser RED/GREEN evidence. Do not duplicate
  that skill's browser-evidence rules here.
- Regression tests must cover field visibility by label/role, every affected
  entry mode, selection persistence, loading/disabled state, and submitted
  payload when those behaviors are in scope.
- Completion requires `docs/evidence/{task}/ui-review.md` with the reviewed routes
  or URLs, entry points, field visibility/layout result, selection persistence,
  loading/disabled result, and screenshot path or explicit reason screenshots are
  unavailable.

## PR/CI Failure Gate

When the user reports a failed pull request, failed CI run, failed workflow,
failed check, or failed task gate, treat it as a triage-first bugfix. Examples:
`PR failed`, `CI failed`, `check failed`, `workflow failed`, `PR 728 failed`,
or any equivalent report.

Before explicit user approval, you may only:

- Fetch PR metadata, workflow jobs, check results, and failed logs.
- Read relevant source, scripts, config, plans, and docs needed to identify the
  failure.
- Reproduce the failed command locally when useful.
- Produce a failure analysis report and proposed fix plan.

Before explicit user approval, you must not:

- Edit code, docs, tests, configuration, generated files, or skill files.
- Format files or perform opportunistic cleanup.
- Commit, push, resolve review threads, or rerun remote jobs.
- Start fixing adjacent review comments or unrelated local lint warnings.

Required failure analysis report:

1. **Failure inventory** — list each failed job/check, command, and the key log
   excerpt or exact error.
2. **Root cause analysis** — explain each failure's direct cause and cite the
   evidence from logs or source.
3. **Git history timeline** — inspect the affected file history and identify
   when the bug was introduced, the commit sequence that led to it, and why the
   introducing change missed the invariant. Include commit hash, commit date,
   subject, and the relevant diff/blame evidence.
4. **Trend analysis** — compare this failure with previous checks, earlier
   commits, prior review rounds, or earlier CI runs when available. State whether
   the failure pattern is converging or widening; call out whether high/P1
   issues are decreasing, whether failures moved from behavior to gate hygiene,
   and whether new failure categories appeared.
5. **Generalization audit** — search the current diff and relevant neighboring
   code for the same class of issue. Examples: one hardcoded query key requires
   searching for other hardcoded query keys in the diff; one missing API type
   JSDoc requires checking every new type in the file; one business-error branch
   requires checking comparable response handlers.
6. **Proposed changes** — list every file you propose to edit and map each edit
   to a specific failure or generalized issue.
7. **Verification plan** — list target tests, target commands, and final task
   gate or equivalent verification.
8. **Risk and rollback** — note behavior risk, CI-only risk, and how to revert
   if the plan is wrong.

Only after the user explicitly approves the report may you edit files.

If you already edited files before this approval gate, stop immediately. List
every uncommitted edit, explain which failure each edit attempts to address, and
ask the user whether to keep those edits for review, revert them, or restart
through the proper failure analysis flow. Do not continue implementation until
the user decides.

## When to Use

- Any bug report or broken behavior
- Runtime errors, UI display issues, incorrect data
- Regression from a recent change
- Failed pull requests, CI checks, workflows, lint/type/test/build jobs, and
  task gates
- Single-file or multi-file fixes alike

## The Flow

```
Branch ──▶ Reproduce/Triage ──gate──▶ Plan Review ──gate──▶ Failing Test/Failing Gate ──gate──▶ Fix ──gate──▶ Prevent ──▶ Done
```

## Phase 0: Branch

Never fix directly on main — no exceptions, no matter how small.

1. Check current state and sync main:

```bash
git branch --show-current && git status --short
git fetch origin main && git merge origin/main --ff-only
```

**Human confirmation gate:** Before switching branches or creating any new branch,
STOP and present the current branch, intended base branch, and proposed branch
name to the user. Wait for explicit confirmation. The user may edit the branch
name; use their confirmed name exactly. Do not silently run `git checkout`,
`git switch`, or `git checkout -b`.

2. Decide:
   - **On a `fix/` or `hotfix/` branch** → use it as-is (multiple bugs on one branch is fine)
   - **On main** → create a fix branch: `git checkout -b fix/<bug-name>`
   - **On any other branch** → switch to main first, then create a fix branch: `git checkout main && git checkout -b fix/<bug-name>`

Branch prefix convention:
- Use `fix/<bug-name>` for ordinary bug fixes.
- Use `hotfix/<bug-name>` only for urgent production/release fixes where the user or release context explicitly calls for a hotfix.
- Do not invent personal, tool-specific, or ad-hoc branch prefixes without explicit user confirmation.

3. Check for worktree environment:

```bash
git worktree list
```

   - **Single entry (main repo only)** → no directory verification needed
   - **Current directory is a worktree** → all file paths in this session MUST be under the current working directory. Do NOT trust paths returned by agents, cached from earlier in the conversation, or recalled from memory — always reconstruct from `pwd`

**Gate: You must NOT be on main before any code changes. If in a worktree, verify all paths are local.**

## Phase 0.5: PRD Check

Check if `docs/prds/` has a PRD document for this bug. If not, ask the user to write one first. The PRD is the user's description of the problem — do not write it yourself.

## Phase 1: Reproduce

1. Understand the bug — read the PRD and any additional report, screenshot,
   error message, or failed PR/CI logs
2. Identify the affected code — find the component/function/module
3. Audit the affected file history before proposing a fix:

```bash
git log --follow --date=iso --stat -- <affected-file>
git blame -L <start>,<end> -- <affected-file>
git show --stat --patch <suspected-commit> -- <affected-file>
```

   - Find the commit that introduced the broken line or invariant gap, not only
     the current line that crashes.
   - Build a concise timeline: preceding working state → introducing commit →
     later edits/reviews/tests that failed to catch it → current failure.
   - Cite commit hash, commit date, subject, and the relevant file/line or diff.
   - If history is inconclusive (generated file, squash merge, rename, or
     missing local refs), state exactly what was checked and why no definitive
     introducing commit can be proven.
4. Describe the root cause in one sentence before proceeding. The sentence must
   include both the direct technical cause and the history-backed introducing
   cause, for example: "The render crashes because `Tooltip` is referenced
   without import; `abc123` added the JSX while only importing enum maps, and no
   test exercised that column render."
5. For PR/CI failures, complete the PR/CI Failure Gate report before proposing
   any fix

**Gate: Can you explain WHY it's broken, WHEN it was introduced, and HOW the
history sequence allowed it through? If not, keep investigating.**

### False-positive guard and coverage check

Before treating a report as a real bug, verify it with evidence. A plausible
report is not enough.

Required evidence:

1. The reported code path is reachable.
2. The behavior violates a requirement, API contract, existing pattern, or
   clearly intended invariant.
3. A targeted test can demonstrate the behavior, or existing tests already
   cover the same contract.

If the main gap is missing coverage, add the smallest targeted test first:

- If the test fails, the bug is confirmed; proceed to the minimal fix.
- If the test passes, stop and reclassify the report as false positive,
  already fixed, or coverage-only. Do not change production code.
- If the behavior is correct but important to preserve, make a test-only
  coverage change and report that no production fix was needed.

Never use missing test coverage as proof that production code is wrong.

## Phase 1.5: Plan Review (mandatory)

Before writing any code or tests:

Derive `{name}` from the PRD filename (strip extension), or from the bug name if no PRD exists.

For PR/CI failures, the failure analysis report may serve as a lightweight
design only when the fix is limited to gate hygiene and does not change product
behavior. If the proposed fix changes behavior, touches several functional
areas, or spans multiple files with user-visible impact, create or update
`docs/designs/{name}.md` and `docs/plans/{name}.md` just like feature work, then
wait for explicit user approval.

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
- Contains: git history timeline (introducing commit, date, sequence, evidence)
- Contains: fix approach (which files, which lines, what the change looks like)
- Contains: test plan (what tests to write, what they assert, which files)
- Contains: execution order (step-by-step sequence including regression checks)
- If an OpenSpec change exists, contains `OpenSpec Change: <change-id>` and `## OpenSpec Traceability`

**Then:** Update `docs/README.md` artifact index. **Present plan to user. Wait for explicit approval.**

**Gate: The user must explicitly approve the plan before you proceed. Do NOT start Phase 2 until the user confirms.** If the user requests changes to the plan, update it and wait for approval again.

This gate applies even when the fix looks obvious, one-line, or urgent. A bug
report, stack trace, failed test, or user saying "handle this first" is not
approval to start implementation; only explicit approval of the proposed plan is.

This gate exists because:
- Fixing the wrong root cause wastes everyone's time
- The user may have context you don't (e.g., which compType actually triggers the bug)
- Reviewing a plan is cheap; reverting an incorrect fix is expensive

## Phase 2: Failing Test

Write a test that:
- Reproduces the exact bug scenario
- **Fails** with the current code
- Will **pass** once the fix is applied
- For frontend interaction UI bugs, exercises the affected entry point and asserts
  visible labels/roles, selection persistence, loading/disabled state, and submit
  payload where relevant
- For browser-visible bugs, uses `wf-ui-browser-verification` to collect Browser
  RED before any production fix.

Before writing or running the test, explicitly record:

- **target test file**
- **target test command**
- **contract being proved** — the requirement or invariant the test enforces

Run the test and confirm it fails:

```bash
pnpm vitest run <test-file>
```

For browser-visible bugs, run the Browser RED check defined in
`wf-ui-browser-verification` before the fix and record it in that evidence
format.

### If the failing test is hard to write

Sometimes a direct failing test is impractical (component not exported, requires full modal rendering, complex async timing, etc.). In this case:

1. **Stop and explain to the user** — describe why a failing test is hard, what the obstacle is
2. **Propose alternatives** — regression test for the fix logic, integration test at a higher level, or extracting the component for testability
3. **Wait for user decision** — the user chooses: adjust approach, skip test for this case, or find another way

**Never silently skip the test and jump to fixing.**

### If the test passes before the fix

Stop. The bug is not proven.

1. Re-check whether the test targets the exact reported behavior.
2. If the test is correct, reclassify the report as false positive, already
   fixed, or coverage-only.
3. Do not write production code unless you can produce a failing test or the
   user explicitly approves a different evidence standard.

## Phase 3: Fix

1. Implement the minimal fix — change only what's needed to make the failing test pass
2. Run the test again and confirm it passes:

```bash
pnpm vitest run <test-file>
```

3. For browser-visible bugs, rerun the Browser GREEN check defined in
   `wf-ui-browser-verification`.
4. Do NOT add features, refactor surrounding code, or update rules at this stage
5. Do not commit. Accumulate changes until Phase 4 is complete and the user
   explicitly approves the final commit.

**Gate: The previously failing test must now pass. If it doesn't, keep fixing.**
For browser-visible bugs, the Browser GREEN gate from `wf-ui-browser-verification`
must also pass before moving to prevention assessment.

## Phase 4: Prevention Assessment

Evaluate whether the bug pattern needs systemic prevention:

| Question | If yes |
|----------|--------|
| Could a lint rule or CI check catch this? | Propose adding it |
| Is this a common pattern others might repeat? | Propose a rule in AGENTS.md (anti-pattern or coding convention) |
| Does an existing rule already cover this? | Document which rule — no new rule needed |
| Is this a one-off mistake? | No new rule needed — the test is sufficient prevention |

**Document your conclusion** — even if the answer is "no new rule needed, existing coverage is sufficient."

For PR/CI failures, also document:

- The trend analysis result after the fix: did failures decrease, move to a
  lower-severity class, or reveal a new category?
- The git history timeline result: which commit introduced the bug, which later
  changes failed to catch it, and what process/test gap allowed it through.
- The generalization audit result after the fix: what same-class issues were
  searched for, which were fixed, and which were intentionally left alone.

For frontend interaction UI bugs, also document or update:

- `docs/evidence/{task}/ui-review.md`
- The affected entry points
- Field visibility/layout result
- Selection persistence result
- Loading/disabled result

Before any completion claim, run and pass:

```bash
pnpm check:task --mode bugfix
node scripts/ci/check-task-gate.mjs --gate completion --mode bugfix
```

If an OpenSpec change exists, final review must check every scenario listed in
`## OpenSpec Traceability`. After merge or release, archive the change or record
why archive is deferred.

**Important: Only update rules/conventions AFTER the fix is verified by tests. Never update rules based on an unverified fix.**

## Red Flags — STOP Immediately

| Thought | Reality |
|---------|---------|
| "I know the fix, let me just do it quickly" | Plan review first, then failing test. No exceptions. |
| "The plan is obvious, no need to confirm" | Present it anyway. The user may have context you lack. |
| "The test is hard to write, I'll skip it" | Explain to user and get approval. Never skip silently. |
| "Let me fix first, then write a regression test" | That's backwards. Test proves the bug exists before you fix it. |
| "The stack trace points to the line, so I know the root cause" | Current location is not enough. Use file history to find when and how the bug was introduced. |
| "There is no test, so the bug must be real" | Missing coverage is not proof. Add a targeted test first. |
| "The new test passes, but I'll still fix the code" | A passing proof test means the report may be false positive or already fixed. Reclassify before coding. |
| "I'll also clean up the surrounding code" | Minimal fix only. Refactoring is a separate task. |
| "I should add a rule to prevent this" | Only after the fix is verified. Rules based on unverified fixes are premature. |
| "The fix works in my head, no need to run the test" | Run the test. Always. |
| "It's a one-liner, I'll fix it on main" | Not on main. Switch to or create a branch first. |
| "The agent found the file at /path/to/main-repo/..." | If in a worktree, that path is wrong. Reconstruct from pwd. |
