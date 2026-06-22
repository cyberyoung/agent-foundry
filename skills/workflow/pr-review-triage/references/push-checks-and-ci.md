# Push Checks And CI Reference

REQUIRED before any push and whenever PR checks fail, do not appear, or could false-pass because CI/coverage/workflow behavior changed.

## Phase 4.5: Push + PR Checks Gate (MANDATORY for code fixes)

For every item that changes code, tests, docs, generated files, scripts, or
configuration, do not reply or resolve yet. First finish all approved local
review-item commits, then push the batch once, wait for PR checks on the
current head SHA, and handle failures.

### Local full-gate policy

Do not use `check:all`, workflow completion, branch-wide coverage, or equivalent
full gates as the default local proof for PR review triage. The default local
proof is:

1. RED/GREEN focused test for each real bug or coverage-first finding.
2. Owner suite for the touched abstraction.
3. Browser/user-boundary proof when the reviewed behavior is visible UI.
4. Cheap hygiene checks such as `git diff --check` when applicable.
5. Pre-push hooks and provider PR checks after the batched push.

Run local full gates only when one of these is true:

- the user explicitly requests them;
- the repository's rules mark the current batch as L3/L4, phase/feature exit,
  pre-PR, pre-merge, or governance closeout;
- the batch changes workflow gates, CI, checkers, coverage policy, OpenSpec
  traceability, hooks, or AGENTS-style repo policy;
- the batch touches security, permission, audit, data-scope, protected data,
  or LLM boundary code and the focused/owner/provider evidence is not enough;
- provider CI is unavailable and the repository's local full gate is the only
  remaining substitute proof.

If you skip a repo-declared hard gate, record the exact allowance. "It was slow"
is not enough. Valid allowances are user approval, an explicit repo/skill
deduplication rule, or already-run pre-push/provider checks that cover the same
gate. Otherwise stop and ask.

The default is: **one commit per review item/finding, one push per approved
batch, one PR checks wait per pushed head SHA**. This keeps rollback and audit
history clean without paying the full PR checks latency for every review
finding.

### Push preflight (MANDATORY)

Before every `git push`, run and inspect a push preflight for the current
branch:

```bash
git status -sb
git ls-remote --heads origin "$(git branch --show-current)"
git log --oneline @{u}..HEAD 2>/dev/null || true
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
git diff --name-only origin/main...HEAD
```

Stop and ask for explicit confirmation if the remote branch is missing, the
push would create/recreate a branch, the upstream/ahead state is unclear, or
the diff scope is larger than the approved review-triage work. If the broad
branch diff is expected because the PR already contains that scope, say so and
still inspect the new commits since upstream.

### Pre-push environment hygiene

When local hooks require sibling repositories or external paths, prefer the
real explicit target environment (for example `SYNC_TARGET_LHOTSE=/path`) over
allow-missing flags. Broad flags such as
`CHECK_SHARED_SYNC_ALLOW_MISSING_TARGETS=1` can leak into nested test processes
and make tests pass or fail for the wrong reason. Scope broad overrides to the
single command that needs them; do not use them for a full `git push` hook
unless the repository explicitly documents that behavior.

### CI false-pass audit for workflow/coverage changes

For changes to CI, coverage, workflow gates, artifact upload/download, provider
checks, or merge-readiness validation, add a targeted false-pass audit before
replying/resolving:

- Artifact paths are uploadable by the configured action defaults; hidden
  directories either use `include-hidden-files: true` or are avoided.
- Aggregate jobs that must gate shard failures use `if: ${{ always() }}` or an
  equivalent mechanism and explicitly inspect shard status/results.
- Shard jobs that emit partial artifacts also emit enough status sidecar data
  for the aggregate job to fail closed.
- Provider-backed rows must match the required check name exactly, include
  provider status source details, include provider URL evidence, and match the
  current head SHA.
- Local automation rows must not satisfy provider-only final-check evidence.

Record the false-pass audit result in the decision notes and final report.

1. Confirm the Phase 4.4 per-review commit plan exists and matches the
   approved decision-table items.
2. Confirm every approved fix/deferred/test-only item has its own local commit
   grouped by review item, or that the user explicitly approved a documented
   exception.
3. Confirm the commits have not been pushed one by one; the default is a single
   batch push after all approved per-review commits are complete.
4. Push the branch containing the completed commit batch.
5. Capture the head SHA after push: `git rev-parse HEAD`.
6. Wait until PR checks for that SHA finish.
7. If any check fails or is cancelled, do NOT reply/resolve review threads.
   Enter the CI failure triage loop below.
8. If the pushed SHA has no check suite/status rollup after a reasonable wait,
   do not treat that as success. Verify the pushed head, workflow YAML, branch
   filters, and Actions state. If the code is correct but GitHub did not create
   checks, create an explicit retrigger commit only when it is safe and record
   the reason.
9. Only continue to Phase 5 when all required PR checks for the current head SHA
   are successful.
10. **Do not re-fetch new review inventory before replying/resolving the old
   approved threads.** The old batch has already been inventoried, classified,
   approved, fixed/deferred/dismissed, and validated by green checks. Reply and
   resolve those old threads first in Phase 5; then run the post-resolve
   inventory in Phase 5.5 to discover any new bot review bodies or inline
   threads created for the pushed head.


### Repo gate plan/evidence supplement path

When a repository gate fails because a required plan, evidence file, coverage
plan row, UI matrix, or completion artifact is missing, treat that as part of
the review item closeout rather than as optional paperwork.

1. Read the failing gate message and identify the exact required artifact,
   heading, row, or evidence link.
2. Add the smallest relevant plan/evidence update in the task's existing
   artifact when one exists. Do not create duplicate plans just to satisfy the
   gate.
3. Map the changed source file to the focused regression command and coverage
   proof. For changed executable source, include the changed-line coverage
   command or the narrowest available substitute.
4. Re-run the failing gate before committing.
5. Include the supplemental artifact path and line in the final report.

Do not bypass the gate by weakening mode/scope, hiding the source change, or
using a broad exemption unless the repository explicitly allows that exemption
and the final report names the residual risk.

### CI failure triage loop

When checks fail after a batch push, treat the failed checks as a new triage
batch:

1. Collect all failed check names, job logs, annotations, failed test files,
   and failed test case names before editing anything.
2. Classify each failure with evidence:
   - **External/transient/infrastructure**: service outage, cancelled run,
     Actions minutes exhausted, missing billing/runner capacity, network-only
     failure, or unavailable external dependency. Rerun failed jobs when
     appropriate; do not create a code commit unless the repository code truly
     needs resilience.
   - **Real regression from this review batch**: reproduce locally when
     possible, identify the root cause, and fix it.
   - **Ambiguous**: narrow by path/test ownership and commit history. Use a
     targeted local test or git diff inspection before deciding.
3. Group real failures by root cause, not by CI job or individual test case.
   If one bug makes five tests fail, make one fix commit. If three independent
   causes fail, make three fix commits.
4. For each independent real root cause, use the same discipline as Phase 4:
   RED/confirm failure when possible → GREEN fix → local commit.
5. Push all CI-repair commits together, then wait for PR checks again on the new
   head SHA.
6. Repeat until checks pass or the remaining failure is proven external and
   requires user/admin action.

Prefer follow-up CI-repair commits over rewriting the original review-item
commits unless the user explicitly asks to amend/squash. The original commits
preserve which review finding each fix addressed; the repair commits preserve
what the checks revealed.

If multiple failed checks appear at once:

- Independent failures: one local repair commit per root cause, then one push.
- Same root cause across many files/cases: one local repair commit.
- Pure flaky/external failure: rerun or report blocker with log evidence; no
  code commit.

Example check wait loop:

```bash
HEAD_SHA="$(git rev-parse HEAD)"
while true; do
  state="$(gh pr view {number} --json headRefOid,statusCheckRollup)"
  echo "$state" | jq '{headRefOid, checks: [.statusCheckRollup[] | {name,status,conclusion}]}'

  current_sha="$(echo "$state" | jq -r '.headRefOid')"
  failed_count="$(echo "$state" | jq '[.statusCheckRollup[] | select(.status == "COMPLETED" and (.conclusion != "SUCCESS" and .conclusion != "SKIPPED"))] | length')"
  pending_count="$(echo "$state" | jq '[.statusCheckRollup[] | select(.status != "COMPLETED")] | length')"

  if [ "$current_sha" = "$HEAD_SHA" ] && [ "$failed_count" -gt 0 ]; then
    echo "PR checks failed"
    exit 1
  fi
  if [ "$current_sha" = "$HEAD_SHA" ] && [ "$pending_count" -eq 0 ]; then
    break
  fi
  sleep 20
done
```

Exceptions:

- If there are no code/docs/config changes in the approved plan, go directly to
  Phase 5 after approval.
- If a fix commit was pushed during this triage run, wait for checks before
  resolving any thread tied to the batch.
- If the user explicitly requests per-finding push/check, follow that request.
