#!/usr/bin/env bash
set -euo pipefail

VAULT="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian Vault}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ $# -lt 1 ]; then
	echo "Usage: bash $0 <directory> [extra-args...]"
	echo ""
	echo "  <directory>   Vault-relative or absolute path to image directory"
	echo "  [extra-args]  Passed through to images_to_note.py (--keep-heic, --remove-heic, --dry-run)"
	echo ""
	echo "Examples:"
	echo "  bash $0 \"stock/Inbox/纸质笔记/研报\""
	echo "  bash $0 \"stock/Inbox/纸质笔记/研报\" --dry-run"
	echo "  bash $0 \"stock/Inbox/纸质笔记/研报\" --keep-heic"
	exit 1
fi

DIR_ARG="$1"
shift

if [[ "$DIR_ARG" = /* ]]; then
	TARGET_DIR="$DIR_ARG"
else
	TARGET_DIR="$VAULT/$DIR_ARG"
fi

if [ ! -d "$TARGET_DIR" ]; then
	echo "Error: directory not found: $TARGET_DIR" >&2
	exit 1
fi

echo "=== images-to-note ==="
echo "Directory: $TARGET_DIR"
echo ""

python3 "$SCRIPT_DIR/images_to_note.py" "$TARGET_DIR" "$@"
