# Installation

This repository is designed so selected skills can be copied or symlinked into a runtime-specific skills directory.

## Supported Runtime Targets

- `~/.claude/skills`
- `~/.codex/skills`
- `~/.config/opencode/skills`

## Install One Skill By Copying

Example:

```bash
cp -R skills/obsidian/pdf-to-obsidian ~/.config/opencode/skills/ob-pdf-to-obsidian
```

## Install One Skill By Symlink

Example:

```bash
ln -s /path/to/agents/skills/obsidian/pdf-to-obsidian ~/.config/opencode/skills/ob-pdf-to-obsidian
```

Use the exposed runtime name when creating the destination directory name.

Examples:

- `ob-pdf-to-obsidian`
- `ob-docx-converter`
- `ob-fix-image-paths`
- `ob-bookmarks-to-note`

## Current Public-First Subset

The initial public-facing subset is:

- `skills/obsidian/pdf-to-obsidian/`
- `skills/obsidian/docx-converter/`
- `skills/obsidian/fix-image-paths/`
- `skills/obsidian/bookmarks-to-note/`

## Notes

- some skills depend on local Python packages
- some skills include local convenience wrappers in addition to their public core scripts
- review each skill's `README.md` before installation
