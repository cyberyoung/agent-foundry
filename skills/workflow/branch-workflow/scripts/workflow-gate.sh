#!/bin/bash
set -e

# Workflow Gate — 检查开发流程规范是否满足
# 用法:
#   scripts/workflow-gate.sh check <plan-name>
#   scripts/workflow-gate.sh status
#
# check: 检查指定 plan 的所有规范项，全部通过返回 0，否则返回 1
# status: 显示当前 git 状态和已有的 plan/design 文件

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SISYPHUS_DIR="$ROOT/.sisyphus"
DESIGNS_DIR="$SISYPHUS_DIR/designs"
PLANS_DIR="$SISYPHUS_DIR/plans"

pass() { printf "${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "${RED}✗${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$1"; }

cmd_status() {
	echo "=== Workflow Gate Status ==="
	echo ""

	local branch
	branch=$(git -C "$ROOT" branch --show-current 2>/dev/null || echo "unknown")
	echo "Branch: $branch"
	echo ""

	if [[ -d "$DESIGNS_DIR" ]]; then
		echo "Designs:"
		find "$DESIGNS_DIR" -name "*-design.md" -exec basename {} \; 2>/dev/null | sed 's/^/  /'
	else
		echo "Designs: (none)"
	fi
	echo ""

	if [[ -d "$PLANS_DIR" ]]; then
		echo "Plans:"
		find "$PLANS_DIR" -name "*.md" -exec basename {} \; 2>/dev/null | sed 's/^/  /'
	else
		echo "Plans: (none)"
	fi
}

cmd_check() {
	local plan_name="$1"
	if [[ -z "$plan_name" ]]; then
		echo "Usage: $0 check <plan-name>"
		echo "Example: $0 check contractor-approval"
		exit 1
	fi

	local errors=0
	echo "=== Workflow Gate Check: $plan_name ==="
	echo ""

	# 1. 检查分支
	local branch
	branch=$(git -C "$ROOT" branch --show-current 2>/dev/null || echo "unknown")
	if [[ "$branch" == feature/* ]]; then
		pass "On feature branch: $branch"
	elif [[ "$branch" == "main" || "$branch" == "master" ]]; then
		fail "On $branch branch — create feature branch first: git checkout -b feature/$plan_name"
		errors=$((errors + 1))
	else
		warn "On branch '$branch' — expected feature/$plan_name"
	fi

	# 2. 检查 design 文档
	local design_file="$DESIGNS_DIR/${plan_name}-design.md"
	if [[ -f "$design_file" ]]; then
		pass "Design doc exists: .sisyphus/designs/${plan_name}-design.md"
	else
		fail "Design doc missing: create .sisyphus/designs/${plan_name}-design.md"
		errors=$((errors + 1))
	fi

	# 3. 检查 plan 文档
	local plan_file="$PLANS_DIR/${plan_name}.md"
	if [[ -f "$plan_file" ]]; then
		pass "Plan doc exists: .sisyphus/plans/${plan_name}.md"
	else
		fail "Plan doc missing: create .sisyphus/plans/${plan_name}.md"
		errors=$((errors + 1))
	fi

	# 4. 检查 plan 是否已 commit（不是 untracked/modified）
	if [[ -f "$plan_file" ]]; then
		local plan_status
		plan_status=$(git -C "$ROOT" status --porcelain ".sisyphus/plans/${plan_name}.md" 2>/dev/null)
		if [[ -z "$plan_status" ]]; then
			pass "Plan doc is committed"
		elif [[ "$plan_status" == "??"* ]]; then
			fail "Plan doc is untracked — commit it before coding"
			errors=$((errors + 1))
		elif [[ "$plan_status" == " M"* || "$plan_status" == "M "* ]]; then
			warn "Plan doc has uncommitted changes"
		else
			warn "Plan doc status: $plan_status"
		fi
	fi

	echo ""
	if [[ $errors -eq 0 ]]; then
		pass "All checks passed — ready to build"
		exit 0
	else
		fail "$errors check(s) failed — fix before coding"
		exit 1
	fi
}

case "${1:-}" in
check) cmd_check "$2" ;;
status) cmd_status ;;
*)
	echo "Usage: $0 {check <plan-name>|status}"
	exit 1
	;;
esac
