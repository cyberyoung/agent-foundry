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
- existing owner regression baseline evidence before new RED tests or fixes
- a defined **target test file**
- a defined **target test command**
- a git-history-backed **root cause timeline** for the affected file(s)
- a structured **decision package** with Decision Table, Evidence & Ownership,
  Owner/RP Coverage Matrix, Regression Plan, and TDD / Verification / Commit
  Plan
- a successful `pnpm check:task --mode bugfix` before claiming completion

## Regression And Fix Definitions

Bugfix mode uses three different kinds of proof. Do not collapse them into one
"test" bucket:

1. **Existing regression baseline** — the owner-layer tests that already existed
   before this fix. Run them before adding a new RED test or editing production
   code. Record the command, GREEN count, and a quality verdict:
   - `Sufficient`: covers the affected owner path and adjacent modes.
   - `Insufficient`: misses the owner path, entry mode, adjacent behavior,
     fallback, legacy, or negative path that could regress.
   - `Unavailable`: cannot be run or does not exist; stop or propose a
     substitute before implementation.
2. **Regression / characterization tests** — old-GREEN tests added before the
   fix to preserve currently correct behavior, adjacent modes, or shared-owner
   contracts. These tests must pass on the current implementation before the
   bug RED test or any production edit. They are coverage and safety proof, not
   the bug reproduction.
3. **Bug RED test** — the failing test that proves the reported broken behavior
   exists. It comes after the baseline is GREEN and quality-sufficient, or after
   missing old-GREEN characterization coverage has been added and proven GREEN.

**Fix** means the minimal production change that makes the bug RED test pass
after the above regression proof is in place. A test-only coverage change is not
a production fix. If a proof test passes before production code changes,
reclassify the report as false positive, already fixed, or coverage-only instead
of changing production code.

Execution order is a hard gate:

1. Run existing owner regression baseline and judge quality.
2. If quality is insufficient, add old-GREEN characterization/regression tests
   first and prove they pass on current code.
3. Add the bug RED test and prove it fails for the reported behavior.
4. Make the minimal owner-layer production fix.
5. Run the bug GREEN test plus baseline/regression tests.

This mirrors the PR-review triage standard: a new RED test does not replace the
existing regression baseline, and a weak baseline changes the first code action
to old-GREEN characterization coverage.

## Decision Package Structure Check

Bugfix plans use the same structured package standard as PR review triage. The
Decision Table is only an index; detailed evidence, ownership, regression
coverage, and execution order must live in separate inspectable blocks.

Required blocks:

- `Decision Table`
- `Problem / Root Cause / Timeline`
- `Evidence & Ownership`
- `Regression Plan`
- `Owner/RP Coverage Matrix`
- `TDD / Verification / Commit Plan`
- `3-Reviewer Regression Plan Review` for shared/lower-level owner changes
- `Local/CI Gate Design` for shared/lower-level owner changes

Before asking for approval, shared/lower-level owner changes must save the
decision package as a markdown artifact and run the lightweight checker:

```bash
node <skill-dir>/scripts/check-decision-package.mjs --mode bugfix --changed-files <comma-separated-changed-files> <decision-package.md>
```

For non-shared changes, run the checker whenever a decision-package artifact
exists. If the checker is not available in the current repo/skill installation,
say so explicitly and manually perform the same checks. The checker verifies
that the package has a Decision Table and Owner/RP Coverage Matrix, every shared
owner named in `Fix Strategy` or detected from `--changed-files` appears in the
matrix, no matrix row has invalid or missing `Coverage Status`, and Regression
Plan rows use explicit proof actions instead of only `preserve`/`保留`
promises. In bugfix mode it must also see a bug `RED` row, plus target test
file and target test command in the TDD plan. For shared owners, it also
requires owner-level Regression Plan rows, three reviewer rows with distinct
real subagent/session ids and `Missing Owner Count=0`, plus `Local/CI Gate
Design` containing a concrete command, detector/gate/hook, and failure rule.
The checker reads the `Evidence` file paths in that table and expects each file
to contain the actual subagent completion notification for the matching
`agent_path` with `no blockers`. Keep those notification files with the decision
package; do not replace them with hand-written session ids.

For any shared/lower-level owner change, run three independent fresh reviews of
the Owner/RP Coverage Matrix and Regression Plan before approval. This applies
to request wrappers, shared components/hooks, public helpers/API surfaces,
generators/templates, scripts, workflow gates, and other lower-level owners. The
reviews must continue until all three report zero missing owner regression
coverage. Record a `3-Reviewer Regression Plan Review` table. If subagents are
unavailable, stop and ask for explicit user approval for the manual substitute.

### Local/CI Gate Design

The durable prevention target is a local/CI gate for "shared owner changed but
no owner regression plan"; the plan must describe concrete wiring or an
explicit fallback, not a general promise:

1. Save bugfix decision packages as markdown artifacts when shared owners are in
   scope.
2. Run `<skill-dir>/scripts/check-decision-package.mjs` locally before approval with
   changed-file input, and wire the same command into the repo task/workflow
   gate when those artifacts exist. Missing changed-file input fails closed by
   default.
3. Add a repo-specific changed-file detector for shared owner paths, such as
   request wrappers, shared hooks/components, generators, scripts, workflow
   gates, and public helpers.
4. Fail the gate when a changed shared owner has no Owner/RP Coverage Matrix
   row, has missing, blank, partial, caller-only, or otherwise invalid
   `Coverage Status`, or only has caller-level regression rows.
5. Permit `N/A` only with a reason and owner-level substitute evidence.
6. If the repo cannot wire the gate in the same fix, record the fallback command,
   missing integration point, and residual risk in `Local/CI Gate Design`; do
   not present that fallback as implemented CI coverage.

Evidence levels:

- `Implemented local/CI gate`: detector command exists in the repo and is wired
  into `check:task`, hook, workflow, or equivalent gate.
- `Local checker only`: the decision package passed the checker, but the repo
  has no durable gate yet; record fallback and residual risk.
- `Manual substitute`: checker or changed-file input is unavailable; stop for
  explicit user approval and keep the manual checklist in the package.

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

### Bugfix decision package

Before approval, present a **decision package**, not a single overloaded table or
a prose-only plan. The package must make the fix strategy, evidence, regression
scope, and execution order separately inspectable.

Use these blocks:

1. **Problem / Root Cause / Timeline** — one-sentence root cause plus the
   history-backed introducing sequence and affected files.
2. **Decision Table** — compact index of each decision. It must include
   `Fix Strategy`, `Regression Plan`, `Evidence/Owner`, and `Action`
   references. `Fix Strategy` must describe the owner-layer production
   approach, not the tests. Do not put long evidence, long regression lists, or
   RED/GREEN details here.
3. **Evidence & Ownership Table** — reachable path, violated contract, evidence,
   abstraction owner, repeated patch/blast-radius check, generator/template
   impact, and browser evidence requirement or `N/A`. Every decision-table row
   needs an `EO-*` reference.
4. **Regression Plan** — start with an **Owner/RP Coverage Matrix** mechanically
   extracted from `Fix Strategy`:

   ```markdown
   | Decision | Owner / Surface Changed By Fix Strategy | RP Group | Coverage Status |
   |---|---|---|---|
   | #1 | request wrapper `get/post` public API | RP-1A | covered |
   | #1 | temporary auth helper | RP-1B | covered |
   ```

   Every shared owner, lower-level helper, public wrapper, script, generated
   template, or caller named in `Fix Strategy` must appear in this matrix. If
   any row has missing, blank, partial, or caller-only `Coverage Status`, stop
   and complete the Regression Plan before asking for approval. Caller-only
   coverage is insufficient when the fix changes a shared owner.

   Then classify each behavior with an explicit action:
   - `Existing GREEN`: already covered; include baseline command/result.
   - `Add old-GREEN`: correct but uncovered/weak; prove before RED or
     production code.
   - `RED`: the bug target that must fail before the fix.
   - `Post-fix GREEN`: only provable after implementation.
   - `N/A`: not applicable, with reason.
   Include coverage target, Browser Regression plan or `N/A`, and preserved
   adjacent modes/contracts.
   A row that only says `preserve`/`保留` is invalid without one of the explicit
   actions above. For shared owners, the action table must include an
   owner-level signal, such as `Regression Scope=owner-level` or an
   `Owner / Surface` cell that matches the matrix owner; caller-only rows do not
   satisfy shared-owner coverage.
5. **TDD / Verification / Commit Plan** — exact sequence, target test file,
   target command, `check:task` command, browser GREEN if needed, and commit
   grouping if commits are in scope.

For shared/lower-level owner changes, save the decision package to a markdown
artifact and run:

```bash
node <skill-dir>/scripts/check-decision-package.mjs --mode bugfix --changed-files <comma-separated-changed-files> <decision-package.md>
```

For non-shared changes, run the checker whenever an artifact exists. If the
checker is unavailable, report that fact and manually verify the same structure
before approval.

If `Fix Strategy` changes any shared/lower-level owner, run three independent
fresh reviews of the Owner/RP Coverage Matrix and Regression Plan. Record the
three results and revise until the missing-owner count is zero before asking for
approval.

Use this review block for shared-owner changes:

```markdown
## 3-Reviewer Regression Plan Review
| Reviewer | Source | Missing Owner Count | Evidence | Notes |
|---|---|---:|---|---|
| A | 01900000-0000-4000-8000-000000000001 | 0 | evidence/subagent-a.json | RP group owner coverage, caller-only masking, first action checked |
| B | 01900000-0000-4000-8000-000000000002 | 0 | evidence/subagent-b.json | RP group owner coverage, caller-only masking, first action checked |
| C | 01900000-0000-4000-8000-000000000003 | 0 | evidence/subagent-c.json | RP group owner coverage, caller-only masking, first action checked |

## Local/CI Gate Design
Command: `node <skill-dir>/scripts/check-decision-package.mjs --mode bugfix --changed-files src/api/request.tsx docs/plans/example.md`
Detector: `git diff --name-only HEAD` supplies changed files to `--changed-files`; replace with a repo-wired detector path when available.
Gate: fail when a shared owner path lacks owner-level matrix/regression coverage; record fallback and residual risk if not wired.
```

If any Regression Plan row is `Add old-GREEN`, the first approved code action
must be that characterization/regression test. If any row is `Existing GREEN`,
name the exact command and result. Do not hide RED/GREEN details inside the
Decision Summary; keep TDD work in the dedicated plan block.

**Post-completion verification:**
- File `docs/designs/{name}.md` exists
- Contains: root cause (what's broken and why)
- Contains: git history timeline (introducing commit, date, sequence, evidence)
- Contains: fix approach / Fix Strategy (which owner layer, files, and behavior
  will change)
- Contains: existing owner regression baseline command, GREEN count, and quality
  verdict (`Sufficient`, `Insufficient`, or `Unavailable`)
- Contains: test plan (what tests to write, what they assert, which files)
- Contains: Decision Table with `Fix Strategy`, `Regression Plan`,
  `Evidence/Owner`, and `Action` references
- Contains: Owner/RP Coverage Matrix with no missing, blank, partial, or
  caller-only `Coverage Status` rows
- Contains: Regression Plan action rows for adjacent behavior, preserved
  contracts, affected modes, browser evidence when needed, and coverage target
- For shared/lower-level owner changes, contains `3-Reviewer Regression Plan
  Review` with three `Missing Owner Count=0` rows
- For shared/lower-level owner changes, contains `Local/CI Gate Design`
- Contains: Evidence & Ownership details including abstraction owner, blast
  radius, generator/template impact, and proof for the verdict
- Contains: execution order (step-by-step sequence including regression checks)
- If an OpenSpec change exists, contains `OpenSpec Change: <change-id>` and `## OpenSpec Traceability`

**Then:** Update `docs/README.md` artifact index. **Present the decision package
to the user. Wait for explicit approval.**

**Gate: The user must explicitly approve the decision package before you
proceed. Do NOT start Phase 2 until the user confirms.** If the user requests
changes to the decision package, update the package and wait for approval again.

This gate applies even when the fix looks obvious, one-line, or urgent. A bug
report, stack trace, failed test, or user saying "handle this first" is not
approval to start implementation; only explicit approval of the proposed decision
package is.

This gate exists because:
- Fixing the wrong root cause wastes everyone's time
- The user may have context you don't (e.g., which compType actually triggers the bug)
- Reviewing a plan is cheap; reverting an incorrect fix is expensive

## Phase 2: Failing Test

Before writing or running the bug RED test, complete the regression baseline
gate:

1. Run the existing owner regression baseline identified in the approved
   decision package.
2. Record the command, exact GREEN count, and quality verdict.
3. If the baseline is `Insufficient`, add the old-GREEN
   characterization/regression tests named in the approved Regression Plan first
   and run them to GREEN on current code.
4. If the baseline is `Unavailable` or failing, stop until the baseline is
   recovered, explicitly re-scoped, or the user approves the documented
   substitute evidence.

Do not combine old-GREEN characterization coverage with the bug RED test. If the
first new test fails, it is not regression baseline coverage.

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

- **existing regression baseline command/result/quality verdict**
- **target test file**
- **target test command**
- **contract being proved** — the requirement or invariant the test enforces
- **regression coverage target** — adjacent behavior, preserved contracts, and
  browser/coverage proof needed before completion

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

### Behavior-preserving changes need old-green/new-green evidence

Some approved fixes include a behavior-preserving implementation change: the
intended user or business behavior stays the same, but code is rewritten,
logic is moved, rendering is replaced with an equivalent helper, parameters are
assembled differently, or a shared utility is reused.

For this class of change, a test that only passes on the new implementation is
not enough. Add the smallest characterization test for the behavior that must
stay unchanged, then run the same test in both states:

1. **Old GREEN** — apply only the new characterization test to the pre-change
   baseline, usually in a temporary worktree at the commit before the rewrite,
   and confirm it passes against the old implementation.
2. **New GREEN** — run the same test on the current implementation after the
   rewrite and confirm it still passes.

This evidence complements, but does not replace, the bugfix RED/GREEN proof.
If the old implementation fails the characterization test, the change is not
behavior-preserving; reclassify it as a behavior change or a newly discovered
bug and get approval for that scope.

## Phase 3: Fix

1. Implement the minimal fix — change only what's needed to make the failing test pass
2. Run the test again and confirm it passes:

```bash
pnpm vitest run <test-file>
```

3. Re-run the existing owner regression baseline and any added old-GREEN
   regression/characterization tests. They must remain GREEN.
4. For browser-visible bugs, rerun the Browser GREEN check defined in
   `wf-ui-browser-verification`.
5. Do NOT add features, refactor surrounding code, or update rules at this stage
6. Do not commit. Accumulate changes until Phase 4 is complete and the user
   explicitly approves the final commit.

**Gate: The previously failing test plus owner baseline/regression tests must
now pass. If any fail, keep fixing.**
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
pnpm check:workflow:completion -- --mode bugfix
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
| "I'll write the RED test first; existing tests can wait" | Run and judge the owner regression baseline first. If weak, add old-GREEN characterization before RED. |
| "The new RED test covers the regression too" | RED proves the bug. Regression/characterization preserves adjacent correct behavior and must be separate when the baseline is weak. |
| "The shared owner is an implementation detail, caller tests are enough" | Shared/lower-level changes need Owner/RP matrix rows and owner-level regression proof. |
| "I'll skip 3-reviewer review because the checker passed" | The checker is only a floor; shared/lower-level changes still need three fresh regression-plan reviews. |
| "Regression Plan says preserve/保留, so it's covered" | Use explicit actions: Existing GREEN, Add old-GREEN, RED, Post-fix GREEN, or N/A. |
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
