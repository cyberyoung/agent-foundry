# bookmarks-to-note

Convert a Chrome bookmark folder into an Obsidian Markdown note.

## What It Does

This skill reads bookmark data from Chrome's exported or local bookmarks file, finds a selected folder, and generates a Markdown note with frontmatter and structured links. It can preserve folder hierarchy or group flat lists by topic.

## When To Use It

- archive a bookmark folder into Obsidian
- turn a research folder into a readable note
- group bookmark links into topic sections for later review

## Main Entry Points

- Core script: `scripts/chrome_bookmarks_to_note.py`
- Local convenience wrapper: `scripts/to_stock_inbox.sh`

The core script is the public entrypoint. The wrapper is local-workflow-oriented and should not be the primary public interface.

## Requirements

- `python3`
- access to a Chrome `Bookmarks` JSON file or compatible local Chrome profile data

## Basic Usage

```bash
python3 scripts/chrome_bookmarks_to_note.py "Bookmarks Bar/AI Tools" /path/to/output-dir
```

With explicit file and simple grouping options:

```bash
python3 scripts/chrome_bookmarks_to_note.py \
  "Bookmarks Bar/AI Tools" \
  /path/to/output-dir \
  --bookmarks-file ~/Library/Application\ Support/Google/Chrome/Default/Bookmarks \
  --group-mode rules
```

## Input / Output

- Input: a bookmark folder name or full bookmark path, plus an output directory
- Output: one Markdown note with YAML frontmatter and grouped links

## Notable Behaviors

- supports matching by folder name or full folder path
- can recurse through nested bookmark folders
- supports `rules`, `llm`, and `hybrid` grouping modes
- skips separator-style bookmark entries automatically
- can learn topic keywords back into `config/topic_rules.json`

## Public Release Boundaries

- the generic public interface is bookmark-folder-to-note conversion
- stock-specific output wrappers should be treated as local convenience helpers, not the main public story
- LLM-assisted grouping should be documented as optional behavior, not the only expected path

## Limitations

- currently focused on Chrome bookmark data
- grouping quality depends on rules, input quality, and optional LLM assistance
- private wrapper defaults should be ignored for public use

## Safety Notes

- review generated grouping and note title before saving into a long-term vault location
- when using LLM or hybrid grouping, verify learned keywords before keeping them permanently

## References

- `references/input-format.md`
- `references/grouping-rules.md`

## Examples

- `examples/bookmark-note.md`
- `examples/nested-folders.md`
