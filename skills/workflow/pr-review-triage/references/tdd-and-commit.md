# TDD And Commit Reference

REQUIRED after a finding is approved or explicitly covered by autonomous mode and before editing, staging, or committing.

## Phase 3.4: Existing Regression Baseline Gate (MANDATORY)

Before writing a new RED test, editing production code, staging, committing,
pushing, replying, or resolving, run and evaluate the existing regression suite
for the owner layer touched by the review item.

Required evidence per review item:

- Existing regression command(s).
- GREEN result with exact test count, such as `32 passed` or `4 tests`.
- Quality judgment:
  - owner layer covered or missing;
  - affected entry path covered or missing;
  - adjacent modes covered or missing;
  - fallback, legacy, or negative behavior covered or missing.
- Decision:
  - `Sufficient`: proceed to the new RED test;
  - `Insufficient`: add old-GREEN characterization/regression tests first;
  - `Unavailable`: stop, explain the blocker, or use a clean temporary
    worktree if the current worktree is already contaminated.

Hard rule: a new RED test does not replace existing regression baseline proof.
Do not edit production code until the original regression baseline is GREEN and
quality-sufficient, or the missing old-GREEN regression coverage has been added
and proven GREEN first.

## Phase 3.5: Confirmation Gate (MANDATORY)

**After verification, do NOT execute any fixes or resolves on your own.** You must first output a decision table and wait for user approval.

This gate applies even when:

- The user asks about one specific review finding.
- The finding looks obviously correct.
- You already fixed another finding in the same PR.
- A previous decision table existed before a new push, bot rerun, or missed
  review item was discovered.

If the inventory changed, the old approval is stale. Present the updated table
and wait for fresh approval before editing, committing, pushing, replying, or
resolving.

### Autonomous approval mode

If the user explicitly authorizes autonomous/self-directed handling for the
current PR triage loop, treat that as approval to proceed through Phase 4-5.5
without pausing at each new decision table. This is not permission to skip the
decision table. Instead:

1. Build the inventory and decision table internally before editing.
2. Keep each review item in its own TDD/proof cycle and commit unless the user
   explicitly approved another grouping.
3. Reply/resolve only after current-head PR checks are green.
4. When new findings appear after a post-resolve re-fetch, continue the same
   loop if the user's authorization said to proceed until no new threads remain.
5. In the final report, include every decision-table row, commit, evidence,
   and thread resolution that would have been shown before execution.

Autonomous approval is single-use for this skill invocation. It expires when
the current PR triage loop reports completion, blocks, or the user switches to
another task. If the same chat later invokes this skill again, start in normal
confirmation mode unless the user gives a fresh autonomous authorization.

If the user's wording is ambiguous, stop and ask whether autonomous mode is
intended. Do not infer it from a casual "continue".

Output format:

Keep the table compact. Do not put long evidence, code snippets, proposed
reply text, or multi-sentence explanations inside table cells; they wrap badly
in chat UIs. Put long details under the table in per-item notes.
Reviewer comments often contain nuance that is easy to miss in English-only
tables. For every decision-table item, include the review comment's original
text and a concise Chinese translation in the per-item notes below the table.
Do not add these as wide table columns.

```
| # | File | Level | Verdict | Closeout | Impact Scope | Existing Regression Baseline | Regression Plan | Action | Thread(s) |
|---|------|-------|---------|----------|--------------|------------------------------|-----------------|--------|-----------|
| 1 | service/foo.go:42 | P2 | Real bug | L1/local | request payload owner; no generated code | GREEN 42/42; owner path sufficient | RED plus 100% branch regression | TDD fix + checks | PRRT_xxx |
| 2 | handler/bar.go:95 | P2 | False positive | L0/no code | handler only | GREEN 18/18; contract already covered | No new code; cite existing proof | Reply + resolve | PRRT_yyy |
| 3 | scripts/x.sh:12 | P2 | Deferred | L4/governance | shared CI helper | N/A no executable change | TODO, no code change | TODO + resolve | review body |
| 4 | service/baz.go:88 | P2 | Needs proof | L2/shared | shared hook + consumers | Missing/weak; add old-GREEN characterization first | Coverage-first test required | Coverage-first test | PRRT_zzz |
```

Then add short notes outside the table:

```
1. Summary: GORM skips zero values.
   Review comment (original): "..."
   Review comment (中文): "..."
   Evidence: `Updates(struct)` skips zero values; API allows clearing this field.
   Abstraction owner: service payload builder, because all callers share the same update contract.
   Repeated patch check: no duplicate call-site guards needed after the shared fix.
   Generator/template impact: N/A, not generated code.
   Impact scope: local service helper; downstream API handler covered.
   Closeout level: L1 in chogori model; current repo has equivalent focused test only.
   Test level: service helper RED plus API handler regression.
   Existing regression baseline: command `pnpm test ./service`; result GREEN 42/42; quality sufficient because owner helper path, API handler path, and non-zero update regression are covered before any new RED test.
   Test plan: RED `testZeroValueSkip`; Regression `testNonZeroUpdateStillWorks`; Coverage target 100% branch coverage for zero/non-zero payload selection via `pnpm vitest run ... --coverage`; Browser Regression N/A: API-only payload formatting; GREEN after map/select update.
   Full gate policy: no local full gate; wait for pre-push/provider CI after batch push. Exception: run repo-required full gate for L3/L4, governance, security, permission, audit, data-scope, or user-requested checks.
   Compatibility exception: N/A, repo has focused tests and PR checks. If missing, name the missing standard, substitute evidence, and residual risk.
   Planned reply: Fixed in `{hash}` after PR checks pass.
```

Then ask the user: **"Do you agree with this plan? Any changes needed?"**

- After user confirms: execute Phase 4 (TDD Fix Cycle) for each approved fix
  item, then create the per-review commits, push the completed batch, wait for
  PR checks, reply/resolve the old approved threads when the pushed head is
  green, and only then re-fetch review inventory for new threads/findings.
  Continue directly from GREEN verification into the per-review commit batch.
- **Batch by default after approval**: keep each real bug, style fix, coverage
  fix, or TODO/doc change in its own commit, but do not push, reply, or resolve
  between findings. Push the completed local commit batch once in Phase 4.5,
  then wait for PR checks once on the resulting head SHA.
- Reply and resolve all approved old findings together in Phase 5 only after
  the batch head is green. False-positive, already-fixed, and deferred/no-code
  findings still wait for the same final reply/resolve pass when there are code
  changes in the batch. New findings discovered after that pass require a fresh
  inventory delta and decision table.
- Use a per-finding push/check loop only when the user explicitly asks for it,
  when the batch is too risky to review coherently, or when an urgent isolated
  hotfix must be landed before continuing.
- If user modifies decisions: execute per their modified version
- **NEVER skip this step**

## Phase 4: TDD Fix Cycle

**For every finding with verdict "Real bug" or "Style issue" that requires a code fix, you MUST follow the TDD Red-Green-Refactor cycle.** This applies to ALL fixes — no exceptions, no shortcuts.

### The Iron Law

**NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.**

Write fix before test? DELETE IT. Start over.

### Red-Green-Refactor Cycle

#### Step 4a: RED — Write Failing Test

Write a test that reproduces the exact bug identified in the review finding.

- The test MUST target the specific issue: wrong behavior, missing edge case, type violation, etc.
- This RED test is not automatically sufficient regression coverage and does
  not replace Phase 3.4. Before writing this RED test, the existing regression
  baseline must already be GREEN and quality-sufficient, or missing old-GREEN
  characterization coverage must have been added. Before editing production
  code, also list the necessary regression tests from Phase 3b.5.1. Add them
  before or immediately after the minimal fix, and run them in the GREEN
  verification.
- For user-visible fixes, include Browser Regression in the approved plan:
  Browser RED when proving the UI bug and Browser GREEN when proving adjacent
  visible behavior still works. If browser coverage is not needed, record the
  reason before editing production code.
- If the approved fix includes a behavior-preserving implementation change,
  also apply `wf-bugfix`'s old-green/new-green characterization rule. Do not
  duplicate that rule here; `wf-bugfix` is the source of truth for this
  evidence standard.
- For UI findings whose bug exists at the user boundary, follow
  `wf-ui-browser-verification` for Browser RED/GREEN evidence. Do not duplicate
  that skill's browser-evidence rules here.
- Run the test — it MUST FAIL. If it passes, your test is wrong (it doesn't actually catch the bug).
- Report the failure in the decision table reply.

```bash
# Run the specific test file to confirm failure
pnpm vitest run path/to/__tests__/file.test.tsx -t "test name"
```

**Required output in decision table for each fix:**

```
RED: test_name — FAILS as expected (reproduces the bug)
```

For browser-visible findings, also record Browser RED using the evidence format
defined in `wf-ui-browser-verification`.

#### Step 4b: GREEN — Minimal Fix

Write ONLY the minimum code to make the test pass.

- No extras. No "while I'm here" improvements.
- No unrelated refactors.
- If the reviewer proposed a specific fix approach, compare it against your own (see Phase 3c).

```bash
# Run the test to confirm it now passes
pnpm vitest run path/to/__tests__/file.test.tsx -t "test name"

# Run the necessary regression tests named in the approved plan
pnpm vitest run path/to/__tests__/file.test.tsx -t "regression test name"

# Run the coverage command named in the approved plan when local tooling supports it
pnpm vitest run path/to/__tests__/file.test.tsx --coverage
```

**Required output:**

```
GREEN: test_name — PASSES (bug fixed)
REGRESSION: regression_test_name — PASSES (adjacent behavior preserved)
COVERAGE: affected_path — 95%+ covered, or 100% for critical decision paths; command/evidence recorded
BROWSER REGRESSION: /route -> action — PASSES, or N/A with reason
```

For browser-visible findings, rerun Browser GREEN using
`wf-ui-browser-verification`.

#### Step 4c: REFACTOR — Clean Up (if needed)

Only if the minimal fix introduced duplication or made the code harder to read:

- Improve code quality in the affected area
- Run ALL tests after each change — must stay green
- No scope creep

```bash
# Run full test suite for the affected domain
pnpm vitest run path/to/__tests__/
```

### TDD Enforcement Rules

| If | Then |
|----|------|
| Existing regression baseline missing before RED/fix | STOP. Run owner regressions, record GREEN count and quality, or add old-GREEN characterization first. |
| Fix code written before test | STOP. Delete fix code. Write test first. |
| Test passes on first run (before fix) | Test is wrong — it didn't catch the bug. Rewrite it. |
| Multiple bugs fixed in one cycle | STOP. One test per bug. Separate cycles. |
| Test doesn't specifically target the bug | Rewrite test to assert the exact condition from the review finding. |
| Fix has no regression coverage plan | STOP. Add necessary regression tests or record why none are needed before editing production code. |
| Fix has no coverage assessment for the touched code | STOP. Add the coverage target and proof command to the plan before editing production code. |
| Affected code stays below 95%, or a critical path stays below 100%, without approved justification | STOP. Add coverage or get explicit approval for the documented limitation before committing. |
| User-visible fix has no Browser Regression plan | STOP. Add Browser RED/GREEN where needed, or record why component/unit coverage is sufficient. |
| Regression test fails after GREEN | Fix the regression before proceeding; the review item is not complete. |
| UI bug has only unit RED but no browser RED | Follow `wf-ui-browser-verification` for Browser RED before fixing, or stop and ask the user to approve a substitute evidence standard. |
| Fix breaks other tests | Fix the regression before proceeding. All tests must pass. |

## Phase 4.4: Per-Review Commit Plan (MANDATORY)

After all approved TDD cycles are GREEN and before running any `git add` or
`git commit`, prepare a compact commit plan that maps review items to commits.
This plan is the grouping rule for execution; it is **not** a separate approval
gate. Once the grouping is clear, stage and commit automatically.

This plan applies to every commit created during review triage, including:

- Real bug/style fixes.
- Coverage-only commits for false positives or proof-first checks.
- TODO/doc commits.
- CI-repair commits after a pushed batch fails checks.

Required commit plan format:

```
Commit plan:
| Commit | Review item(s) | Thread(s) | Files | Message |
|--------|----------------|-----------|-------|---------|
| 1 | #2 Clear temporary session | PRRT_xxx | a.ts, a.test.ts | fix(auth): clear temporary session on sign out |
| 2 | #3 Preserve root employee id | PRRT_yyy | b.ts, b.test.ts | fix(auth): preserve contractor employee root fields |
```

Hard gates:

- Do not stage or commit until the per-review grouping and messages are clear.
- If files for multiple review items overlap, use partial staging, temporary
  patch extraction, or another non-destructive method to keep commits grouped by
  review item. If clean separation is not practical, stop and ask the user to
  approve the exception before committing.
- A broad "fix all review comments" commit is forbidden unless the user
  explicitly approves that exact grouping after seeing the commit plan.
- A follow-up CI repair commit must be grouped by the independent CI root cause.
- The commit plan must show one commit per deduped review item by default. If
  two independent review items would be grouped, stop and ask the user to
  approve that exact exception.
- Each commit row must include the source/test files that prove RED, regression
  coverage, coverage target, and Browser Regression evidence when applicable.

### Per-Review Commit Strategy

Each review item/finding produces one commit by default. "Review item" means
the deduped decision-table row, including all duplicate inline threads or review
body findings mapped to that row.

Valid grouping:

- One real bug/style finding -> one fix commit containing its RED/GREEN test,
  necessary regression tests, coverage proof for the affected path, Browser
  Regression evidence when needed, and minimal source changes.
- One false-positive coverage item -> one test-only coverage commit, if the
  approved plan keeps coverage.
- One deferred item -> one TODO/doc commit.
- Duplicate comments for the same deduped finding -> one commit that references
  all mapped threads/comments.
- CI failures after push -> one repair commit per independent root cause, not
  one blob commit for all failed jobs.

Invalid grouping:

- One aggregate commit for multiple independent review items.
- Mixing a false-positive coverage-only item with a real bug fix.
- Mixing CI repair with an unrelated review fix.

After preparing the commit plan, create the commits exactly as planned:

```bash
git add <test_file> <source_file>
git commit -m "fix(scope): description of the fix"
```

When the repository commit policy allows a body, include the review URL or
thread/comment identifier in the commit body to preserve traceability:

```bash
git commit -m "fix(scope): description of the fix" \
  -m "Review: https://github.com/{owner}/{repo}/pull/{number}#discussion_r..."
```

Keep the subject project-style. Never add AI attribution, assistant footers, or
co-author trailers.

The commit hash is then referenced in the reply to the review thread after PR
checks pass (see Phase 4.5 and Phase 5).
