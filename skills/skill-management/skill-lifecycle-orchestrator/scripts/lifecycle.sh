#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NAMESPACE_ROOT="$(cd -- "$SKILL_ROOT/.." && pwd)"
SKILLS_ROOT="$(cd -- "$NAMESPACE_ROOT/.." && pwd)"
AGENTS_ROOT="$(cd -- "$SKILLS_ROOT/.." && pwd)"
UPM="$SKILLS_ROOT/skill-management/skills-upstream-manager/scripts"
DISC="$SKILLS_ROOT/skill-management/skill-discovery-check/scripts"
SYNC="$SKILLS_ROOT/skill-management/sync-skills/scripts/sync.sh"
VERIFY="$UPM/verify-upstream.sh"

parse_github_skill_url() {
	local skill_url="$1"
	local cleaned owner repo ref source_path

	cleaned="${skill_url%%\?*}"
	cleaned="${cleaned%%\#*}"
	cleaned="${cleaned%/}"

	if [[ "$cleaned" =~ ^https://github\.com/([^/]+)/([^/]+)/tree/([^/]+)/(.+)$ ]]; then
		owner="${BASH_REMATCH[1]}"
		repo="${BASH_REMATCH[2]}"
		ref="${BASH_REMATCH[3]}"
		source_path="${BASH_REMATCH[4]}"
	elif [[ "$cleaned" =~ ^https://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$ ]]; then
		owner="${BASH_REMATCH[1]}"
		repo="${BASH_REMATCH[2]}"
		ref="${BASH_REMATCH[3]}"
		source_path="${BASH_REMATCH[4]}"
		source_path="${source_path%/SKILL.md}"
	elif [[ "$cleaned" =~ ^https://github\.com/([^/]+)/([^/]+)/tree/([^/]+)$ ]]; then
		owner="${BASH_REMATCH[1]}"
		repo="${BASH_REMATCH[2]}"
		ref="${BASH_REMATCH[3]}"
		source_path="."
	elif [[ "$cleaned" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]]; then
		owner="${BASH_REMATCH[1]}"
		repo="${BASH_REMATCH[2]}"
		ref="main"
		source_path="."
	else
		echo "Unsupported skill URL: $skill_url" >&2
		echo "Supported formats:" >&2
		echo "  https://github.com/<owner>/<repo>" >&2
		echo "  https://github.com/<owner>/<repo>/tree/<ref>" >&2
		echo "  https://github.com/<owner>/<repo>/tree/<ref>/<path>" >&2
		echo "  https://github.com/<owner>/<repo>/blob/<ref>/<path>/SKILL.md" >&2
		return 1
	fi

	local upstream_skill
	if [ "$source_path" = "." ]; then
		upstream_skill="$repo"
	else
		upstream_skill="${source_path##*/}"
	fi
	printf "%s\t%s\t%s\t%s\n" "https://github.com/$owner/$repo" "$ref" "$source_path" "$upstream_skill"
}

usage() {
	cat <<'EOF'
Usage:
  lifecycle.sh onboard <github-url> [--dest-name <name>] [--force]
  lifecycle.sh install-sync --repo <repo> --skill <skill> [--ref <ref>]
  lifecycle.sh install-sync-verify --repo <repo> --skill <skill> [--ref <ref>]
  lifecycle.sh install-url-sync-verify --skill-url <github-url> [--dest-name <name>] [--force]
  lifecycle.sh update-sync [--skill <local-skill-name>]
  lifecycle.sh update-sync-verify [--skill <local-skill-name>]
  lifecycle.sh discover-sync --query <query>
  lifecycle.sh discover-install-sync --query <query> --repo <repo> --skill <skill> [--ref <ref>]
  lifecycle.sh discover-install-sync-verify --query <query> --repo <repo> --skill <skill> [--ref <ref>]

Sync options (passed through to sync.sh):
  --skip <targets>       Comma-separated target aliases to skip
  --only <targets>       Comma-separated target aliases to sync (whitelist)
  --dry-run              Dry-run sync step only (install/update/verify still execute)

Target aliases: claude, codex, opencode, obsidian
EOF
}

if [ "$#" -lt 1 ]; then
	usage
	exit 1
fi

FLOW="$1"
shift

SYNC_ARGS=()
PASSTHROUGH_ARGS=()
while [ "$#" -gt 0 ]; do
	case "$1" in
	--skip | --only)
		SYNC_ARGS+=("$1" "$2")
		shift 2
		;;
	--dry-run)
		SYNC_ARGS+=("$1")
		shift
		;;
	*)
		PASSTHROUGH_ARGS+=("$1")
		shift
		;;
	esac
done
set -- "${PASSTHROUGH_ARGS[@]+${PASSTHROUGH_ARGS[@]}}"

case "$FLOW" in
onboard)
	if [ "$#" -lt 1 ]; then
		echo "Missing required <github-url>"
		echo "Example: lifecycle.sh onboard https://github.com/vercel-labs/skills/tree/main/skills/find-skills"
		exit 1
	fi
	if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
		echo "Usage: lifecycle.sh onboard <github-url> [--dest-name <name>] [--force]"
		exit 0
	fi
	SKILL_URL="$1"
	shift
	bash "$0" install-url-sync-verify --skill-url "$SKILL_URL" "${SYNC_ARGS[@]+${SYNC_ARGS[@]}}" "$@"
	bash "$UPM/status-upstream.sh" --compact
	;;
install-sync)
	bash "$UPM/install-upstream.sh" --no-sync "$@"
	bash "$SYNC" "${SYNC_ARGS[@]+${SYNC_ARGS[@]}}"
	;;
install-sync-verify)
	bash "$UPM/install-upstream.sh" --no-sync "$@"
	bash "$SYNC" "${SYNC_ARGS[@]+${SYNC_ARGS[@]}}"
	bash "$VERIFY"
	;;
install-url-sync-verify)
	SKILL_URL=""
	INSTALL_ARGS=()
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--skill-url)
			SKILL_URL="$2"
			shift 2
			;;
		*)
			INSTALL_ARGS+=("$1")
			shift
			;;
		esac
	done
	if [ -z "$SKILL_URL" ]; then
		echo "Missing required --skill-url"
		exit 1
	fi
	PARSED="$(parse_github_skill_url "$SKILL_URL")" || exit 1
	IFS=$'\t' read -r REPO_URL URL_REF SOURCE_PATH URL_SKILL <<<"$PARSED"
	bash "$UPM/install-upstream.sh" \
		--no-sync \
		--repo "$REPO_URL" \
		--skill "$URL_SKILL" \
		--source-path "$SOURCE_PATH" \
		--ref "$URL_REF" \
		"${INSTALL_ARGS[@]}"
	bash "$SYNC" "${SYNC_ARGS[@]+${SYNC_ARGS[@]}}"
	bash "$VERIFY"
	;;
update-sync)
	bash "$UPM/update-upstream.sh" --no-sync "$@"
	bash "$SYNC" "${SYNC_ARGS[@]+${SYNC_ARGS[@]}}"
	;;
update-sync-verify)
	bash "$UPM/update-upstream.sh" --no-sync "$@"
	bash "$SYNC" "${SYNC_ARGS[@]+${SYNC_ARGS[@]}}"
	bash "$VERIFY"
	;;
discover-sync)
	QUERY=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--query)
			QUERY="$2"
			shift 2
			;;
		*)
			if [ -z "$QUERY" ]; then
				QUERY="$1"
			fi
			shift
			;;
		esac
	done
	if [ -z "$QUERY" ]; then
		echo "Missing query. Use positional query or --query <value>."
		exit 1
	fi
	bash "$DISC/discovery-check.sh" "$QUERY"
	;;
discover-install-sync)
	QUERY=""
	INSTALL_ARGS=()
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--query)
			QUERY="$2"
			shift 2
			;;
		*)
			INSTALL_ARGS+=("$1")
			shift
			;;
		esac
	done
	if [ -z "$QUERY" ]; then
		echo "Missing required --query"
		exit 1
	fi
	bash "$DISC/discovery-check.sh" "$QUERY"
	bash "$UPM/install-upstream.sh" --no-sync "${INSTALL_ARGS[@]}"
	bash "$SYNC" "${SYNC_ARGS[@]+${SYNC_ARGS[@]}}"
	;;
discover-install-sync-verify)
	QUERY=""
	INSTALL_ARGS=()
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--query)
			QUERY="$2"
			shift 2
			;;
		*)
			INSTALL_ARGS+=("$1")
			shift
			;;
		esac
	done
	if [ -z "$QUERY" ]; then
		echo "Missing required --query"
		exit 1
	fi
	bash "$DISC/discovery-check.sh" "$QUERY"
	bash "$UPM/install-upstream.sh" --no-sync "${INSTALL_ARGS[@]}"
	bash "$SYNC" "${SYNC_ARGS[@]+${SYNC_ARGS[@]}}"
	bash "$VERIFY"
	;;
*)
	usage
	exit 1
	;;
esac
