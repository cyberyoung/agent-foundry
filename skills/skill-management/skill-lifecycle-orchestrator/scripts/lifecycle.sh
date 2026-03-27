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
	else
		echo "Unsupported skill URL: $skill_url" >&2
		echo "Expected GitHub tree/blob URL, e.g." >&2
		echo "  https://github.com/<owner>/<repo>/tree/<ref>/<path-to-skill-dir>" >&2
		echo "  https://github.com/<owner>/<repo>/blob/<ref>/<path-to-skill-dir>/SKILL.md" >&2
		return 1
	fi

	if [ -z "$source_path" ]; then
		echo "Cannot resolve source path from URL: $skill_url" >&2
		return 1
	fi

	local upstream_skill
	upstream_skill="${source_path##*/}"
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
EOF
}

if [ "$#" -lt 1 ]; then
	usage
	exit 1
fi

FLOW="$1"
shift

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
	bash "$0" install-url-sync-verify --skill-url "$SKILL_URL" "$@"
	bash "$UPM/status-upstream.sh" --compact
	;;
install-sync)
	bash "$UPM/install-upstream.sh" "$@"
	bash "$SYNC"
	;;
install-sync-verify)
	bash "$UPM/install-upstream.sh" "$@"
	bash "$SYNC"
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
		--repo "$REPO_URL" \
		--skill "$URL_SKILL" \
		--source-path "$SOURCE_PATH" \
		--ref "$URL_REF" \
		"${INSTALL_ARGS[@]}"
	bash "$SYNC"
	bash "$VERIFY"
	;;
update-sync)
	bash "$UPM/update-upstream.sh" "$@"
	bash "$SYNC"
	;;
update-sync-verify)
	bash "$UPM/update-upstream.sh" "$@"
	bash "$SYNC"
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
	bash "$UPM/install-upstream.sh" "${INSTALL_ARGS[@]}"
	bash "$SYNC"
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
	bash "$UPM/install-upstream.sh" "${INSTALL_ARGS[@]}"
	bash "$SYNC"
	bash "$VERIFY"
	;;
*)
	usage
	exit 1
	;;
esac
