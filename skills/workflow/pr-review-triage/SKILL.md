---
name: wf-pr-review-triage
description: "Use when handling PR review comments - triaging, verifying, fixing (with TDD), replying, and resolving bot and human review threads. All code fixes require TDD: RED→GREEN→REFACTOR. Triggers include 'resolve PR comments', 'handle review feedback', 'triage PR reviews', or when a PR has unresolved review threads to process."
---

# PR Review Comment Triage

## Overview

Systematically process all review comments on a PR: classify, verify against code and API docs, fix real bugs, dismiss false positives with evidence, and resolve all threads.

**Core principles:**

1. Bot suggestions are hypotheses, not facts. Every finding must be verified against source code and API documentation before acting.
2. **Judge by first principles, not by scope.** "Is this a bug?" is the only question. "Was this introduced in this PR?" is irrelevant — bot reviews mark code in the PR diff. "Not in this PR" must NEVER appear as a reason to skip or dismiss a finding. If code has a bug, fix it. Period.
3. The ONLY valid reasons to skip a finding: (a) genuine false positive — bot misread the code, (b) architectural refactor needed, create a TODO. Nothing else.
4. **Every fix follows TDD.** No production code without a failing test first. Write test → see it fail → implement fix → see it pass. No exceptions.

## When to Use

- PR has unresolved review threads (bot or human)
- User asks to handle/resolve/triage PR review comments
- After pushing code, before merge, to clear review backlog

## Input

PR number (or auto-detect from current branch).

## The Flow

```
Fetch ──▶ Inventory audit ──▶ Classify ──▶ Verify ──▶ Decision table ──▶ Wait for user approval ──▶ TDD fixes ──▶ Commit plan ──▶ Wait for commit approval ──▶ Per-review commits ──▶ Batch push + PR checks ──▶ Batch reply/resolve ──▶ Report
                                                                                                                                        ▲                                                                       │
                                                                                                                                        └────────────────────────────  re-run Phase 1 after every push ──────────┘
```

**After every `git push` that modifies code on the PR branch, re-run Phase 1 completely (inline threads + review bodies + review comments).** Bot reviewers re-run on new commits and can produce new P1/P2 findings in review bodies that were not present in the previous fetch. Skipping this re-fetch is the #1 cause of missed findings.

## Phase 1: Fetch & Inventory

**必须同时执行以下 3 步，缺一不可。** 缺少任何一步都会漏掉 findings。

**User-provided review comments are hints, not the inventory.** Even if the user
pastes one specific PR review finding, asks "what about this one?", or says
"continue", first rerun this phase for the whole PR and reconcile the pasted
finding with the complete inventory. Never start a fix, commit, push, reply, or
resolve based only on the single finding shown in chat.

### Step 1: Unresolved inline threads

Fetch inline review threads with **complete pagination**. Long PRs regularly
exceed 100 review threads, and unresolved new findings may sit after the first
page. A first-page-only query is invalid inventory, even when it returns zero
unresolved threads.

```bash
# Preferred: use the GitHub connector full review-thread listing when available.
# Otherwise, paginate GraphQL reviewThreads until hasNextPage is false. GitHub
# CLI GraphQL pagination requires an $endCursor variable and pageInfo.
gh api graphql --paginate \
  -f owner="{owner}" \
  -f name="{repo}" \
  -F number={number} \
  -f query='
query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $endCursor) {
        totalCount
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          comments(first: 10) {
            nodes { databaseId path line author { login } body url }
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads'
```

**Never rely on only `reviewThreads(first: 100)`.** GitHub returns review
threads in chronological order and long PRs can have newer unresolved threads
after the first page. `first + last` is only a quick diagnostic, not a complete
inventory. If a GitHub connector is available, call its full review-thread
listing and compare results with the paginated CLI output; connector output is
the tie-breaker when CLI pagination is suspicious.

Hard gate:

- Record `totalCount`, fetched thread count, and `hasNextPage`.
- If `hasNextPage` is true after the final inventory command, stop.
- If fetched thread count is lower than `totalCount`, stop.
- If connector unresolved count differs from CLI unresolved count, stop and
  reconcile before producing the decision table.

### Step 2: Review bodies with P1/P2 findings（MANDATORY）

codex-connector bot 的 findings 大部分在 review body 中，不在 inline threads。**跳过此步 = 漏掉大部分 findings。**

**This step is NOT a one-time check.** Re-run it every time a new commit is pushed to the PR, because bot reviewers trigger on new commits and post new review bodies. After Phase 4.5 (push), restart from Step 2 before declaring the inventory empty.

```bash
# 提取所有含 P1/P2 Badge 的 review body
gh api "repos/{owner}/{repo}/pulls/{number}/reviews?per_page=100" \
  --jq '.[] | select(.body | test("P1|P2|Badge"; "i")) | {id, review_id: .id, user: .user.login, submitted_at, body: .body[0:800]}'
```

从 body 中提取：文件路径（`{url}#L14-L17` 模式）、行号、summary。

### Step 3: Deduplicate

review body findings 可能与 inline threads 重复。用 `{path}:{line}` 去重：inline thread 优先（有 threadId 可直接 reply + resolve），review body findings 作为补充。

**Duplicate comments from repeated bot reviews are normal.** Treat duplicate
inline threads separately if they have different `threadId`s: reply and resolve
each one, even when the verdict/fix is identical. Treat duplicate review-body
findings as one decision-table item, but include all unresolved inline threads
that map to it in the execution checklist.

### Reply 方式

- **Inline thread findings**: 通过 thread reply + resolve；不能只发 PR-level review comment
- **Review body findings（无 thread）**: 通过 `gh api repos/{owner}/{repo}/pulls/{number}/reviews -f body="..." -f event=COMMENT` 提交 PR review 回复

### Step 4: Inventory audit gate（MANDATORY）

Before Phase 2, output a compact inventory summary and stop if any source was
not checked. This is a completeness gate, not a status update.

Required summary:

```
Inventory:
- Inline unresolved threads: {count} (source: paginated GraphQL fetched {fetched}/{total}, hasNextPage={false}; connector: {count_or_N/A})
- Review body P1/P2 findings: {count} (fetched at commit {sha_or_"latest"})
- PR-level comments/actions-only items: {count_or_N/A}
- Deduped decision-table items: {count}
- User-pasted finding matched: {yes/no/N/A} -> #{item_number_or_reason}
```

**Hard gates** — stop and do NOT classify, fix, commit, push, reply, or resolve if any of:

- The inline source says `hasNextPage=true`, `fetched < total`, or connector comparison was skipped when the connector is available.
- Review body findings were **not re-fetched after the latest push** — stale review bodies from a previous commit are invalid inventory.
- The user-pasted finding does not appear in the fetched inventory: keep it as a separate candidate item and verify it; do not discard it silently.
- The fetched inventory contains findings the user did not paste: include them in the decision table too.

If the user-pasted finding does not appear in the fetched inventory, keep it as
a separate candidate item and verify it; do not discard it silently. If the
fetched inventory contains findings the user did not paste, include them in the
decision table too.

If a new commit is pushed, a bot reruns review, PR checks fail, or the user
points out a missed review item, restart from Phase 1 and produce a new
inventory delta:

```
Inventory delta:
- Newly discovered: {items}
- Previously planned: {items}
- Already handled/resolved: {items}
```

Do not continue implementing until the updated decision table is approved.

## Phase 2: Classify

For each comment, determine:

**A. Is it a real issue?** Verify against code — does the code actually have this bug?

**B. Severity**

| Level | Criteria | Action |
|-------|----------|--------|
| P1 | Real bug, affects functionality/data | Verify, then fix or dismiss |
| P2 | Risky but non-blocking | Verify, handle as appropriate |
| Style (introduced by this PR) | Convention/style issue from this change | Fix and resolve |
| Style (pre-existing) | Convention/style issue from older code | Resolve directly, leave for a dedicated PR |

## Phase 3: Verify

**For each P1/P2 comment, verify one by one:**

### 3a0. Check shared-component and shared-file blast radius

Review comments often point at one call site while the real contract lives in a
shared component, hook, or script. Before deciding the verdict, check whether
the touched code is shared.

**Shared UI/component state contract check:**

1. If the comment touches a reusable component, hook, modal, tab container, or
   state holder, run `rg` for all call sites before changing behavior.
2. Record the affected entry points in the decision table, including the
   originally reported path and at least one existing user path if present.
3. For state-like props (`defaultXxx`, `activeXxx`, `value`, `onXxxChange`,
   `onChange`), identify the contract explicitly:
   - `defaultXxx` initializes internal state only.
   - `activeXxx` / `value` controls state from the parent.
   - `onXxxChange` / `onChange` reports user interaction.
4. If a reviewer asks for controlled behavior, preserve existing uncontrolled
   interaction unless the product request explicitly removes it.
5. The test plan must include both the review-comment path and the existing
   interaction path, so a fix for one call site cannot regress another.

**Shared script/file maintenance check:**

1. If the comment touches CI helpers, generated files, managed blocks, scripts,
   or files with headers such as "shared with ...", read the file header and
   nearby docs before editing.
2. Determine whether the change is shared behavior or repo-specific config.
3. For shared behavior, sync the consumer repo/file in the same task when it is
   available; otherwise record the explicit non-sync reason in the decision
   table and TODO.
4. Verify both the source repo and the synced consumer repo, or report which
   side could not be verified and why.

**Skill ownership boundary:** keep these local workflow rules here and in the
repo's `AGENTS.md`. Do not edit the upstream
`dot-agents/skills/superpowers/receiving-code-review/SKILL.md`, because it is
owned upstream and may be overwritten by upgrades.

### 3a. Read code to confirm whether the issue exists

```bash
# Read the lines the comment points to
sed -n '{line-5},{line+10}p' {path}
```

The issue may already be fixed (comment was from an earlier revision). If so, mark as "already fixed".

### 3b. Check API docs to confirm bot assumptions

Bots often guess behavior based on other modules. Always verify against API docs:

```
# Use VShield API MCP or read the OAS directly
mcp__VShield_API_____read_project_oas_ref_resources
```

### 3b.2 Check installed third-party contracts before accepting API claims

When a review finding depends on third-party library behavior, version-specific
API names, hook return fields, component props, or deprecation status, verify
the **locally installed contract** before deciding the verdict.

Required checks:

1. Read the exact installed version from `node_modules`, the lockfile, or the
   package manager metadata; do not rely only on broad ranges such as `"4"`.
2. Inspect the installed `.d.ts` and, when the claim is about runtime behavior,
   the installed runtime source/build output.
3. If the reviewer claims an API is unavailable or wrong but the local installed
   contract shows it is available and supported, classify the finding as
   **False positive** unless another concrete bug remains.
4. Record the installed version and the checked file/path in the decision-table
   notes. For example: `@tanstack/react-query@4.43.0` exposes `isPending` as
   the mutation loading alias while `isLoading` is deprecated.

### 3b.5 False-positive guard and coverage check

Before marking any finding as "Real bug", confirm it with concrete evidence.
Do not rely on the reviewer comment plus a plausible reading of the code.

Required evidence for a "Real bug" verdict:

1. The reported path is reachable in the current code.
2. The current behavior violates an API contract, product requirement, existing
   pattern, or clearly intended invariant.
3. A targeted test can demonstrate the behavior, or an existing test already
   covers the same contract and would fail if the bug exists.

If the code looks suspicious but there is no test coverage for the contract,
classify the next action as **coverage-first verification** in the decision
table. After user approval, add the smallest targeted test first:

- If the test fails, the finding is confirmed as a real bug; continue with the
  TDD fix cycle.
- If the test passes, stop and reclassify the finding as false positive,
  already fixed, or coverage-only. Do not change production code.
- If the behavior is correct but important enough to lock down, add a
  test-only coverage commit and reply that the finding was not a bug but the
  contract is now covered.

Never turn a coverage gap into a production fix without first proving the bug
with a failing test.

### 3b.6 Prove async UI races at the user-action boundary

When a finding claims an async timing bug in UI code, such as `useEffect`
fire-and-forget promises, session renewal, upload readiness, render timing,
loading gates, or a brief window where the user can click before async work
finishes, static code is not enough to mark it as a real bug.

Required checks:

1. Split the finding into separate claims:
   - static fact (for example, a promise is not awaited)
   - reachable user action (for example, the upload button is enabled before
     renewal finishes)
   - user impact (for example, the upload reads stale auth and receives `401`)
2. Static code may prove the static fact only. It does **not** prove reachable
   user impact.
3. Before verdict **Real bug**, prove the user-action boundary with a controlled
   async test or browser/page verification:
   - hold the relevant promise pending
   - reach the page state under review
   - assert whether the user-visible action is available before the promise
     settles
4. If the static fact is suspicious but the user-action boundary is unproved,
   classify the item as **Needs proof / coverage-first verification** in the
   decision table. Only after the proof test fails may production code be
   changed.

### 3b.7 Browser verification for UI findings

For UI review findings, also apply `wf-ui-browser-verification`. Treat that
skill as the source of truth for user-boundary verification, browser control
tool selection, and auth strategy. This section adds PR-triage-specific gates
and reporting requirements. Do not duplicate the browser workflow here; update
`wf-ui-browser-verification` when the shared browser rules change.

When a finding is about visible page state, form defaults, disabled/enabled
buttons, navigation, toast behavior, uploads, loading/error/empty states, or any
claim that "the user can see/click/submit/reach X", Phase 3 must include
browser/page verification unless the item is classified as Needs proof and no
verdict is being made yet. Execute the verification using
`wf-ui-browser-verification`, then record the PR-triage evidence below.

Record in the decision-table notes:

- `Browser path`: route and user steps
- `Browser control`: in-app browser, user-profile browser, or scripted /
  protocol-driven automation, including the concrete tool when known
- `Auth method`: real login, injected auth, or mocked auth/backend; mention the
  project auth-state helper when used
- `Evidence`: what was visible/clickable/disabled/selected
- `Limitations`: anything not covered, such as mocked backend responses

### 3c. Compare reviewer's solution against your own (MANDATORY)

When a review comment proposes a concrete alternative implementation (e.g., "use `Get-NetTCPConnection` instead of `findstr`"), and you decide on a different fix, you MUST:

1. List both approaches in the decision table with pros/cons
2. Justify why your approach is better with concrete evidence — **OR** adopt the reviewer's approach
3. Never silently dismiss the reviewer's suggestion in favor of your own

If unsure which approach is better, present both to the user and let them decide.

### 3d. Determine verdict

| Verdict | Action |
|---------|--------|
| Real bug | **TDD fix**: RED test → GREEN fix → reply (✅ commit hash + test name), resolve |
| False positive | Reply (ℹ️ cite code/API docs as evidence), resolve |
| Already fixed | Reply (✅ confirm fix + commit hash), resolve |
| Coverage gap only | Add targeted test-only coverage if useful, reply (ℹ️ not a bug + test evidence), resolve |
| Deferred (TODO) | Create `docs/todo/` entry, reply (📋 link + reason), resolve |
| Style issue | **TDD fix**: RED test → GREEN fix → reply (✅ fixed + test name), resolve |

**Deferred 必须记入 `docs/todo/`**（见下方 "Deferred → TODO 文件"）。

### Reply format

Every resolve MUST be preceded by a reply explaining the verdict. This gives reviewers (bot or human) transparency into the decision.

**Fixed:**
> ✅ Fixed in `{hash}`: `{file}` line N — {specific change}. TDD: RED `{test_name}` → GREEN.

**False positive:**
> ℹ️ Not an issue — {evidence}. (e.g., "backend validates at line N", "GORM naturally skips zero values")

**Already fixed:**
> ✅ Already fixed in `{hash}`. Current code: {specific state}.

**Deferred (TODO):**
> 📋 Recorded as `docs/todo/{slug}.md` — {reason for deferral}. (e.g., "needs architecture change")

### Deferred → TODO 文件

每个 Deferred 项必须在 `docs/todo/` 创建对应文件：

```yaml
---
priority: low | medium | high
area: 对应模块（如 contractor, components, infrastructure）
source: PR #{number} review — {日期} {bot/人}
refs:
  - designs/xxx.md    # 或 plans/xxx.md 或 prds/xxx.md（至少一个）
---

# {标题}

{简要描述问题、为何暂缓、建议方案}
```

文件命名：`{简短-slug}.md`。创建后在 reply 和 decision table 中用相对路径引用（如 `docs/todo/audit-component-directory.md`）。

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

Output format:

Keep the table compact. Do not put long evidence, code snippets, proposed
reply text, or multi-sentence explanations inside table cells; they wrap badly
in chat UIs. Put long details under the table in per-item notes.
Reviewer comments often contain nuance that is easy to miss in English-only
tables. For every decision-table item, include the review comment's original
text and a concise Chinese translation in the per-item notes below the table.
Do not add these as wide table columns.

```
| # | File | Level | Verdict | Action | Thread(s) |
|---|------|-------|---------|--------|-----------|
| 1 | service/foo.go:42 | P2 | Real bug | TDD fix + checks | PRRT_xxx |
| 2 | handler/bar.go:95 | P2 | False positive | Reply + resolve | PRRT_yyy |
| 3 | scripts/x.sh:12 | P2 | Deferred | TODO + resolve | review body |
| 4 | service/baz.go:88 | P2 | Needs proof | Coverage-first test | PRRT_zzz |
```

Then add short notes outside the table:

```
1. Summary: GORM skips zero values.
   Review comment (original): "..."
   Review comment (中文): "..."
   Evidence: `Updates(struct)` skips zero values; API allows clearing this field.
   Test plan: RED `testZeroValueSkip`, GREEN after map/select update.
   Planned reply: Fixed in `{hash}` after PR checks pass.
```

Then ask the user: **"Do you agree with this plan? Any changes needed?"**

- After user confirms: execute Phase 4 (TDD Fix Cycle) for each approved fix
  item. This approval permits edits and verification only; it does **not**
  permit staging, committing, pushing, replying, or resolving.
- **Batch by default after approval**: keep each real bug, style fix, coverage
  fix, or TODO/doc change in its own commit, but do not push, reply, or resolve
  between findings. Push the completed local commit batch once in Phase 4.5,
  then wait for PR checks once on the resulting head SHA.
- Reply and resolve all approved findings together in Phase 5 only after the
  batch head is green. False-positive, already-fixed, and deferred/no-code
  findings still wait for the same final reply/resolve pass when there are code
  changes in the batch.
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
```

**Required output:**

```
GREEN: test_name — PASSES (bug fixed)
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
| Fix code written before test | STOP. Delete fix code. Write test first. |
| Test passes on first run (before fix) | Test is wrong — it didn't catch the bug. Rewrite it. |
| Multiple bugs fixed in one cycle | STOP. One test per bug. Separate cycles. |
| Test doesn't specifically target the bug | Rewrite test to assert the exact condition from the review finding. |
| UI bug has only unit RED but no browser RED | Follow `wf-ui-browser-verification` for Browser RED before fixing, or stop and ask the user to approve a substitute evidence standard. |
| Fix breaks other tests | Fix the regression before proceeding. All tests must pass. |

## Phase 4.4: Commit Confirmation Gate (MANDATORY)

After all approved TDD cycles are GREEN and before running any `git add` or
`git commit`, output a compact commit plan and wait for explicit user approval.
The Phase 3.5 decision approval is stale for commits; committing requires this
separate gate.

This gate applies to every commit created during review triage, including:

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

Then ask: **"Approve these commits and messages?"**

Hard gates:

- Do not stage or commit until the user approves the commit plan.
- If the user changes grouping or messages, follow the revised plan exactly.
- If files for multiple review items overlap, use partial staging, temporary
  patch extraction, or another non-destructive method to keep commits grouped by
  review item. If clean separation is not practical, stop and ask the user to
  approve the exception before committing.
- A broad "fix all review comments" commit is forbidden unless the user
  explicitly approves that exact grouping after seeing the commit plan.
- A follow-up CI repair commit must be grouped by the independent CI root cause
  and must also pass this confirmation gate before committing.

### Per-Review Commit Strategy

Each review item/finding produces one commit by default. "Review item" means
the deduped decision-table row, including all duplicate inline threads or review
body findings mapped to that row.

Valid grouping:

- One real bug/style finding -> one fix commit containing its RED/GREEN test
  and minimal source changes.
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

After the commit plan is approved, create the commits exactly as approved:

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

## Phase 4.5: Push + PR Checks Gate (MANDATORY for code fixes)

For every item that changes code, tests, docs, generated files, scripts, or
configuration, do not reply or resolve yet. First finish all approved local
review-item commits, then push the batch once, wait for PR checks on the
current head SHA, and handle failures.

The default is: **one commit per review item/finding, one push per approved
batch, one PR checks wait per pushed head SHA**. This keeps rollback and audit
history clean without paying the full PR checks latency for every review
finding.

1. Confirm the Phase 4.4 commit plan was approved by the user.
2. Confirm every approved fix/deferred/test-only item has its own local commit
   grouped by review item, or that the user explicitly approved a documented
   exception.
3. Push the branch containing the completed commit batch.
4. Capture the head SHA after push: `git rev-parse HEAD`.
5. Wait until PR checks for that SHA finish.
6. If any check fails or is cancelled, do NOT reply/resolve review threads.
   Enter the CI failure triage loop below.
7. Only continue to Phase 5 when all required PR checks for the current head SHA
   are successful.
8. **Re-run Phase 1 Step 2 (review bodies) immediately after checks pass.** Bot
   reviewers trigger on every new commit and can post new P1/P2 review bodies
   after the push. Do NOT proceed to Phase 5 reply/resolve until the fresh
   inventory confirms zero new findings.

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

## Phase 5: Reply + Resolve

**Every thread gets a reply before being resolved.** This provides an audit trail for reviewers.
PR-level review comments do **not** resolve inline threads. If a finding has a
`threadId`, use the inline reply endpoint and then resolve that exact thread.
If the same finding appears in two unresolved inline threads, reply and resolve
both.

For any triage run that pushed code/docs/config changes, Phase 5 is allowed
only after Phase 4.5 confirms PR checks are green on the final pushed head SHA.
Reply and resolve the full approved batch together. Review replies should
mention the original review-item commit hash and RED→GREEN test name; if a
later CI-repair commit changed the same behavior, mention that repair commit as
well. The final report should mention the check result and final head SHA.

```bash
# Step 1: Reply to the review comment (using REST API)
# {comment_id} is the databaseId from Phase 1
gh api repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies \
  -f body="{reply_text}"

# Step 2: Resolve the thread (using GraphQL)
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "{threadId}"}) {
    thread { isResolved }
  }
}'
```

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
  gh api "repos/{owner}/{repo}/pulls/{number}/comments/$cid/replies" -f body="$reply"
  # Resolve
  gh api graphql -f query="mutation { resolveReviewThread(input: {threadId: \"$tid\"}) { thread { isResolved } } }"
done
```

## Phase 5.5: Final Cross-Check

Before reporting completion, verify there are no unresolved review threads with
two independent views:

1. CLI GraphQL with `reviewThreads(first: 100)` and `reviewThreads(last: 100)`,
   merged by `id`.
2. GitHub connector full thread listing, when available.

If either view shows unresolved threads, continue triage. Do not report "all
resolved" based only on PR-level review comments, review decision, or a single
`first: 100` query.

## Phase 6: Report

Output a summary report:

```
PR #{number} review triage complete:
- Total: {total} comments
- Fixed: {fixed} ({files}) — all TDD verified (RED→GREEN)
- Commits: {per_finding_commits}; CI repair commits: {ci_repair_commits_or_none}
- Dismissed (false positive): {dismissed}
- Deferred: {deferred}
- Style: {style}
- PR checks: {green/failing/not applicable} @ {head_sha}
- All resolved: Y/N
```

## Red Flags

| Wrong approach | Correct approach |
|----------------|------------------|
| Trust bot findings at face value | Verify against code + API docs |
| Leave unhandled comments unresolved | Resolve them; new comments will appear on next review |
| Reply "known issue" without evidence | Reply with specific evidence (code line, commit hash, TODO #) |
| Resolve without replying | Always reply before resolving — provides audit trail for reviewers |
| Use PR-level review comment for inline thread | Reply to the inline comment and resolve its `threadId` |
| Check only `reviewThreads(first: 100)` | Check `first + last`, and connector full listing when available |
| Fetch review bodies only once at the start | Re-run Step 2 (review bodies) after every push — bot reviewers re-run on new commits |
| Declare inventory empty based on inline threads only | Review body P1/P2 is mandatory input; if it wasn't checked against the latest commit, the inventory is incomplete |
| Write long explanations | Keep replies to 1-2 lines with evidence |
| Execute fixes/resolves without user approval | Always output decision table and wait for confirmation |
| Stage or commit after plan approval without a separate commit confirmation | After GREEN verification, show a commit plan with grouping and messages, then wait for explicit commit approval |
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
| Report fix as done without showing RED→GREEN | Every fix reply must reference the test name and confirm RED→GREEN cycle. |
| Push and wait PR checks after every finding by default | Commit each approved review item separately after commit confirmation, push the approved batch once, then wait once on the batch head SHA. |
| Reply/resolve immediately after push | Wait for PR checks on the pushed head SHA; fix failures before replying/resolving the batch. |
| Fix multiple CI failures in one blob commit | Group failures by root cause; commit each independent CI repair separately, then push the repair batch once. |
| Treat external CI failures as code regressions | Use logs/annotations to prove the cause; rerun or report a blocker when it is external, such as exhausted Actions minutes. |
| Put long evidence in decision-table cells | Keep the table compact; move evidence, test plan, and planned replies into per-item notes below it. |
