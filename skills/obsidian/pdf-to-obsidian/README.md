# pdf-to-obsidian

Convert PDF files into Obsidian-compatible Markdown notes with extracted images, optional table conversion, frontmatter, and a generated table of contents.

## What It Does

This skill turns a document-style PDF into a Markdown note that is easier to review and edit inside an Obsidian vault. It focuses on readable note output rather than pixel-perfect visual reproduction.

## When To Use It

- import a research paper or report into Obsidian
- convert a text-based PDF into editable Markdown
- preserve images, headings, and simple formatting where practical

## Main Entry Points

- Core script: `scripts/pdf_to_obsidian.py`
- Local convenience wrapper: `scripts/to_vault.sh`

The core script is the public entrypoint. The wrapper is useful for local vault-relative output workflows.

## Requirements

- `python3`
- `pymupdf`

Install dependency:

```bash
pip3 install --break-system-packages pymupdf
```

## Basic Usage

```bash
python3 scripts/pdf_to_obsidian.py /path/to/report.pdf /path/to/output-dir
```

Analyze first:

```bash
python3 scripts/pdf_to_obsidian.py /path/to/report.pdf /path/to/output-dir --analyze
```

## Input / Output

- Input: one `.pdf` file and an output directory
- Output: one Markdown note plus extracted assets under `assets/<pdf-name>/`

Typical result:

```text
output-dir/
├── report.md
└── assets/
    └── report/
        ├── image1.png
        └── image2.png
```

## Notable Behaviors

- extracts embedded images when possible
- converts detected tables to Markdown when table detection is enabled
- preserves some bold/highlight/color markers heuristically
- builds a table of contents from heading-size heuristics
- adds YAML frontmatter suitable for Obsidian notes

## Limitations

- scanned PDFs may need OCR before conversion is useful
- complex multi-column layouts may degrade
- table extraction is heuristic and can require manual cleanup
- formatting preservation is best-effort, not exact visual fidelity

## Safety Notes

- review image placement after conversion
- verify table rendering in Obsidian preview
- confirm heading hierarchy and TOC links manually

## References

- `references/limitations.md`
- `references/output-structure.md`
- `references/dependency-notes.md`

## Examples

- `examples/sample-input.md`
- `examples/sample-output.md`
- `examples/expected-assets.md`
