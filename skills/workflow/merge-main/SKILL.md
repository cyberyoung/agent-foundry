---
name: wf-merge-main
description: Use when the user asks to merge main, sync main, rebase main, update a branch from main, resolve merge conflicts, or audit conflict resolution against main.
---

# Merge Main Workflow

## Overview

Merge-main work is correctness work, not just conflict cleanup. The invariant:
no resolution may delete, restore, or move logic from either parent without
evidence from history and call sites.

## When to Use

- User says `merge main`, `sync main`, `rebase main`, `update from main`
- User asks to resolve conflicts after merging `main`
- A branch has already merged `main` and needs audit
- A previous merge lost logic or restored intentionally removed code

Do not use for ordinary feature implementation or PR review triage unless the
task has turned into a main-sync/conflict-resolution task.

## Required Flow

### 1. Preflight

Run:

```bash
git branch --show-current
git status --short
git fetch origin main
git rev-parse HEAD origin/main
```

Stop if the worktree has unrelated dirty files. Ask before stashing,
committing, or overwriting anything. Never rebase a published PR branch unless
the user explicitly asks for history rewrite.

Record:

- current branch
- branch `HEAD` before merge
- `origin/main` SHA being merged
- whether the branch is published

### 2. Merge

Prefer:

```bash
git merge origin/main
```

Use the user-requested target if it is not `origin/main`. Resolve conflicts
locally and inspect every conflicted file before committing the merge.

After the merge commit exists, record:

```bash
git rev-parse HEAD HEAD^1 HEAD^2
git diff --name-only --diff-filter=U
rg -n '<<<<<<<|=======|>>>>>>>' .
```

Unmerged files or conflict markers are hard blockers.

### 3. Resolution Audit

Always run:

```bash
git show --remerge-diff --name-only HEAD
```

If it outputs files, those files had manual resolution. For each manual
resolution, decide whether it touches any high-risk object:

- public exports, barrel files, shared `utils`, `hooks`, `api` types/functions
- CI gates, scripts, package scripts, workflows
- `AGENTS.md`, workflow skills, OpenSpec rules
- routes, menu operations, permission operations, route `meta.action`

For each high-risk deletion/replacement/move, run history and call-site checks:

```bash
git log --all -S'<symbol>' -- <path>
git grep '<symbol>' HEAD^1 -- src scripts
git grep '<symbol>' HEAD^2 -- src scripts
git grep '<symbol>' HEAD -- src scripts
```

Treat docs/dev-log hits as historical context, not runtime call sites. If a
symbol was intentionally removed upstream, preserve the replacement contract
instead of restoring the old symbol.

### 4. Evidence

If manual resolution touched a high-risk object, create or update:

```text
docs/evidence/merge-audit/<merge-sha>.md
```

Each entry must include:

- `Decision`: `keep-main`, `keep-branch`, `combine`, or `intentional-removal`
- `Evidence`: relevant `git log -S` commit, both parent call-site checks, final
  call-site check
- `Rationale`: why the final resolution preserves both sides' intended logic

If no high-risk manual resolution exists, include the audit table in the final
response instead of creating an evidence file.

### 5. Test Discipline

RED tests after conflict resolution must be based on verified evidence. Do not
edit expected export lists, snapshots, or allowlists from a guess.

Valid RED sources:

- historical commit message or patch
- review comment text
- live call site in either parent
- AGENTS/OpenSpec rule
- existing failing behavior reproduced locally

Invalid RED source:

- "the symbol existed in one parent, therefore it must still exist"

### 6. Verification

At minimum run:

```bash
git diff --name-only --diff-filter=U
rg -n '<<<<<<<|=======|>>>>>>>' .
git diff --check
```

Then run targeted tests for affected code and the repository's required task
gate. For infrastructure/script changes, include the relevant script tests. For
docs-only merge-audit evidence, include `pnpm check:task --test-exempt docs-only`
when applicable.

Do not claim the merge is safe until:

- no unmerged files remain
- no conflict markers remain
- manual resolutions have audit decisions
- high-risk decisions have evidence
- targeted verification passed or any inability to run it is explicitly stated

## Final Report

Report:

- merge commit SHA and both parents
- manual resolution files from `remerge-diff`
- high-risk decisions and evidence path, if any
- tests/gates run and results
- remaining risk or skipped verification
