# Skills

This directory contains the public skill catalog for `agent-foundry`.

## Namespaces

- `find-skills/` - standalone upstream skill kept at the top level
- `obsidian/` - Obsidian-focused skills, exposed with the `ob-` prefix via `obsidian/.prefix`
- `skill-management/` - internal lifecycle and sync skills, exposed with the `sm-` prefix via `skill-management/.prefix`

## Exposure Rules

- A top-level directory without `.prefix` is exposed as a standalone skill
- A top-level directory with `.prefix` is treated as a namespace container
- Each child skill under a namespaced directory is exposed as `{prefix}-{child-name}`

## Current Runtime Namespaces

- `ob-*` for `obsidian/`
- `sm-*` for `skill-management/`

## Public Skill Set

- `obsidian/pdf-to-obsidian/`
- `obsidian/docx-converter/`
- `obsidian/fix-image-paths/`
- `obsidian/bookmarks-to-note/`
- `obsidian/images-to-note/`
- `obsidian/image-captioner/`

See root-level public docs for install, structure, and compatibility guidance.
