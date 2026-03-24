# Installation

This repository is designed so selected skills can be copied or symlinked into a runtime-specific skills directory.

## Supported Runtime Targets

- `~/.claude/skills`
- `~/.codex/skills`
- `~/.config/opencode/skills`

## Compatibility Notes

### Runtime Targets

The active skills system syncs into the same three runtime targets listed above.

### Public Skill Set Compatibility

#### `pdf-to-obsidian`

- runtime name: `ob-pdf-to-obsidian`
- requires: `python3`, `pymupdf`

#### `docx-converter`

- runtime name: `ob-docx-converter`
- requires: `python3`, `python-docx`

#### `fix-image-paths`

- runtime name: `ob-fix-image-paths`
- requires: `python3`

#### `bookmarks-to-note`

- runtime name: `ob-bookmarks-to-note`
- requires: `python3`, access to Chrome bookmarks JSON input

#### `images-to-note`

- runtime name: `ob-images-to-note`
- requires: `python3`
- optional platform-specific dependency: macOS `sips` for HEIC conversion

#### `image-captioner`

- runtime name: `ob-image-captioner`
- requires: `python3`

### Wrapper and Namespace Notes

- Some skills include local convenience wrappers. The public-facing core interface should be considered the main script described in each skill's `README.md`.
- `obsidian/` uses `.prefix = ob`
- `skill-management/` uses `.prefix = sm`, but that namespace is not part of the current public-first subset

## Creating a New Skill First?

If you are creating a brand-new skill (instead of installing an existing one), use:

- `skills/docs/authoring.md`

That guide covers directory layout, required `SKILL.md`, naming with namespace prefixes, sync workflow, and verification.

## Install One Skill By Copying

Example:

```bash
mkdir -p ~/.config/opencode/skills
cp -R skills/obsidian/pdf-to-obsidian ~/.config/opencode/skills/ob-pdf-to-obsidian
```

## Install One Skill By Symlink

Example:

```bash
mkdir -p ~/.config/opencode/skills
ln -s /path/to/agent-foundry/skills/obsidian/pdf-to-obsidian ~/.config/opencode/skills/ob-pdf-to-obsidian
```

Use the exposed runtime name when creating the destination directory name.

Examples:

- `ob-pdf-to-obsidian`
- `ob-docx-converter`
- `ob-fix-image-paths`
- `ob-bookmarks-to-note`

## Current Public Catalog

The current public catalog includes:

- `skills/obsidian/pdf-to-obsidian/`
- `skills/obsidian/docx-converter/`
- `skills/obsidian/fix-image-paths/`
- `skills/obsidian/bookmarks-to-note/`
- `skills/obsidian/images-to-note/`
- `skills/obsidian/image-captioner/`

## Notes

- some skills depend on local Python packages
- some skills include local convenience wrappers in addition to their public core scripts
- review each skill's `README.md` before installation
