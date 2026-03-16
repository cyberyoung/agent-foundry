#!/usr/bin/env python3
"""
Relocate misplaced images in an Obsidian note to the conventional assets directory.

Convention: images for <dir>/<note>.md should live in <dir>/assets/<note>/<filename>.

Usage:
    python3 fix_image_paths.py <note.md> [--vault-root <path>] [--dry-run]
"""

import argparse
import os
import re
import shutil
import sys
from pathlib import Path

IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".bmp", ".tiff"}
EMBED_PATTERN = re.compile(r"!\[\[([^\]]+)\]\]")


def find_vault_root(note_path: Path) -> Path:
    """Walk up from note to find the vault root (directory containing .obsidian/)."""
    current = note_path.parent
    while current != current.parent:
        if (current / ".obsidian").is_dir():
            return current
        current = current.parent
    return note_path.parent


def is_image_path(embed_target: str) -> bool:
    clean = embed_target.split("|")[0].strip()
    return Path(clean).suffix.lower() in IMAGE_EXTENSIONS


def resolve_image(embed_target: str, note_dir: Path, vault_root: Path) -> Path | None:
    """Resolve an Obsidian embed target to an actual file path."""
    clean = embed_target.split("|")[0].strip()

    candidate = note_dir / clean
    if candidate.is_file():
        return candidate

    candidate = vault_root / clean
    if candidate.is_file():
        return candidate

    # Obsidian shortest-path search: walk the entire vault
    target_name = Path(clean).name
    for root, _dirs, files in os.walk(vault_root):
        if ".obsidian" in root:
            continue
        if target_name in files:
            return Path(root) / target_name

    return None


def compute_target_assets_dir(note_path: Path) -> Path:
    return note_path.parent / "assets" / note_path.stem


def process_note(
    note_path: Path, vault_root: Path, dry_run: bool = False
) -> list[dict]:
    """Process a note: find misplaced images, move them, update links."""
    note_dir = note_path.parent
    target_assets = compute_target_assets_dir(note_path)
    target_assets_rel = target_assets.relative_to(note_dir)

    with open(note_path, "r", encoding="utf-8") as f:
        content = f.read()

    actions = []
    new_content = content

    for match in EMBED_PATTERN.finditer(content):
        embed_target = match.group(1)
        if not is_image_path(embed_target):
            continue

        clean_target = embed_target.split("|")[0].strip()
        alias = embed_target.split("|")[1].strip() if "|" in embed_target else None

        # Already under <note-dir>/assets/ → skip (any subdirectory is fine)
        try:
            resolved = note_dir / clean_target
            if resolved.is_file():
                rel = resolved.relative_to(note_dir)
                if str(rel).startswith("assets/"):
                    continue
        except (ValueError, OSError):
            pass

        actual_path = resolve_image(embed_target, note_dir, vault_root)
        if actual_path is None:
            actions.append(
                {
                    "embed": embed_target,
                    "status": "NOT_FOUND",
                    "source": None,
                    "dest": None,
                }
            )
            continue

        dest_filename = Path(clean_target).name
        dest_path = target_assets / dest_filename
        new_rel = f"{target_assets_rel}/{dest_filename}"
        new_embed = f"![[{new_rel}]]" if alias is None else f"![[{new_rel}|{alias}]]"

        actions.append(
            {
                "embed": embed_target,
                "status": "MOVE",
                "source": str(actual_path),
                "dest": str(dest_path),
                "old_link": match.group(0),
                "new_link": new_embed,
            }
        )

        if not dry_run:
            target_assets.mkdir(parents=True, exist_ok=True)
            if actual_path != dest_path:
                shutil.move(str(actual_path), str(dest_path))
            new_content = new_content.replace(match.group(0), new_embed, 1)

    if not dry_run and new_content != content:
        with open(note_path, "w", encoding="utf-8") as f:
            f.write(new_content)

    return actions


def main():
    parser = argparse.ArgumentParser(
        description="Relocate misplaced images in Obsidian notes to assets/<note-stem>/"
    )
    parser.add_argument("note", help="Path to the Obsidian note (.md file)")
    parser.add_argument(
        "--vault-root", help="Vault root directory (auto-detected if omitted)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes",
    )
    args = parser.parse_args()

    note_path = Path(args.note).resolve()
    if not note_path.is_file():
        print(f"Error: {note_path} does not exist", file=sys.stderr)
        sys.exit(1)

    vault_root = (
        Path(args.vault_root).resolve()
        if args.vault_root
        else find_vault_root(note_path)
    )
    print(f"Vault root: {vault_root}")
    print(f"Note: {note_path.relative_to(vault_root)}")
    print(f"Target assets: assets/{note_path.stem}/")

    if args.dry_run:
        print("\n[DRY RUN] No changes will be made.\n")

    actions = process_note(note_path, vault_root, dry_run=args.dry_run)

    moved = [a for a in actions if a["status"] == "MOVE"]
    not_found = [a for a in actions if a["status"] == "NOT_FOUND"]

    if not actions:
        print("\nAll images are already in the correct location.")
        return

    if moved:
        prefix = "Would move" if args.dry_run else "Moved"
        print(f"\n{prefix} {len(moved)} image(s):")
        for a in moved:
            src_rel = Path(a["source"]).relative_to(vault_root)
            dest_rel = Path(a["dest"]).relative_to(vault_root)
            print(f"  {src_rel} → {dest_rel}")
            print(f"    {a['old_link']} → {a['new_link']}")

    if not_found:
        print(f"\nWARNING: {len(not_found)} image(s) not found:")
        for a in not_found:
            print(f"  ![[{a['embed']}]]")

    if not args.dry_run and moved:
        print(f"\nDone. Updated {note_path.name} with {len(moved)} new link(s).")


if __name__ == "__main__":
    main()
