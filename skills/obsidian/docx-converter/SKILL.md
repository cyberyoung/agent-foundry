---
name: ob-docx-converter
description: "Convert Word (.docx) files into Obsidian-compatible Markdown notes with full fidelity. Use this skill whenever the user wants to convert a .docx file to Markdown for Obsidian, import Word documents into their vault, or migrate content from Word to Obsidian. Triggers include: any mention of 'docx to markdown', 'Word to Obsidian', 'convert docx', 'import Word document', or requests to turn a .docx file into a note. This skill handles the hard parts that naive converters miss: embedded image extraction, table layout conversion, rich text formatting preservation (highlights, colored text), hierarchical list detection, and chapter TOC generation with anchor links."
---

# Docx to Obsidian Converter

## Overview

Converts `.docx` files into Obsidian-compatible `.md` notes. This is NOT a naive text dump — it handles the structural and formatting nuances that matter for a usable Obsidian note.

**Input**: A `.docx` file path + an output directory
**Output**: A `.md` file (same name as the docx) + an `assets/` subfolder for images

## What This Skill Handles

| Feature | How |
|---------|-----|
| Embedded images | Extracted to `assets/<docx-name>/imageN.png`, embedded via `![[...]]` |
| Layout tables (2-col: label \| content) | Converted to heading + content structure (not markdown tables) |
| Data tables (3+ cols or tabular data) | Converted to markdown table syntax |
| Yellow highlight | `==highlighted text==` (Obsidian native) |
| Red text | `<span style="color:red">text</span>` |
| Bold | `**bold text**` |
| Hierarchical lists | Category headers as top-level `- item`, details indented as `  - sub-item` |
| Chapter TOC | Auto-generated with `[heading](#anchor)` links |
| YAML frontmatter | `title`, `date`, `tags`, `category` |
| Heading hierarchy | Docx Heading1→`##`, Heading2→`###`, etc. |
| Emoji/special char prefixes | Stripped cleanly (common in research notes) |
| Numbered lists (Chinese) | `chineseCountingThousand` → `#### 一、{text}` H4 headings |
| Bullet lists | `bullet` at ilvl=0 → `- text`, ilvl=1 → `  - text` (nested) |
| Decimal lists | `decimal` → `1. text` ordered markdown list |
| Blank line compaction | Label lines (e.g. `清仓：`) grouped without blank lines between them |
| Table styling via CSS | `cssclasses: table-nowrap` in frontmatter + bundled CSS snippet |

## Conversion Script

Use the bundled `scripts/docx_to_obsidian.py`. It requires `python-docx`:

```bash
pip3 install --break-system-packages python-docx
```

Run:
```bash
python3 <skill-path>/scripts/docx_to_obsidian.py <input.docx> <output-dir>
```

Local convenience wrapper (vault-relative output path):

```bash
bash <skill-path>/scripts/to_vault.sh <input.docx> [output-rel-path]
```

Examples:

```bash
# Interactive output selection
bash <skill-path>/scripts/to_vault.sh /path/to/report.docx

# Output to a research note directory
bash <skill-path>/scripts/to_vault.sh /path/to/report.docx "research/notes"

# Skip confirmation prompt
bash <skill-path>/scripts/to_vault.sh /path/to/report.docx "research/notes" --yes
```

Wrapper notes:
- Vault root: `$OBSIDIAN_VAULT`; otherwise the wrapper uses its local default vault path
- If output path is omitted, wrapper shows an interactive directory selector
- Directory selector prioritizes de-duplicated last 3 used paths, then discovered vault directories
- Extra flags are passed through (e.g. `--analyze`, `--no-layout-tables`)
- Wrapper shows a final execution preview and asks for confirmation by default
- Use `--yes` / `--no-confirm` to skip confirmation, `--confirm` to force it

The script produces:
- `<output-dir>/<docx-name>.md` — the Obsidian note
- `<output-dir>/assets/<docx-name>/` — extracted images

## CSS Table Styling

The script adds `cssclasses: [table-nowrap]` to frontmatter. For this to take effect, deploy the bundled CSS snippet to the Obsidian vault:

```bash
cp <skill-path>/styles/table-nowrap.css <vault>/.obsidian/snippets/
```

Then enable it in Obsidian: Settings → Appearance → CSS snippets → toggle on `table-nowrap`.

The snippet provides:
- Non-last columns: `nowrap` (display content in one line)
- Last column: expands to fill remaining width
- Table width: `fit-content` (min 80%, max 100%)
- Zebra striping (alternating row background)
- Cell borders using Obsidian theme colors
- Bold header row with background color
- Comfortable padding (`8px 14px`)

## Step-by-Step Workflow

### Phase 1: Analyze the Docx Structure

Before converting, understand what you're working with. Run the analysis mode:

```bash
python3 <skill-path>/scripts/docx_to_obsidian.py <input.docx> <output-dir> --analyze
```

This prints:
- Heading hierarchy (Heading1, Heading2, etc.)
- Number of tables and their column counts
- Number of embedded images
- Text formatting statistics (bold, highlight, colored text counts)

Review the output to understand the document's structure. Key questions:
1. Are tables used for **layout** (2-column label|content) or for **data** (tabular info)?
2. Are there heading levels that map to a logical hierarchy (weeks→days, chapters→sections)?
3. How many images need extraction?

### Phase 2: Run the Conversion

```bash
python3 <skill-path>/scripts/docx_to_obsidian.py <input.docx> <output-dir>
```

### Phase 3: Verify and Fix

After conversion, always check:

1. **Image count**: Verify all images were extracted
   ```bash
   ls <output-dir>/assets/<docx-name>/ | wc -l
   ```

2. **Image placement**: Search for `![[` in the output to confirm images are embedded at correct positions

3. **Formatting markers**: Check highlight and color markers exist
   ```bash
   grep -c '==' <output.md>
   grep -c 'color:red' <output.md>
   ```

4. **Hierarchical lists**: Manually inspect sections with nested content (e.g., category→stock lists). The script uses heuristics — short labels (< 10 chars, no parentheses) become top-level items; longer descriptive lines become sub-items. This may need manual adjustment for edge cases.

5. **TOC links**: Click each TOC link in Obsidian preview to verify anchors work.

## Edge Cases and Solutions

### Layout Tables vs Data Tables

The script treats 2-column tables as **layout** (column 1 = category heading, column 2 = content body). Tables with 3+ columns are treated as **data** and converted to markdown table syntax.

If a 2-column table is actually data (not layout), pass `--no-layout-tables` to force all tables to markdown table format.

### Hierarchical List Detection

Within a content cell, the script detects hierarchy by paragraph characteristics:
- **Category header**: Short text (<=10 chars), no parentheses, may end with `：` or `:`
- **Sub-item**: Longer text with stock names, descriptions, parenthetical details

This heuristic works well for financial research notes but may need tuning for other content types. If the detection is wrong, manually fix the indentation in the output.

### Emoji and Special Character Prefixes

Research notes often use emoji bullets (🔥, 📌, etc.) or bracket markers (【太阳】, 【月亮】). These are stripped during conversion since they don't render consistently in markdown. The semantic meaning is preserved through the heading/list structure.

### Adjacent Highlight Regions

When consecutive runs are all yellow-highlighted, they are merged into a single `==...==` block. When red text appears inside a yellow region, it nests: `==text <span style="color:red">red</span> more text==`.

### YAML Frontmatter

The script generates frontmatter from the docx filename and metadata:
```yaml
---
title: <derived from filename or docx title>
date: <today or docx creation date>
tags: []
category: <parent directory name>
---
```

The user should add appropriate tags after conversion.

## Agent 确认流程（必须遵守）

调用此 skill 前，agent 必须用 **一次** mcp_question 调用收集全部参数，用户填完一起提交：

```
mcp_question({
  questions: [
    { header: "输入文件", question: "要转换的 .docx 文件", options: [{label: "<推断的文件路径>", description: "..."}] },
    { header: "输出目录", question: "输出目录", options: [{label: "<最近3次去重目录/推荐目录>", description: "..."}] }
  ]
})
```

禁止：拆成多次 mcp_question 调用（每次都有 LLM round-trip 延迟）。
禁止：使用 --yes 跳过确认。

## Manual Adjustments Checklist

After automated conversion, review:

- [ ] Frontmatter `title`, `date`, `tags` are correct
- [ ] Images display properly in Obsidian preview
- [ ] Hierarchical lists have correct indentation
- [ ] Highlighted text renders as yellow background
- [ ] Red text renders in red
- [ ] TOC anchor links navigate correctly
- [ ] No content was lost or duplicated
- [ ] `[[wiki-links]]` added to related notes (manual step)

## Public Release Notes

- The core public interface is `scripts/docx_to_obsidian.py`.
- `scripts/to_vault.sh` is a local convenience wrapper for vault-relative output paths.
- Public-facing docs should avoid assuming a specific private vault layout.
