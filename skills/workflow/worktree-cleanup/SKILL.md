---
name: wf-worktree-cleanup
description: "Clean up git worktrees whose PRs have been merged. Use when the user asks to clean up a worktree, remove a finished feature worktree, or tidy up after PR merge. Triggers include: 'clean worktree', 'remove worktree', 'worktree cleanup', 'PR已合并清理', or any request to clean up after a merged PR."
---

# Worktree Cleanup

Clean up git worktrees after their PRs have been merged. Verifies merge status via GitHub before deleting anything.

## Safety

- **Never deletes a worktree whose PR is still open or has no PR** — always checks `gh pr list --state merged` first
- Handles repos that auto-delete remote branches on merge (silently skips the remote delete if branch is already gone)
- Uses `git branch -d` (safe delete) first, falls back to `-D` only when PR merge is confirmed

## Pre-flight (MANDATORY before running the script)

1. Identify the branch: `git worktree list | grep <path>`
2. Query PR status: `gh pr list --head <branch> --state merged --repo <owner/repo> --json number,title,mergedAt`
3. **Show the result to the user** — PR number, title, merge date
4. **Wait for user confirmation** before running the cleanup script
5. If no merged PR found, also check `--state closed` and `--state open` to report the actual status

Do NOT run the cleanup script directly — always confirm PR status with the user first.

## Usage

### From the skill (Claude Code invocation)

The user may invoke this skill in three ways:

**1. Clean current worktree**

If the user's cwd is inside a worktree and they say "clean up this worktree":

```bash
bash <skill-base-dir>/scripts/worktree-cleanup.sh "$(pwd)"
```

**2. Clean a specific worktree**

```bash
bash <skill-base-dir>/scripts/worktree-cleanup.sh /path/to/worktree
```

**3. Clean all merged worktrees**

```bash
bash <skill-base-dir>/scripts/worktree-cleanup.sh --all
```

## What it does

For each target worktree:

1. **Identify branch** — extracts the branch name from `git worktree list`
2. **Check PR status** — queries GitHub via `gh pr list --head <branch>`
   - `MERGED` → proceed with cleanup
   - `OPEN` → skip, warn user
   - `NO_PR` → skip, warn user
3. **Remove worktree** — `git worktree remove <path>` (force if untracked files)
4. **Delete local branch** — `git branch -d` (safe), falls back to `-D` if PR is confirmed merged
5. **Delete remote branch** — `git push origin --delete` — if remote branch already gone (auto-deleted on merge), silently succeeds

## Prerequisites

- `gh` CLI authenticated (`gh auth status`)
- Must be run from within a git repository (any worktree of it)

## Important: CWD after cleanup

If the user is inside the worktree being cleaned, their shell cwd will become invalid after removal. Remind them to `cd` to the main repo or another worktree.
