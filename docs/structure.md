# Repository Structure

This repository is organized around reusable agent assets.

## Current Shape

```text
/etc/agents/
├── README.md
├── LICENSE
├── docs/
├── skills/
├── claude.json
├── dot-claude/
└── dot-codex/
```

## Public-First Shape

The intended first public-facing shape focuses on a narrow subset of this tree:

```text
/etc/agents/
├── README.md
├── LICENSE
├── docs/
│   ├── architecture.md
│   ├── installation.md
│   ├── structure.md
│   └── compatibility.md
└── skills/
    ├── README.md
    └── obsidian/
        ├── pdf-to-obsidian/
        ├── docx-converter/
        ├── fix-image-paths/
        └── bookmarks-to-note/
```

## Why The Public View Is Narrower

- `skills/find-skills/` is upstream and not republished as original work
- `skills/skill-management/` is an internal maintenance namespace
- `topic-tracker-note` and `wx-article-digest` remain local until generalized further
- runtime/config state such as `dot-claude/`, `dot-codex/`, and `claude.json` is not part of the public-first subset
