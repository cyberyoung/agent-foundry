#!/usr/bin/env python3
import argparse
import importlib
import os
import re
from collections import Counter
from datetime import datetime
from pathlib import Path

fitz = importlib.import_module("pymupdf")


def int_to_rgb(color_int):
    return ((color_int >> 16) & 255, (color_int >> 8) & 255, color_int & 255)


def is_red_rgb(rgb):
    r, g, b = rgb
    return r >= 180 and g <= 110 and b <= 110


def is_yellow_bg(bg):
    if bg is None:
        return False
    rgb = int_to_rgb(bg)
    r, g, b = rgb
    return r >= 200 and g >= 180 and b <= 130


def span_is_bold(span):
    font_name = str(span.get("font", "")).lower()
    if "bold" in font_name:
        return True
    flags = int(span.get("flags", 0))
    return bool(flags & 16)


def format_span_text(span):
    text = span.get("text", "")
    if not text:
        return ""

    color = int(span.get("color", 0))
    bgcolor = span.get("bgcolor", None)

    out = text
    if is_red_rgb(int_to_rgb(color)):
        out = f'<span style="color:red">{out}</span>'
    if is_yellow_bg(bgcolor):
        out = f"=={out}=="
    if span_is_bold(span):
        out = f"**{out}**"
    return out


def normalize_line(s):
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"\s+==", "==", s)
    s = re.sub(r"==\s+", "==", s)
    return s


def escape_table_cell(s):
    return s.replace("|", r"\|").replace("\n", "<br>")


def table_to_markdown(table_rows):
    if not table_rows:
        return ""
    width = max(len(r) for r in table_rows)
    rows = []
    for row in table_rows:
        vals = [escape_table_cell((c or "").strip()) for c in row]
        if len(vals) < width:
            vals.extend([""] * (width - len(vals)))
        rows.append(vals)
    header = rows[0]
    sep = ["---"] * width
    out = ["| " + " | ".join(header) + " |", "| " + " | ".join(sep) + " |"]
    for row in rows[1:]:
        out.append("| " + " | ".join(row) + " |")
    return "\n".join(out)


def collect_size_stats(doc):
    sizes = []
    for page in doc:
        text_dict = page.get_text("dict")
        for block in text_dict.get("blocks", []):
            if block.get("type") != 0:
                continue
            for line in block.get("lines", []):
                for span in line.get("spans", []):
                    if span.get("text", "").strip():
                        sizes.append(round(float(span.get("size", 0)), 1))
    return Counter(sizes)


def derive_heading_sizes(size_counter):
    if not size_counter:
        return set(), 0
    body_size = size_counter.most_common(1)[0][0]
    heading_sizes = {s for s in size_counter if s >= body_size + 1.2}
    return heading_sizes, body_size


def block_intersects_table(block_bbox, table_bboxes):
    x0, y0, x1, y1 = block_bbox
    for tx0, ty0, tx1, ty1 in table_bboxes:
        if x1 < tx0 or tx1 < x0 or y1 < ty0 or ty1 < y0:
            continue
        return True
    return False


def extract_images(doc, output_dir, stem):
    assets_dir = os.path.join(output_dir, "assets", stem)
    os.makedirs(assets_dir, exist_ok=True)
    seen = set()
    refs = []
    index = 0
    for page in doc:
        for img in page.get_images(full=True):
            xref = img[0]
            if xref in seen:
                continue
            seen.add(xref)
            index += 1
            image = doc.extract_image(xref)
            ext = image.get("ext", "png")
            filename = f"image{index}.{ext}"
            path = os.path.join(assets_dir, filename)
            with open(path, "wb") as f:
                f.write(image["image"])
            refs.append(f"assets/{stem}/{filename}")
    return refs


def page_tables(page):
    try:
        tf = page.find_tables()
    except Exception:
        return [], []
    tables = []
    bboxes = []
    for t in tf.tables:
        try:
            rows = t.extract() or []
        except Exception:
            rows = []
        if rows:
            tables.append(rows)
            bboxes.append(tuple(t.bbox))
    return tables, bboxes


def analyze_pdf(pdf_path):
    doc = fitz.open(pdf_path)
    stem = Path(pdf_path).name
    print(f"=== Document Analysis: {stem} ===\n")

    size_counter = collect_size_stats(doc)
    heading_sizes, _body = derive_heading_sizes(size_counter)

    headings = []
    tables_count = 0
    images_count = 0
    yellow = 0
    red = 0
    bold = 0

    seen_xref = set()
    for page in doc:
        for img in page.get_images(full=True):
            if img[0] not in seen_xref:
                seen_xref.add(img[0])
                images_count += 1

        tables, table_bboxes = page_tables(page)
        tables_count += len(tables)

        text_dict = page.get_text("dict")
        blocks = sorted(
            text_dict.get("blocks", []),
            key=lambda b: (b.get("bbox", [0, 0])[1], b.get("bbox", [0, 0])[0]),
        )
        for block in blocks:
            if block.get("type") != 0:
                continue
            bbox = tuple(block.get("bbox", (0, 0, 0, 0)))
            if block_intersects_table(bbox, table_bboxes):
                continue
            line_texts = []
            line_sizes = []
            for line in block.get("lines", []):
                segs = []
                for span in line.get("spans", []):
                    t = span.get("text", "")
                    if not t.strip():
                        continue
                    color = int(span.get("color", 0))
                    bgcolor = span.get("bgcolor", None)
                    if is_red_rgb(int_to_rgb(color)):
                        red += 1
                    if is_yellow_bg(bgcolor):
                        yellow += 1
                    if span_is_bold(span):
                        bold += 1
                    segs.append(t)
                    line_sizes.append(round(float(span.get("size", 0)), 1))
                if segs:
                    line_texts.append(normalize_line("".join(segs)))
            if not line_texts:
                continue
            joined = normalize_line(" ".join(line_texts))
            if (
                line_sizes
                and max(line_sizes) in heading_sizes
                and 1 <= len(joined) <= 80
            ):
                headings.append(joined)

    print(f"Pages: {doc.page_count}")
    print(f"Headings (heuristic): {len(headings)}")
    for h in headings[:20]:
        print(f"  ## {h}")
    if len(headings) > 20:
        print(f"  ... and {len(headings) - 20} more")
    print(f"\nTables: {tables_count}")
    print(f"Images: {images_count}")
    print("\nFormatting spans:")
    print(f"  Yellow highlight: {yellow}")
    print(f"  Red text: {red}")
    print(f"  Bold: {bold}")


def convert_pdf(pdf_path, output_dir, extract_tables=True):
    doc = fitz.open(pdf_path)
    stem = Path(pdf_path).stem
    for suffix in [".pdf"]:
        if stem.lower().endswith(suffix):
            stem = stem[: -len(suffix)]

    size_counter = collect_size_stats(doc)
    heading_sizes, _body = derive_heading_sizes(size_counter)
    image_refs = extract_images(doc, output_dir, stem)
    print(f"Extracted {len(image_refs)} images to assets/{stem}/")

    lines = []
    headings = []
    img_idx = 0

    for page_num, page in enumerate(doc, start=1):
        tables = []
        table_bboxes = []
        if extract_tables:
            tables, table_bboxes = page_tables(page)

        text_dict = page.get_text("dict")
        blocks = sorted(
            text_dict.get("blocks", []),
            key=lambda b: (b.get("bbox", [0, 0])[1], b.get("bbox", [0, 0])[0]),
        )
        for block in blocks:
            if block.get("type") != 0:
                continue
            bbox = tuple(block.get("bbox", (0, 0, 0, 0)))
            if block_intersects_table(bbox, table_bboxes):
                continue

            block_lines = []
            sizes = []
            for line in block.get("lines", []):
                parts = []
                for span in line.get("spans", []):
                    t = format_span_text(span)
                    if not t.strip():
                        continue
                    parts.append(t)
                    sizes.append(round(float(span.get("size", 0)), 1))
                if parts:
                    block_lines.append(normalize_line("".join(parts)))

            if not block_lines:
                continue

            text = normalize_line(" ".join(block_lines))
            if not text:
                continue

            if sizes and max(sizes) in heading_sizes and 1 <= len(text) <= 80:
                lines.append(f"\n## {text}\n")
                headings.append(text)
            else:
                lines.append(text)
                lines.append("")

        if extract_tables and tables:
            for t in tables:
                md_table = table_to_markdown(t)
                if md_table:
                    lines.append("")
                    lines.append(md_table)
                    lines.append("")

        page_image_count = len(page.get_images(full=True))
        for _ in range(page_image_count):
            if img_idx >= len(image_refs):
                break
            lines.append(f"\n![[{image_refs[img_idx]}]]\n")
            img_idx += 1

        if page_num < doc.page_count:
            lines.append("\n---\n")

    title = stem
    meta = doc.metadata or {}
    if meta.get("title"):
        title = meta["title"].strip() or stem

    date_str = datetime.now().strftime("%Y-%m-%d")
    frontmatter = f"""---
title: {title}
date: {date_str}
tags: []
category: {os.path.basename(output_dir)}
cssclasses:
  - table-nowrap
---"""

    toc = "\n".join(f"- [{h}](#{h})" for h in headings)
    parts = [frontmatter, "", f"# {title}", ""]
    if toc:
        parts.extend(["## 目录", "", toc, "", "---", ""])
    parts.extend(lines)

    content = "\n".join(parts)
    content = re.sub(r"\n{3,}", "\n\n", content)

    output_path = os.path.join(output_dir, f"{stem}.md")
    os.makedirs(output_dir, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"Written: {output_path}")
    print(f"Total headings in TOC: {len(headings)}")
    return output_path


def main():
    parser = argparse.ArgumentParser(
        description="Convert .pdf to Obsidian-compatible Markdown"
    )
    parser.add_argument("input", help="Path to the .pdf file")
    parser.add_argument("output_dir", help="Output directory for the .md file")
    parser.add_argument(
        "--analyze",
        action="store_true",
        help="Only analyze the pdf structure, do not convert",
    )
    parser.add_argument(
        "--no-tables",
        action="store_true",
        help="Skip table detection and markdown table conversion",
    )
    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"ERROR: File not found: {args.input}")
        raise SystemExit(1)

    if args.analyze:
        analyze_pdf(args.input)
    else:
        convert_pdf(args.input, args.output_dir, extract_tables=not args.no_tables)


if __name__ == "__main__":
    main()
