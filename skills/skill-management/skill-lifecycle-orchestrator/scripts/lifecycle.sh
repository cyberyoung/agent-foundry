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

usage() {
	cat <<'EOF'
Usage:
  lifecycle.sh install-sync --repo <repo> --skill <skill> [--ref <ref>]
  lifecycle.sh update-sync [--skill <local-skill-name>]
  lifecycle.sh discover-sync --query <query>
  lifecycle.sh discover-install-sync --query <query> --repo <repo> --skill <skill> [--ref <ref>]
EOF
}

if [ "$#" -lt 1 ]; then
	usage
	exit 1
fi

FLOW="$1"
shift

case "$FLOW" in
install-sync)
	bash "$UPM/install-upstream.sh" "$@"
	bash "$SYNC"
	;;
update-sync)
	bash "$UPM/update-upstream.sh" "$@"
	bash "$SYNC"
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
*)
	usage
	exit 1
	;;
esac
