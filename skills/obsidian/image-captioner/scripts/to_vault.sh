#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  bash to_vault.sh <note-path-or-rel> [extra-args...]

Examples:
  bash to_vault.sh "stock/调研笔记/研报阅读202603-W2.md" --dry-run
  bash to_vault.sh "stock/调研笔记/研报阅读202603-W2.md" --captions-json /tmp/captions.json
  bash to_vault.sh "/absolute/path/to/note.md" --force

Defaults:
  vault root: $OBSIDIAN_VAULT or "$HOME/Documents/Obsidian Vault"
EOF
}

if [ $# -lt 1 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	usage
	if [ $# -lt 1 ]; then
		exit 1
	fi
	exit 0
fi

note_input="$1"
shift

vault_root="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian Vault}"
if [[ "$note_input" = /* ]]; then
	note_path="$note_input"
else
	note_path="$vault_root/$note_input"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core_script="$script_dir/caption_images_in_note.py"

if [ ! -f "$core_script" ]; then
	echo "Error: core script not found: $core_script" >&2
	exit 1
fi

if [ ! -f "$note_path" ]; then
	echo "Error: note not found: $note_path" >&2
	exit 1
fi

has_vault_root=false
for arg in "$@"; do
	if [ "$arg" = "--vault-root" ] || [[ "$arg" == --vault-root=* ]]; then
		has_vault_root=true
		break
	fi
done

extra_args=("$@")
if [ "$has_vault_root" = false ]; then
	extra_args=(--vault-root "$vault_root" "${extra_args[@]}")
fi

python3 "$core_script" "$note_path" "${extra_args[@]}"
