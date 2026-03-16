#!/usr/bin/env python3
"""Scan one Obsidian note for missing image captions and apply generated captions."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import NotRequired, TypedDict, cast


EMBED_RE = re.compile(
    r"^(?P<indent>\s*)(?:\d+\.\s+)?!\[\[(?P<target>[^\]|]+)(?:\|[^\]]+)?\]\]"
)
HEADING_RE = re.compile(r"^#{1,6}\s+")
UNORDERED_BULLET_RE = re.compile(r"^\s*[-*+]\s+")
ORDERED_BULLET_RE = re.compile(r"^\s*\d+\.\s+")
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".bmp", ".tiff"}


class EmbedInfo(TypedDict):
    target: str
    line_index: int
    indent: str
    line: str


class ScanItem(TypedDict, total=False):
    status: str
    target: str
    line_index: int
    indent: str
    image_path: str
    reason: str


class ScanSummary(TypedDict):
    total_images: int
    already_captioned: int
    pending_captions: int
    missing_images: int


class ScanReport(TypedDict):
    summary: ScanSummary
    items: list[ScanItem]


class CaptionInput(TypedDict):
    line_index: int
    caption: str
    indent: NotRequired[str]


class ApplySummary(TypedDict):
    applied: int
    note_path: str
    dry_run: bool


def parse_embeds(note_text: str) -> list[EmbedInfo]:
    embeds: list[EmbedInfo] = []
    for line_index, line in enumerate(note_text.splitlines()):
        match = EMBED_RE.match(line)
        if match is None:
            continue
        embeds.append(
            {
                "target": match.group("target").strip(),
                "line_index": line_index,
                "indent": match.group("indent"),
                "line": line,
            }
        )
    return embeds


def _is_separator(line: str) -> bool:
    return line.strip() in {"---", "----", "*****"}


def _is_image_line(line: str) -> bool:
    return EMBED_RE.match(line) is not None


def _line_indent(line: str) -> str:
    return line[: len(line) - len(line.lstrip())]


def has_following_caption(
    lines: list[str], image_line_index: int, expected_indent: str
) -> bool:
    for next_index in range(image_line_index + 1, len(lines)):
        line = lines[next_index]
        stripped = line.strip()
        if not stripped:
            continue
        if _is_separator(line) or HEADING_RE.match(line) or _is_image_line(line):
            return False

        line_indent = _line_indent(line)
        if UNORDERED_BULLET_RE.match(line):
            return len(line_indent) >= len(expected_indent)

        if ORDERED_BULLET_RE.match(line):
            return len(line_indent) > len(expected_indent)

        return len(stripped) <= 140

    return False


def is_image_target(target: str) -> bool:
    return Path(target).suffix.lower() in IMAGE_EXTENSIONS


def find_vault_root(note_path: Path) -> Path:
    current = note_path.parent
    while current != current.parent:
        if (current / ".obsidian").is_dir():
            return current
        current = current.parent
    return note_path.parent


def resolve_image_path(target: str, note_path: Path, vault_root: Path) -> Path | None:
    clean_target = target.strip()
    target_path = Path(clean_target)
    note_dir = note_path.parent

    candidates = [
        note_dir / target_path,
        note_dir / "assets" / target_path,
        note_dir / "assets" / target_path.name,
        note_dir / "assets" / note_path.stem / target_path.name,
        vault_root / target_path,
    ]

    for candidate in candidates:
        if candidate.is_file():
            return candidate

    return None


def scan_note(note_path: Path, vault_root: Path, force: bool = False) -> ScanReport:
    lines = note_path.read_text(encoding="utf-8").splitlines()
    embeds = parse_embeds("\n".join(lines))
    items: list[ScanItem] = []
    summary: ScanSummary = {
        "total_images": 0,
        "already_captioned": 0,
        "pending_captions": 0,
        "missing_images": 0,
    }

    for embed in embeds:
        target = embed["target"]
        if not is_image_target(target):
            continue

        summary["total_images"] += 1
        line_index = embed["line_index"]
        indent = embed["indent"]
        resolved = resolve_image_path(target, note_path, vault_root)
        if resolved is None:
            summary["missing_images"] += 1
            items.append(
                {
                    "status": "missing-image",
                    "target": target,
                    "line_index": line_index,
                    "indent": indent,
                    "reason": "missing image",
                }
            )
            continue

        has_caption = has_following_caption(lines, line_index, indent)
        if has_caption and not force:
            summary["already_captioned"] += 1
            status = "already-captioned"
        else:
            summary["pending_captions"] += 1
            status = "pending-caption"

        items.append(
            {
                "status": status,
                "target": target,
                "line_index": line_index,
                "indent": indent,
                "image_path": str(resolved),
            }
        )

    return {"summary": summary, "items": items}


def apply_captions(
    note_path: Path, captions: list[CaptionInput], dry_run: bool = False
) -> ApplySummary:
    lines = note_path.read_text(encoding="utf-8").splitlines()

    for caption_item in sorted(
        captions, key=lambda item: item["line_index"], reverse=True
    ):
        line_index = caption_item["line_index"]
        indent = caption_item.get("indent", "")
        caption = caption_item["caption"]
        lines.insert(line_index + 1, f"{indent}{caption}")

    if not dry_run:
        _ = note_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    return {
        "applied": len(captions),
        "note_path": str(note_path),
        "dry_run": dry_run,
    }


def _load_captions_json(captions_json_path: Path) -> list[CaptionInput]:
    raw_data = cast(object, json.loads(captions_json_path.read_text(encoding="utf-8")))
    if not isinstance(raw_data, list):
        raise ValueError("captions JSON must be a list")

    captions: list[CaptionInput] = []
    items = cast(list[object], raw_data)
    for item in items:
        if not isinstance(item, dict):
            raise ValueError("each caption item must be an object")
        item_dict = cast(dict[object, object], item)
        line_index = item_dict.get("line_index")
        caption = item_dict.get("caption")
        indent = item_dict.get("indent", "")
        if (
            not isinstance(line_index, int)
            or not isinstance(caption, str)
            or not isinstance(indent, str)
        ):
            raise ValueError(
                "caption items require int line_index, str caption, optional str indent"
            )
        captions.append(
            {"line_index": line_index, "caption": caption, "indent": indent}
        )

    return captions


def run_cli(argv: list[str]) -> dict[str, object]:
    parser = argparse.ArgumentParser(
        description="Add missing image captions to one Obsidian note"
    )
    _ = parser.add_argument("note", help="Path to the Obsidian note")
    _ = parser.add_argument("--vault-root", help="Vault root directory")
    _ = parser.add_argument(
        "--dry-run", action="store_true", help="Preview without writing changes"
    )
    _ = parser.add_argument(
        "--force", action="store_true", help="Treat already-captioned images as pending"
    )
    _ = parser.add_argument(
        "--captions-json", help="JSON file containing captions to apply"
    )
    args = parser.parse_args(argv)

    note_arg = cast(str, args.note)
    vault_root_arg = cast(str | None, args.vault_root)
    captions_json_arg = cast(str | None, args.captions_json)
    dry_run = cast(bool, args.dry_run)
    force = cast(bool, args.force)

    note_path = Path(note_arg).resolve()
    if not note_path.is_file():
        raise FileNotFoundError(f"note not found: {note_path}")

    vault_root = (
        Path(vault_root_arg).resolve() if vault_root_arg else find_vault_root(note_path)
    )

    if captions_json_arg:
        captions = _load_captions_json(Path(captions_json_arg).resolve())
        apply_summary = apply_captions(note_path, captions, dry_run=dry_run)
        return {"mode": "apply", "summary": apply_summary}

    report = scan_note(note_path, vault_root, force=force)
    return {
        "mode": "scan",
        "summary": report["summary"],
        "items": report["items"],
        "dry_run": dry_run,
    }


def main() -> int:
    try:
        result = run_cli(sys.argv[1:])
    except Exception as exc:  # pragma: no cover - exercised through CLI behavior
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1

    _ = print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
