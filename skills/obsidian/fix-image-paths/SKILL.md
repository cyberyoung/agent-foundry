---
name: ob-fix-image-paths
description: 修复 Obsidian 笔记中的图片路径，将不规范位置的图片迁移到约定的 assets 目录并自动更新嵌入链接。
---

# fix-image-paths

Relocate misplaced images in Obsidian notes to the conventional `assets/` directory.

## Convention

Images referenced in `<dir>/<note>.md` should live under `<dir>/assets/`. Images found elsewhere (e.g. vault root from Obsidian paste) are moved to `<dir>/assets/<note-stem>/` and links are updated.

## Usage

### Single note (core script)

```bash
python3 scripts/fix_image_paths.py <note.md> --dry-run
python3 scripts/fix_image_paths.py <note.md>
python3 scripts/fix_image_paths.py <note.md> --vault-root /path/to/vault
```

### Single note (convenience wrapper)

```bash
bash scripts/to_vault.sh <note-path-or-rel> [extra-args...]
bash scripts/to_vault.sh "stock/调研笔记/2026/03/研报阅读202603-W1.md" --dry-run
bash scripts/to_vault.sh "stock/调研笔记/2026/03/研报阅读202603-W1.md" --yes --dry-run
```

When no note path is given, the wrapper shows an interactive menu listing recent notes and `.md` files (recursively) from `stock/文章笔记/` and `stock/调研笔记/`:

```bash
bash scripts/to_vault.sh
bash scripts/to_vault.sh --dry-run
```

Wrapper notes:
- Vault root: `$OBSIDIAN_VAULT`; otherwise the wrapper uses its local default vault path
- If note path is relative, it is resolved against the vault root
- `--vault-root` is auto-injected unless explicitly provided
- Wrapper shows a final execution preview and asks for confirmation by default
- Use `--yes` / `--no-confirm` to skip confirmation, `--confirm` to force it
- Recent note selections are saved to `.to_vault_note_history`

### Batch processing

```bash
bash scripts/batch_fix.sh --dry-run
bash scripts/batch_fix.sh
bash scripts/batch_fix.sh "stock/文章笔记"
bash scripts/batch_fix.sh --vault-root ~/vault "research/notes" "stock/调研笔记"
```

- Recursively processes all `.md` files in the given directories (default: `stock/文章笔记`, `stock/调研笔记`)
- Supports `--dry-run` and `--vault-root`
- Prints per-note results and a final summary
- Scheduled via launchd (`com.liyang.obfix.daily`) to run every day at 9:00 AM

## Features

| Feature | Description |
|---------|-------------|
| Auto vault-root detection | Walks up from note to find `.obsidian/` |
| Obsidian path resolution | Resolves `![[name]]` via relative, vault-root, and shortest-path search |
| Smart skip | Images already under `assets/` are left untouched |
| Alias preservation | `![[img\|alias]]` links retain their display text |
| Dry run | `--dry-run` previews all changes without modifying anything |
| Image formats | `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.webp`, `.bmp`, `.tiff` |
| Recursive discovery | Finds notes in nested subdirectories (e.g. `2026/03/`) |
| Interactive selection | `to_vault.sh` prompts for note when no path given |
| Batch processing | `batch_fix.sh` recursively processes all notes in configurable directories |

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

- Core script: `scripts/fix_image_paths.py`
- Interactive wrapper: `scripts/to_vault.sh` (supports interactive note selection when no path given)
- Batch script: `scripts/batch_fix.sh` (processes all notes in configurable directories, scheduled via launchd)
