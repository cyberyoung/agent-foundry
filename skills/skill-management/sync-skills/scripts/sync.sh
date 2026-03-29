#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NAMESPACE_ROOT="$(cd -- "$SKILL_ROOT/.." && pwd)"
SKILLS_ROOT="$(cd -- "$NAMESPACE_ROOT/.." && pwd)"
AGENTS_ROOT="$(cd -- "$SKILLS_ROOT/.." && pwd)"

# ---------------------------------------------------------------------------
# Portable realpath (macOS 12.3+ has realpath; python3 fallback for older)
# ---------------------------------------------------------------------------
resolve_realpath() {
	realpath "$1" 2>/dev/null ||
		python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null ||
		echo "$1"
}

SKILLS_ROOT_RESOLVED="$(resolve_realpath "$SKILLS_ROOT")"

# ---------------------------------------------------------------------------
# Target registry (indexed arrays — bash 3.2 compatible)
# ---------------------------------------------------------------------------
TARGET_NAMES=(claude codex opencode obsidian)
TARGET_PATHS=(
	"$HOME/.claude/skills"
	"$HOME/.codex/skills"
	"$HOME/.config/opencode/skills"
	"$HOME/Documents/Obsidian Vault/.claude/skills"
)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
DRY_RUN=false
SKIP_LIST=""
ONLY_LIST=""

usage() {
	cat <<'EOF'
Usage:
  sync.sh [options]

Options:
  --skip <targets>       Comma-separated target aliases to skip
  --only <targets>       Comma-separated target aliases to sync (whitelist)
  --dry-run              Print planned operations without executing
  --list-targets         List available target aliases and paths
  -h, --help             Show this help message

--skip and --only are mutually exclusive.

Target aliases: claude, codex, opencode, obsidian

Note: --dry-run only affects symlink operations (create/fix/remove).
EOF
}

list_targets() {
	echo "Available sync targets:"
	echo ""
	for i in "${!TARGET_NAMES[@]}"; do
		printf "  %-12s %s\n" "${TARGET_NAMES[$i]}" "${TARGET_PATHS[$i]}"
	done
}

# Resolve alias to path; returns 1 if alias unknown
resolve_alias() {
	local alias="$1"
	for i in "${!TARGET_NAMES[@]}"; do
		if [ "${TARGET_NAMES[$i]}" = "$alias" ]; then
			echo "${TARGET_PATHS[$i]}"
			return 0
		fi
	done
	echo "[error] unknown target alias: $alias" >&2
	echo "Valid aliases: ${TARGET_NAMES[*]}" >&2
	return 1
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--skip)
		if [ "$#" -lt 2 ]; then
			echo "[error] missing value for $1" >&2
			exit 1
		fi
		SKIP_LIST="$2"
		shift 2
		;;
	--only)
		if [ "$#" -lt 2 ]; then
			echo "[error] missing value for $1" >&2
			exit 1
		fi
		ONLY_LIST="$2"
		shift 2
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	--list-targets)
		list_targets
		exit 0
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "[error] unknown argument: $1" >&2
		usage
		exit 1
		;;
	esac
done

# Mutual exclusion check
if [ -n "$SKIP_LIST" ] && [ -n "$ONLY_LIST" ]; then
	echo "[error] --skip and --only are mutually exclusive" >&2
	exit 1
fi

# ---------------------------------------------------------------------------
# Build effective TARGETS array from skip/only filters
# ---------------------------------------------------------------------------
TARGETS=()

if [ -n "$ONLY_LIST" ]; then
	IFS=',' read -ra only_aliases <<<"$ONLY_LIST"
	for alias in "${only_aliases[@]}"; do
		alias="$(echo "$alias" | tr -d ' ')"
		path="$(resolve_alias "$alias")" || exit 1
		TARGETS+=("$path")
	done
elif [ -n "$SKIP_LIST" ]; then
	IFS=',' read -ra skip_aliases <<<"$SKIP_LIST"
	# Build skip set
	skip_set=""
	for alias in "${skip_aliases[@]}"; do
		alias="$(echo "$alias" | tr -d ' ')"
		resolve_alias "$alias" >/dev/null || exit 1
		skip_set="$skip_set $alias "
	done
	for i in "${!TARGET_NAMES[@]}"; do
		if [[ "$skip_set" != *" ${TARGET_NAMES[$i]} "* ]]; then
			TARGETS+=("${TARGET_PATHS[$i]}")
		fi
	done
else
	TARGETS=("${TARGET_PATHS[@]}")
fi

if [ "${#TARGETS[@]}" -eq 0 ]; then
	echo "[error] no targets remaining after filter" >&2
	exit 1
fi

# ---------------------------------------------------------------------------
# Ensure target directories exist
# ---------------------------------------------------------------------------
for target_dir in "${TARGETS[@]}"; do
	if [ ! -d "$target_dir" ]; then
		if [ "$DRY_RUN" = true ]; then
			echo "[dry-run] would create $target_dir"
		else
			mkdir -p "$target_dir"
		fi
	fi
done

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
created=0
skipped=0
fixed=0
conflict=0
warned=0

# ---------------------------------------------------------------------------
# Core sync function
# ---------------------------------------------------------------------------
sync_skill() {
	local skill_path="$1"
	local link_name="$2"

	for target_dir in "${TARGETS[@]}"; do
		local link_path="$target_dir/$link_name"

		if [ -L "$link_path" ]; then
			local current_target
			current_target="$(readlink "$link_path")"
			if [ "$current_target" = "$skill_path" ]; then
				skipped=$((skipped + 1))
			else
				# Resolve to real path to handle OneDrive symlink aliases
				local link_resolved
				link_resolved="$(resolve_realpath "$link_path")"
				if [[ "$link_resolved" == "$SKILLS_ROOT_RESOLVED"/* ]]; then
					# Points into our skills tree (path changed) — safe to overwrite
					if [ "$DRY_RUN" = true ]; then
						echo "[dry-run] would fix $link_path -> $skill_path (was: $current_target)"
					else
						rm "$link_path"
						ln -s "$skill_path" "$link_path"
						echo "[fixed]   $link_path -> $skill_path (was: $current_target)"
					fi
					fixed=$((fixed + 1))
				else
					# Points outside our tree (plugin / external) — do not touch
					echo "[conflict] $link_path -> $current_target (external, skipped)"
					conflict=$((conflict + 1))
				fi
			fi
		elif [ -e "$link_path" ]; then
			echo "[warn]    $link_path exists as regular file/dir, skipped"
			warned=$((warned + 1))
		else
			if [ "$DRY_RUN" = true ]; then
				echo "[dry-run] would create $link_path -> $skill_path"
			else
				ln -s "$skill_path" "$link_path"
				echo "[created] $link_path -> $skill_path"
			fi
			created=$((created + 1))
		fi
	done
}

# ---------------------------------------------------------------------------
# Discover and sync skills
# ---------------------------------------------------------------------------
for entry in "$SKILLS_ROOT"/*/; do
	[ -d "$entry" ] || continue
	entry_name="$(basename "$entry")"

	if [ -f "$entry/.prefix" ]; then
		prefix="$(cat "$entry/.prefix")"
		for skill_path in "$entry"/*/; do
			[ -d "$skill_path" ] || continue
			[ -f "$skill_path/SKILL.md" ] || continue
			skill_name="$(basename "$skill_path")"
			sync_skill "$skill_path" "${prefix}-${skill_name}"
		done
	else
		[ -f "$entry/SKILL.md" ] || continue
		sync_skill "$entry" "$entry_name"
	fi
done

# ---------------------------------------------------------------------------
# Clean stale symlinks (broken links whose target no longer exists)
# ---------------------------------------------------------------------------
for target_dir in "${TARGETS[@]}"; do
	[ -d "$target_dir" ] || continue
	while IFS= read -r -d '' link_path; do
		if [ "$DRY_RUN" = true ]; then
			echo "[dry-run] would remove $link_path (stale)"
		else
			echo "[removed] $link_path (stale)"
			rm -- "$link_path"
		fi
	done < <(find "$target_dir" -maxdepth 1 -type l ! -exec test -e {} \; -print0)
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [ "$DRY_RUN" = true ]; then
	echo "Dry-run: $created would create, $fixed would fix, $skipped unchanged, $conflict conflicts, $warned warnings"
else
	echo "Done: $created created, $fixed fixed, $skipped unchanged, $conflict conflicts, $warned warnings"
fi
