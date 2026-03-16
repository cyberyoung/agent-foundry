# Agent Foundry

A collection of reusable assets for agent workflows, starting with Obsidian-focused skills for document conversion and note maintenance.

## Included Skills

The current public set includes:

- `pdf-to-obsidian` - Convert PDF files into Obsidian-compatible Markdown notes.
- `docx-converter` - Convert Word documents into Obsidian-compatible Markdown notes.
- `fix-image-paths` - Normalize embedded image paths and local asset layout in notes.
- `bookmarks-to-note` - Convert Chrome bookmark folders into structured Markdown notes.
- `images-to-note` - Generate a note from a directory of images.
- `image-captioner` - Add missing captions to embedded images in a single note.

## Quick Start

Install a skill by copying or symlinking its directory into your runtime's skills directory.

Example:

```bash
ln -s /path/to/agent-foundry/skills/obsidian/pdf-to-obsidian ~/.config/opencode/skills/ob-pdf-to-obsidian
```

See `docs/installation.md` for more installation options.

## Repository Layout

- `skills/` - public skill catalog
- `docs/` - repository-level installation, structure, and compatibility notes

## Skill Namespaces

- `obsidian/` - publicly exposed as `ob-*`

## Learn More

- `docs/installation.md`
- `docs/structure.md`
- `docs/compatibility.md`
- `skills/README.md`
