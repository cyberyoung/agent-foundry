#!/usr/bin/env python3
"""Generate an Obsidian note from all images in a directory.

Images are embedded in filename-sorted order.
HEIC files are converted to JPG via macOS `sips` by default.
Idempotent: safe to run repeatedly on the same directory.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path

SUPPORTED_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".gif",
    ".webp",
    ".bmp",
    ".tiff",
    ".tif",
    ".heic",
}

EMBEDDABLE_EXTENSIONS = SUPPORTED_EXTENSIONS - {".heic"}


def find_images(directory: Path) -> list[Path]:
    """Return image files in *directory* sorted case-insensitively by name."""
    return sorted(
        (
            f
            for f in directory.iterdir()
            if f.is_file() and f.suffix.lower() in SUPPORTED_EXTENSIONS
        ),
        key=lambda p: p.name.lower(),
    )


def convert_heic_to_jpg(heic_path: Path) -> Path:
    """Convert a HEIC file to JPG using macOS sips. Returns the new path."""
    jpg_path = heic_path.with_suffix(".jpg")
    subprocess.run(
        ["sips", "-s", "format", "jpeg", str(heic_path), "--out", str(jpg_path)],
        check=True,
        capture_output=True,
    )
    return jpg_path


def read_existing_date(note_path: Path) -> str | None:
    """Extract the date field from an existing note's YAML frontmatter."""
    if not note_path.exists():
        return None
    try:
        text = note_path.read_text(encoding="utf-8")
    except OSError:
        return None
    match = re.search(r"^date:\s*(.+)$", text, re.MULTILINE)
    return match.group(1).strip() if match else None


def convert_heic_files(heic_images: list[Path], *, dry_run: bool) -> list[Path]:

    converted: list[Path] = []
    for heic in heic_images:
        jpg_path = heic.with_suffix(".jpg")
        if jpg_path.exists():
            print(f"Already converted: {heic.name} (skipped)")
            continue
        if dry_run:
            print(f"[dry-run] Would convert: {heic.name} -> {heic.stem}.jpg")
        else:
            print(f"Converting: {heic.name} -> {heic.stem}.jpg")
            convert_heic_to_jpg(heic)
        converted.append(heic)
    return converted


def collect_embed_list(
    directory: Path, *, convert_heic: bool, dry_run: bool
) -> list[Path]:
    """Build the deduplicated, sorted list of images to embed.

    When convert_heic is True, HEIC files are excluded from the embed list
    (their JPG counterparts are used instead).  In dry-run mode, not-yet-
    converted JPGs are synthesised so the preview is accurate.
    """
    if not convert_heic:
        return find_images(directory)

    real_files = sorted(
        (
            f
            for f in directory.iterdir()
            if f.is_file() and f.suffix.lower() in EMBEDDABLE_EXTENSIONS
        ),
        key=lambda p: p.name.lower(),
    )

    if not dry_run:
        return real_files

    real_names = {f.name.lower() for f in real_files}
    pending_jpgs = [
        heic.with_suffix(".jpg")
        for heic in directory.iterdir()
        if heic.is_file()
        and heic.suffix.lower() == ".heic"
        and heic.with_suffix(".jpg").name.lower() not in real_names
    ]
    return sorted(real_files + pending_jpgs, key=lambda p: p.name.lower())


def extract_existing_images(note_path: Path) -> set[str]:
    """Extract image filenames already embedded in the note.

    Returns a set of filenames (case-sensitive as they appear in the note).
    """
    if not note_path.exists():
        return set()
    try:
        text = note_path.read_text(encoding="utf-8")
    except OSError:
        return set()

    # Match ![[filename.ext]] format
    pattern = r"!\[\[([^\]]+\.(?:jpg|jpeg|png|gif|webp|bmp|tiff?|heic))\]\]"
    matches = re.findall(pattern, text, re.IGNORECASE)
    return {Path(m).name for m in matches}


def generate_image_title(image_path: Path) -> str:
    """Generate a readable title from image filename.

    Examples:
        IMG_20260211_160442.jpg -> "2026-02-11 16:04:42"
        IMG_9609.jpg -> "IMG_9609"
    """
    stem = image_path.stem

    # Pattern: IMG_YYYYMMDD_HHMMSS
    match = re.match(r"IMG_(\d{8})_(\d{6})", stem, re.IGNORECASE)
    if match:
        date_str, time_str = match.groups()
        try:
            dt = datetime.strptime(f"{date_str}{time_str}", "%Y%m%d%H%M%S")
            return dt.strftime("%Y-%m-%d %H:%M:%S")
        except ValueError:
            pass

    # Pattern: IMG_YYYYMMDD (no time)
    match = re.match(r"IMG_(\d{8})", stem, re.IGNORECASE)
    if match:
        try:
            dt = datetime.strptime(match.group(1), "%Y%m%d")
            return dt.strftime("%Y-%m-%d")
        except ValueError:
            pass

    # Fallback: use stem as title
    return stem


def generate_note(
    directory: Path,
    *,
    convert_heic: bool = True,
    remove_heic: bool = False,
    dry_run: bool = False,
) -> None:
    dir_name = directory.name
    note_path = directory / f"{dir_name}.md"
    is_update = note_path.exists()

    all_images = find_images(directory)
    if not all_images:
        print(f"No images found in {directory}")
        return

    if convert_heic:
        heic_files = [f for f in all_images if f.suffix.lower() == ".heic"]
        converted = convert_heic_files(heic_files, dry_run=dry_run)

        if remove_heic and not dry_run:
            for heic in converted:
                heic.unlink()
                print(f"Removed original: {heic.name}")

    embed_images = collect_embed_list(
        directory,
        convert_heic=convert_heic,
        dry_run=dry_run,
    )

    if not embed_images:
        print(f"No embeddable images in {directory}")
        return

    # === 新增：提取已有图片 ===
    existing_images = extract_existing_images(note_path)

    # === 新增：计算新增图片 ===
    new_images = [img for img in embed_images if img.name not in existing_images]

    if not new_images:
        print(f"No new images to add (all {len(embed_images)} already embedded)")
        return

    # === 区分新建 vs 追加 ===
    if not is_update:
        # 新建笔记：完整生成
        note_date = date.today().isoformat()
        lines = [
            "---",
            f"title: {dir_name}",
            f"date: {note_date}",
            "tags:",
            "  - paper-notes",
            f"category: {directory.parent.name}",
            "---",
            "",
            f"# {dir_name}",
            "",
        ]
        for img in embed_images:
            title = generate_image_title(img)
            lines.append(f"## {title}")
            lines.append(f"![[{img.name}]]")
            lines.append("")

        content = "\n".join(lines)

        if dry_run:
            print(f"\n[dry-run] Would create: {note_path}")
            print(f"[dry-run] Images: {len(embed_images)}")
            print("--- preview ---")
            print(content)
        else:
            note_path.write_text(content, encoding="utf-8")
            print(f"\nCreated: {note_path}")
            print(f"Images embedded: {len(embed_images)}")
    else:
        # 已存在：追加新图片
        if dry_run:
            print(
                f"\n[dry-run] Would append {len(new_images)} new images to: {note_path}"
            )
            for img in new_images:
                title = generate_image_title(img)
                print(f"  - {title}: {img.name}")
        else:
            with note_path.open("a", encoding="utf-8") as f:
                for img in new_images:
                    title = generate_image_title(img)
                    f.write(f"\n## {title}\n")
                    f.write(f"![[{img.name}]]\n")
            print(f"\nAppended {len(new_images)} new images to: {note_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate an Obsidian note embedding all images in a directory."
    )
    parser.add_argument("directory", help="Directory containing images")
    parser.add_argument(
        "--keep-heic",
        action="store_true",
        help="Embed HEIC files directly without converting to JPG",
    )
    parser.add_argument(
        "--remove-heic",
        action="store_true",
        help="Delete original HEIC files after conversion",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without writing anything",
    )
    args = parser.parse_args()

    directory = Path(args.directory).resolve()
    if not directory.is_dir():
        print(f"Error: {directory} is not a directory", file=sys.stderr)
        sys.exit(1)

    generate_note(
        directory,
        convert_heic=not args.keep_heic,
        remove_heic=args.remove_heic,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
