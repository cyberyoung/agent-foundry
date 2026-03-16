# Sorting And HEIC Behavior

- images are embedded in deterministic filename order
- sorting is case-insensitive
- HEIC files are converted to JPG by default using macOS `sips`
- `--keep-heic` skips conversion
- `--remove-heic` removes original HEIC files after conversion
