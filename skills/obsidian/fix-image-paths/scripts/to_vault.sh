#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  bash to_vault.sh [note-path-or-rel] [extra-args...]

Examples:
  bash to_vault.sh "stock/调研笔记/研报阅读202603-W1.md" --dry-run
  bash to_vault.sh "/Users/liyang/Documents/Obsidian Vault/stock/调研笔记/研报阅读202603-W1.md"
  bash to_vault.sh --yes --dry-run          # interactive note selection, skip confirm
  bash to_vault.sh                           # interactive note selection + confirm

Defaults:
  vault root: $OBSIDIAN_VAULT or "$HOME/Documents/Obsidian Vault"

If note-path-or-rel is omitted:
  interactive selection prompt (recent + discovered .md files)

Wrapper options:
  --yes | --no-confirm  Skip final confirmation prompt
  --confirm             Force final confirmation prompt (default)
EOF
}

confirm=true

contains_item() {
	local needle="$1"
	shift
	for item in "$@"; do
		if [ "$item" = "$needle" ]; then
			return 0
		fi
	done
	return 1
}

add_unique() {
	local value="$1"
	[ -n "$value" ] || return 0
	if ! contains_item "$value" "${candidates[@]:-}"; then
		candidates+=("$value")
	fi
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	usage
	exit 0
fi

# --- Resolve vault root ---
vault_root=""
if command -v obsidian &>/dev/null; then
	vault_root=$(obsidian vault info=path 2>/dev/null) || vault_root=""
fi
vault_root="${vault_root:-${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian Vault}}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core_script="$script_dir/fix_image_paths.py"
history_file="$script_dir/.to_vault_note_history"

if [ ! -f "$core_script" ]; then
	echo "Error: core script not found: $core_script" >&2
	exit 1
fi

# --- Parse arguments: separate note input from flags ---
note_input=""
remaining_args=()

for arg in "$@"; do
	case "$arg" in
	--yes | --no-confirm)
		confirm=false
		;;
	--confirm)
		confirm=true
		;;
	--dry-run | --vault-root | --vault-root=*)
		remaining_args+=("$arg")
		;;
	*)
		if [ -z "$note_input" ] && [[ "$arg" != --* ]]; then
			note_input="$arg"
		else
			remaining_args+=("$arg")
		fi
		;;
	esac
done

# --- Interactive note selection when no note path given ---
if [ -z "$note_input" ]; then
	candidates=()

	if [ -f "$history_file" ]; then
		history_lines=()
		while IFS= read -r history_line || [ -n "$history_line" ]; do
			history_lines+=("$history_line")
		done <"$history_file"
		history_count=${#history_lines[@]}
		start=$((history_count - 1))
		added=0
		while [ "$start" -ge 0 ] && [ "$added" -lt 5 ]; do
			candidate="${history_lines[$start]}"
			if [ -n "$candidate" ] && ! contains_item "$candidate" "${candidates[@]:-}"; then
				if [ -f "$vault_root/$candidate" ]; then
					candidates+=("$candidate")
					added=$((added + 1))
				fi
			fi
			start=$((start - 1))
		done
	fi

	for search_dir in "stock/文章笔记" "stock/调研笔记"; do
		target="$vault_root/$search_dir"
		if [ -d "$target" ]; then
			while IFS= read -r md_file; do
				rel="${md_file#"$vault_root"/}"
				add_unique "$rel"
			done < <(find "$target" -name '*.md' -type f | sort -r)
		fi
	done

	if [ ${#candidates[@]} -eq 0 ]; then
		printf "No .md files found in vault. Enter note path manually.\n"
		printf "Note path (relative to vault): "
		read -r manual_path
		if [ -n "$manual_path" ]; then
			note_input="$manual_path"
		else
			printf "Error: note path cannot be empty.\n" >&2
			exit 1
		fi
	else
		printf "\nSelect note to fix image paths (relative to vault):\n"
		for i in "${!candidates[@]}"; do
			printf "  [%d] %s\n" "$((i + 1))" "${candidates[$i]}"
		done
		printf "  [m] Manual input\n"

		while true; do
			printf "Choose one: "
			read -r selection

			if [ "$selection" = "m" ] || [ "$selection" = "M" ]; then
				printf "Note path (relative to vault): "
				read -r manual_path
				if [ -n "$manual_path" ]; then
					note_input="$manual_path"
					break
				fi
				printf "Path cannot be empty.\n"
				continue
			fi

			if [[ "$selection" =~ ^[0-9]+$ ]]; then
				idx=$((selection - 1))
				if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#candidates[@]} ]; then
					note_input="${candidates[$idx]}"
					break
				fi
			fi

			printf "Invalid choice. Pick a number or 'm'.\n"
		done
	fi
fi

# --- Resolve note path ---
if [[ "$note_input" = /* ]]; then
	note_path="$note_input"
else
	note_path="$vault_root/$note_input"
fi

if [ ! -f "$note_path" ]; then
	echo "Error: note not found: $note_path" >&2
	exit 1
fi

# --- Build final args for core script ---
has_vault_root=false
for arg in "${remaining_args[@]:-}"; do
	if [ "$arg" = "--vault-root" ] || [[ "$arg" == --vault-root=* ]]; then
		has_vault_root=true
		break
	fi
done

extra_args=("${remaining_args[@]:-}")
if [ "$has_vault_root" = false ]; then
	extra_args=(--vault-root "$vault_root" "${extra_args[@]}")
fi

vault_root_preview="$vault_root"
if [ "$has_vault_root" = true ]; then
	vault_root_preview="(provided via args)"
fi

# --- Confirmation ---
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

# --- Execute ---
python3 "$core_script" "$note_path" "${extra_args[@]}"

# --- Save to history ---
note_rel="${note_path#"$vault_root"/}"
tmp_history="${history_file}.tmp"
if [ -f "$history_file" ]; then
	cat "$history_file" >"$tmp_history"
else
	: >"$tmp_history"
fi
printf "%s\n" "$note_rel" >>"$tmp_history"
tail -n 50 "$tmp_history" >"$history_file"
rm -f "$tmp_history"
