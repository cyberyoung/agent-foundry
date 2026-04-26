#!/bin/bash
set -euo pipefail

# Worktree Cleanup — 清理已 merge 的 worktree
# 用法:
#   worktree-cleanup.sh <path>       清理指定 worktree
#   worktree-cleanup.sh --all        扫描所有 worktree，清理已 merge 的
#
# 前置条件: gh CLI 已登录

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass()  { printf "${GREEN}✓${NC} %s\n" "$1"; }
fail()  { printf "${RED}✗${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}!${NC} %s\n" "$1"; }
info()  { printf "${CYAN}→${NC} %s\n" "$1"; }

usage() {
  echo "Usage: $(basename "$0") <worktree-path> | --all"
  echo ""
  echo "  <worktree-path>  Clean up a specific worktree (must be merged)"
  echo "  --all            Scan all worktrees and clean up merged ones"
  exit 1
}

# Get the main worktree (repo root)
main_worktree() {
  git worktree list --porcelain | head -1 | sed 's/^worktree //'
}

# List non-main worktrees: "path branch"
list_worktrees() {
  local main
  main="$(main_worktree)"
  git worktree list --porcelain | awk '
    /^worktree / { path = substr($0, 10) }
    /^branch /   { branch = substr($0, 8); sub("refs/heads/", "", branch); if (path != "") print path "\t" branch; path = "" }
  ' | while IFS=$'\t' read -r path branch; do
    [ "$path" = "$main" ] && continue
    printf '%s\t%s\n' "$path" "$branch"
  done
}

# Check if a branch's PR is merged. Returns: MERGED, OPEN, NO_PR
check_pr_status() {
  local branch="$1"
  local merged open

  merged=$(gh pr list --head "$branch" --state merged --json number,title --jq 'length' 2>/dev/null || echo "0")
  if [ "$merged" -gt 0 ]; then
    echo "MERGED"
    return
  fi

  open=$(gh pr list --head "$branch" --state open --json number --jq 'length' 2>/dev/null || echo "0")
  if [ "$open" -gt 0 ]; then
    echo "OPEN"
    return
  fi

  echo "NO_PR"
}

# Get PR info for display
get_pr_info() {
  local branch="$1"
  gh pr list --head "$branch" --state merged --json number,title --jq '.[0] | "#\(.number) \(.title)"' 2>/dev/null || echo ""
}

# Clean up a single worktree
cleanup_one() {
  local path="$1"
  local branch="$2"
  local dry_run="${3:-false}"

  echo ""
  info "Worktree: $path"
  info "Branch:   $branch"

  # Step 1: Check PR status
  local status
  status=$(check_pr_status "$branch")

  case "$status" in
    MERGED)
      local pr_info
      pr_info=$(get_pr_info "$branch")
      pass "PR merged: $pr_info"
      ;;
    OPEN)
      fail "PR is still open — skipping"
      return 1
      ;;
    NO_PR)
      fail "No PR found for branch '$branch' — skipping"
      return 1
      ;;
  esac

  if [ "$dry_run" = "true" ]; then
    info "[dry-run] Would remove worktree, local branch, and remote branch"
    return 0
  fi

  # Step 2: Remove worktree
  if git worktree remove "$path" 2>/dev/null; then
    pass "Removed worktree: $path"
  else
    # Force remove if there are untracked files
    warn "Worktree has untracked files, force removing..."
    git worktree remove --force "$path" 2>/dev/null || { fail "Failed to remove worktree"; return 1; }
    pass "Force removed worktree: $path"
  fi

  # Step 2.5: Clean up leftover directory (non-git files like .claude/ survive worktree remove)
  if [ -d "$path" ]; then
    rm -rf "$path"
    pass "Cleaned leftover directory: $path"
  fi

  # Step 3: Delete local branch
  if git branch -d "$branch" 2>/dev/null; then
    pass "Deleted local branch: $branch"
  elif git branch -D "$branch" 2>/dev/null; then
    warn "Force deleted local branch: $branch (was not fully merged to HEAD, but PR is merged)"
  else
    warn "Local branch '$branch' already deleted or not found"
  fi

  # Step 4: Delete remote branch (silently handle already-deleted)
  if git push origin --delete "$branch" 2>/dev/null; then
    pass "Deleted remote branch: origin/$branch"
  else
    pass "Remote branch already deleted (auto-deleted on merge)"
  fi

  return 0
}

# --- Main ---

[ $# -eq 0 ] && usage

MODE="$1"
CLEANED=0
SKIPPED=0

if [ "$MODE" = "--all" ]; then
  echo "=== Worktree Cleanup: scanning all worktrees ==="

  while IFS=$'\t' read -r path branch; do
    if cleanup_one "$path" "$branch"; then
      CLEANED=$((CLEANED + 1))
    else
      SKIPPED=$((SKIPPED + 1))
    fi
  done < <(list_worktrees)

  echo ""
  printf "=== Done: ${GREEN}%d cleaned${NC}, ${YELLOW}%d skipped${NC} ===\n" "$CLEANED" "$SKIPPED"

  if [ "$CLEANED" -eq 0 ] && [ "$SKIPPED" -eq 0 ]; then
    info "No non-main worktrees found"
  fi
else
  # Single worktree mode
  TARGET_PATH="$MODE"

  # Resolve to absolute path
  TARGET_PATH="$(cd "$TARGET_PATH" 2>/dev/null && pwd || echo "$TARGET_PATH")"

  # Find branch for this worktree
  BRANCH=""
  while IFS=$'\t' read -r path branch; do
    if [ "$path" = "$TARGET_PATH" ]; then
      BRANCH="$branch"
      break
    fi
  done < <(list_worktrees)

  if [ -z "$BRANCH" ]; then
    fail "No worktree found at: $TARGET_PATH"
    exit 1
  fi

  echo "=== Worktree Cleanup ==="
  if cleanup_one "$TARGET_PATH" "$BRANCH"; then
    echo ""
    pass "Cleanup complete"
  else
    echo ""
    fail "Cleanup skipped (see above)"
    exit 1
  fi
fi
