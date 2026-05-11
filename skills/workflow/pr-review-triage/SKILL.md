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
Fetch ──▶ Classify ──▶ Verify ──▶ Decision table ──▶ Wait for user approval ──▶ TDD fix cycle ──▶ Reply/resolve ──▶ Report
```

## Phase 1: Fetch & Inventory

**必须同时执行以下 3 步，缺一不可。** 缺少任何一步都会漏掉 findings。

### Step 1: Unresolved inline threads

```bash
gh api graphql -f query='
query {
  repository(owner: "{owner}", name: "{repo}") {
    pullRequest(number: {number}) {
      first: reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes { databaseId path author { login } body }
          }
        }
      }
      last: reviewThreads(last: 100) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes { databaseId path author { login } body }
          }
        }
      }
    }
  }
}' --jq '[.data.repository.pullRequest.first.nodes[], .data.repository.pullRequest.last.nodes[]] | unique_by(.id)[] | select(.isResolved == false) | {threadId: .id, commentId: .comments.nodes[0].databaseId, path: .comments.nodes[0].path, author: .comments.nodes[0].author.login, body: (.comments.nodes[0].body[0:200])}'
```

**Never rely on only `reviewThreads(first: 100)`.** GitHub returns review threads in
chronological order and long PRs can have newer unresolved threads after the
first page. Use `first + last` at minimum. If a GitHub connector is available,
also call its full review-thread listing and compare results; connector output
is the tie-breaker when CLI pagination is suspicious.

### Step 2: Review bodies with P1/P2 findings（MANDATORY）

codex-connector bot 的 findings 大部分在 review body 中，不在 inline threads。**跳过此步 = 漏掉大部分 findings。**

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

Output format:

```
| # | File | Summary | Level | Verdict | Action | Reply |
|---|------|---------|-------|---------|--------|-------|
| 1 | service/foo.go | GORM skips zero values | P2 | Real bug | TDD fix | ✅ Fixed in `abc123` — RED: `testZeroValueSkip` → GREEN |
| 2 | handler/bar.go | null attachments enqueued | P2 | False positive | Resolve | ℹ️ Not an issue — backend validates |
| 3 | scripts/x.sh | CI branch missing | P2 | Needs refactor | Defer | 📋 `docs/todo/ci-branch-coverage.md` — needs architecture change |
```

Then ask the user: **"Do you agree with this plan? Any changes needed?"**

- After user confirms: for each fix item, execute Phase 4 (TDD Fix Cycle) then Phase 5 (Reply + Resolve)
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
| Fix breaks other tests | Fix the regression before proceeding. All tests must pass. |

### Per-Fix Commit Strategy

Each TDD fix cycle produces one commit:

```bash
git add <test_file> <source_file>
git commit -m "fix(scope): description of the fix"
```

The commit hash is then referenced in the reply to the review thread (see Phase 5).

## Phase 5: Reply + Resolve

**Every thread gets a reply before being resolved.** This provides an audit trail for reviewers.
PR-level review comments do **not** resolve inline threads. If a finding has a
`threadId`, use the inline reply endpoint and then resolve that exact thread.
If the same finding appears in two unresolved inline threads, reply and resolve
both.

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
- Dismissed (false positive): {dismissed}
- Deferred: {deferred}
- Style: {style}
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
| Write long explanations | Keep replies to 1-2 lines with evidence |
| Execute fixes/resolves without user approval | Always output decision table and wait for confirmation |
| Propose own fix without comparing to reviewer's suggestion | When reviewer proposes concrete solution, explicitly list both approaches with pros/cons in decision table |
| Classify bot findings as "pre-existing" or "out of scope" | Bot comments are on PR diff code. Judge by first principles: is it a bug? |
| Skip obvious bugs because "not in this PR" | "Is it a bug?" is the ONLY question. If yes, fix it. No other excuse. |
| Judge by "was this introduced here?" | Judge by "is the code correct or not?" — first principles over scope concerns |
| Write fix code before a failing test | Delete fix code. Write test first. TDD is non-negotiable for ALL fixes. |
| Fix + refactor unrelated code in same cycle | Fix only what the test covers. Refactor only what the fix touches. |
| Skip writing a test because "it's a simple fix" | No exceptions. Every fix gets a test. "Simple" fixes are where hidden bugs live. |
| Report fix as done without showing RED→GREEN | Every fix reply must reference the test name and confirm RED→GREEN cycle.
