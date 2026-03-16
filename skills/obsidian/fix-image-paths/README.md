# fix-image-paths

Relocate misplaced images in an Obsidian note into a predictable `assets/` layout and rewrite the note's embeds to match.

## What It Does

This skill scans one Markdown note, resolves embedded image paths, moves images into the note's local `assets/` area when needed, and updates the note so the embeds point to the new location.

## When To Use It

- clean up broken or inconsistent image embeds
- normalize pasted images that ended up in the wrong place
- standardize note-local asset layout before publishing or reorganizing notes

## Main Entry Points

- Core script: `scripts/fix_image_paths.py`
- Local convenience wrapper: `scripts/to_vault.sh`

The core script is the public entrypoint. `weekly_stock_fix.sh` is workflow-specific and should not be treated as the main public interface.

## Requirements

- `python3` 3.10+
- no external Python packages required

## Basic Usage

```bash
python3 scripts/fix_image_paths.py /path/to/note.md --dry-run
python3 scripts/fix_image_paths.py /path/to/note.md
python3 scripts/fix_image_paths.py /path/to/note.md --vault-root /path/to/vault
```

## Input / Output

- Input: one Markdown note with Obsidian image embeds
- Output: the same note with updated embeds, plus moved image files under a note-local `assets/` layout

## Notable Behaviors

- auto-detects vault root when possible
- preserves embed aliases such as `![[image.png|caption]]`
- skips images already under the expected `assets/` area
- supports dry-run preview mode

## Safety Notes

- this skill edits notes in place
- this skill may move image files
- review the note diff and resulting asset tree after execution

## Limitations

- only documented image embed patterns are handled
- collision and broken-link handling should still be manually verified in edge cases
- workflow-specific helper scripts are not part of the public core interface

## References

- `references/path-rules.md`
- `references/safety-behavior.md`

## Examples

- `examples/before-after.md`
- `examples/sample-note.md`
