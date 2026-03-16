# Skills

Shared skill source tree for `/Users/liyang/OneDrive/life/etc/agents`.

For the initial public-facing repository shape, the published subset is the first-wave Obsidian skills under `obsidian/`.

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

## Public-First Published Subset

- `obsidian/pdf-to-obsidian/`
- `obsidian/docx-converter/`
- `obsidian/fix-image-paths/`
- `obsidian/bookmarks-to-note/`

See root-level public docs for install, structure, and compatibility guidance.
