# wf-worktree-workflow

Enforce plan-first workflow for git worktree feature isolation.

## What It Does

Prevents agents from skipping the planning phase when creating worktrees. All design docs and plans must be created on the main branch first, reviewed by the human, then physically moved (`mv`) to the canonical worktree at `../worktrees/{repo-name}/{slug}`.

## When To Use It

- Multi-file feature work requiring a plan
- Before any worktree creation command
- Task involves isolated development branches

## Project Integration

This skill defines the universal flow. Project-specific conventions (naming patterns, plan template paths, artifact directories) are read from the project's AGENTS.md at execution time. Projects may add stricter rules, but they must not fall back to scattered sibling worktrees.

When `using-git-worktrees`, `executing-plans`, or `subagent-driven-development` asks for isolated development after this skill has created the canonical worktree, the already-created canonical worktree satisfies that isolation requirement. Do not create a second worktree.

## Requirements

- Project AGENTS.md with a `GIT WORKFLOW` section
- Planning directory structure (e.g., `.sisyphus/designs/`, `.sisyphus/plans/`)
- Canonical path shape: `../worktrees/{repo-name}/{slug}`
- No repo-local `.worktrees/`, repo-local `worktrees/`, global fallback, or scattered sibling worktree fallback
