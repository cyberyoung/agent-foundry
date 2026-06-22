# Inventory Reference

REQUIRED before classifying or fixing PR review feedback. Fetch all sources with complete pagination and stop if inventory is incomplete.

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
after the first page. Sampling the first and last pages is only a diagnostic,
not a complete inventory. If a GitHub connector is available, call its full
review-thread listing and compare results with the paginated CLI output;
connector output is the tie-breaker when CLI pagination is suspicious.

Hard gate:

- Record `totalCount`, fetched thread count, and `hasNextPage`.
- If `hasNextPage` is true after the final inventory command, stop.
- If fetched thread count is lower than `totalCount`, stop.
- If connector unresolved count differs from CLI unresolved count, stop and
  reconcile before producing the decision table.

### Step 2: Review bodies with P1/P2 findings（MANDATORY）

codex-connector bot 的 findings 大部分在 review body 中，不在 inline threads。**跳过此步 = 漏掉大部分 findings。**

**This step is NOT a one-time check.** Re-run it every time a new commit is
pushed to the PR, because bot reviewers trigger on new commits and post new
review bodies. After Phase 4.5 (push + green checks) and Phase 5
(reply/resolve the old approved threads), restart from Step 2 before declaring
the inventory empty.

```bash
# 提取所有含 P1/P2 Badge 的 review body. Paginate; do not trust page 1.
gh api --paginate "repos/{owner}/{repo}/pulls/{number}/reviews?per_page=100" \
  --jq '.[] | select(.body | test("P1|P2|Badge"; "i")) | {id, review_id: .id, user: .user.login, submitted_at, body: .body[0:800]}'
```

从 body 中提取：文件路径（`{url}#L14-L17` 模式）、行号、summary。

Record the fetched review count and the newest submitted timestamp. If the API
is paginated and pagination was not followed to completion, stop.

### Step 2.5: PR-level comments / actions-only items

Some reviewers leave action items as PR-level issue comments instead of review
threads or review bodies. Fetch them with pagination and scan for direct
requests, P1/P2 labels, failing-check instructions, or user-mentioned comments:

```bash
gh api --paginate "repos/{owner}/{repo}/issues/{number}/comments?per_page=100" \
  --jq '.[] | {id, user: .user.login, created_at, body: .body[0:800], html_url}'
```

PR-level comments cannot resolve inline threads, but they must be included in
the decision table when actionable.

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
- Review body P1/P2 findings: {count} (source: paginated REST fetched {count}; fetched at commit {sha_or_"latest"})
- PR-level comments/actions-only items: {count} (source: paginated REST fetched {count})
- Deduped decision-table items: {count}
- User-pasted finding matched: {yes/no/N/A} -> #{item_number_or_reason}
```

**Hard gates** — stop and do NOT classify, fix, commit, push, reply, or resolve if any of:

- The inline source says `hasNextPage=true`, `fetched < total`, or connector comparison was skipped when the connector is available.
- Review body findings were **not re-fetched after the latest pushed batch's
  old approved threads were replied/resolved** — stale review bodies from a
  previous commit are invalid inventory.
- Review bodies or PR-level comments were fetched without pagination when the
  API supports pagination.
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
