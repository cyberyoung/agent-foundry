---
name: wf-pr-review-triage
description: Use when handling PR review comments — triaging, verifying, fixing, replying, and resolving bot and human review threads. Triggers include 'resolve PR comments', 'handle review feedback', 'triage PR reviews', or when a PR has unresolved review threads to process.
---

# PR Review Comment Triage

## Overview

Systematically process all review comments on a PR: classify, verify against code and API docs, fix real bugs, dismiss false positives with evidence, and resolve all threads.

**Core principles:**

1. Bot suggestions are hypotheses, not facts. Every finding must be verified against source code and API documentation before acting.
2. **Judge by first principles, not by scope.** "Is this a bug?" is the only question. "Was this introduced in this PR?" is irrelevant — bot reviews mark code in the PR diff. "Not in this PR" must NEVER appear as a reason to skip or dismiss a finding. If code has a bug, fix it. Period.
3. The ONLY valid reasons to skip a finding: (a) genuine false positive — bot misread the code, (b) architectural refactor needed, create a TODO. Nothing else.

## When to Use

- PR has unresolved review threads (bot or human)
- User asks to handle/resolve/triage PR review comments
- After pushing code, before merge, to clear review backlog

## Input

PR number (or auto-detect from current branch).

## The Flow

```
Fetch ──▶ Classify ──▶ Verify ──▶ Decision table ──▶ Wait for user approval ──▶ Execute fix/resolve
```

## Phase 1: Fetch & Inventory

```bash
# Get all inline review comments (threads)
gh api repos/{owner}/{repo}/pulls/{number}/comments \
  --jq '.[] | {id, path, line, body: (.body | split("\n")[0:3] | join(" ")), user: .user.login}'

# Get unresolved thread IDs + comment IDs (for Phase 4 reply + resolve)
gh api graphql -f query='
query {
  repository(owner: "{owner}", name: "{repo}") {
    pullRequest(number: {number}) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes { databaseId path }
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | {threadId: .id, commentId: .comments.nodes[0].databaseId, path: .comments.nodes[0].path}'

# CRITICAL: Also fetch review bodies — codex-connector bot often puts findings in
# the review body (not as inline threads). These have no thread to resolve.
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --jq '.[] | select(.body | length > 100) | {id, user: .user.login, submitted_at, body_preview: (.body[0:300])}'
```

Group by source: `gemini-code-assist[bot]`, `chatgpt-codex-connector[bot]`, human reviewers.

**For review body findings:** extract the file path, line range, and summary from the body (codex uses `{url}#L14-L17` pattern). There is no thread — reply by submitting a PR review (`gh api repos/.../reviews -f body="..." -f event=COMMENT`).

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
| Real bug | Fix, reply (✅ commit hash + description), resolve |
| False positive | Reply (ℹ️ cite code/API docs as evidence), resolve |
| Already fixed | Reply (✅ confirm fix + commit hash), resolve |
| Deferred (TODO) | Reply (📋 TODO # + reason), resolve |
| Style issue | Fix, reply (✅ fixed), resolve |

### Reply format

Every resolve MUST be preceded by a reply explaining the verdict. This gives reviewers (bot or human) transparency into the decision.

**Fixed:**
> ✅ Fixed in `{hash}`: `{file}` line N — {specific change}.

**False positive:**
> ℹ️ Not an issue — {evidence}. (e.g., "backend validates at line N", "GORM naturally skips zero values")

**Already fixed:**
> ✅ Already fixed in `{hash}`. Current code: {specific state}.

**Deferred (TODO):**
> 📋 Recorded as TODO #{N} — {reason for deferral}. (e.g., "needs architecture change")

## Phase 3.5: Confirmation Gate (MANDATORY)

**After verification, do NOT execute any fixes or resolves on your own.** You must first output a decision table and wait for user approval.

Output format:

```
| # | File | Summary | Level | Verdict | Action | Reply |
|---|------|---------|-------|---------|--------|-------|
| 1 | service/foo.go | GORM skips zero values | P2 | Real bug | Fix | ✅ Fixed in `abc123` |
| 2 | handler/bar.go | null attachments enqueued | P2 | No functional impact | Resolve | ℹ️ Not an issue — backend validates |
| 3 | scripts/x.sh | CI branch missing | P2 | Out of scope | Resolve | ⏭️ Out of scope — pre-existing |
```

Then ask the user: **"Do you agree with this plan? Any changes needed?"**

- After user confirms: execute Phase 4 per the decision table
- If user modifies decisions: execute per their modified version
- **NEVER skip this step**

## Phase 4: Reply + Resolve

**Every thread gets a reply before being resolved.** This provides an audit trail for reviewers.

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
  "12345|PRRT_xxx|✅ Fixed in \`abc123\`: added timeout check"
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

## Phase 5: Report

Output a summary report:

```
PR #{number} review triage complete:
- Total: {total} comments
- Fixed: {fixed} ({files})
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
| Write long explanations | Keep replies to 1-2 lines with evidence |
| Execute fixes/resolves without user approval | Always output decision table and wait for confirmation |
| Propose own fix without comparing to reviewer's suggestion | When reviewer proposes concrete solution, explicitly list both approaches with pros/cons in decision table |
| Classify bot findings as "pre-existing" or "out of scope" | Bot comments are on PR diff code. Judge by first principles: is it a bug? |
| Skip obvious bugs because "not in this PR" | "Is it a bug?" is the ONLY question. If yes, fix it. No other excuse. |
| Judge by "was this introduced here?" | Judge by "is the code correct or not?" — first principles over scope concerns |
