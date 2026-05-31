#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NAMESPACE_ROOT="$(cd -- "$SKILL_ROOT/.." && pwd)"
DEFAULT_SKILLS_ROOT="$(cd -- "$NAMESPACE_ROOT/.." && pwd)"
DEFAULT_AGENTS_ROOT="$(cd -- "$DEFAULT_SKILLS_ROOT/.." && pwd)"
DEFAULT_CONFIG_PATH="$SKILL_ROOT/sync-config.json"
DEFAULT_REGISTRY_PATH="$NAMESPACE_ROOT/skills-upstream-manager/upstream-registry.json"

resolve_realpath() {
	realpath "$1" 2>/dev/null ||
		python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null ||
		echo "$1"
}

DRY_RUN=false
SKIP_LIST=""
ONLY_LIST=""
INCLUDE_UPSTREAM=false
CONFIG_PATH=""
SKILLS_ROOT=""
REGISTRY_PATH=""

usage() {
	cat <<'EOF'
Usage:
  sync.sh [options]

Options:
  --skip <targets>       Comma-separated target aliases to skip
  --only <targets>       Comma-separated target aliases to sync (whitelist)
  --include-upstream     Include upstream skills this run (ignore global toggle)
  --config <path>        Path to sync-config.json
  --skills-root <path>   Path to skills source root
  --registry <path>      Path to upstream-registry.json
  --dry-run              Print planned operations without executing
  --list-targets         List available target aliases and paths
  --migrate-config       Upgrade v1 config to v2 template and exit
  -h, --help             Show this help message

--skip and --only are mutually exclusive.
Note: --dry-run only affects symlink operations (create/fix/remove).
EOF
}

LIST_TARGETS_REQUESTED=false
MIGRATE_CONFIG_REQUESTED=false

while [ "$#" -gt 0 ]; do
	case "$1" in
	--skip)
		[ "$#" -ge 2 ] || {
			echo "[error] missing value for $1" >&2
			exit 1
		}
		SKIP_LIST="$2"
		shift 2
		;;
	--only)
		[ "$#" -ge 2 ] || {
			echo "[error] missing value for $1" >&2
			exit 1
		}
		ONLY_LIST="$2"
		shift 2
		;;
	--include-upstream)
		INCLUDE_UPSTREAM=true
		shift
		;;
	--config)
		[ "$#" -ge 2 ] || {
			echo "[error] missing value for $1" >&2
			exit 1
		}
		CONFIG_PATH="$2"
		shift 2
		;;
	--skills-root)
		[ "$#" -ge 2 ] || {
			echo "[error] missing value for $1" >&2
			exit 1
		}
		SKILLS_ROOT="$2"
		shift 2
		;;
	--registry)
		[ "$#" -ge 2 ] || {
			echo "[error] missing value for $1" >&2
			exit 1
		}
		REGISTRY_PATH="$2"
		shift 2
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	--list-targets)
		LIST_TARGETS_REQUESTED=true
		shift
		;;
	--migrate-config)
		MIGRATE_CONFIG_REQUESTED=true
		shift
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

[ -n "$SKIP_LIST" ] && [ -n "$ONLY_LIST" ] && {
	echo "[error] --skip and --only are mutually exclusive" >&2
	exit 1
}

[ -z "$CONFIG_PATH" ] && CONFIG_PATH="$DEFAULT_CONFIG_PATH"
[ -z "$SKILLS_ROOT" ] && SKILLS_ROOT="$DEFAULT_SKILLS_ROOT"
[ -z "$REGISTRY_PATH" ] && REGISTRY_PATH="$DEFAULT_REGISTRY_PATH"

SKILLS_ROOT_RESOLVED="$(resolve_realpath "$SKILLS_ROOT")"

BUILTIN_TARGETS_NAMES=(claude codex opencode obsidian)
BUILTIN_TARGETS_PATHS=(
	"$HOME/.claude/skills"
	"$HOME/.codex/skills"
	"$HOME/.config/opencode/skills"
	"$HOME/Documents/Obsidian Vault/.claude/skills"
)

load_config() {
	if [ ! -f "$CONFIG_PATH" ]; then
		echo "[compat] no sync-config.json found, using builtin defaults" >&2
		UPSTREAM_SYNC=false
		TARGET_NAMES=("${BUILTIN_TARGETS_NAMES[@]}")
		TARGET_PATHS=("${BUILTIN_TARGETS_PATHS[@]}")
		SKILL_TARGETS_JSON="{}"
		DEFAULT_TARGETS_JSON="[]"
		GROUPS_JSON="{}"
		return
	fi

	local config_json
	config_json="$(cat "$CONFIG_PATH")"

	local config_version
	config_version="$(echo "$config_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('config_version',1))" 2>/dev/null || echo "1")"

	if [ "$config_version" = "1" ]; then
		echo "[compat] config_version missing, using builtin targets" >&2
		TARGET_NAMES=("${BUILTIN_TARGETS_NAMES[@]}")
		TARGET_PATHS=("${BUILTIN_TARGETS_PATHS[@]}")
		SKILL_TARGETS_JSON="{}"
		DEFAULT_TARGETS_JSON="[]"
		GROUPS_JSON="{}"
	else
		TARGET_NAMES=()
		TARGET_PATHS=()
		while IFS='=' read -r name path; do
			TARGET_NAMES+=("$name")
			TARGET_PATHS+=("$path")
		done < <(echo "$config_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for name, path in data.get('targets', {}).items():
    import os
    print(f'{name}={os.path.expanduser(path)}')
" 2>/dev/null)
	fi

	UPSTREAM_SYNC="$(echo "$config_json" | python3 -c "import sys,json; print('true' if json.load(sys.stdin).get('upstream_sync',False) else 'false')" 2>/dev/null || echo "false")"

	SKILL_TARGETS_JSON="$(echo "$config_json" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('skills',{})))" 2>/dev/null || echo "{}")"
	DEFAULT_TARGETS_JSON="$(echo "$config_json" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('default_targets',[])))" 2>/dev/null || echo "[]")"
	GROUPS_JSON="$(echo "$config_json" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('groups',{})))" 2>/dev/null || echo "{}")"
}

load_config

if [ "$INCLUDE_UPSTREAM" = true ]; then
	UPSTREAM_SYNC=true
fi

load_upstream_registry() {
	if [ -f "$REGISTRY_PATH" ]; then
		UPSTREAM_REGISTRY_JSON="$(cat "$REGISTRY_PATH")"
	else
		UPSTREAM_REGISTRY_JSON="{}"
	fi
}

load_upstream_registry

is_upstream_skill() {
	local name="$1"
	echo "$UPSTREAM_REGISTRY_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
sys.exit(0 if '$name' in data else 1)
" 2>/dev/null
}

get_skill_targets() {
	local skill_name="$1"
	local group_name="${2:-}"
	python3 -c "
import json, os, sys
skill_targets = json.loads('$SKILL_TARGETS_JSON')
groups_cfg = json.loads('$GROUPS_JSON')
default_targets = json.loads('$DEFAULT_TARGETS_JSON')

def extract(val):
    if isinstance(val, list):
        return val
    if isinstance(val, dict):
        return val.get('targets', None)
    return None

targets = extract(skill_targets.get('$skill_name'))
if targets is None and '$group_name':
    grp = groups_cfg.get('$group_name')
    if grp is not None:
        targets = extract(grp)
if targets is None:
    targets = default_targets if default_targets else None
if targets is not None and len(targets) == 0:
    print('__EMPTY__')
elif targets:
    for t in targets:
        print(t)
" 2>/dev/null
}

if [ "$LIST_TARGETS_REQUESTED" = true ]; then
	echo "Available sync targets:"
	echo ""
	for i in "${!TARGET_NAMES[@]}"; do
		printf "  %-12s %s\n" "${TARGET_NAMES[$i]}" "${TARGET_PATHS[$i]}"
	done
	exit 0
fi

if [ "$MIGRATE_CONFIG_REQUESTED" = true ]; then
	python3 -c "
import json, os, sys
config_path = '$CONFIG_PATH'
if not os.path.exists(config_path):
    print('[error] config file not found: ' + config_path, file=sys.stderr)
    sys.exit(1)
with open(config_path) as f:
    data = json.load(f)
cv = data.get('config_version', 1)
if cv >= 3:
    print('Config already at v3')
    sys.exit(0)
backup = config_path + f'.v{cv}-backup'
import shutil
shutil.copy2(config_path, backup)
print(f'Backup: {backup}')
if cv < 2:
    builtin = {'claude':'~/.claude/skills','codex':'~/.codex/skills','opencode':'~/.config/opencode/skills','obsidian':'~/Documents/Obsidian Vault/.claude/skills'}
    data['targets'] = builtin
data['config_version'] = 3
if 'groups' not in data:
    data['groups'] = {}
skills = data.get('skills', {})
for k, v in skills.items():
    if isinstance(v, list):
        skills[k] = {'targets': v}
data['skills'] = skills
with open(config_path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('Migrated to v3 (from v' + str(cv) + ')')
"
	exit $?
fi

resolve_alias() {
	local alias_name="$1"
	for i in "${!TARGET_NAMES[@]}"; do
		if [ "${TARGET_NAMES[$i]}" = "$alias_name" ]; then
			echo "${TARGET_PATHS[$i]}"
			return 0
		fi
	done
	echo "[error] unknown target alias: $alias_name" >&2
	echo "Valid aliases: ${TARGET_NAMES[*]}" >&2
	return 1
}

TARGETS=()

if [ -n "$ONLY_LIST" ]; then
	IFS=',' read -ra only_aliases <<<"$ONLY_LIST"
	for a in "${only_aliases[@]}"; do
		a="$(echo "$a" | tr -d ' ')"
		path="$(resolve_alias "$a")" || exit 1
		TARGETS+=("$path")
	done
elif [ -n "$SKIP_LIST" ]; then
	IFS=',' read -ra skip_aliases <<<"$SKIP_LIST"
	skip_set=""
	for a in "${skip_aliases[@]}"; do
		a="$(echo "$a" | tr -d ' ')"
		resolve_alias "$a" >/dev/null || exit 1
		skip_set="$skip_set $a "
	done
	for i in "${!TARGET_NAMES[@]}"; do
		if [[ "$skip_set" != *" ${TARGET_NAMES[$i]} "* ]]; then
			TARGETS+=("${TARGET_PATHS[$i]}")
		fi
	done
else
	TARGETS=("${TARGET_PATHS[@]}")
fi

[ "${#TARGETS[@]}" -eq 0 ] && {
	echo "[error] no targets remaining after filter" >&2
	exit 1
}

target_name_for_path() {
	local p="$1"
	for i in "${!TARGET_PATHS[@]}"; do
		if [ "${TARGET_PATHS[$i]}" = "$p" ]; then
			echo "${TARGET_NAMES[$i]}"
			return 0
		fi
	done
	echo "unknown"
}

for target_dir in "${TARGETS[@]}"; do
	if [ ! -d "$target_dir" ]; then
		if [ "$DRY_RUN" = true ]; then
			echo "[dry-run] would create $target_dir"
		else
			mkdir -p "$target_dir"
		fi
	fi
done

created=0
skipped=0
fixed=0
conflict=0
warned=0
skip_upstream_count=0
skip_target_count=0
removed_mismatch=0

sync_skill() {
	local skill_path="$1"
	local link_name="$2"
	local is_upstream="$3"
	local group_name="${4:-}"

	if [ "$is_upstream" = "true" ] && [ "$UPSTREAM_SYNC" = "false" ]; then
		for target_dir in "${TARGETS[@]}"; do
			local tname
			tname="$(target_name_for_path "$target_dir")"
			echo "[skip-upstream] $tname $link_name"
			skip_upstream_count=$((skip_upstream_count + 1))
		done
		return
	fi

	local allowed_targets
	allowed_targets="$(get_skill_targets "$link_name" "$group_name")"

	# __EMPTY__ means explicitly configured as [] (no targets)
	local explicit_empty=false
	if [ "$allowed_targets" = "__EMPTY__" ]; then
		explicit_empty=true
		allowed_targets=""
	fi

	for target_dir in "${TARGETS[@]}"; do
		local tname
		tname="$(target_name_for_path "$target_dir")"
		local link_path="$target_dir/$link_name"

		if [ -n "$allowed_targets" ] || [ "$explicit_empty" = true ]; then
			if ! echo "$allowed_targets" | grep -qx "$tname"; then
				if [ -L "$link_path" ]; then
					local link_resolved
					link_resolved="$(resolve_realpath "$link_path")"
					if [[ "$link_resolved" == "$SKILLS_ROOT_RESOLVED"/* ]]; then
						if [ "$DRY_RUN" = true ]; then
							echo "[dry-run] would remove $link_path (not in target set)"
						else
							rm "$link_path"
							echo "[removed-mismatch] $link_path (not in target set)"
						fi
						removed_mismatch=$((removed_mismatch + 1))
						continue
					fi
				fi
				echo "[skip-target] $tname $link_name"
				skip_target_count=$((skip_target_count + 1))
				continue
			fi
		fi

		if [ -L "$link_path" ]; then
			local current_target
			current_target="$(readlink "$link_path")"
			local current_resolved
			current_resolved="$(resolve_realpath "$current_target")"
			local skill_resolved
			skill_resolved="$(resolve_realpath "$skill_path")"
			if [ "$current_resolved" = "$skill_resolved" ]; then
				skipped=$((skipped + 1))
			else
				local link_resolved
				link_resolved="$(resolve_realpath "$link_path")"
				if [[ "$link_resolved" == "$SKILLS_ROOT_RESOLVED"/* ]]; then
					if [ "$DRY_RUN" = true ]; then
						echo "[dry-run] would fix $link_path -> $skill_path (was: $current_target)"
					else
						rm "$link_path"
						ln -s "$skill_path" "$link_path"
						echo "[fixed]   $link_path -> $skill_path (was: $current_target)"
					fi
					fixed=$((fixed + 1))
				else
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

for entry in "$SKILLS_ROOT"/*/; do
	[ -d "$entry" ] || continue
	entry_name="$(basename "$entry")"

	if [ -f "$entry/.prefix" ]; then
		prefix="$(cat "$entry/.prefix")"
		for skill_path in "$entry"/*/; do
			[ -d "$skill_path" ] || continue
			[ -f "$skill_path/SKILL.md" ] || continue
			skill_name="$(basename "$skill_path")"
			exposed_name="${prefix}-${skill_name}"
			is_up=false
			is_upstream_skill "$exposed_name" && is_up=true
			sync_skill "$skill_path" "$exposed_name" "$is_up" "$entry_name"
		done
	else
		[ -f "$entry/SKILL.md" ] || continue
		is_up=false
		is_upstream_skill "$entry_name" && is_up=true
		sync_skill "$entry" "$entry_name" "$is_up" ""
	fi
done

if [ "$UPSTREAM_SYNC" = "true" ]; then
	UPSTREAM_DIR="$SKILLS_ROOT/.upstream"
	if [ -d "$UPSTREAM_DIR" ]; then
		for entry in "$UPSTREAM_DIR"/*/; do
			[ -d "$entry" ] || continue
			[ -f "$entry/SKILL.md" ] || continue
			entry_name="$(basename "$entry")"
			sync_skill "$entry" "$entry_name" "true" ""
		done
	fi
fi

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

echo ""
if [ "$DRY_RUN" = true ]; then
	echo "Dry-run: $created would create, $fixed would fix, $skipped unchanged, $conflict conflicts, $warned warnings, $skip_upstream_count skip-upstream, $skip_target_count skip-target, $removed_mismatch removed-mismatch"
else
	echo "Done: $created created, $fixed fixed, $skipped unchanged, $conflict conflicts, $warned warnings, $skip_upstream_count skip-upstream, $skip_target_count skip-target, $removed_mismatch removed-mismatch"
fi
