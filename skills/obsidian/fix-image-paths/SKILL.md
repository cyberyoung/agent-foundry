---
name: ob-fix-image-paths
description: 修复 Obsidian 笔记中的图片路径，将不规范位置的图片迁移到约定的 assets 目录并自动更新嵌入链接。
---

# fix-image-paths

Relocate misplaced images in Obsidian notes to the conventional `assets/` directory.

## Convention

Images referenced in `<dir>/<note>.md` should live under `<dir>/assets/`. Images found elsewhere (e.g. vault root from Obsidian paste) are moved to `<dir>/assets/<note-stem>/` and links are updated.

## Usage

```bash
# Dry run (preview only)
python3 scripts/fix_image_paths.py <note.md> --dry-run

# Execute (move files + update links)
python3 scripts/fix_image_paths.py <note.md>

# With explicit vault root
python3 scripts/fix_image_paths.py <note.md> --vault-root /path/to/vault
```

Local convenience wrapper (accepts vault-relative note path):

```bash
bash scripts/to_vault.sh <note-path-or-rel> [extra-args...]

# Dry run with vault-relative note path
bash scripts/to_vault.sh "research/weekly-review.md" --dry-run

# Skip confirmation prompt
bash scripts/to_vault.sh "research/weekly-review.md" --yes --dry-run
```

Wrapper notes:
- Vault root: `$OBSIDIAN_VAULT`; otherwise the wrapper uses its local default vault path
- If note path is relative, it is resolved against the vault root
- `--vault-root` is auto-injected unless explicitly provided
- Wrapper shows a final execution preview and asks for confirmation by default
- Use `--yes` / `--no-confirm` to skip confirmation, `--confirm` to force it

## Features

| Feature | Description |
|---------|-------------|
| Auto vault-root detection | Walks up from note to find `.obsidian/` |
| Obsidian path resolution | Resolves `![[name]]` via relative, vault-root, and shortest-path search |
| Smart skip | Images already under `assets/` are left untouched |
| Alias preservation | `![[img\|alias]]` links retain their display text |
| Dry run | `--dry-run` previews all changes without modifying anything |
| Image formats | `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.webp`, `.bmp`, `.tiff` |

## How It Works

1. Parse all `![[...]]` image embeds in the note
2. For each image, check if it's already under `<note-dir>/assets/`
3. If not, locate the actual file (note dir → vault root → full vault search)
4. Move the file to `<note-dir>/assets/<note-stem>/`
5. Update the embed link in the note to use the new relative path

## Dependencies

- Python 3.10+ (uses `Path | None` union syntax)
- No external packages required

## Public Release Notes

- The core public interface is `scripts/fix_image_paths.py`.
- `scripts/to_vault.sh` is a local convenience wrapper for vault-relative note paths.
- `scripts/weekly_stock_fix.sh` is workflow-specific and should not be treated as the primary public entrypoint.
