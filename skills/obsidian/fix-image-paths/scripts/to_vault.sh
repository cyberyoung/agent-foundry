#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  bash to_vault.sh <note-path-or-rel> [extra-args...]

Examples:
  bash to_vault.sh "stock/调研笔记/研报阅读202603-W1.md" --dry-run
  bash to_vault.sh "/Users/liyang/Documents/Obsidian Vault/stock/调研笔记/研报阅读202603-W1.md"
  bash to_vault.sh "stock/调研笔记/研报阅读202603-W1.md" --yes --dry-run

Defaults:
  vault root: $OBSIDIAN_VAULT or "$HOME/Documents/Obsidian Vault"

Wrapper options:
  --yes | --no-confirm  Skip final confirmation prompt
  --confirm             Force final confirmation prompt (default)
EOF
}

confirm=true

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
core_script="$script_dir/fix_image_paths.py"

if [ ! -f "$core_script" ]; then
	echo "Error: core script not found: $core_script" >&2
	exit 1
fi

if [ ! -f "$note_path" ]; then
	echo "Error: note not found: $note_path" >&2
	exit 1
fi

filtered_args=()
for arg in "$@"; do
	case "$arg" in
	--yes | --no-confirm)
		confirm=false
		;;
	--confirm)
		confirm=true
		;;
	*)
		filtered_args+=("$arg")
		;;
	esac
done

has_vault_root=false
for arg in "${filtered_args[@]}"; do
	if [ "$arg" = "--vault-root" ] || [[ "$arg" == --vault-root=* ]]; then
		has_vault_root=true
		break
	fi
done

extra_args=("${filtered_args[@]}")
if [ "$has_vault_root" = false ]; then
	extra_args=(--vault-root "$vault_root" "${extra_args[@]}")
fi

vault_root_preview="$vault_root"
if [ "$has_vault_root" = true ]; then
	vault_root_preview="(provided via args)"
fi

if [ "$confirm" = true ]; then
	printf "\nExecution Preview\n"
	printf -- "- Skill: ob-fix-image-paths\n"
	printf -- "- Note input: %s\n" "$note_input"
	printf -- "- Resolved note path: %s\n" "$note_path"
	printf -- "- Vault root: %s\n" "$vault_root_preview"
	if [ ${#extra_args[@]} -gt 0 ]; then
		printf -- "- Args passed to core script:\n"
		for arg in "${extra_args[@]}"; do
			printf "  - %q\n" "$arg"
		done
	fi

	while true; do
		printf "Proceed? [1] Yes  [2] No: "
		read -r choice
		case "$choice" in
		1 | y | Y | yes | YES)
			break
			;;
		2 | n | N | no | NO | "")
			printf "Cancelled.\n"
			exit 1
			;;
		*)
			printf "Please enter 1 or 2.\n"
			;;
		esac
	done
fi

python3 "$core_script" "$note_path" "${extra_args[@]}"
