# Agents

Source tree for reusable agent assets.

This repository is being shaped so `/Users/liyang/OneDrive/life/etc/agents` can serve as the future public repository root. The current public-first scope is limited to selected skills under `skills/obsidian/`.

## Current Scope

`/Users/liyang/OneDrive/life/etc/agents` is the design root for a broader agent repository.

Today, the only actively implemented asset domain is `skills/`.

## Current Implementation Boundary

The working implementation is currently centered on:

- `skills/`
- `docs/`

Within `skills/`, the active namespaces are:

- `obsidian/` exposed as `ob-*`
- `skill-management/` exposed as `sm-*`

`find-skills/` remains a standalone upstream skill at the top level of the `skills/` subtree.

## Runtime Distribution

Skills are synced into:

- `~/.claude/skills`
- `~/.codex/skills`
- `~/.config/opencode/skills`

## Public-First Scope

The initial public-facing skill set is centered on:

- `skills/obsidian/pdf-to-obsidian/`
- `skills/obsidian/docx-converter/`
- `skills/obsidian/fix-image-paths/`
- `skills/obsidian/bookmarks-to-note/`

See:

- `docs/installation.md`
- `docs/structure.md`
- `docs/compatibility.md`
- `skills/README.md`
