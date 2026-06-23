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
  confirmation gate; instead record the inventory, decision table, TDD proof,
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
  decision table. If the baseline is missing or weak, add old-GREEN
  characterization/regression coverage first.
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
| TDD + commits | `references/tdd-and-commit.md` | Before presenting the decision table, writing production code, staging, or committing. |
| Push + CI | `references/push-checks-and-ci.md` | Before push; whenever checks fail, do not appear, or CI/coverage/workflow logic changed. |
| Reply + report | `references/reply-resolve-report.md` | After PR checks are green and before resolving or reporting completion. |

## Quick Flow

1. Fetch inventory. REQUIRED: `references/inventory.md`.
2. Classify and verify every deduped item. REQUIRED: `references/verification.md`.
3. Before the decision table, run the existing owner regression baseline or
   record why it is unavailable; include GREEN count and quality verdict.
4. Present a decision table and wait, unless explicit autonomous approval is
   active for this invocation.
5. TDD fix each real issue. REQUIRED: `references/tdd-and-commit.md`.
6. Commit each review item separately by default.
7. Run push preflight, push, and wait for current-head PR checks. REQUIRED:
   `references/push-checks-and-ci.md`.
8. Reply and resolve old approved threads only after checks are green.
9. Wait the stabilization window and re-fetch inventory. REQUIRED:
   `references/reply-resolve-report.md`.
10. Repeat if new findings appear; otherwise report with evidence table.

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
verification unless the decision table explicitly records why unit/component
coverage is sufficient.

## Confirmation And Autonomous Mode

Default mode: after verification, output the decision table and wait for user
approval before edits, commits, pushes, replies, or resolves.

Autonomous mode: only if explicitly authorized for this invocation, proceed
without pausing, but still build the decision table internally and include every
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
| Resolve before current-head checks are green | Wait for provider checks on local HEAD. |
| Finish immediately after resolving | Wait, re-fetch full inventory, then decide. |
| Ignore user's report columns | Use them first, then add missing audit columns. |
