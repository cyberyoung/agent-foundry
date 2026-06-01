#!/bin/bash

worktree_paths_fail() {
  printf 'worktree-paths: %s\n' "$*" >&2
  return 1
}

physical_existing_path() {
  local path="$1"
  [ -e "$path" ] || return 1
  if [ -d "$path" ]; then
    (cd -P "$path" 2>/dev/null && pwd)
    return
  fi
  local dir base
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  (cd -P "$dir" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$base")
}

primary_repo_root() {
  local context="${1:-.}"
  local common_dir primary

  common_dir="$(
    git -C "$context" rev-parse --path-format=absolute --git-common-dir \
      2>/dev/null
  )" || return 1
  [ -n "$common_dir" ] || return 1

  if git --git-dir="$common_dir" rev-parse --is-bare-repository \
    2>/dev/null | grep -qx 'true'; then
    worktree_paths_fail "bare repository is not supported"
    return 1
  fi

  case "$common_dir" in
    */.git) primary="${common_dir%/.git}" ;;
    *) worktree_paths_fail "cannot map common git dir to primary checkout"; return 1 ;;
  esac

  primary="$(physical_existing_path "$primary")" || return 1
  if ! git -C "$primary" rev-parse --is-inside-work-tree \
    >/dev/null 2>&1; then
    worktree_paths_fail "primary checkout is not a worktree"
    return 1
  fi

  local found=0
  while IFS= read -r candidate; do
    candidate="$(physical_existing_path "$candidate" 2>/dev/null || true)"
    if [ "$candidate" = "$primary" ]; then
      found=1
      break
    fi
  done < <(git -C "$primary" worktree list --porcelain |
    awk '/^worktree / { print substr($0, 10) }')

  if [ "$found" -ne 1 ]; then
    worktree_paths_fail "primary checkout is not listed by git worktree"
    return 1
  fi

  printf '%s\n' "$primary"
}

repo_name_from_primary() {
  basename "$1"
}

canonical_worktree_root() {
  local primary="${1:-}"
  if [ -z "$primary" ]; then
    primary="$(primary_repo_root .)" || return 1
  fi
  primary="$(physical_existing_path "$primary")" || return 1
  local workspace_root repo_name root root_parent
  workspace_root="$(dirname "$primary")"
  repo_name="$(repo_name_from_primary "$primary")"
  root="$workspace_root/worktrees/$repo_name"

  root_parent="$(dirname "$root")"
  if [ -e "$root_parent" ]; then
    root_parent="$(physical_existing_path "$root_parent")" || return 1
    root="$root_parent/$(basename "$root")"
  fi

  case "$primary/" in
    "$root"/*) worktree_paths_fail "primary checkout is inside canonical root"; return 1 ;;
  esac

  printf '%s\n' "$root"
}

validate_worktree_slug() {
  local slug="$1"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

canonical_worktree_path() {
  local slug="$1"
  local primary="${2:-}"
  validate_worktree_slug "$slug" ||
    { worktree_paths_fail "invalid worktree slug: $slug"; return 1; }
  local root
  root="$(canonical_worktree_root "$primary")" || return 1
  printf '%s/%s\n' "$root" "$slug"
}

is_path_under_dir() {
  local target="$1"
  local root="$2"
  target="$(physical_existing_path "$target")" || return 1
  root="$(physical_existing_path "$root")" || return 1
  [ "$target" != "$root" ] || return 1
  case "$target/" in
    "$root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_path_under_canonical_root() {
  local target="$1"
  local primary="${2:-}"
  local root
  root="$(canonical_worktree_root "$primary")" || return 1
  is_path_under_dir "$target" "$root"
}

branch_name_for_worktree() {
  local primary="$1"
  local target="$2"
  local physical_target
  physical_target="$(physical_existing_path "$target")" || return 1
  git -C "$primary" worktree list --porcelain | awk -v target="$physical_target" '
    /^worktree / {
      path = substr($0, 10)
      branch = ""
      next
    }
    /^branch / {
      branch = substr($0, 8)
      sub("refs/heads/", "", branch)
      if (path == target) {
        print branch
        found = 1
      }
    }
    END { if (!found) exit 1 }
  '
}

list_canonical_worktrees() {
  local primary="$1"
  local root
  root="$(canonical_worktree_root "$primary")" || return 1
  [ -d "$root" ] || return 0
  git -C "$primary" worktree list --porcelain | awk -v root="$root" '
    /^worktree / {
      path = substr($0, 10)
      branch = ""
      next
    }
    /^branch / {
      branch = substr($0, 8)
      sub("refs/heads/", "", branch)
      if (path != "" && path != root && index(path "/", root "/") == 1) {
        print path "\t" branch
      }
    }
  '
}

remote_owner_repo() {
  local primary="$1"
  local url
  url="$(git -C "$primary" remote get-url origin 2>/dev/null)" || return 1
  case "$url" in
    git@github.com:*) url="${url#git@github.com:}" ;;
    ssh://git@github.com/*) url="${url#ssh://git@github.com/}" ;;
    https://github.com/*) url="${url#https://github.com/}" ;;
    http://github.com/*) url="${url#http://github.com/}" ;;
    *) worktree_paths_fail "unsupported GitHub remote: $url"; return 1 ;;
  esac
  url="${url%.git}"
  [[ "$url" == */* ]] || return 1
  printf '%s\n' "$url"
}
