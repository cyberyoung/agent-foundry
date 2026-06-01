#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/worktree-cleanup.sh"

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

SANDBOX="$(mktemp -d /tmp/worktree-cleanup-boundary.XXXXXX)"
SANDBOX="$(physical_existing_path "$SANDBOX")"
PATH="$SANDBOX/bin:$PATH"
export PATH
trap 'rm -rf "$SANDBOX"' EXIT

mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" <<'EOF'
#!/bin/bash
if [ "${GH_STUB_FAIL:-}" = "1" ]; then
  echo "network down" >&2
  exit 2
fi
case "$*" in
  *"--state merged"*) echo "${GH_STUB_MERGED:-0}" ;;
  *"--state open"*) echo "${GH_STUB_OPEN:-0}" ;;
  *"--state closed"*) echo "${GH_STUB_CLOSED:-0}" ;;
  *) echo "0" ;;
esac
EOF
chmod +x "$SANDBOX/bin/gh"

git_init_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git init -b main "$repo" >/dev/null
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test-user
  git -C "$repo" remote add origin git@github.com:vrenlabs/chogori.git
  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -m baseline >/dev/null
}

PRIMARY="$SANDBOX/chogori"
git_init_repo "$PRIMARY"
git -C "$PRIMARY" branch feature/canonical
git -C "$PRIMARY" branch feature/legacy
mkdir -p "$SANDBOX/worktrees/chogori"
git -C "$PRIMARY" worktree add "$SANDBOX/worktrees/chogori/canonical" feature/canonical >/dev/null
git -C "$PRIMARY" worktree add "$SANDBOX/chogori-legacy" feature/legacy >/dev/null

assert_eq "main_worktree uses primary resolver" "$PRIMARY" "$(main_worktree "$PRIMARY")"
assert_eq "list_worktrees only returns canonical target" "$SANDBOX/worktrees/chogori/canonical	feature/canonical" "$(cd "$PRIMARY" && list_worktrees)"
assert_fail "legacy single target is rejected before PR lookup" cleanup_one "$SANDBOX/chogori-legacy" feature/legacy true

export GH_STUB_FAIL=1
assert_eq "gh failure becomes GH_ERROR" "GH_ERROR" "$(check_pr_status feature/canonical "$PRIMARY")"
unset GH_STUB_FAIL
export GH_STUB_MERGED=1
assert_eq "merged PR is detected" "MERGED" "$(check_pr_status feature/canonical "$PRIMARY")"
unset GH_STUB_MERGED
export GH_STUB_OPEN=1
assert_eq "open PR is detected" "OPEN" "$(check_pr_status feature/canonical "$PRIMARY")"
unset GH_STUB_OPEN
export GH_STUB_CLOSED=1
assert_eq "closed PR is detected" "CLOSED" "$(check_pr_status feature/canonical "$PRIMARY")"
unset GH_STUB_CLOSED

printf 'untracked\n' > "$SANDBOX/worktrees/chogori/canonical/untracked.txt"
assert_fail "dirty canonical worktree blocks cleanup" check_worktree_clean "$SANDBOX/worktrees/chogori/canonical"

ROLLBACK_MAIN="$SANDBOX/rollback-main"
ROLLBACK_WT="$SANDBOX/rollback-wt"
mkdir -p "$ROLLBACK_MAIN/.claude" "$ROLLBACK_WT/.claude"
printf '{"permissions":{"allow":["original"]}}\n' > "$ROLLBACK_MAIN/.claude/settings.local.json"
printf '{"permissions":{"allow":["changed"]}}\n' > "$ROLLBACK_WT/.claude/settings.local.json"
printf '{"mcp":{"safe":{"type":"local"}}}\n' > "$ROLLBACK_MAIN/opencode.json"
printf 'not valid json {{{\n' > "$ROLLBACK_WT/opencode.json"
assert_fail "main-side merge failure rolls back settings" run_main_side_merges "$ROLLBACK_WT" "$ROLLBACK_MAIN"
assert_eq "settings restored after rollback" '["original"]' "$(jq -c '.permissions.allow' "$ROLLBACK_MAIN/.claude/settings.local.json")"

printf 'total: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
