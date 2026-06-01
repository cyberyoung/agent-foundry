#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/worktree-paths.sh"

PASSED=0
FAILED=0

pass_test() { printf 'PASS %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail_test() {
  printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
  FAILED=$((FAILED + 1))
}
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  [ "$expected" = "$actual" ] && pass_test "$desc" || fail_test "$desc" "$expected" "$actual"
}
assert_fail() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail_test "$desc" "command to fail" "command passed"
  else
    pass_test "$desc"
  fi
}

SANDBOX="$(mktemp -d /tmp/worktree-paths.XXXXXX)"
SANDBOX="$(physical_existing_path "$SANDBOX")"
trap 'rm -rf "$SANDBOX"' EXIT

git_init_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git init -b main "$repo" >/dev/null
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test-user
  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -m baseline >/dev/null
}

PRIMARY="$SANDBOX/chogori"
git_init_repo "$PRIMARY"
git -C "$PRIMARY" branch feature/one
mkdir -p "$SANDBOX/worktrees/chogori"
git -C "$PRIMARY" worktree add "$SANDBOX/worktrees/chogori/one" feature/one >/dev/null

assert_eq "primary resolver from primary" "$PRIMARY" "$(primary_repo_root "$PRIMARY")"
assert_eq "primary resolver from linked worktree" "$PRIMARY" "$(primary_repo_root "$SANDBOX/worktrees/chogori/one")"
assert_eq "canonical root" "$SANDBOX/worktrees/chogori" "$(canonical_worktree_root "$PRIMARY")"
assert_eq "canonical path" "$SANDBOX/worktrees/chogori/abc-123" "$(canonical_worktree_path abc-123 "$PRIMARY")"

for slug in '' '../escape' 'BadSlug' 'a_b' 'a/b' 'a b' '-bad'; do
  assert_fail "invalid slug rejects [$slug]" canonical_worktree_path "$slug" "$PRIMARY"
done

assert_fail "canonical containment rejects primary repo" ensure_path_under_canonical_root "$PRIMARY" "$PRIMARY"
assert_fail "canonical containment rejects sibling legacy path" ensure_path_under_canonical_root "$SANDBOX/chogori-old" "$PRIMARY"
assert_eq "canonical containment accepts linked canonical worktree" "ok" "$(
  ensure_path_under_canonical_root "$SANDBOX/worktrees/chogori/one" "$PRIMARY" &&
    printf ok
)"

ln -s "$PRIMARY" "$SANDBOX/worktrees/chogori/escape-link"
assert_fail "physical containment rejects symlink escape" ensure_path_under_canonical_root "$SANDBOX/worktrees/chogori/escape-link" "$PRIMARY"

printf 'total: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
