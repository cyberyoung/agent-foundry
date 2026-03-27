# Architecture

## Purpose

This repository packages reusable assets for agent workflows. The current public emphasis is on `skills/`, with an initial focus on Obsidian-oriented document and note utilities.

## Public-Facing Structure

```text
agent-foundry/
├── README.md
├── LICENSE
├── docs/
└── skills/
```

## Repository Shape

### Current Shape

```text
/etc/agents/
├── README.md
├── LICENSE
├── docs/
├── scripts/
├── skills/
├── claude.json
├── dot-claude/
└── dot-codex/
```

### Public-First Shape

The intended first public-facing shape focuses on a narrower subset:

```text
/etc/agents/
├── README.md
├── LICENSE
├── docs/
│   ├── architecture.md
│   └── installation.md
└── skills/
    ├── README.md
    └── obsidian/
        ├── pdf-to-obsidian/
        ├── docx-converter/
        ├── fix-image-paths/
        └── bookmarks-to-note/
```

### Why The Public View Is Narrower

- `skills/find-skills/` is upstream and not republished as original work
- `skills/skill-management/` is an internal maintenance namespace
- `topic-tracker-note` and `wx-article-digest` remain local until generalized further
- runtime/config state such as `dot-claude/`, `dot-codex/`, and `claude.json` is not part of the public-first subset

## Skills Layout

The current public skill catalog lives under `skills/`.

```text
skills/
├── README.md
└── obsidian/
    ├── pdf-to-obsidian/
    ├── docx-converter/
    ├── fix-image-paths/
    ├── bookmarks-to-note/
    ├── images-to-note/
    └── image-captioner/
```

## Namespace Rules

- `obsidian/` uses `.prefix = ob`, so runtime names appear as `ob-*`
- `skill-management/` uses `.prefix = sm`, but that namespace is maintained for internal workflow support and is not part of the public-first catalog

## Command Domains

Global commands are split into two domains, each with its own restore script for new-machine recovery:

### opencode domain

Profile and health commands for Oh-My-OpenCode. Source lives in `~/.config/opencode/`.

- `omop` / `omo-profile` — profile management
- `omo-health` / `omop-health` — model health check
- `restore-opencode-links` — restore opencode-domain symlinks

### agents domain

Skill lifecycle commands for this repository. Source lives in `scripts/`.

- `sm-lifecycle` — upstream skill onboarding, upgrade, and verification
- `restore-agents-link` — restore agents-domain symlinks

Both restore scripts are self-locating (derive paths from `BASH_SOURCE[0]`), so they work regardless of clone location.

## Design Principles

- keep each skill independently understandable and installable
- keep public docs focused on current capabilities, not internal planning history
- separate public skill interfaces from local convenience wrappers when they serve different purposes
