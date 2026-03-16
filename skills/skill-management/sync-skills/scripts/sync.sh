#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NAMESPACE_ROOT="$(cd -- "$SKILL_ROOT/.." && pwd)"
SKILLS_ROOT="$(cd -- "$NAMESPACE_ROOT/.." && pwd)"
AGENTS_ROOT="$(cd -- "$SKILLS_ROOT/.." && pwd)"
TARGETS=(
	"$HOME/.claude/skills"
	"$HOME/.codex/skills"
	"$HOME/.config/opencode/skills"
)

created=0
skipped=0
fixed=0
warned=0

for target_dir in "${TARGETS[@]}"; do
	mkdir -p "$target_dir"
done

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
				rm "$link_path"
				ln -s "$skill_path" "$link_path"
				echo "[fixed]   $link_path -> $skill_path (was: $current_target)"
				fixed=$((fixed + 1))
			fi
		elif [ -e "$link_path" ]; then
			echo "[warn]    $link_path exists as regular file/dir, skipped"
			warned=$((warned + 1))
		else
			ln -s "$skill_path" "$link_path"
			echo "[created] $link_path -> $skill_path"
			created=$((created + 1))
		fi
	done
}

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

# Clean stale symlinks (broken symlinks not matched by glob, use find)
for target_dir in "${TARGETS[@]}"; do
	find "$target_dir" -maxdepth 1 -type l ! -exec test -e {} \; -print | while read -r link_path; do
		echo "[removed] $link_path (stale)"
		rm "$link_path"
	done
done

echo ""
echo "Done: $created created, $fixed fixed, $skipped unchanged, $warned warnings"
