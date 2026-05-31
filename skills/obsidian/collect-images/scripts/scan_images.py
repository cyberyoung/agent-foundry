#!/usr/bin/env python3
"""Scan Obsidian notes in a directory for image embeds and extract context.

Usage:
    python3 scan_images.py <source-dir> --vault-root <vault-root> [--dry-run]
    python3 scan_images.py <source-dir> --vault-root <vault-root> --write <classified-json>
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".heic"}
EMBED_RE = re.compile(r"!\[\[([^\]]+)\]\]")
WIKILINK_RE = re.compile(r"\[\[([^\]]+)\]\]")


def is_image(target: str) -> bool:
    return Path(target).suffix.lower() in IMAGE_EXTS


def resolve_image(target: str, note_path: Path, vault_root: Path) -> Path | None:
    """Resolve an image target to an absolute path within the vault."""
    clean = target.strip()
    tp = Path(clean)
    note_dir = note_path.parent

    candidates = [
        note_dir / tp,
        note_dir / "assets" / tp,
        note_dir / "assets" / tp.name,
        note_dir / "assets" / note_path.stem / tp.name,
        vault_root / clean,
    ]

    for c in candidates:
        try:
            if c.resolve().is_file():
                return c.resolve()
        except OSError:
            continue
    return None


def relative_to_output(image_abs: Path, output_dir: Path) -> str:
    """Compute relative path from output dir to image file."""
    try:
        rel = image_abs.relative_to(output_dir)
        return str(rel)
    except ValueError:
        pass
    # Go up from output_dir then to image
    # output_dir is like vault/stock/逻辑技术沉淀/
    # image is like vault/stock/调研笔记/2026/04/assets/xxx/webp
    # relative: ../调研笔记/2026/04/assets/xxx/webp
    try:
        # Find common parent
        output_parts = output_dir.resolve().parts
        image_parts = image_abs.resolve().parts
        common = 0
        for i, (a, b) in enumerate(zip(output_parts, image_parts)):
            if a == b:
                common = i + 1
            else:
                break

        up_count = len(output_parts) - common
        down_parts = image_parts[common:]
        rel = "/".join([".."] * up_count + list(down_parts))
        return rel
    except Exception:
        return str(image_abs)


def extract_context(lines: list[str], embed_line_idx: int) -> dict[str, Any]:
    """Extract heading hierarchy and nearby text context for an image embed."""
    # Find headings above
    headings: list[str] = []
    for i in range(embed_line_idx - 1, -1, -1):
        m = re.match(r"^(#{1,6})\s+(.+)", lines[i])
        if m:
            headings.append(m.group(2).strip())
            if len(headings) >= 3:
                break

    headings.reverse()

    # Get text before and after
    before_lines: list[str] = []
    for i in range(embed_line_idx - 1, max(embed_line_idx - 6, -1), -1):
        line = lines[i].strip()
        if line and not line.startswith("#") and not line.startswith("![["):
            before_lines.insert(0, line)
        elif line.startswith("#"):
            break

    after_lines: list[str] = []
    for i in range(embed_line_idx + 1, min(embed_line_idx + 6, len(lines))):
        line = lines[i].strip()
        if line and not line.startswith("![["):
            after_lines.append(line)
        elif line.startswith("![["):
            break

    # Check for existing caption (blockquote or list item right after image)
    existing_caption = ""
    if embed_line_idx + 1 < len(lines):
        next_line = lines[embed_line_idx + 1].strip()
        if next_line.startswith(">"):
            existing_caption = next_line.lstrip(">").strip()
        elif next_line.startswith("-"):
            existing_caption = next_line.lstrip("-").strip()

    return {
        "headings": headings,
        "before": " ".join(before_lines)[:300],
        "after": " ".join(after_lines)[:300],
        "existing_caption": existing_caption,
    }


def scan_directory(source_dir: Path, vault_root: Path, output_dir: Path) -> list[dict]:
    """Scan all .md files in source_dir recursively for image embeds."""
    items = []
    for md_file in sorted(source_dir.rglob("*.md")):
        try:
            text = md_file.read_text(encoding="utf-8")
        except Exception:
            continue

        lines = text.splitlines()
        # Strip frontmatter lines from context extraction
        fm_end = 0
        if lines and lines[0].strip() == "---":
            for i in range(1, len(lines)):
                if lines[i].strip() == "---":
                    fm_end = i + 1
                    break

        for i, line in enumerate(lines):
            m = EMBED_RE.search(line)
            if not m:
                continue

            target = m.group(1)
            if not is_image(target):
                continue

            resolved = resolve_image(target, md_file, vault_root)
            rel_path = relative_to_output(resolved, output_dir) if resolved else ""
            ctx = extract_context(lines, i)

            items.append({
                "source_file": md_file.stem,
                "source_rel": str(md_file.relative_to(vault_root)),
                "line_index": i + 1,  # 1-based
                "image_target": target,
                "image_filename": Path(target).name,
                "resolved": str(resolved) if resolved else None,
                "relative_path": rel_path,
                "context": ctx,
            })

    return items


def extract_existing_embeds(note_path: Path) -> set[str]:
    """Extract set of image filenames already embedded in a note."""
    if not note_path.exists():
        return set()
    try:
        text = note_path.read_text(encoding="utf-8")
    except Exception:
        return set()
    return {m.group(1) for m in EMBED_RE.finditer(text) if is_image(m.group(1))}


def write_classified(
    classified: list[dict],
    vault_root: Path,
    output_dir: Path,
    dry_run: bool = False,
) -> None:
    """Write classified images into categorized notes."""
    from datetime import date

    # Group by category
    categories: dict[str, list[dict]] = {}
    for item in classified:
        cat = item.get("category", "其他产业图集")
        categories.setdefault(cat, []).append(item)

    for cat_name, items in categories.items():
        note_path = output_dir / f"{cat_name}.md"
        existing = extract_existing_embeds(note_path)

        # Build content to append
        sections: dict[str, list[str]] = {}
        tags = set()
        for item in items:
            img_filename = item["image_filename"]
            if img_filename in existing:
                continue

            subcategory = item.get("subcategory", "")
            rel_path = item.get("relative_path", "")
            caption = item.get("caption", "")
            source = item.get("source_file", "")

            tag_list = item.get("tags", [])
            tags.update(tag_list)

            line = f"![[{rel_path}]]\n"
            if caption:
                line += f"> {caption}"
                if source:
                    line += f" — 来源：[[{source}]]"
                line += "\n"

            sections.setdefault(subcategory, []).append(line)

        if not sections:
            print(f"  [{cat_name}] 无新图片，跳过")
            continue

        # Build new content
        new_content = ""
        for sub, lines in sections.items():
            if sub:
                new_content += f"\n## {sub}\n\n"
            new_content += "\n".join(lines) + "\n"

        if dry_run:
            print(f"  [{cat_name}] 将追加 {sum(len(v) for v in sections.values())} 张图片到 {note_path.name}")
            print(new_content[:200] + "..." if len(new_content) > 200 else new_content)
            continue

        # Ensure output dir exists
        output_dir.mkdir(parents=True, exist_ok=True)

        if note_path.exists():
            # Append to existing note
            existing_text = note_path.read_text(encoding="utf-8")
            note_path.write_text(existing_text.rstrip() + "\n\n---\n" + new_content, encoding="utf-8")
            print(f"  [{cat_name}] 追加到已有笔记")
        else:
            # Create new note with frontmatter
            today = date.today().isoformat()
            tags_str = "\n".join(f"  - {t}" for t in sorted(tags)) if tags else "  - 图集"
            frontmatter = f"""---
title: {cat_name}
date: {today}
tags:
{tags_str}
category: 逻辑技术沉淀
---

# {cat_name}

"""
            note_path.write_text(frontmatter + new_content, encoding="utf-8")
            print(f"  [{cat_name}] 创建新笔记")


def main():
    parser = argparse.ArgumentParser(description="Scan notes for images and classify")
    parser.add_argument("source_dir", help="Directory to scan for notes")
    parser.add_argument("--vault-root", help="Obsidian vault root directory")
    parser.add_argument("--output-dir", default="stock/逻辑技术沉淀", help="Output directory (vault-relative)")
    parser.add_argument("--dry-run", action="store_true", help="Preview only")
    parser.add_argument("--write", metavar="JSON", help="Classified JSON file to write")

    args = parser.parse_args()

    source = Path(args.source_dir).resolve()
    if not source.exists():
        print(f"Error: source directory not found: {source}", file=sys.stderr)
        sys.exit(1)

    # Find vault root
    if args.vault_root:
        vault = Path(args.vault_root).resolve()
    else:
        # Try to detect from OBSIDIAN_VAULT env or common paths
        import os
        vault_env = os.environ.get("OBSIDIAN_VAULT")
        if vault_env:
            vault = Path(vault_env).resolve()
        else:
            # Default
            vault = Path.home() / "Documents" / "Obsidian Vault"
            if not vault.exists():
                print("Error: cannot determine vault root. Use --vault-root.", file=sys.stderr)
                sys.exit(1)

    output = vault / args.output_dir

    # Scan
    print(f"Scanning: {source}")
    print(f"Vault root: {vault}")
    print(f"Output dir: {output}")
    print()

    items = scan_directory(source, vault, output)

    if args.write:
        # Write mode: read classified JSON and write notes
        json_path = Path(args.write)
        if not json_path.exists():
            print(f"Error: classified JSON not found: {json_path}", file=sys.stderr)
            sys.exit(1)
        classified = json.loads(json_path.read_text(encoding="utf-8"))
        write_classified(classified, vault, output, dry_run=args.dry_run)
    else:
        # Scan mode: output JSON
        result = {
            "summary": {
                "total_images": len(items),
                "resolved": sum(1 for i in items if i["resolved"]),
                "unresolved": sum(1 for i in items if not i["resolved"]),
            },
            "items": items,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
