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

Execution order is part of the gate:

1. Baseline GREEN and quality-sufficient -> write the review-finding RED.
2. Baseline GREEN but quality-insufficient -> write old-GREEN
   characterization/regression coverage first, run it to GREEN, then write the
   review-finding RED.
3. Baseline unavailable or failing -> stop until the baseline is recovered or
   explicitly re-scoped.

Do not combine step 2 into the RED test. If the first new test fails, it is not
old-GREEN characterization coverage.

Hard rule: a new RED test does not replace existing regression baseline proof.
Do not edit production code until the original regression baseline is GREEN and
quality-sufficient, or the missing old-GREEN regression coverage has been added
and proven GREEN first.

## Phase 3.5: Confirmation Gate (MANDATORY)

**After verification, do NOT execute any fixes or resolves on your own.** You must first output a decision package and wait for user approval.

This gate applies even when:

- The user asks about one specific review finding.
- The finding looks obviously correct.
- You already fixed another finding in the same PR.
- A previous decision package existed before a new push, bot rerun, or missed
  review item was discovered.

If the inventory changed, the old approval is stale. Present the updated package
and wait for fresh approval before editing, committing, pushing, replying, or
resolving.

### Autonomous approval mode

If the user explicitly authorizes autonomous/self-directed handling for the
current PR triage loop, treat that as approval to proceed through Phase 4-5.5
without pausing at each new decision package. This is not permission to skip the
decision package. Instead:

1. Build the inventory and decision package internally before editing.
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

Produce a **decision package**, not one overloaded table. The package has five
blocks in this order. The decision table is only an index; detailed evidence,
regression planning, and execution steps live in their own tables so the fix
strategy remains visible.

### 1. Inventory Summary

Keep this short and factual. Include fetched counts, actionable counts, latest
head/time, and whether pagination completed.

```
| Source | Fetched | Actionable | Notes |
|---|---:|---:|---|
| Inline threads | 14/14 | 1 | hasNextPage=false |
| Review bodies | 22 | 0 | newest 2026-... |
| PR comments | 0 | 0 | - |
```

### 2. Decision Table

The decision table must answer "what will change and where do I inspect the
details?" Do not put long evidence, long regression lists, proposed replies,
or multi-sentence explanations in these cells.

`Fix Strategy` is mandatory for any real bug/style/code change. It must state
the owner-layer implementation approach, not the tests. If the table does not
make the proposed fix understandable without reading the regression plan, the
table is incomplete.

```
| # | Review Item | Verdict | Fix Strategy | Regression Plan | Evidence/Owner | Action |
|---|-------------|---------|--------------|-----------------|----------------|--------|
| 1 | zero-value clear | P2 Real bug | build explicit update map in payload owner | RP-1 | EO-1 | TDD-1 |
| 2 | payload path | P2 False positive | no code; hook already maps field to payload | RP-2 | EO-2 | Reply only |
```

### 3. Evidence & Ownership Table

Move detailed verdict notes here. Every decision row needs an
Evidence/Owner reference. Include the review comment original text and concise
Chinese translation outside the decision table, either in this table when short
or immediately below the table under the same `EO-*` ref.

```
| Ref | Source | Path | Evidence | Owner Layer | Blast Radius | Generator/Template |
|---|---|---|---|---|---|---|
| EO-1 | PRRT_xxx | [service/foo.go](/absolute/repo/service/foo.go:42) | `Updates(struct)` skips zero values; API allows clearing | service payload builder | API handler and update callers | N/A |
```

Required Evidence/Ownership fields:

- source thread/comment/review id and GitHub URL when available;
- clickable absolute local path and line;
- review comment original text and Chinese translation;
- concrete evidence for the verdict;
- abstraction owner and why lower-level call-site patches are not enough;
- repeated patch check / blast radius;
- generator/template impact, or `N/A`;
- closeout level / compatibility exception when relevant.

### 4. Regression Plan Table

Regression planning must not be a promise such as "preserve X". It must classify
each behavior by current coverage and the exact action needed.

Before listing behavior rows, emit an **Owner/RP Coverage Matrix** extracted
from `Fix Strategy`. This is a hard completeness check:

```
| Decision | Owner / Surface Changed By Fix Strategy | RP Group | Coverage Status |
|---|---|---|---|
| #1 | request wrapper `get/post` public API | RP-1A | covered |
| #1 | temporary auth helper | RP-1B | covered |
| #1 | caller `getOmConfigWithToken` | RP-1C | covered |
| #1 | caller `changePasswordWithToken` | RP-1C | covered |
```

If any owner/surface named in `Fix Strategy` has missing, blank, partial, or
caller-only `Coverage Status`, stop and complete the Regression Plan before
asking for approval. Do not bury this gap in prose.

Every owner layer named in `Fix Strategy` must appear in this table. If the fix
strategy changes a shared/lower-level API, create a separate `RP-*` group for
that owner before caller-level regressions. A decision package that changes a
request wrapper, shared hook, generator, script, or component contract but only
lists caller-level tests is incomplete.

Allowed `Regression Action` values:

- `Existing GREEN`: already covered; record the baseline command/result.
- `Add old-GREEN`: currently correct but uncovered/weak; add and prove it
  before the review-finding RED test or production code.
- `RED`: the review bug target; write a failing test that proves the bug.
- `Post-fix GREEN`: only provable after the implementation change.
- `N/A`: not applicable, with a short reason.

```
| Ref | Owner / Surface | Regression Scope | Behavior / Contract | Current Coverage | Regression Action | Test / Proof |
|---|---|---|---|---|---|---|
| RP-1A | request wrapper `get/post` | owner-level | default request behavior | Existing test covers wrapper | Existing GREEN | `pnpm test ./service` 42/42 |
| RP-1A | request wrapper `get/post` | owner-level | zero value clears field | Missing, bug target | RED | `testZeroValueClear` fails before fix |
| RP-1C | generated caller | caller | generated caller uses same payload owner | Missing but current behavior is correct | Add old-GREEN | generator/helper regression before RED |
```

If any row is `Add old-GREEN`, the first approved code action for that item is
that old-GREEN test. If any row is `Existing GREEN`, name the exact baseline
command and result. If the affected behavior is visible UI, include Browser
RED/GREEN here or explicitly mark Browser Regression `N/A` with a reason.

Before asking for approval, shared/lower-level owner changes must save the
decision package as a markdown artifact and run the lightweight checker:

```bash
node <skill-dir>/scripts/check-decision-package.mjs --mode pr-review --changed-files <comma-separated-changed-files> <decision-package.md>
```

For non-shared changes, run the checker whenever a decision-package artifact
exists. If the checker is not available in the current repo/skill installation,
say so and manually perform the same checks. The checker is a structural floor:
it requires a Decision Table, Owner/RP Coverage Matrix, shared owners from
`Fix Strategy` or `--changed-files` represented in the matrix, no invalid or
missing `Coverage Status`, and Regression Plan rows with explicit `Existing
GREEN`, `Add old-GREEN`, `RED`, `Post-fix GREEN`, or `N/A` actions rather than
only `preserve`/`保留` wording. For shared owners, the Regression Plan action
table must include an owner-level signal, such as
`Regression Scope=owner-level` or an `Owner / Surface` cell that matches the
matrix owner. The checker also requires three distinct real subagent/session
review sources and a `Local/CI Gate Design` with command, detector/gate/hook,
and failure rule. The `Evidence` cell must be a file path, relative to the
decision package, containing the actual subagent completion notification for the
matching `agent_path` with `no blockers`.

If `Fix Strategy` changes a shared/lower-level owner, run three independent
fresh reviews of the Owner/RP Coverage Matrix and Regression Plan before asking
for approval. Reviewers must check whether every shared owner named in
`Fix Strategy` has owner-level regression coverage, whether caller-only tests
are hiding a shared-owner gap, and whether missing old-GREEN coverage changes
the first approved code action. Revise until all three report zero missing
owner regression coverage. Record the result:

```
## 3-Reviewer Regression Plan Review
| Reviewer | Source | Missing Owner Count | Evidence | Notes |
|---|---|---:|---|---|
| A | 01900000-0000-4000-8000-000000000001 | 0 | evidence/subagent-a.json | RP group owner coverage, caller-only masking, first action checked |
| B | 01900000-0000-4000-8000-000000000002 | 0 | evidence/subagent-b.json | RP group owner coverage, caller-only masking, first action checked |
| C | 01900000-0000-4000-8000-000000000003 | 0 | evidence/subagent-c.json | RP group owner coverage, caller-only masking, first action checked |

## Local/CI Gate Design
Contract version: `2026-06-shared-owner-rp-v1`
Repo-local durable gate: `pnpm check:decision-package -- --mode pr-review --package docs/plans/example.md` (or `N/A: no repo-local gate found`)
Repo integration: `check:task` / pre-push / CI workflow path that calls the repo-local gate, or `N/A` with residual risk.
Skill-local fallback: `node <skill-dir>/scripts/check-shared-owner-regression-gate.mjs --mode pr-review --changed-files src/api/request.tsx --package docs/plans/example.md`
Gate: fail when a shared owner path changed but no package exists, no package passes, or the package lacks owner-level matrix/regression coverage.
Fallback warning: if repo-local durable gate is absent, state that CI will not enforce this rule yet.
```

### 5. TDD / Commit / Reply Plan

This table is execution-only. It should not explain the whole bug again.

```
| Ref | Sequence | Commit Plan | Checks | Reply Target |
|---|---|---|---|---|
| TDD-1 | old-GREEN -> RED -> fix -> GREEN | `fix(api): clear zero values` | focused tests + check:task + PR checks | PRRT_xxx after current-head green |
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
  inventory delta and decision package.
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
  characterization coverage must have been added and proven GREEN. If the
  approved `Regression Plan` names missing adjacent regression, coverage-only,
  or behavior-preserving characterization tests, add and run those tests first.
  Only then write the review-finding RED test and edit production code.
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
- Report the failure in the TDD / Commit / Reply Plan evidence.

```bash
# Run the specific test file to confirm failure
pnpm vitest run path/to/__tests__/file.test.tsx -t "test name"
```

**Required output in the TDD / Commit / Reply Plan for each fix:**

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
| Existing regression baseline is GREEN but quality-insufficient | STOP before RED. Add old-GREEN characterization/regression coverage first and prove it passes on current code. |
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
