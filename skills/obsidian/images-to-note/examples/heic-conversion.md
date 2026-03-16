# HEIC Conversion Example

Input directory:

```text
photos/
├── IMG_0001.HEIC
├── IMG_0002.HEIC
└── IMG_0003.JPG
```

Typical behavior:

- HEIC files are converted to JPG
- the generated note embeds the resulting image files
- original HEIC files remain unless `--remove-heic` is used
