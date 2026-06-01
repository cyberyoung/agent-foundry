---
name: wf-worktree-cleanup
description: "Clean up git worktrees whose PRs have been merged. Use when the user asks to clean up a worktree, remove a finished feature worktree, or tidy up after PR merge. Triggers include: 'clean worktree', 'remove worktree', 'worktree cleanup', 'PR已合并清理', or any request to clean up after a merged PR."
---

# Worktree Cleanup

Clean up git worktrees after their PRs have been merged. Verifies merge status via GitHub before deleting anything. Automated cleanup is canonical-only: targets must be under `../worktrees/{repo-name}/{slug}`.

## Safety

- **Never deletes a worktree outside `../worktrees/{repo-name}/{slug}`** — legacy sibling worktrees require inventory and manual confirmation
- **Never deletes a worktree whose PR is still open, closed-unmerged, has no PR, or has a GitHub query error** — always checks `gh pr list --repo <owner/repo>` first
- Handles repos that auto-delete remote branches on merge (silently skips the remote delete if branch is already gone)
- Uses `git branch -d` (safe delete) first; force deletion requires proof that the branch head is safe relative to the merged baseline
- Merges `.claude/settings.local.json`, `opencode.json`, and Claude memory from the worktree back to the primary repo before removal. If settings or opencode merge fails, cleanup stops and the worktree is preserved.

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

**2. Clean a specific canonical worktree**

```bash
bash <skill-base-dir>/scripts/worktree-cleanup.sh ../worktrees/{repo-name}/{slug}
```

**3. Clean all merged canonical worktrees**

```bash
bash <skill-base-dir>/scripts/worktree-cleanup.sh --all
```

## What it does

For each target worktree:

1. **Resolve primary repo** — uses the shared primary repo resolver, not porcelain `head -1`
2. **Enforce canonical boundary** — refuses any target outside `../worktrees/{repo-name}/{slug}`
3. **Identify branch** — extracts the branch name from `git worktree list`
4. **Check PR status** — queries GitHub via `gh pr list --repo <owner/repo> --head <branch>`
   - `MERGED` → proceed with cleanup
   - `OPEN` → skip, warn user
   - `CLOSED` → skip, warn user
   - `NO_PR` → skip, warn user
   - `GH_ERROR` → skip, warn user with the underlying error summary
5. **Validate clean state** — blocks detached HEAD, merge/rebase/cherry-pick state, unstaged/staged/untracked files, missing upstream, unresolved upstream, and unpushed commits
6. **Merge local agent state** — merges `.claude/settings.local.json`, `opencode.json`, and Claude memory into the primary repo
7. **Remove worktree** — `git worktree remove <path>`; unexpected failure stops cleanup and does not unconditionally force remove
8. **Clean leftover residue** — only for verified canonical target residue that is no longer registered as a worktree; empty parents are cleaned with `rmdir`
9. **Delete local branch** — `git branch -d` first; stronger deletion only with safety proof
10. **Delete remote branch** — `git push origin --delete` — if remote branch already gone (auto-deleted on merge), silently succeeds

## Post-cleanup review summary (MANDATORY)

After cleanup attempts finish, provide a factual review table of the exact
things that happened. Do not summarize only the intended workflow. Include
script successes, script skips, manual follow-up actions, moved/preserved files,
remaining dirty state, and final verification.

Use this table format:

| Target | Branch | PR status | Actions actually performed | Result | Review notes |
| --- | --- | --- | --- | --- | --- |
| `/path/to/worktree` | `branch-name` | `#123 merged at YYYY-MM-DDTHH:MM:SSZ` | `git worktree remove`; deleted local branch; remote already gone | cleaned | Note any force delete, residual directory cleanup, moved files, skipped remote delete, or remaining files in main worktree |

The final answer must also include:

- Final `git worktree list` verification for each affected repository
- Whether each target path still exists
- Any files preserved outside the removed worktree and their new paths
- Whether `.claude/settings.local.json`, `opencode.json`, and Claude memory were merged, skipped, or blocked
- Any remaining untracked or modified files in the main worktree

## Prerequisites

- `gh` CLI authenticated (`gh auth status`)
- Must be run from within a git repository (any worktree of it)

## Important: CWD after cleanup

If the user is inside the worktree being cleaned, their shell cwd will become invalid after removal. Remind them to `cd` to the main repo or another worktree.
