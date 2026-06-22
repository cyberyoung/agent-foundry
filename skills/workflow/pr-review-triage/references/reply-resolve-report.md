# Reply Resolve And Report Reference

REQUIRED after pushed-head PR checks are green and before resolving review threads or reporting completion.

## Phase 5: Reply + Resolve

**Every thread gets a reply before being resolved.** This provides an audit trail for reviewers.
PR-level review comments do **not** resolve inline threads. If a finding has a
`threadId`, use the inline reply endpoint and then resolve that exact thread.
If the same finding appears in two unresolved inline threads, reply and resolve
both.

For any triage run that pushed code/docs/config changes, Phase 5 is allowed
only after Phase 4.5 confirms PR checks are green on the final pushed head SHA.
Reply and resolve the full old approved batch together before checking for new
threads. Review replies should mention the original review-item commit hash and
RED→GREEN test name; if a later CI-repair commit changed the same behavior,
mention that repair commit as well. The final report should mention the check
result and final head SHA.

```bash
# Step 1: Reply to the inline thread. Prefer the thread GraphQL endpoint when
# {thread_id} is available; it avoids replying at the wrong PR/comment level.
gh api graphql \
  -f query='mutation($thread:ID!,$body:String!){ addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$thread,body:$body}){ comment{ id url } } }' \
  -F thread="{thread_id}" \
  -F body="{reply_text}"

# Step 2: Resolve the thread.
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "{thread_id}"}) {
    thread { isResolved }
  }
}'
```

Use REST comment replies only as a fallback when a thread ID is unavailable but
a review-comment `databaseId` is available.

**Batch execution pattern:**

```bash
# Array of: commentId|threadId|replyText
ITEMS=(
  "12345|PRRT_xxx|✅ Fixed in \`abc123\`: added timeout check. TDD: RED \`testTimeoutGuard\` → GREEN"
  "12346|PRRT_yyy|ℹ️ Not an issue — backend validates at handler.go:95"
  "12347|PRRT_zzz|📋 Recorded as TODO #28"
)

for item in "${ITEMS[@]}"; do
  IFS='|' read -r cid tid reply <<< "$item"
  # Reply
  gh api graphql \
    -f query='mutation($thread:ID!,$body:String!){ addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$thread,body:$body}){ comment{ id url } } }' \
    -F thread="$tid" \
    -F body="$reply"
  # Resolve
  gh api graphql -f query="mutation { resolveReviewThread(input: {threadId: \"$tid\"}) { thread { isResolved } } }"
done
```

## Phase 5.5: Post-Resolve Re-fetch & Final Cross-Check

After Phase 5 replies/resolves the old approved threads, re-run Phase 1 against
the pushed head to discover new review output from bot reruns:

1. Wait the user-specified stabilization window before the re-fetch. If the
   user did not specify one, choose and record a short repo-appropriate wait;
   do not skip the wait merely because the current inventory is empty.
2. Re-fetch review bodies with P1/P2 findings using complete pagination.
3. Re-fetch unresolved inline threads with complete pagination.
4. Re-check PR-level comments/actions-only items with complete pagination.

If the post-resolve inventory contains new findings, output an inventory delta
and return to Phase 2/3.5 for fresh approval before fixing, replying, resolving,
or reporting completion.

Before reporting completion, also verify there are no unresolved review threads:

1. CLI GraphQL with complete pagination until `hasNextPage=false`, recording
   `totalCount`, fetched count, and unresolved count.
2. GitHub connector full thread listing, when available.
3. Review bodies and PR-level comments fetched with complete REST pagination.

`reviewThreads(first: 100)` / `last: 100` are diagnostic shortcuts only, not
completion evidence. If any full source shows unresolved or actionable items,
continue triage. Do not report "all resolved" based only on PR-level review
comments, review decision, or a single-page query.

## Phase 6: Report

Output a summary report:

```
PR #{number} review triage complete:
- Total: {total} comments
- Fixed: {fixed} ({files}) — all TDD verified (RED→GREEN) with necessary regression coverage, 95%+ affected-path coverage / 100% critical-path coverage where applicable, and Browser Regression where needed
- Commits: {per_finding_commits}; CI repair commits: {ci_repair_commits_or_none}
- Dismissed (false positive): {dismissed}
- Deferred: {deferred}
- Style: {style}
- PR checks: {green/failing/not applicable} @ {head_sha}
- All resolved: Y/N
```

Then include a detailed table. Do not replace this table with a short prose
summary when there were code changes, test-only coverage commits,
false-positive evidence, or deferred items.

If the user specified report columns, use the user's columns first and add any
missing audit columns after them. Always include commit/topic, GitHub review
location, actual current-head change location, regression test location, review
problem, fix strategy, and result.

| Commit / Topic | GitHub Review Location | Actual Change Location @ HEAD | Regression Test Location | Review Problem | Fix Strategy | Result | Standard / Actual / Exception |
| -------------- | ---------------------- | ----------------------------- | ------------------------ | -------------- | ------------ | ------ | ----------------------------- |
| `{hash}` / `{topic}` | `{thread/comment/path:line/url}` | `{path:line or N/A}` | `{test path:line / case / summary}` | `{what reviewer claimed}` | `{owner-layer fix or false-positive evidence}` | `{local checks, pre-push, PR checks, reply/resolve}` | `Expected: {Lx + coverage target}; Actual: {evidence}; Exception: {N/A or fallback reason + residual risk}` |

The report must make every compatibility fallback visible. If a repository lacks
chogori-style L0-L4, coverage, pre-push, or provider CI, keep the same table and
write `unavailable` plus the substitute proof. Do not omit the column.

## Red Flags

| Wrong approach | Correct approach |
|----------------|------------------|
| Trust bot findings at face value | Verify against code + API docs |
| Leave unhandled comments unresolved | Resolve them; new comments will appear on next review |
| Reply "known issue" without evidence | Reply with specific evidence (code line, commit hash, TODO #) |
| Resolve without replying | Always reply before resolving — provides audit trail for reviewers |
| Use PR-level review comment for inline thread | Reply to the inline comment and resolve its `threadId` |
| Check only `reviewThreads(first: 100)` | Use complete pagination until `hasNextPage=false`, and compare connector full listing when available |
| Fetch review bodies only once at the start | After green checks, reply/resolve the old approved threads first, then re-run Step 2 (review bodies) — bot reviewers re-run on new commits |
| Declare inventory empty based on inline threads only | Review body P1/P2 is mandatory input; if it wasn't checked against the latest commit, the inventory is incomplete |
| Write long explanations | Keep replies to 1-2 lines with evidence |
| Execute fixes/resolves without user approval | Always output decision table and wait for confirmation |
| Stage a blob commit after plan approval | After GREEN verification, prepare the per-review commit plan, then automatically create one commit per review item by default |
| Put multiple independent review findings into one broad commit | Create one commit per review item/finding; duplicate threads for the same deduped finding may share one commit |
| Claim overlapping files force a blob commit | Use partial staging or patch extraction; if clean separation is impractical, stop and ask the user to approve the exception |
| Act on a user-pasted single review item without full PR inventory | Treat pasted comments as hints; rerun Phase 1 and map them into a complete decision table |
| Continue after a missed review item is found | Stop, rerun inventory, show inventory delta, and get fresh approval |
| Mark a plausible bot finding as real without proof | Confirm reachability, contract violation, and test evidence first. |
| Accept a reviewer claim about a third-party API from broad package version alone | Check the exact installed package version plus local `.d.ts`/runtime contract before deciding; local contract beats generic version lore |
| Treat missing tests as proof of a bug | Add coverage-first verification; only fix production code if the test fails. |
| Conclude an async UI race from fire-and-forget code alone | Prove the user-visible action is reachable before the async work settles; otherwise classify as Needs proof |
| Decide UI findings from source code only | Use browser/page verification at the user boundary, and document route, auth method, evidence, and limitations |
| Treat one browser tool as the default for every UI finding | Select in-app browser, user-profile browser, or scripted/protocol-driven automation by evidence need; follow `wf-ui-browser-verification` |
| Skip browser verification because login is inconvenient | Use a test account, injected local auth state, or mocked fixtures as appropriate; ask before sensitive real-account actions |
| Propose own fix without comparing to reviewer's suggestion | When reviewer proposes concrete solution, explicitly list both approaches with pros/cons in decision table |
| Conclude a component lifecycle bug from static code alone | Verify framework defaults (keepDOM, destroyOnClose, key) and browser-test before committing to fix. Framework behavior at runtime (mount/unmount) often differs from what static reading suggests |
| Classify bot findings as "pre-existing" or "out of scope" | Bot comments are on PR diff code. Judge by first principles: is it a bug? |
| Skip obvious bugs because "not in this PR" | "Is it a bug?" is the ONLY question. If yes, fix it. No other excuse. |
| Judge by "was this introduced here?" | Judge by "is the code correct or not?" — first principles over scope concerns |
| Write fix code before a failing test | Delete fix code. Write test first. TDD is non-negotiable for ALL fixes. |
| Fix + refactor unrelated code in same cycle | Fix only what the test covers. Refactor only what the fix touches. |
| Skip writing a test because "it's a simple fix" | No exceptions. Every fix gets a test. "Simple" fixes are where hidden bugs live. |
| Add only the narrow RED test and skip adjacent behavior | Add necessary regression tests for neighboring modes, entry points, and preserved contracts, or explicitly record why none are needed. |
| Skip coverage assessment for the reviewed code path | Record current coverage, target 95%+ for affected paths, and 100% for critical branches, or document the tooling limitation and substitute evidence. |
| Treat PR-level coverage as enough when a critical path is untested | Add targeted tests for the reviewed critical path; broad suite coverage cannot hide an uncovered data-loss/auth/submit/destructive/navigation/upload branch. |
| Treat browser regression as optional for visible UI changes | Add Browser Regression to the plan, or explicitly record why component/unit coverage proves the visible contract. |
| Treat a weaker repo as permission to ignore chogori-style standards | Classify against the target model first, then record a controlled compatibility exception with substitute evidence and residual risk. |
| Skip a repo-declared hard gate because it is slow | Stop unless user approval, explicit deduplication, or equivalent pre-push/provider proof covers the same gate. |
| Report fix as done without showing RED→GREEN | Every fix reply must reference the test name and confirm RED→GREEN cycle. |
| Squash independent review fixes into one convenience commit | Commit each deduped review item separately by default, then push the completed batch once. |
| Push and wait PR checks after every finding by default | Commit each approved review item separately from the per-review commit plan, push the approved batch once, then wait once on the batch head SHA. |
| Reply/resolve immediately after push | Wait for PR checks on the pushed head SHA; fix failures before replying/resolving the old approved batch, then re-fetch for new findings after resolving old threads. |
| Fix multiple CI failures in one blob commit | Group failures by root cause; commit each independent CI repair separately, then push the repair batch once. |
| Treat external CI failures as code regressions | Use logs/annotations to prove the cause; rerun or report a blocker when it is external, such as exhausted Actions minutes. |
| Put long evidence in decision-table cells | Keep the table compact; move evidence, test plan, and planned replies into per-item notes below it. |
| Push without inspecting remote branch / ahead commits / diff scope | Run push preflight first; stop if the push would create/recreate a branch or exceed approved scope. |
| Treat absent PR checks as success | Verify current head has provider checks; if no suite appears, diagnose and safely retrigger instead of resolving. |
| Use broad allow-missing env vars for full hooks | Prefer real `SYNC_TARGET_*` paths; broad env vars can leak into nested tests and change test semantics. |
| Assume coverage/CI green means no false-pass path | Audit artifact visibility, aggregate job `always()` behavior, shard status sidecars, exact provider check matching, and current-head provider URLs. |
| Finish immediately after resolving the last known thread | Wait the requested stabilization window, then re-fetch paginated threads, review bodies, and PR-level comments. |
