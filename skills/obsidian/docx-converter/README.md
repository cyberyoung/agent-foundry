# docx-converter

Convert Word `.docx` files into Obsidian-compatible Markdown notes with extracted images, frontmatter, and structure-aware handling for headings, tables, and lists.

## What It Does

This skill converts Word documents into Markdown notes intended for Obsidian. It aims to preserve structure and important formatting while producing output that remains editable and readable.

## When To Use It

- import a Word document into an Obsidian vault
- migrate `.docx` research or meeting notes into Markdown
- preserve headings, images, and simple formatting better than a plain text dump

## Main Entry Points

- Core script: `scripts/docx_to_obsidian.py`
- Local convenience wrapper: `scripts/to_vault.sh`

The core script is the public entrypoint. The wrapper is useful for local vault-relative output workflows.

## Requirements

- `python3`
- `python-docx`

Install dependency:

```bash
pip3 install --break-system-packages python-docx
```

## Basic Usage

```bash
python3 scripts/docx_to_obsidian.py /path/to/report.docx /path/to/output-dir
```

Analyze first:

```bash
python3 scripts/docx_to_obsidian.py /path/to/report.docx /path/to/output-dir --analyze
```

## Input / Output

- Input: one `.docx` file and an output directory
- Output: one Markdown note plus extracted assets under `assets/<docx-name>/`

## Notable Behaviors

- extracts embedded images
- converts data tables to Markdown
- can reinterpret layout-style two-column tables as heading/content blocks
- preserves highlights, red text, bold text, and nested list structure where possible
- builds a table of contents from detected headings

## Limitations

- layout-heavy documents may require manual cleanup
- complex tables may degrade
- formatting fidelity is high-effort but not exact visual reproduction
- some heuristics are especially tuned to note-like documents rather than polished desktop publishing layouts

## Safety Notes

- review list nesting and heading levels after conversion
- verify image placement and TOC links in Obsidian preview
- verify whether two-column tables were treated correctly for your document type

## References

- `references/format-preservation.md`
- `references/output-structure.md`
- `references/dependency-notes.md`

## Examples

- `examples/sample-input.md`
- `examples/sample-output.md`
- `examples/embedded-images.md`
