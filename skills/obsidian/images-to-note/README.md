# images-to-note

Generate an Obsidian note from all images in a directory, sorted by filename.

## What It Does

This skill scans a directory of images, sorts the files deterministically, and creates a Markdown note that embeds them in order. It is useful for turning screenshots, scans, or photo batches into an Obsidian note.

## When To Use It

- create a gallery-style note from a folder of screenshots
- turn scanned pages into a single note
- batch embed image files in filename order

## Main Entry Points

- Core script: `scripts/images_to_note.py`
- Local convenience wrapper: `scripts/to_vault.sh`

The core script is the public entrypoint. The wrapper is useful for local vault-relative output workflows.

## Requirements

- `python3`
- macOS `sips` if HEIC conversion is required

## Basic Usage

```bash
python3 scripts/images_to_note.py /path/to/image-dir
```

Preview only:

```bash
python3 scripts/images_to_note.py /path/to/image-dir --dry-run
```

## Input / Output

- Input: one directory containing image files
- Output: one Markdown note named after the directory, embedding those images in sorted order

## Notable Behaviors

- sorts by filename case-insensitively
- converts HEIC to JPG by default through macOS `sips`
- can keep HEIC files untouched with `--keep-heic`
- can remove HEIC originals after conversion with `--remove-heic`

## Limitations

- HEIC conversion is macOS-specific when using `sips`
- image ordering depends on filename order, not capture time or EXIF metadata
- the generated note is intentionally simple and may need manual sectioning afterward

## Safety Notes

- `--remove-heic` deletes original HEIC files after conversion
- review generated embeds if your folder contains mixed formats or inconsistent filenames

## References

- `references/sorting-and-heic.md`
- `references/output-structure.md`

## Examples

- `examples/gallery-output.md`
- `examples/heic-conversion.md`
