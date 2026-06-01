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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/worktree-paths.sh"

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

# Get the primary worktree (repo root). This must be stable from any linked
# worktree and must not depend on the first porcelain entry.
main_worktree() {
  primary_repo_root "${1:-.}"
}

# List canonical non-primary worktrees: "path branch"
list_worktrees() {
  local main
  main="$(main_worktree)"
  list_canonical_worktrees "$main"
}

# Check if a branch's PR is merged. Returns: MERGED, OPEN, CLOSED, NO_PR, GH_ERROR
check_pr_status() {
  local branch="$1"
  local primary="${2:-}"
  local repo_arg=()
  local merged open closed

  if [ -n "$primary" ]; then
    local owner_repo
    owner_repo="$(remote_owner_repo "$primary")" || {
      echo "GH_ERROR"
      return
    }
    repo_arg=(--repo "$owner_repo")
  fi

  if ! merged=$(gh pr list "${repo_arg[@]}" --head "$branch" --state merged --json number,title --jq 'length' 2>&1); then
    echo "GH_ERROR"
    warn "gh pr list failed for $branch: $merged" >&2
    return
  fi
  if [ "$merged" -gt 0 ]; then
    echo "MERGED"
    return
  fi

  if ! open=$(gh pr list "${repo_arg[@]}" --head "$branch" --state open --json number --jq 'length' 2>&1); then
    echo "GH_ERROR"
    warn "gh pr list failed for $branch: $open" >&2
    return
  fi
  if [ "$open" -gt 0 ]; then
    echo "OPEN"
    return
  fi

  if ! closed=$(gh pr list "${repo_arg[@]}" --head "$branch" --state closed --json number --jq 'length' 2>&1); then
    echo "GH_ERROR"
    warn "gh pr list failed for $branch: $closed" >&2
    return
  fi
  if [ "$closed" -gt 0 ]; then
    echo "CLOSED"
    return
  fi

  echo "NO_PR"
}

# Get PR info for display
get_pr_info() {
  local branch="$1"
  local primary="${2:-}"
  local repo_arg=()

  if [ -n "$primary" ]; then
    local owner_repo
    owner_repo="$(remote_owner_repo "$primary")" || return 0
    repo_arg=(--repo "$owner_repo")
  fi

  gh pr list "${repo_arg[@]}" --head "$branch" --state merged --json number,title,mergedAt --jq '.[0] | "#\(.number) \(.title) mergedAt=\(.mergedAt)"' 2>/dev/null || echo ""
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

# Convert filesystem path to ~/.claude/projects/ key
# e.g. /Users/liyang/Workspace/vren/chogori → -Users-liyang-Workspace-vren-chogori
path_to_project_key() {
  echo "-$(echo "$1" | tr '/' '-')"
}

# Merge memory files from worktree's ~/.claude/projects/ dir back to main project.
# Each worktree gets its own project dir under ~/.claude/projects/; without this,
# any memories saved during worktree work are lost on cleanup.
# Also cleans up the worktree's project dir (jsonl, wakatime, sessions-index, etc.).
merge_memory() {
  local worktree_path="$1"
  local main_path="$2"

  local wt_key main_key
  wt_key="$(path_to_project_key "$worktree_path")"
  main_key="$(path_to_project_key "$main_path")"

  local wt_proj_dir="$HOME/.claude/projects/$wt_key"
  local main_proj_dir="$HOME/.claude/projects/$main_key"

  # No memory to merge — nothing to do
  [ -d "$wt_proj_dir/memory" ] || return 0

  info "Found worktree memory: $wt_proj_dir/memory"
  mkdir -p "$main_proj_dir/memory"

  # Copy memory .md files that don't exist in main
  for f in "$wt_proj_dir/memory/"*.md; do
    [ -f "$f" ] || continue
    local basename
    basename="$(basename "$f")"

    if [ ! -f "$main_proj_dir/memory/$basename" ]; then
      cp "$f" "$main_proj_dir/memory/$basename"
      pass "复制 memory/$basename → 主项目"
    elif ! cmp -s "$f" "$main_proj_dir/memory/$basename"; then
      warn "memory/$basename 在主项目和工作树中都存在且不同，保留主项目版本"
    fi
  done

  # Merge MEMORY.md index (unique lines from both)
  local wt_index="$wt_proj_dir/memory/MEMORY.md"
  local main_index="$main_proj_dir/memory/MEMORY.md"
  if [ -f "$wt_index" ] && [ -f "$main_index" ]; then
    if ! cmp -s "$wt_index" "$main_index"; then
      local merged_index
      merged_index="$(mktemp)"
      awk '!seen[$0]++' "$main_index" "$wt_index" > "$merged_index"
      if [ -s "$merged_index" ]; then
        mv "$merged_index" "$main_index"
        pass "合并 MEMORY.md 索引 → 主项目"
      else
        rm -f "$merged_index"
      fi
    fi
  elif [ -f "$wt_index" ] && [ ! -f "$main_index" ]; then
    cp "$wt_index" "$main_index"
    pass "复制 MEMORY.md → 主项目"
  fi

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
  local rebase_merge merge_head cherry_pick_head
  rebase_merge="$(git -C "$wt_path" rev-parse --git-path rebase-merge 2>/dev/null || true)"
  merge_head="$(git -C "$wt_path" rev-parse --git-path MERGE_HEAD 2>/dev/null || true)"
  cherry_pick_head="$(git -C "$wt_path" rev-parse --git-path CHERRY_PICK_HEAD 2>/dev/null || true)"
  if [ -d "$rebase_merge" ] || [ -f "$merge_head" ] || [ -f "$cherry_pick_head" ]; then
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

  # 6. Upstream and unpushed commits
  if ! git -C "$wt_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    fail "缺少 upstream — 无法判断是否有未推送提交"
    dirty=1
  fi

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

ensure_primary_merge_targets_clean() {
  local main_path="$1"
  local dirty=0
  local paths=(
    ".claude/settings.local.json"
    "opencode.json"
  )

  for rel in "${paths[@]}"; do
    if git -C "$main_path" status --short -- "$rel" 2>/dev/null | grep -q .; then
      fail "主仓库目标文件有本地变更: $rel"
      dirty=1
    fi
  done

  [ "$dirty" -eq 0 ]
}

restore_backup_path() {
  local backup_root="$1"
  local root="$2"
  local rel="$3"
  local backup="$backup_root/$rel"
  local marker="$backup_root/$rel.__missing__"

  if [ -e "$backup" ]; then
    mkdir -p "$(dirname "$root/$rel")"
    rm -rf "$root/$rel"
    cp -R "$backup" "$root/$rel"
  elif [ -e "$marker" ]; then
    rm -rf "$root/$rel"
  fi
}

snapshot_path() {
  local backup_root="$1"
  local root="$2"
  local rel="$3"
  if [ -e "$root/$rel" ]; then
    mkdir -p "$(dirname "$backup_root/$rel")"
    cp -R "$root/$rel" "$backup_root/$rel"
  else
    mkdir -p "$(dirname "$backup_root/$rel")"
    : > "$backup_root/$rel.__missing__"
  fi
}

run_main_side_merges() {
  local worktree_path="$1"
  local main_repo="$2"
  local backup_root
  backup_root="$(mktemp -d)"
  local main_memory_rel=""
  local main_key
  main_key="$(path_to_project_key "$main_repo")"
  main_memory_rel="$main_key/memory"

  snapshot_path "$backup_root" "$main_repo" ".claude/settings.local.json"
  snapshot_path "$backup_root" "$main_repo" "opencode.json"

  local claude_projects_root="$HOME/.claude/projects"
  mkdir -p "$backup_root/.home"
  if [ -e "$claude_projects_root/$main_key/memory" ]; then
    mkdir -p "$(dirname "$backup_root/.home/$main_memory_rel")"
    cp -R "$claude_projects_root/$main_key/memory" "$backup_root/.home/$main_memory_rel"
  else
    mkdir -p "$(dirname "$backup_root/.home/$main_memory_rel")"
    : > "$backup_root/.home/$main_memory_rel.__missing__"
  fi

  if ! merge_claude_settings "$worktree_path" "$main_repo" ||
    ! merge_opencode_settings "$worktree_path" "$main_repo" ||
    ! merge_memory "$worktree_path" "$main_repo"; then
    restore_backup_path "$backup_root" "$main_repo" ".claude/settings.local.json"
    restore_backup_path "$backup_root" "$main_repo" "opencode.json"
    restore_backup_path "$backup_root/.home" "$claude_projects_root" "$main_memory_rel"
    rm -rf "$backup_root"
    return 1
  fi

  rm -rf "$backup_root"
  return 0
}

safe_remove_leftover_path() {
  local path="$1"
  local main_repo="$2"
  local root
  root="$(canonical_worktree_root "$main_repo")" || return 1

  ensure_path_under_canonical_root "$path" "$main_repo" || {
    fail "拒绝清理 canonical root 之外的残留目录: $path"
    return 1
  }

  if git -C "$main_repo" worktree list --porcelain |
    awk '/^worktree / { print substr($0, 10) }' |
    grep -Fxq "$path"; then
    fail "目标仍是已注册 worktree，拒绝残留清理: $path"
    return 1
  fi

  rm -rf "$path"

  local parent
  parent="$(dirname "$path")"
  while [ "$parent" != "$root" ] && [ "$parent" != "/" ]; do
    rmdir "$parent" 2>/dev/null || break
    parent="$(dirname "$parent")"
  done
}

# Clean up a single worktree
cleanup_one() {
  local path="$1"
  local branch="$2"
  local dry_run="${3:-false}"

  echo ""
  info "Worktree: $path"
  info "Branch:   $branch"

  local main_repo
  main_repo="$(main_worktree "$path")" || {
    fail "无法解析 primary repo — skipping"
    return 1
  }

  ensure_path_under_canonical_root "$path" "$main_repo" || {
    fail "非 canonical worktree，自动 cleanup 拒绝处理: $path"
    return 1
  }

  # Step 1: Check PR status
  local status
  status=$(check_pr_status "$branch" "$main_repo")

  case "$status" in
    MERGED)
      local pr_info
      pr_info=$(get_pr_info "$branch" "$main_repo")
      pass "PR merged: $pr_info"
      ;;
    OPEN)
      fail "PR is still open — skipping"
      return 1
      ;;
    CLOSED)
      fail "PR is closed but not merged — skipping"
      return 1
      ;;
    NO_PR)
      fail "No PR found for branch '$branch' — skipping"
      return 1
      ;;
    GH_ERROR)
      fail "GitHub PR status query failed — skipping"
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

  # Step 1.6: Merge main-side local agent state back to primary repo
  ensure_primary_merge_targets_clean "$main_repo" || {
    fail "主仓库目标文件不干净 — 中止清理（不删除 worktree）"
    return 1
  }

  run_main_side_merges "$path" "$main_repo" || {
    fail "合并主仓本地 agent 状态失败且已回滚 — 中止清理（不删除 worktree）"
    return 1
  }

  # Step 2: Remove worktree from the primary repo context
  if git -C "$main_repo" worktree remove "$path" 2>/dev/null; then
    pass "Removed worktree: $path"
  else
    fail "Failed to remove worktree; refusing unconditional --force"
    return 1
  fi

  # Step 2.5: Clean up leftover directory (non-git files like .claude/ survive worktree remove)
  if [ -d "$path" ]; then
    safe_remove_leftover_path "$path" "$main_repo" || return 1
    pass "Cleaned leftover directory: $path"
  fi

  # Step 3: Delete local branch
  if git -C "$main_repo" branch -d "$branch" 2>/dev/null; then
    pass "Deleted local branch: $branch"
  elif git -C "$main_repo" merge-base --is-ancestor "$branch" HEAD 2>/dev/null &&
    git -C "$main_repo" branch -D "$branch" 2>/dev/null; then
    warn "Force deleted local branch: $branch (was not fully merged to HEAD, but PR is merged)"
  else
    warn "Local branch '$branch' already deleted or not found"
  fi

  # Step 4: Delete remote branch (silently handle already-deleted)
  if git -C "$main_repo" push origin --delete "$branch" 2>/dev/null; then
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
  MAIN_REPO="$(main_worktree "$TARGET_PATH")" || {
    fail "Unable to resolve primary repo for: $TARGET_PATH"
    exit 1
  }
  ensure_path_under_canonical_root "$TARGET_PATH" "$MAIN_REPO" || {
    fail "Refusing non-canonical worktree target: $TARGET_PATH"
    exit 1
  }

  # Find branch for this worktree
  if ! BRANCH="$(branch_name_for_worktree "$MAIN_REPO" "$TARGET_PATH")"; then
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
