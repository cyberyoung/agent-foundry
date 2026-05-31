---
name: wf-infra-merge-refresh
description: Use when preparing to merge a PR or branch that may include infrastructure changes, migration-analysis updates, CI/scripts/hooks/docs tooling, or when the user asks to check infra PR merge readiness.
---

# Infrastructure Merge Refresh

## Overview

Before any infra-affecting PR merges, refresh the migration analysis against the
latest target branch. The invariant is snapshot comparison: compare the latest
`origin/main` document baseline to the branch's final `HEAD`, not commit dates,
author dates, or PR merge order.

## When to Use

Use this for PRs or branches that touch, add, remove, or may indirectly affect:

- `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.github/`, `.claude/`
- `scripts/`, CI checks, hooks, generators, docs tooling
- package scripts, lockfile/tooling updates
- `docs/infrastructure-migration-analysis.md`
- reusable process docs that change how future work is performed

Do not use this for pure product code with no infra/tooling/process impact.

## Required Sources

1. Read the repo's `AGENTS.md`.
2. Read `docs/infrastructure-migration-analysis.md`.
3. Use the single guarded bash block in that document's “合并前刷新流程”.

If the document is missing from `origin/main`, report that this is the first
landing flow and a full infra inventory is required. Do not pretend an
incremental diff is reliable.

## Core Flow

1. Confirm the current branch and target branch.
   - Default target is `origin/main`.
   - Never operate directly on local `main`.
   - Determine whether the branch is a published PR branch: it has an upstream
     remote branch or an open PR. If unsure and the branch has an upstream,
     treat it as published.
2. Check working tree state with `git status --short`.
   - If dirty, do not sync blindly.
   - Ask whether to commit/stash, or use the document's dirty-analysis path
     only after the branch already contains latest `origin/main`.
3. Fetch and sync latest target branch into the PR branch.
   - For published PR branches, prefer `git merge origin/main` so existing PR
     history is not rewritten.
   - For unpublished local-only branches, rebase is acceptable unless repo/user
     policy says merge.
   - Never rebase a published PR branch or force-push unless the user
     explicitly asks for that history rewrite.
4. Run the document's single guarded bash block.
   - First pass with empty `INFRA_PATHS` and `UNTRACKED_INFRA_FILES` is only
     discovery and must not be treated as merge-ready.
   - Fill `INFRA_PATHS` and/or `UNTRACKED_INFRA_FILES` from discovery output,
     then rerun the same block for detail diff.
5. Decide whether the migration analysis doc needs an update.
   - Update it if the infra change affects portability, target project fit,
     migration steps, dependencies, config, maintenance boundary, or future
     process.
   - If no update is needed, record the reason in the PR summary/comment.
6. Verify before reporting ready.
   - For docs-only updates in chogori, use:
     `pnpm check:task --test-exempt docs-only`
   - Also run `git diff --check`.
   - If `AGENTS.md` or `CLAUDE.md` changed, run:
     `node scripts/ci/check-agents-language.mjs`

## Decision Rules

- PR order does not determine coverage. Final tree diff determines coverage.
- Older commits on the PR branch are still detected after syncing `origin/main`
  if their final file changes remain in `HEAD`.
- Missing diff is acceptable only when the final branch tree has no net infra
  change relative to the main document baseline.
- If conflict resolution dropped infra changes, the diff will not show them;
  inspect the conflict result before declaring ready.
- If another infra PR merges after the refresh, repeat the flow.

## Red Flags

Stop and report the issue when any of these appear:

- The agent copies a local `git diff` command instead of using the single
  guarded document block.
- `MAIN_DOC_BASE` is empty but the agent continues with incremental analysis.
- Discovery output is used as final proof without a second detail pass.
- Staged or untracked files are ignored.
- The branch is behind `origin/main` during dirty analysis.
- A published PR branch is rebased, or a force-push is attempted, without
  explicit user authorization.
- The agent updates review findings automatically without explicit user
  authorization, unless the user asked for automatic fixes.

## Report Format

End with:

- branch and target branch
- whether latest `origin/main` was synced
- document baseline source
- infra paths inspected
- whether `docs/infrastructure-migration-analysis.md` was updated or why not
- verification commands and results
