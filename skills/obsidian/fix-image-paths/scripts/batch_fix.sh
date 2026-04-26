#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/fix_image_paths.py"

DEFAULT_DIRS=("stock/文章笔记" "stock/调研笔记")

usage() {
	cat <<'EOF'
Usage:
  bash batch_fix.sh [options] [dir1 dir2 ...]

Batch-fix image paths for all .md files under the given directories.

Options:
  --dry-run         Preview changes without modifying anything
  --vault-root DIR  Vault root directory (auto-detected if omitted)
  -h, --help        Show this help

Arguments:
  dir1 dir2 ...     Vault-relative directories to process
                    Default: stock/文章笔记  stock/调研笔记

Examples:
  bash batch_fix.sh --dry-run
  bash batch_fix.sh
  bash batch_fix.sh "stock/文章笔记"
  bash batch_fix.sh --vault-root ~/vault "research/notes" "stock/调研笔记"
EOF
}

dry_run=false
vault_root=""
target_dirs=()

while [ $# -gt 0 ]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	--dry-run)
		dry_run=true
		shift
		;;
	--vault-root)
		vault_root="$2"
		shift 2
		;;
	--vault-root=*)
		vault_root="${1#--vault-root=}"
		shift
		;;
	-*)
		printf "Unknown option: %s\n" "$1" >&2
		usage >&2
		exit 1
		;;
	*)
		target_dirs+=("$1")
		shift
		;;
	esac
done

if [ ${#target_dirs[@]} -eq 0 ]; then
	target_dirs=("${DEFAULT_DIRS[@]}")
fi

if [ ! -f "$CORE_SCRIPT" ]; then
	printf "[ERROR] core script not found: %s\n" "$CORE_SCRIPT" >&2
	exit 1
fi

# --- Resolve vault root ---
if [ -z "$vault_root" ]; then
	if command -v obsidian &>/dev/null; then
		vault_root=$(obsidian vault info=path 2>/dev/null) || vault_root=""
	fi
	vault_root="${vault_root:-${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian Vault}}"
fi

printf "Vault root: %s\n" "$vault_root"
printf "Directories: %s\n" "${target_dirs[*]}"
if [ "$dry_run" = true ]; then
	printf "[DRY RUN] No changes will be made.\n"
fi
printf "\n"

total_notes=0
total_moved=0
total_not_found=0
total_skipped=0
failed_notes=()

core_args=(--vault-root "$vault_root")
if [ "$dry_run" = true ]; then
	core_args+=(--dry-run)
fi

for rel_dir in "${target_dirs[@]}"; do
	abs_dir="$vault_root/$rel_dir"
	if [ ! -d "$abs_dir" ]; then
		printf "[WARN] Directory not found, skipping: %s\n" "$rel_dir"
		continue
	fi

	printf "=== %s ===\n" "$rel_dir"

	while IFS= read -r note; do
		total_notes=$((total_notes + 1))
		note_rel="${note#"$vault_root"/}"
		printf -- "--- %s ---\n" "$note_rel"

		if output=$(python3 "$CORE_SCRIPT" "$note" "${core_args[@]}" 2>&1); then
			if echo "$output" | grep -q "already in the correct location"; then
				total_skipped=$((total_skipped + 1))
				printf "  (all images OK)\n"
			else
				moved=$(echo "$output" | sed -nE 's/.*(Moved|Would move) ([0-9]+) image.*/\2/p' | head -1)
				moved="${moved:-0}"
				not_found=$(echo "$output" | sed -nE 's/.*WARNING: ([0-9]+) image.*/\1/p' | head -1)
				not_found="${not_found:-0}"
				total_moved=$((total_moved + moved))
				total_not_found=$((total_not_found + not_found))
				if [ "$moved" -gt 0 ]; then
					printf "  %s image(s) %s\n" "$moved" "$([ "$dry_run" = true ] && echo 'would move' || echo 'moved')"
				fi
				if [ "$not_found" -gt 0 ]; then
					printf "  %s image(s) not found\n" "$not_found"
				fi
			fi
		else
			failed_notes+=("$note_rel")
			printf "  [ERROR] %s\n" "$output"
		fi
	done < <(find "$abs_dir" -name '*.md' -type f | sort)

	printf "\n"
done

# --- Summary ---
printf "========== Summary ==========\n"
printf "Notes processed:  %d\n" "$total_notes"
printf "Images %s:  %d\n" "$([ "$dry_run" = true ] && echo 'to move' || echo 'moved')" "$total_moved"
printf "Images not found: %d\n" "$total_not_found"
printf "Notes skipped:    %d (all images OK)\n" "$total_skipped"

if [ ${#failed_notes[@]} -gt 0 ]; then
	printf "Failed notes:     %d\n" "${#failed_notes[@]}"
	for fn in "${failed_notes[@]}"; do
		printf "  - %s\n" "$fn"
	done
fi

if [ "$dry_run" = true ]; then
	printf "\n[DRY RUN] Re-run without --dry-run to apply changes.\n"
else
	printf "\nDone.\n"
fi
