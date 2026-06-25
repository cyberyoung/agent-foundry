---
name: wf-pr-review-triage
description: "Use when a GitHub PR has unresolved review threads, bot review findings, failing PR checks after review fixes, or the user asks to handle, triage, reply to, or resolve PR feedback."
---

# PR Review Comment Triage

## Overview

Systematically process PR review feedback: fetch the full review inventory,
verify each finding, fix real issues with TDD, commit review items separately,
push safely, wait for current-head PR checks, reply/resolve, then re-fetch until
no actionable feedback remains.

**Target standard:** use the chogori-style model where possible: closeout level,
owner-layer fix, shared blast radius, regression coverage target, per-item
commits, provider PR checks, and post-resolve inventory. If a repository lacks a
capability, record the fallback evidence and residual risk.

## Pressure-Tested Hard Gates

These gates exist because real PR triage runs failed without them:

- **Autonomous user approval is allowed only when explicit.** If the user says
  they authorize autonomous/self-directed handling, do not pause at the
  confirmation gate; instead record the inventory, decision package, TDD proof,
  commit grouping, push/check evidence, and final post-resolve inventory in the
  report. Without that explicit wording, stop for approval at Phase 3.5.
- **Autonomous approval is single-use.** It expires when the current PR triage
  loop reports completion, blocks, or the user switches tasks. If the same chat
  later invokes this skill again, start in normal confirmation mode unless the
  user gives fresh autonomous authorization.
- **Existing regression baseline is mandatory before RED or fixes.** Before
  adding a new failing test or editing production code, run the existing owner
  regression tests, record the GREEN count, judge whether their quality covers
  the affected owner path and adjacent modes, and show that verdict in the
  decision package. If the baseline is missing or weak, add old-GREEN
  characterization/regression coverage first.
- **Shared/lower-level owner changes require 3-reviewer regression-plan review.**
  If `Fix Strategy` changes a request wrapper, shared component/hook, public
  helper/API surface, generator/template, workflow script/gate, or other
  lower-level owner, the Owner/RP Coverage Matrix and Regression Plan must get
  three independent fresh reviews before approval. Continue revising until all
  three report zero missing owner regression coverage, and record the reviewer
  result in the decision package. If subagents are unavailable, stop and request
  explicit user approval for the manual substitute.
- **Weak baseline changes the first code action.** When the decision package says
  the existing baseline is `Insufficient`, the first approved code change must
  be an old-GREEN characterization/regression test that passes on current code.
  A review-finding RED test before that old-GREEN proof is a gate violation,
  even if the RED would correctly reproduce the bug.
- **Push preflight is mandatory before every remote update.** Before `git push`,
  inspect the remote branch, ahead commits, and diff scope. Stop for user
  confirmation if the push would create/recreate a remote branch or the diff
  scope exceeds the approved PR-review work.
- **Provider checks must be current-head proof.** Do not reply or resolve after
  a push until the PR's current `headRefOid` equals local HEAD and required
  checks have completed successfully on that SHA.
- **Post-resolve wait is part of done.** After replying/resolving, wait the
  user-specified window; if none is specified, use a short stabilization window
  appropriate for the repo. Then re-fetch full inline threads, review bodies,
  and PR-level comments.
- **Do not let helper env vars pollute nested tests.** Prefer configuring the
  real dependency path, such as `SYNC_TARGET_*`, over broad allow-missing env
  variables when running full hooks. Scope broad overrides to the one command
  that needs them and record the exception.

## Required References

Read these files at the named phase. Do not keep plowing ahead from this summary
when the phase says a reference is required.

| Phase | Required reference | When to read |
| --- | --- | --- |
| Inventory | `references/inventory.md` | Before classifying, fixing, replying, or resolving anything. |
| Verification | `references/verification.md` | While deciding verdict, owner layer, coverage, API/OAS, UI/browser, or false-positive status. |
| TDD + commits | `references/tdd-and-commit.md` | Before presenting the decision package, writing production code, staging, or committing. |
| Decision package check | `<skill-dir>/scripts/check-decision-package.mjs` | Before asking for approval. Shared/lower-level owner changes must save a markdown decision package and run it; if the checker is absent in a repo copy, say so and do the same checks manually. |
| Push + CI | `references/push-checks-and-ci.md` | Before push; whenever checks fail, do not appear, or CI/coverage/workflow logic changed. |
| Reply + report | `references/reply-resolve-report.md` | After PR checks are green and before resolving or reporting completion. |

## Quick Flow

1. Fetch inventory. REQUIRED: `references/inventory.md`.
2. Classify and verify every deduped item. REQUIRED: `references/verification.md`.
3. Before the decision package, run the existing owner regression baseline or
   record why it is unavailable; include GREEN count and quality verdict.
4. REQUIRED: read `references/tdd-and-commit.md`, because it defines the Phase
   3.5 decision package format and approval gate.
5. For shared/lower-level owner changes, save the decision package as a markdown
   artifact and run
   `node <skill-dir>/scripts/check-decision-package.mjs --mode pr-review --changed-files <comma-separated-changed-files> <artifact>`
   before approval. Shared/lower-level owner changes must provide the branch or
   staged changed-file list. The checker also falls back to git diff and fails
   closed when no changed-file source is available; use
   `--no-require-changed-files` only for explicit manual document-only checks
   with residual risk. For non-shared changes, run the checker when an artifact
   exists. If the checker is not available, report that and manually verify the
   same structure before approval.
6. For shared/lower-level owner changes, run three independent reviews of the
   Owner/RP Coverage Matrix and Regression Plan to missing-owner count `0`, and
   document `Local/CI Gate Design`.
7. Present the checked decision package and wait, unless explicit autonomous
   approval is active for this invocation.
8. TDD fix each real issue.
9. Commit each review item separately by default.
10. Run push preflight, push, and wait for current-head PR checks. REQUIRED:
   `references/push-checks-and-ci.md`.
11. Reply and resolve old approved threads only after checks are green.
12. Wait the stabilization window and re-fetch inventory. REQUIRED:
   `references/reply-resolve-report.md`.
13. Repeat if new findings appear; otherwise report with evidence table.

## Inventory Completeness Gate

Never act on a pasted single comment alone. Complete inventory means:

- inline review threads fetched with GraphQL pagination until `hasNextPage=false`;
- review bodies fetched with REST pagination;
- PR-level comments fetched with REST pagination;
- dedupe by finding while still replying/resolving every unresolved thread;
- fetched counts and latest commit/head recorded.

If any source is incomplete, stop.

## Verification Gate

Judge by first principles: is the current code wrong? Do not dismiss a finding
because it seems pre-existing or outside this PR. Before calling a finding real,
prove reachability, contract violation, and failing or failure-capable test
evidence. For shared components, hooks, scripts, generators, workflow gates, or
payload builders, fix the owner layer rather than patching one call site.

For visible UI behavior, async user-action timing, form defaults, enabled state,
toasts, navigation, uploads, or loading/error states, use browser/user-boundary
verification unless the decision package explicitly records why unit/component
coverage is sufficient.

Shared UI/component state contract check: when a review-comment path touches a
shared component, hook, state container, or modal/drawer contract, inspect the
existing call sites before judging or fixing. For `defaultXxx`, `value`,
`activeXxx`, `onChange`, and `onXxxChange`, decide whether the prop is an
initial default or a controlled state contract, whether the reviewer is asking
for new controlled behavior, and whether the change would break an existing
interaction path. Real fixes must cover the shared owner and adjacent callers,
not only the single reviewed path.

Shared script/file maintenance check: for CI scripts, generated files, managed
blocks, shared helpers, or files marked `shared with ...`, decide whether the
change is repo-specific config or shared behavior. If shared behavior changes,
sync the consumer repo/file or record an explicit non-sync reason and verify the
consumer gate. Do not edit the upstream
`receiving-code-review/SKILL.md`; keep local workflow hardening in this skill
and repo-level rules.

## Decision Package Structure Check

The decision package is a structured artifact, not prose. It must contain:

- `Decision Table`
- `Inventory Summary`
- `Owner/RP Coverage Matrix`
- `Evidence & Ownership`
- `Regression Plan`
- `TDD / Commit / Reply Plan`
- `3-Reviewer Regression Plan Review` for shared/lower-level owner changes
- `Local/CI Gate Design` for shared/lower-level owner changes

Before asking for approval, shared/lower-level owner changes must save the
decision package as a markdown artifact and run the lightweight checker:

```bash
node <skill-dir>/scripts/check-decision-package.mjs --mode pr-review --changed-files <comma-separated-changed-files> <decision-package.md>
```

For non-shared changes, run the checker whenever a decision-package artifact
exists. If the checker file is not present in the current repo/skill
installation, say so explicitly and manually perform the same checks. The
checker is a floor, not the whole review: it catches missing structure,
invalid or missing `Coverage Status`, shared owners named in `Fix Strategy` or
detected from `--changed-files` but absent from the matrix, and Regression Plan
rows that only promise `preserve`/`保留` without `Existing GREEN`, `Add
old-GREEN`, `RED`, `Post-fix GREEN`, or `N/A`. For shared owners, it also
requires owner-level Regression Plan rows, three reviewer rows with distinct
real subagent/session ids and `Missing Owner Count=0`, plus `Local/CI Gate
Design` containing a concrete command, detector/gate/hook, and failure rule.
The checker reads the `Evidence` file paths in that table and expects each file
to contain the actual subagent completion notification for the matching
`agent_path` with `no blockers`. Keep those notification files with the decision
package; do not replace them with hand-written session ids.

For any shared/lower-level owner change, run three independent fresh reviews of
the Owner/RP Coverage Matrix and Regression Plan before approval. The reviewers
must specifically answer whether every shared owner named in `Fix Strategy` has
owner-level regression coverage, whether caller-only coverage is hiding an owner
gap, and whether the first code action is correct when old-GREEN coverage is
missing. Record a `3-Reviewer Regression Plan Review` table and do not proceed
until the missing-owner count is zero for all three reviews.

### Local/CI Gate Design

The gate design must make "shared owner changed but no owner regression plan"
mechanically hard to miss, not merely promise a future improvement:

1. Require decision packages to be saved as markdown artifacts for PR triage
   work that changes shared owners.
2. Run `<skill-dir>/scripts/check-decision-package.mjs` locally before approval
   for the specific decision package.
3. Wire `<skill-dir>/scripts/check-shared-owner-regression-gate.mjs` into the
   repo's task/workflow gate, pre-push hook, or CI job. This wrapper is the
   actual local/CI gate: it detects changed shared owner files, fails when no
   decision package is supplied, and invokes the package checker with the
   detected changed files.
4. Add or configure a repo-specific changed-file source for the wrapper when
   the default git detector is not enough. The default detector covers tracked,
   staged, and untracked files; explicit `--changed-files` or
   `DECISION_PACKAGE_CHANGED_FILES` may be used by CI.
5. Fail the local/CI gate if a flagged owner has no matrix row, has missing,
   blank, partial, caller-only, or otherwise invalid `Coverage Status`, or only
   has caller-level Regression Plan rows.
6. Allow explicit `N/A` only with a reason and owner-level substitute evidence.
7. If the repo cannot wire the gate in the same PR, record the fallback command,
   the missing integration point, and the explicit residual risk in
   `Local/CI Gate Design`; do not describe that as implemented CI coverage.

Evidence levels:

- `Implemented local/CI gate`: `check-shared-owner-regression-gate.mjs` or a
  repo wrapper around it is wired into `check:task`, hook, workflow, or
  equivalent gate.
- `Local checker only`: the decision package passed the checker, but the repo
  has no durable gate yet; record fallback and residual risk.
- `Manual substitute`: checker or changed-file input is unavailable; stop for
  explicit user approval and keep the manual checklist in the package.

## Confirmation And Autonomous Mode

Default mode: after verification, output the decision package and wait for user
approval before edits, commits, pushes, replies, or resolves.

Autonomous mode: only if explicitly authorized for this invocation, proceed
without pausing, but still build the decision package internally and include every
row, commit, test, check, reply, and resolution in the final report. Ambiguous
phrases such as "continue" do not enable autonomous mode.

## TDD And Coverage Gate

No production code without a failing test first. The RED test must reproduce the
review finding. GREEN must include the focused test, necessary adjacent
regressions, owner suite where appropriate, and the narrowest coverage evidence
available. Target 95%+ for affected paths and 100% for critical decision paths
such as data loss, authorization, submit payloads, destructive actions,
navigation, uploads, and async user-action gates.

If a repo gate fails because a plan/evidence/coverage-plan artifact is missing,
add the smallest correct artifact update and re-run the gate. Do not bypass by
weakening scope/mode or hiding the source change. Details:
`references/push-checks-and-ci.md#repo-gate-planevidence-supplement-path`.

## Commit Gate

Prepare a compact per-review commit plan after GREEN and before staging. One
deduped review item gets one commit by default. If clean separation is not
practical, stop for user approval before grouping. Commit messages must be plain
project-style and must not contain AI attribution or co-author trailers.

## Push And PR Checks Gate

Before push, run push preflight and inspect remote branch, ahead commits, and
diff scope. For workflow/CI/coverage changes, run the false-pass audit in
`references/push-checks-and-ci.md`: artifact visibility, aggregate jobs,
shard status sidecars, exact provider check matching, provider URLs, and current
head SHA.

After push, wait for PR checks on the pushed local HEAD. If checks fail, enter
CI triage. If checks do not appear, diagnose head/workflow/branch filters and
only create a retrigger commit when safe and recorded. Never resolve threads on
absent, stale, pending, failed, or wrong-SHA checks.

## Reply, Resolve, And Final Cross-Check

Every inline thread gets a reply before resolve. Prefer GraphQL
`addPullRequestReviewThreadReply` when a thread ID is available; REST comment
reply is fallback only.

After resolving, wait the stabilization window, then re-fetch inline threads,
review bodies, and PR-level comments with complete pagination. Report complete
only when all full sources show no unresolved/actionable items.

## Final Report

Use user-specified columns first when provided. Always include commit/topic,
GitHub review location, current-head change location, regression test location,
review problem, fix strategy, result, and any standard/actual/exception
fallbacks. Name local checks, changed-line coverage, pre-push result, provider
PR checks, final head SHA, and post-resolve inventory.

## Red Flags

| Wrong approach | Correct approach |
| --- | --- |
| Act on one pasted comment | Fetch full paginated inventory first. |
| Treat bot text as fact | Verify code/API/OAS/installed contracts and test failure power. |
| Write fix before RED | Delete it and restart with a failing test. |
| Patch a call site for shared behavior | Fix the owner layer and cover it there. |
| Skip browser proof for visible behavior | Verify at the user-action boundary or record why not needed. |
| Push without preflight | Inspect remote branch, ahead commits, and diff scope first. |
| Use broad env overrides for full hooks | Prefer real target env such as `SYNC_TARGET_*`; scope exceptions tightly. |
| Treat missing checks as green | Diagnose and safely retrigger; never resolve on absent checks. |
| Assume CI green means no false-pass path | Audit artifacts, aggregate gates, shard statuses, and provider proof. |
| Change a shared owner with caller-only regressions | Add Owner/RP matrix rows and owner-level regression proof for the shared surface. |
| Skip 3-reviewer review for shared/lower-level changes | Run three fresh reviews of the matrix/regression plan and clear all missing-owner findings. |
| Write Regression Plan as "preserve/保留 old behavior" | Use explicit actions: Existing GREEN, Add old-GREEN, RED, Post-fix GREEN, or N/A. |
| Resolve before current-head checks are green | Wait for provider checks on local HEAD. |
| Finish immediately after resolving | Wait, re-fetch full inventory, then decide. |
| Ignore user's report columns | Use them first, then add missing audit columns. |
