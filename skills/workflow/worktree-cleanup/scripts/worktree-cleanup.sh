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

# Merge .claude/settings.local.json from worktree back to main repo before deletion.
# (settings.json is in git — all worktrees share the same version.)
# Otherwise per-worktree permission grants etc. are lost.
merge_claude_settings() {
  local worktree_path="$1"
  local main_path="$2"

  # 检查 jq 可用性
  command -v jq >/dev/null 2>&1 || { warn "jq 不可用，跳过 .claude 配置合并"; return 0; }

  for fname in settings.local.json; do
    local wt_file="$worktree_path/.claude/$fname"
    local main_file="$main_path/.claude/$fname"

    [ -f "$wt_file" ] || continue

    # 主仓库无此文件 → 直接复制
    if [ ! -f "$main_file" ]; then
      mkdir -p "$main_path/.claude"
      cp "$wt_file" "$main_file"
      pass "复制 .claude/$fname → 主仓库（主仓库原本无此文件）"
      continue
    fi

    # 内容一致 → 跳过
    if cmp -s "$wt_file" "$main_file"; then
      continue
    fi

    # 合并：以 main 为基础，worktree 的字段覆盖；permissions.allow / .deny 数组联合去重
    local merged
    merged="$(mktemp)"
    if jq -s '
      (.[0] // {}) as $main |
      (.[1] // {}) as $wt |
      ($main * $wt) as $combined |
      $combined
      | (if ($main.permissions.allow // []) + ($wt.permissions.allow // []) | length > 0 then
          .permissions.allow = ((($main.permissions.allow // []) + ($wt.permissions.allow // [])) | unique)
         else . end)
      | (if ($main.permissions.deny // []) + ($wt.permissions.deny // []) | length > 0 then
          .permissions.deny = ((($main.permissions.deny // []) + ($wt.permissions.deny // [])) | unique)
         else . end)
    ' "$main_file" "$wt_file" > "$merged" 2>/dev/null && [ -s "$merged" ]; then
      mv "$merged" "$main_file"
      pass "合并 .claude/$fname → 主仓库（permissions 数组已去重）"
    else
      rm -f "$merged"
      warn "合并 .claude/$fname 失败（jq 错误），请手动检查 $wt_file"
      return 1
    fi
  done

  return 0
}

# Merge opencode.json from worktree back to main repo before deletion.
# Handles mcp (object merge, wt overrides) and plugin (array join + dedupe).
# .opencode/ directory is NOT merged — it stays under version control via git.
merge_opencode_settings() {
  local worktree_path="$1"
  local main_path="$2"

  command -v jq >/dev/null 2>&1 || { warn "jq 不可用，跳过 opencode.json 合并"; return 0; }

  local wt_file="$worktree_path/opencode.json"
  local main_file="$main_path/opencode.json"

  [ -f "$wt_file" ] || return 0

  if [ ! -f "$main_file" ]; then
    cp "$wt_file" "$main_file"
    pass "复制 opencode.json → 主仓库（主仓库原本无此文件）"
    return 0
  fi

  if cmp -s "$wt_file" "$main_file"; then
    return 0
  fi

  local merged
  merged="$(mktemp)"
  if jq -s '
    (.[0] // {}) as $main |
    (.[1] // {}) as $wt |
    ($main * $wt) as $combined |
    $combined
    | .mcp  = ((($main.mcp  // {}) * ($wt.mcp  // {})) // if ($wt.mcp)  then $wt.mcp  else $main.mcp  end)
    | .plugin = (if (($main.plugin // []) + ($wt.plugin // [])) | length > 0 then
                  ((($main.plugin // []) + ($wt.plugin // [])) | unique)
                else .plugin end)
    | del(."$schema")
  ' "$main_file" "$wt_file" > "$merged" 2>/dev/null && [ -s "$merged" ]; then
    jq '. + {"$schema": "https://opencode.ai/config.json"}' "$merged" > "${merged}.tmp"
    mv "${merged}.tmp" "$main_file"
    rm -f "$merged"
    pass "合并 opencode.json → 主仓库（mcp 按 server 合并，plugin 已去重）"
  else
    rm -f "$merged"
    warn "合并 opencode.json 失败（jq 错误），请手动检查 $wt_file"
    return 1
  fi

  return 0
}

# Check worktree for uncommitted / unpushed / dirty state before cleanup.
# Returns 0 if clean, 1 if anything needs handling.
check_worktree_clean() {
  local wt_path="$1"
  local dirty=0

  # 1. Detached HEAD — can't determine branch
  if ! git -C "$wt_path" symbolic-ref -q HEAD >/dev/null 2>&1; then
    fail "detached HEAD — 请先切到分支: git checkout -b <name> 或 git switch main"
    dirty=1
  fi

  # 2. Ongoing rebase / merge / cherry-pick
  if [ -d "$wt_path/.git/rebase-merge" ] || [ -f "$wt_path/.git/MERGE_HEAD" ] || [ -f "$wt_path/.git/CHERRY_PICK_HEAD" ]; then
    fail "正在进行 rebase/merge/cherry-pick — 请先完成或 abort"
    dirty=1
  fi

  # 3. Unstaged changes
  local unstaged
  unstaged=$(git -C "$wt_path" diff --name-only 2>/dev/null)
  if [ -n "$unstaged" ]; then
    fail "有未暂存的修改:"
    while IFS= read -r f; do
      echo "    $f"
    done <<< "$unstaged"
    echo "    → 处理: git stash 或 git add + git commit"
    dirty=1
  fi

  # 4. Staged but uncommitted
  local staged
  staged=$(git -C "$wt_path" diff --cached --name-only 2>/dev/null)
  if [ -n "$staged" ]; then
    fail "有已暂存但未提交的文件:"
    while IFS= read -r f; do
      echo "    $f"
    done <<< "$staged"
    echo "    → 处理: git commit"
    dirty=1
  fi

  # 5. Untracked files
  local untracked
  untracked=$(git -C "$wt_path" ls-files --others --exclude-standard 2>/dev/null)
  if [ -n "$untracked" ]; then
    fail "有未追踪的文件:"
    while IFS= read -r f; do
      echo "    $f"
    done <<< "$untracked"
    echo "    → 处理: git add 或删除"
    dirty=1
  fi

  # 6. Unpushed commits
  local unpushed
  unpushed=$(git -C "$wt_path" log @{u}..HEAD --oneline 2>/dev/null)
  if [ -n "$unpushed" ]; then
    fail "有未推送的提交:"
    while IFS= read -r line; do
      echo "    $line"
    done <<< "$unpushed"
    echo "    → 处理: git push"
    dirty=1
  fi

  [ "$dirty" -eq 0 ] && return 0 || return 1
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
    info "[dry-run] Would check worktree cleanliness, merge .claude settings, remove worktree, local branch, and remote branch"
    return 0
  fi

  # Step 1.5: Check worktree is clean (no uncommitted / unpushed work)
  check_worktree_clean "$path" || {
    fail "Worktree 有未处理的工作 — 请先处理上述问题再清理"
    return 1
  }

  # Step 1.6: Merge .claude/settings.local.json back to main repo
  local main_repo
  main_repo="$(main_worktree)"
  merge_claude_settings "$path" "$main_repo" || {
    fail "合并 settings.local.json 失败 — 中止清理（不删除 worktree）"
    return 1
  }

  merge_opencode_settings "$path" "$main_repo" || {
    fail "合并 opencode.json 失败 — 中止清理（不删除 worktree）"
    return 1
  }

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
# Only execute main when run directly, not when sourced (for test reuse)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

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

fi  # [[ "${BASH_SOURCE[0]}" == "${0}" ]] guard
