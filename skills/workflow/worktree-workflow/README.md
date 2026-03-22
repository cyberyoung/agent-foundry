# wf-worktree-workflow

Enforce plan-first workflow for git worktree feature isolation.

## What It Does

Prevents agents from skipping the planning phase when creating worktrees. All design docs and plans must be created on the main branch first, reviewed by the human, then physically moved (`mv`) to the worktree.

## When To Use It

- Multi-file feature work requiring a plan
- Before any `git worktree add` command
- Task involves isolated development branches

## Project Integration

This skill defines the universal flow. Project-specific conventions (naming patterns, plan template paths, artifact directories) are read from the project's AGENTS.md at execution time.

## Requirements

- Project AGENTS.md with a `GIT WORKFLOW` section
- Planning directory structure (e.g., `.sisyphus/designs/`, `.sisyphus/plans/`)
