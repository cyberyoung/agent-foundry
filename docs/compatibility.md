# Compatibility

This document summarizes the current public-first compatibility expectations.

## Runtime Targets

The active skills system syncs into:

- `~/.claude/skills`
- `~/.codex/skills`
- `~/.config/opencode/skills`

## Public Skill Set

### `pdf-to-obsidian`

- runtime name: `ob-pdf-to-obsidian`
- requires: `python3`, `pymupdf`

### `docx-converter`

- runtime name: `ob-docx-converter`
- requires: `python3`, `python-docx`

### `fix-image-paths`

- runtime name: `ob-fix-image-paths`
- requires: `python3`

### `bookmarks-to-note`

- runtime name: `ob-bookmarks-to-note`
- requires: `python3`, access to Chrome bookmarks JSON input

### `images-to-note`

- runtime name: `ob-images-to-note`
- requires: `python3`
- optional platform-specific dependency: macOS `sips` for HEIC conversion

### `image-captioner`

- runtime name: `ob-image-captioner`
- requires: `python3`

## Wrapper Notes

Some skills include local convenience wrappers. The public-facing core interface should be considered the main script described in each skill's `README.md`.

## Namespace Notes

- `obsidian/` uses `.prefix = ob`
- `skill-management/` uses `.prefix = sm`, but that namespace is not part of the current public-first subset
