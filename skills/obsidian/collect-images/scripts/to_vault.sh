#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Default vault root
VAULT="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian Vault}"

# Find vault root from .obsidian marker
if [ ! -d "$VAULT/.obsidian" ]; then
  # Try to find it
  FOUND=$(find "$HOME/Documents" -maxdepth 2 -name ".obsidian" -type d 2>/dev/null | head -1)
  if [ -n "$FOUND" ]; then
    VAULT="$(dirname "$FOUND")"
  fi
fi

python3 "$SCRIPT_DIR/scan_images.py" "$@" --vault-root "$VAULT"
