---
name: ob-pdf-to-obsidian
description: "Convert PDF files into Obsidian-compatible Markdown notes with image extraction, table conversion, formatting preservation, and TOC/frontmatter generation. Use this skill whenever the user wants to import a .pdf into Obsidian as a markdown note."
---

# Pdf to Obsidian Converter

## Overview

Converts `.pdf` files into Obsidian-compatible `.md` notes. It extracts text in reading order, images, detected tables, and preserves common inline formatting markers where available.

**Input**: A `.pdf` file path + an output directory  
**Output**: A `.md` file (same name as the pdf) + an `assets/` subfolder for images

## What This Skill Handles

| Feature | How |
|---------|-----|
| Embedded images | Extracted to `assets/<pdf-name>/imageN.ext`, embedded via `![[...]]` |
| Table detection | Uses PyMuPDF table detection and converts to markdown table syntax |
| Yellow highlight | Converted to `==highlighted text==` when PDF span background is yellow-like |
| Red text | Converted to `<span style="color:red">text</span>` when span color is red-like |
| Bold text | Converted to `**bold text**` when font/flags indicate bold |
| YAML frontmatter | `title`, `date`, `tags`, `category`, `cssclasses` |
| Chapter TOC | Auto-generated from heading-size heuristics |
| Heading hierarchy | Derived from larger font-size spans (heuristic) |
| Table styling via CSS | `cssclasses: table-nowrap` in frontmatter + bundled CSS snippet |

## Conversion Script

Use the bundled `scripts/pdf_to_obsidian.py`. It requires `pymupdf`:

```bash
pip3 install --break-system-packages pymupdf
```

Run:

```bash
python3 <skill-path>/scripts/pdf_to_obsidian.py <input.pdf> <output-dir>
```

Local convenience wrapper (vault-relative output path):

```bash
bash <skill-path>/scripts/to_vault.sh <input.pdf> [output-rel-path]
```

Examples:

```bash
# Interactive output selection
bash <skill-path>/scripts/to_vault.sh /path/to/report.pdf

# Output to a research note directory
bash <skill-path>/scripts/to_vault.sh /path/to/report.pdf "research/notes"

# Analyze only
bash <skill-path>/scripts/to_vault.sh /path/to/report.pdf "research/notes" --analyze
```

Wrapper notes:

- Vault root: `$OBSIDIAN_VAULT`; otherwise the wrapper uses its local default vault path
- If output path is omitted, wrapper shows an interactive directory selector
- Directory selector prioritizes de-duplicated last 3 used paths, then discovered vault directories
- Wrapper shows a final execution preview and asks for confirmation by default
- Use `--yes` / `--no-confirm` to skip confirmation, `--confirm` to force it
- Extra flags are passed through (e.g. `--analyze`, `--no-tables`)

The script produces:

- `<output-dir>/<pdf-name>.md` — the Obsidian note
- `<output-dir>/assets/<pdf-name>/` — extracted images

## CSS Table Styling

The script adds `cssclasses: [table-nowrap]` to frontmatter. For this to take effect, deploy the bundled CSS snippet to the Obsidian vault:

```bash
cp <skill-path>/styles/table-nowrap.css <vault>/.obsidian/snippets/
```

Then enable it in Obsidian: Settings → Appearance → CSS snippets → toggle on `table-nowrap`.

## Step-by-Step Workflow

### Phase 1: Analyze the PDF Structure

```bash
python3 <skill-path>/scripts/pdf_to_obsidian.py <input.pdf> <output-dir> --analyze
```

This prints:

- Page count
- Heading candidates (font-size heuristic)
- Table count
- Image count
- Formatting span statistics (bold, highlight, red)

### Phase 2: Run the Conversion

```bash
python3 <skill-path>/scripts/pdf_to_obsidian.py <input.pdf> <output-dir>
```

### Phase 3: Verify and Fix

After conversion, always check:

1. **Image count**
   ```bash
   ls <output-dir>/assets/<pdf-name>/ | wc -l
   ```
2. **Image placement** (`![[` occurrences in output)
3. **Formatting markers**
   ```bash
   grep -c '==' <output.md>
   grep -c 'color:red' <output.md>
   ```
4. **Table rendering** in Obsidian preview
5. **TOC links** in Obsidian preview

## Edge Cases and Notes

- PDF extraction is heuristic and depends on source encoding/rendering order.
- Highlight/red/bold preservation is best-effort based on span colors and font flags.
- Some scanned/image-only PDFs require OCR before high-quality markdown conversion.
- If table detection is noisy, pass `--no-tables` and keep text-first conversion.

## Agent 确认流程（必须遵守）

调用此 skill 前，agent 必须用 **一次** mcp_question 调用收集全部参数，用户填完一起提交：

```
mcp_question({
  questions: [
    { header: "输入文件", question: "要转换的 .pdf 文件", options: [{label: "<推断的文件路径>", description: "..."}] },
    { header: "输出目录", question: "输出目录", options: [{label: "<最近3次去重目录/推荐目录>", description: "..."}] }
  ]
})
```

禁止：拆成多次 mcp_question 调用。  
禁止：使用 --yes 跳过确认。

## Manual Adjustments Checklist

- [ ] Frontmatter `title`, `date`, `tags` are correct
- [ ] Images display properly in Obsidian preview
- [ ] Highlighted text renders as yellow background (if present in source PDF)
- [ ] Red text renders in red (if present in source PDF)
- [ ] Tables render correctly
- [ ] TOC anchor links navigate correctly
- [ ] No content was lost or duplicated
- [ ] `[[wiki-links]]` added to related notes (manual step)

## Public Release Notes

- The core public interface is `scripts/pdf_to_obsidian.py`.
- `scripts/to_vault.sh` is a local convenience wrapper for vault-relative output paths.
- Public-facing docs should avoid assuming a specific private vault layout.
