---
name: wf-everest-pr-merge
description: Use when the user asks to merge, approve, or review an Everest GitHub PR for merge. Triggers include PR numbers with 'merge', 'squash', 'approve and merge', or reviewing a PR before merging.
---

# Everest PR Merge

## Overview

Two-phase PR merge: gather info and present summary, then approve + squash merge on user confirmation. **Never merge without explicit confirmation.**

## When to Use

- User provides a PR number and wants to merge it
- User says "merge PR X", "squash and merge X", "approve and merge X"
- User asks to review a PR before merging

**Do NOT use for:** Creating PRs, reviewing code in detail, or non-Everest repos.

## The Flow

```
Gather ──▶ Present ──gate──▶ Approve + Squash Merge
```

## Phase 1: Gather

Run these three commands in parallel:

```bash
# PR metadata
gh pr view <PR_NUMBER> --json title,state,baseRefName,headRefName,mergeable,mergeStateStatus,statusCheckRollup,reviews,commits

# Review comments (for critical/P0 detection)
gh api repos/vrenlabs/everest/pulls/<PR_NUMBER>/comments \
  --jq '.[] | {path: .path, body: .body, line: .line}'

# Review thread resolve status (GraphQL — needed because REST API doesn't expose isResolved)
gh api graphql -f query='{ repository(owner:"vrenlabs", name:"everest") { pullRequest(number:<PR_NUMBER>) { reviewThreads(first:50) { nodes { id isResolved path line comments(first:1) { nodes { body } } } } } } }'
```

## Phase 2: Present

Display a summary with these sections:

### Required Fields

| Field | Source |
|-------|--------|
| **Title** | `title` from PR metadata |
| **State** | `state` — if not `OPEN`, warn and stop |
| **Base / Head** | `baseRefName` ← `headRefName` |
| **CI Checks** | Count passed/failed/pending from `statusCheckRollup` |
| **Merge State** | `mergeStateStatus` and `mergeable` |
| **Approvals** | Count approved reviews from humans (exclude bots) |

### Critical / P0 Comments

Scan all review comments for priority indicators:

- Image URLs containing `high-priority` or `critical-priority`
- Text containing `P0`, `critical`, `blocker`, `breaking`

**MUST check resolve status** using the GraphQL result (`isResolved` field):

- If a comment thread `isResolved: true` → the author already addressed it in a subsequent commit. **Mark it as ✅ Resolved** in the summary and do NOT flag it as a warning.
- If a comment thread `isResolved: false` → still open. **Flag it as an active issue** requiring attention.

Match REST comments to GraphQL threads by `path` + `line` (or body text snippet).

Presentation format:

```
### High-Priority Comments (if any)
- ✅ Resolved (N total): list each with one-line summary + "— Resolved"
- ⚠️ Unresolved (N total): list each with file path, line, and summary

If all resolved: "All N high-priority comments have been resolved."
If none found: "No critical / P0 comments found."
```

### Medium-Priority Summary

Briefly count and categorize medium-priority comments (one line each). Do not expand details unless asked. Also check resolve status from GraphQL — note how many are resolved vs unresolved.

**Gate: STOP here. Wait for user confirmation before proceeding.**

Confirmation signals: "confirm", "approved", "go ahead", "merge it", "yes", "ok", "lgtm", or similar affirmative intent.

## Phase 3: Merge

Run approve and squash merge sequentially:

```bash
gh pr review <PR_NUMBER> --approve && gh pr merge <PR_NUMBER> --squash
```

If merge fails due to branch protection, report the exact error and suggest options:
- Need human approval from another team member
- CI checks not passing
- Merge conflicts

After merge, verify:

```bash
gh pr view <PR_NUMBER> --json state,mergedAt,mergeCommit \
  --jq '{state, mergedAt, mergeCommit: .mergeCommit.oid}'
```

Report final state and merge commit hash.

## Red Flags

| Thought | Reality |
|---------|---------|
| "User said merge, just do it" | Present summary first. Always. |
| "No critical comments, skip the summary" | Show the summary anyway — user decides. |
| "CI is green so it's safe" | CI green + no approval ≠ safe. Show all signals. |
| "I'll approve my own PR silently" | Approval is part of the explicit flow. Never hide it. |
| "High-priority comment = blocker" | Check `isResolved` first. Resolved means author already fixed it. Don't flag resolved comments as warnings. |
