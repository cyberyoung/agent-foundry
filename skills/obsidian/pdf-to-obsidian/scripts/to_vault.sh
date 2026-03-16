#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  bash to_vault.sh <input.pdf> [output-rel-path] [extra-args...]

Examples:
  bash to_vault.sh "/path/to/report.pdf"
  bash to_vault.sh "/path/to/report.pdf" "stock/调研笔记"
  bash to_vault.sh "/path/to/report.pdf" "stock/交易笔记" --analyze
  bash to_vault.sh "/path/to/report.pdf" --yes

Defaults:
  vault root: $OBSIDIAN_VAULT or "$HOME/Documents/Obsidian Vault"

If output-rel-path is omitted:
  interactive selection prompt (recent + discovered directories)

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

if [ $# -lt 1 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	usage
	if [ $# -lt 1 ]; then
		exit 1
	fi
	exit 0
fi

input_pdf="$1"
shift

output_rel=""
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
	output_rel="$1"
	shift
fi

vault_root="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian Vault}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core_script="$script_dir/pdf_to_obsidian.py"
history_file="$script_dir/.to_vault_output_history"

if [ ! -f "$core_script" ]; then
	echo "Error: core script not found: $core_script" >&2
	exit 1
fi

if [ ! -f "$input_pdf" ]; then
	echo "Error: input pdf not found: $input_pdf" >&2
	exit 1
fi

extra_args=()
for arg in "$@"; do
	case "$arg" in
	--yes | --no-confirm)
		confirm=false
		;;
	--confirm)
		confirm=true
		;;
	*)
		extra_args+=("$arg")
		;;
	esac
done

if [ -z "$output_rel" ]; then
	candidates=()

	if [ -f "$history_file" ]; then
		history_lines=()
		while IFS= read -r history_line || [ -n "$history_line" ]; do
			history_lines+=("$history_line")
		done <"$history_file"
		history_count=${#history_lines[@]}
		start=$((history_count - 1))
		added=0
		while [ "$start" -ge 0 ] && [ "$added" -lt 3 ]; do
			candidate="${history_lines[$start]}"
			if [ -n "$candidate" ] && ! contains_item "$candidate" "${candidates[@]:-}"; then
				candidates+=("$candidate")
				added=$((added + 1))
			fi
			start=$((start - 1))
		done
	fi

	for recommended in "stock/调研笔记" "stock/Inbox" "myk/调研笔记"; do
		if [ -d "$vault_root/$recommended" ]; then
			add_unique "$recommended"
		fi
	done

	for d in "$vault_root"/stock/* "$vault_root"/myk/*; do
		if [ -d "$d" ]; then
			rel="${d#"$vault_root"/}"
			add_unique "$rel"
		fi
	done

	printf "\nSelect output directory (relative to vault):\n"
	if [ ${#candidates[@]} -gt 0 ]; then
		for i in "${!candidates[@]}"; do
			printf "  [%d] %s\n" "$((i + 1))" "${candidates[$i]}"
		done
	fi
	printf "  [m] Manual input\n"

	while true; do
		printf "Choose one: "
		read -r selection

		if [ "$selection" = "m" ] || [ "$selection" = "M" ]; then
			printf "Enter output-rel-path: "
			read -r manual_path
			if [ -n "$manual_path" ]; then
				output_rel="$manual_path"
				break
			fi
			printf "Path cannot be empty.\n"
			continue
		fi

		if [[ "$selection" =~ ^[0-9]+$ ]]; then
			idx=$((selection - 1))
			if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#candidates[@]} ]; then
				output_rel="${candidates[$idx]}"
				break
			fi
		fi

		printf "Invalid choice. Pick a number or 'm'.\n"
	done
fi

output_dir="$vault_root/$output_rel"

if [ "$confirm" = true ]; then
	printf "\nExecution Preview\n"
	printf -- "- Skill: ob-pdf-converter\n"
	printf -- "- Input pdf: %s\n" "$input_pdf"
	printf -- "- Vault root: %s\n" "$vault_root"
	printf -- "- Output rel path: %s\n" "$output_rel"
	printf -- "- Output dir: %s\n" "$output_dir"
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

mkdir -p "$output_dir"

python3 "$core_script" "$input_pdf" "$output_dir" "${extra_args[@]}"

tmp_history="${history_file}.tmp"
if [ -f "$history_file" ]; then
	cat "$history_file" >"$tmp_history"
else
	: >"$tmp_history"
fi
printf "%s\n" "$output_rel" >>"$tmp_history"
tail -n 50 "$tmp_history" >"$history_file"
rm -f "$tmp_history"
