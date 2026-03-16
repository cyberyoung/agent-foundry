# Agents Architecture

## Design Root

The design root is:

`/Users/liyang/OneDrive/life/etc/agents`

This root currently exposes a public-first view centered on reusable skills.

## Current State

The current public-first shape centers on `skills/` and a small set of root-level documentation.

Current shape:

```text
/etc/agents/
├── skills/
├── docs/
├── claude.json
├── dot-claude/
└── dot-codex/
```

The active work is scoped to `skills/` and the current root-level docs, not to a broader multi-domain rollout.

## Design Principles

- keep `skills/` as the current source-of-truth asset domain
- keep public-facing docs focused on current facts and current release scope
- keep runtime distribution separate from source layout

## Current Namespace Decisions

Within `skills/`:

- `obsidian/` is a live namespace with `.prefix = ob`
- `skill-management/` is a live namespace with `.prefix = sm`
- `find-skills/` remains standalone and upstream-sourced

## Compatibility Constraint

The current sync/discovery mechanism exposes namespace children only when the namespace directory has a `.prefix` file. This is why `skill-management/` required `.prefix = sm` when it became a real namespace.
