# Sample Note

Example request:

```bash
python3 scripts/fix_image_paths.py /path/to/project-note.md --dry-run
```

Expected outcome:

- misplaced image embeds are identified
- proposed move targets are shown
- rerunning without `--dry-run` rewrites embeds and moves files into the expected `assets/` location
