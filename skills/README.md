# Skills

This directory contains the public skill catalog for `agent-foundry`.

## Current Catalog

The current public catalog is focused on Obsidian-oriented skills for document conversion and note maintenance.

## Included Skills

- `obsidian/pdf-to-obsidian/` - convert PDF files into Obsidian-compatible Markdown notes
- `obsidian/docx-converter/` - convert Word documents into Obsidian-compatible Markdown notes
- `obsidian/fix-image-paths/` - normalize embedded image paths and local asset layout in notes
- `obsidian/bookmarks-to-note/` - convert Chrome bookmark folders into structured Markdown notes
- `obsidian/images-to-note/` - generate a note from a directory of images
- `obsidian/image-captioner/` - add missing captions to embedded images in a single note

## Runtime Names

Published Obsidian skills are exposed with the `ob-` prefix in supported runtimes.

If you want to create a new skill from scratch and install it locally, see:

- `docs/authoring.md`

Examples:

- `ob-pdf-to-obsidian`
- `ob-docx-converter`
- `ob-fix-image-paths`
- `ob-bookmarks-to-note`
- `ob-images-to-note`
- `ob-image-captioner`

See the root-level public docs for install, structure, and compatibility guidance.

## Document Index (skills/)

This index lists all Markdown documents under `skills/docs/`.

| Document | Description |
| --- | --- |
| `docs/authoring.md` | End-to-end runbook for skill authoring and local deployment. |
| `docs/compatibility.md` | Runtime compatibility and exposed-name rules for synced skills. |
| `docs/first-release-gap-analysis.md` | Gap matrix and readiness analysis for first public release. |
| `docs/first-release-shortlist.md` | First-wave, second-wave, deferred, and excluded skill shortlist. |
| `docs/publishing-policy.md` | Publishing policy by source type and release scope. |
| `docs/structure.md` | Skills tree structure, naming layers, and namespace behavior. |
