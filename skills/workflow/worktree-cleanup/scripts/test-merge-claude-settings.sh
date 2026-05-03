#!/bin/bash
# 测试 worktree-cleanup.sh 中 merge_claude_settings 函数的合并逻辑
# 不用真实数据，构造各种场景验证

set -uo pipefail

# 引入被测函数（修改后的 worktree-cleanup.sh）
SCRIPT="/Users/liyang/.claude/skills/wf-worktree-cleanup/scripts/worktree-cleanup.sh"

# 提取函数定义但不执行 main — sed 打印所有行直到 "# --- Main ---" 之前一行（macOS 兼容）
TMP_FUNC="$(mktemp)"
sed -n '/# --- Main ---/q;p' "$SCRIPT" > "$TMP_FUNC"
# shellcheck disable=SC1090
source "$TMP_FUNC"
rm -f "$TMP_FUNC"

# 关闭被 source 进来的 set -e — 测试脚本用自己的 assert 框架管理失败
set +e

# sanity check: 确认目标函数已加载
if ! type -t merge_claude_settings >/dev/null 2>&1; then
  echo "FATAL: merge_claude_settings 未加载，测试无意义"
  exit 2
fi

# --- 测试辅助 ---
PASS_COUNT=0
FAIL_COUNT=0
FAILED_TESTS=()

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "✓ PASS: $desc"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "✗ FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_TESTS+=("$desc")
  fi
}

assert_json_eq() {
  local desc="$1" file="$2" jq_expr="$3" expected="$4"
  local actual
  actual="$(jq -c "$jq_expr" "$file" 2>/dev/null)"
  assert_eq "$desc" "$expected" "$actual"
}

setup() {
  local id="$1"
  WT_DIR="$(mktemp -d -t "wt-$id-XXX")"
  MAIN_DIR="$(mktemp -d -t "main-$id-XXX")"
  mkdir -p "$WT_DIR/.claude" "$MAIN_DIR/.claude"
}

teardown() {
  rm -rf "$WT_DIR" "$MAIN_DIR"
}

# --- 测试用例 ---

echo "=== Test 1: 主仓库无 settings.local.json，worktree 有 → 应整体复制 ==="
setup "t1"
echo '{"permissions":{"allow":["Bash(ls)","Bash(cat)"]}}' > "$WT_DIR/.claude/settings.local.json"
merge_claude_settings "$WT_DIR" "$MAIN_DIR" >/dev/null 2>&1
[ -f "$MAIN_DIR/.claude/settings.local.json" ] && actual=1 || actual=0
assert_eq "目标文件应被创建" "1" "$actual"
assert_json_eq "permissions.allow 应完整" "$MAIN_DIR/.claude/settings.local.json" '.permissions.allow' '["Bash(ls)","Bash(cat)"]'
teardown
echo ""

echo "=== Test 2: 两边 permissions.allow 不同 → 应合并去重 ==="
setup "t2"
echo '{"permissions":{"allow":["Bash(git:*)","Bash(ls)"]}}' > "$MAIN_DIR/.claude/settings.local.json"
echo '{"permissions":{"allow":["Bash(ls)","Bash(npm:*)","Bash(node:*)"]}}' > "$WT_DIR/.claude/settings.local.json"
merge_claude_settings "$WT_DIR" "$MAIN_DIR" >/dev/null 2>&1
assert_json_eq "permissions.allow 应为联合去重" "$MAIN_DIR/.claude/settings.local.json" '.permissions.allow | sort' '["Bash(git:*)","Bash(ls)","Bash(node:*)","Bash(npm:*)"]'
teardown
echo ""

echo "=== Test 3: 两边内容完全一致 → 应跳过，文件不变 ==="
setup "t3"
echo '{"permissions":{"allow":["a","b"]}}' > "$MAIN_DIR/.claude/settings.local.json"
echo '{"permissions":{"allow":["a","b"]}}' > "$WT_DIR/.claude/settings.local.json"
md5_before="$(md5 -q "$MAIN_DIR/.claude/settings.local.json")"
merge_claude_settings "$WT_DIR" "$MAIN_DIR" >/dev/null 2>&1
md5_after="$(md5 -q "$MAIN_DIR/.claude/settings.local.json")"
assert_eq "文件 md5 应不变" "$md5_before" "$md5_after"
teardown
echo ""

echo "=== Test 4: 主仓库有 hooks 设置，worktree 只改 permissions → hooks 应保留 ==="
setup "t4"
cat > "$MAIN_DIR/.claude/settings.local.json" <<'EOF'
{
  "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"command": "/foo"}]}]},
  "permissions": {"allow": ["a"]}
}
EOF
echo '{"permissions":{"allow":["b","c"]}}' > "$WT_DIR/.claude/settings.local.json"
merge_claude_settings "$WT_DIR" "$MAIN_DIR" >/dev/null 2>&1
assert_json_eq "hooks 应保留" "$MAIN_DIR/.claude/settings.local.json" '.hooks.PreToolUse[0].matcher' '"Bash"'
assert_json_eq "permissions.allow 应合并" "$MAIN_DIR/.claude/settings.local.json" '.permissions.allow | sort' '["a","b","c"]'
teardown
echo ""

echo "=== Test 5: worktree 文件不存在 → 主仓库不应被修改 ==="
setup "t5"
echo '{"permissions":{"allow":["existing"]}}' > "$MAIN_DIR/.claude/settings.local.json"
md5_before="$(md5 -q "$MAIN_DIR/.claude/settings.local.json")"
merge_claude_settings "$WT_DIR" "$MAIN_DIR" >/dev/null 2>&1
md5_after="$(md5 -q "$MAIN_DIR/.claude/settings.local.json")"
assert_eq "无 worktree 文件时主仓库 md5 应不变" "$md5_before" "$md5_after"
teardown
echo ""

echo "=== Test 6: permissions.deny 也要合并去重 ==="
setup "t6"
echo '{"permissions":{"deny":["Bash(rm:*)","Bash(curl:*)"]}}' > "$MAIN_DIR/.claude/settings.local.json"
echo '{"permissions":{"deny":["Bash(curl:*)","Bash(wget:*)"]}}' > "$WT_DIR/.claude/settings.local.json"
merge_claude_settings "$WT_DIR" "$MAIN_DIR" >/dev/null 2>&1
assert_json_eq "permissions.deny 应联合去重" "$MAIN_DIR/.claude/settings.local.json" '.permissions.deny | sort' '["Bash(curl:*)","Bash(rm:*)","Bash(wget:*)"]'
teardown
echo ""

echo "=== Test 7: 损坏 JSON → 应保留主仓库原文件 ==="
setup "t8"
echo '{"permissions":{"allow":["original"]}}' > "$MAIN_DIR/.claude/settings.local.json"
echo 'not valid json {{{ broken' > "$WT_DIR/.claude/settings.local.json"
merge_claude_settings "$WT_DIR" "$MAIN_DIR" >/dev/null 2>&1
assert_json_eq "损坏 JSON 时主仓库应保留原内容" "$MAIN_DIR/.claude/settings.local.json" '.permissions.allow' '["original"]'
teardown
echo ""

echo "=== Test 8: 主仓库有 .claude 但无目标文件，worktree 有 → 应创建新文件不破坏其他 ==="
setup "t8"
# 主仓库的 .claude 已有 settings.json（其他文件）
echo '{"existing": "data"}' > "$MAIN_DIR/.claude/settings.json"
echo '{"permissions":{"allow":["new"]}}' > "$WT_DIR/.claude/settings.local.json"
merge_claude_settings "$WT_DIR" "$MAIN_DIR" >/dev/null 2>&1
[ -f "$MAIN_DIR/.claude/settings.local.json" ] && actual=1 || actual=0
assert_eq "settings.local.json 应被创建" "1" "$actual"
assert_json_eq "settings.json 不应被影响" "$MAIN_DIR/.claude/settings.json" '.existing' '"data"'
teardown
echo ""

# --- 总结 ---
echo "================================="
echo "总计: $((PASS_COUNT + FAIL_COUNT)) 个断言, $PASS_COUNT 通过, $FAIL_COUNT 失败"
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo ""
  echo "失败列表："
  for t in "${FAILED_TESTS[@]}"; do
    echo "  - $t"
  done
  exit 1
fi
exit 0
