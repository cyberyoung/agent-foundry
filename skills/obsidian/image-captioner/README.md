# image-captioner

Add missing captions to embedded images in a single Obsidian note.

## What It Does

This skill scans one note, finds image embeds that do not already have a nearby caption, and inserts a short caption line beneath those images. It is intentionally conservative and avoids rewriting content that already looks captioned.

## When To Use It

- add captions to screenshot-heavy notes
- make documentation notes easier to scan
- fill in missing image descriptions without rewriting the whole note

## Main Entry Points

- Core script: `scripts/caption_images_in_note.py`
- Local convenience wrapper: `scripts/to_vault.sh`

The core script is the public entrypoint. The wrapper is useful for local vault-relative note paths.

## Requirements

- `python3`

## Basic Usage

Preview scan only:

```bash
python3 scripts/caption_images_in_note.py /path/to/note.md --vault-root /path/to/vault --dry-run
```

Apply captions from prepared JSON:

```bash
python3 scripts/caption_images_in_note.py /path/to/note.md --vault-root /path/to/vault --captions-json /tmp/captions.json
```

## Input / Output

- Input: one Obsidian Markdown note
- Output: the same note with missing captions inserted beneath image embeds

## Notable Behaviors

- only processes one note at a time
- skips images that already appear captioned unless `--force` is used
- preserves list indentation and local Markdown structure
- treats image parsing and note rewriting deterministically; only caption text generation is variable

## Limitations

- caption quality depends on the caption-generation workflow used upstream of `--captions-json`
- only handles one note at a time
- existing-caption detection is conservative and heuristic

## Safety Notes

- use `--dry-run` first when testing on a new note style
- review generated captions before keeping them in a long-term knowledge base
- `--force` can re-open images that were previously treated as captioned

## References

- `references/caption-behavior.md`
- `references/safety-behavior.md`

## Examples

- `examples/captioned-note.md`
- `examples/existing-captions.md`
