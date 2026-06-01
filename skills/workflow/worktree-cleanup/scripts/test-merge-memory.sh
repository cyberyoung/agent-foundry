#!/bin/bash
# 测试 worktree-cleanup.sh 中 merge_memory 函数的合并逻辑
# 仿照 test-merge-claude-settings.sh 模式

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/worktree-cleanup.sh"

# shellcheck disable=SC1090
source "$SCRIPT"

set +e

if ! type -t merge_memory >/dev/null 2>&1; then
  echo "FATAL: merge_memory 未加载，测试无意义"
  exit 2
fi

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

assert_file_exists() {
  local desc="$1" file="$2"
  if [ -f "$file" ]; then
    echo "✓ PASS: $desc"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "✗ FAIL: $desc"
    echo "  文件不存在: $file"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_TESTS+=("$desc")
  fi
}

assert_file_not_exists() {
  local desc="$1" file="$2"
  if [ ! -f "$file" ]; then
    echo "✓ PASS: $desc"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "✗ FAIL: $desc"
    echo "  文件不应存在: $file"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_TESTS+=("$desc")
  fi
}

# 生成与 merge_memory 一致的 project key
# path_to_project_key 的定义：echo "-$(echo "$1" | tr '/' '-')"
project_key() {
  echo "-$(echo "$1" | tr '/' '-')"
}

setup() {
  local id="$1"

  FAKE_HOME="$(mktemp -d -t "fakehome-$id-XXX")"
  mkdir -p "$FAKE_HOME/.claude/projects"

  # 主路径固定
  MAIN_PATH="/fake/main/repo-$id"
  MAIN_KEY="$(project_key "$MAIN_PATH")"
  mkdir -p "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory"
}

teardown() {
  rm -rf "$FAKE_HOME"
}

# 用 fake HOME 跑 merge_memory，截 std{out,err}
run_merge() {
  HOME="$FAKE_HOME" merge_memory "$1" "$MAIN_PATH"
}

# --- 测试用例 ---

echo "=== Test 1: worktree memory 无文件 → 静默返回 0 ==="
setup "t1"
WT_PATH="/fake/worktree/empty"
WT_KEY="$(project_key "$WT_PATH")"
mkdir -p "$FAKE_HOME/.claude/projects/$WT_KEY/memory"
ret=0
run_merge "$WT_PATH" >/dev/null 2>&1 || ret=$?
assert_eq "无文件应返回 0" "0" "$ret"
teardown
echo ""

echo "=== Test 2: worktree 有单个 memory 文件，主项目没有 → 复制 ==="
setup "t2"
WT_PATH="/fake/worktree/t2"
WT_KEY="$(project_key "$WT_PATH")"
mkdir -p "$FAKE_HOME/.claude/projects/$WT_KEY/memory"
echo "--- foo: bar ---" > "$FAKE_HOME/.claude/projects/$WT_KEY/memory/test_memory.md"
run_merge "$WT_PATH" >/dev/null 2>&1
assert_file_exists "应复制到主项目" "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/test_memory.md"
actual="$(cat "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/test_memory.md")"
assert_eq "内容应相同" "--- foo: bar ---" "$actual"
teardown
echo ""

echo "=== Test 3: 两边有同名文件且内容相同 → 跳过 ==="
setup "t3"
WT_PATH="/fake/worktree/t3"
WT_KEY="$(project_key "$WT_PATH")"
mkdir -p "$FAKE_HOME/.claude/projects/$WT_KEY/memory"
echo "same content" > "$FAKE_HOME/.claude/projects/$WT_KEY/memory/shared.md"
echo "same content" > "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/shared.md"
md5_before="$(md5 -q "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/shared.md")"
run_merge "$WT_PATH" >/dev/null 2>&1
md5_after="$(md5 -q "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/shared.md")"
assert_eq "主项目文件应不变" "$md5_before" "$md5_after"
teardown
echo ""

echo "=== Test 4: 两边有同名文件但内容不同 → 保留主项目版本 ==="
setup "t4"
WT_PATH="/fake/worktree/t4"
WT_KEY="$(project_key "$WT_PATH")"
mkdir -p "$FAKE_HOME/.claude/projects/$WT_KEY/memory"
echo "wt content" > "$FAKE_HOME/.claude/projects/$WT_KEY/memory/conflict.md"
echo "main content" > "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/conflict.md"
run_merge "$WT_PATH" >/dev/null 2>&1
actual="$(cat "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/conflict.md")"
assert_eq "应保留主项目版本" "main content" "$actual"
teardown
echo ""

echo "=== Test 5: worktree 没有 memory 目录 → 返回 0 不报错 ==="
setup "t5"
WT_PATH="/fake/worktree/t5"
WT_KEY="$(project_key "$WT_PATH")"
mkdir -p "$FAKE_HOME/.claude/projects/$WT_KEY"
ret=0
run_merge "$WT_PATH" >/dev/null 2>&1 || ret=$?
assert_eq "无 memory dir 应返回 0" "0" "$ret"
teardown
echo ""

echo "=== Test 6: worktree project 目录不存在 → 返回 0 ==="
setup "t6"
WT_PATH="/fake/worktree/t6"
ret=0
run_merge "$WT_PATH" >/dev/null 2>&1 || ret=$?
assert_eq "目录不存在应返回 0" "0" "$ret"
teardown
echo ""

echo "=== Test 7: MEMORY.md 索引合并（双方都有）→ 内容去重 ==="
setup "t7"
WT_PATH="/fake/worktree/t7"
WT_KEY="$(project_key "$WT_PATH")"
mkdir -p "$FAKE_HOME/.claude/projects/$WT_KEY/memory"
cat > "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/MEMORY.md" <<'EOF'
# Memory
- [user_skill](user_skill.md)
- [project_context](project_context.md)
EOF
cat > "$FAKE_HOME/.claude/projects/$WT_KEY/memory/MEMORY.md" <<'EOF'
# Memory
- [project_context](project_context.md)
- [feedback_new](feedback_new.md)
EOF
run_merge "$WT_PATH" >/dev/null 2>&1
actual="$(cat "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/MEMORY.md")"
echo "$actual" | grep -q "user_skill" && has_user=1 || has_user=0
echo "$actual" | grep -q "project_context" && has_ctx=1 || has_ctx=0
echo "$actual" | grep -q "feedback_new" && has_fb=1 || has_fb=0
assert_eq "合并后应包含 user_skill" "1" "$has_user"
assert_eq "合并后应包含 project_context" "1" "$has_ctx"
assert_eq "合并后应包含 feedback_new" "1" "$has_fb"
teardown
echo ""

echo "=== Test 8: MEMORY.md 只在 worktree 有 → 复制到主 ==="
setup "t8"
WT_PATH="/fake/worktree/t8"
WT_KEY="$(project_key "$WT_PATH")"
mkdir -p "$FAKE_HOME/.claude/projects/$WT_KEY/memory"
echo "- [new_mem](new_mem.md)" > "$FAKE_HOME/.claude/projects/$WT_KEY/memory/MEMORY.md"
run_merge "$WT_PATH" >/dev/null 2>&1
assert_file_exists "应创建主 MEMORY.md" "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/MEMORY.md"
actual="$(cat "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/MEMORY.md")"
assert_eq "内容应相同" "- [new_mem](new_mem.md)" "$actual"
teardown
echo ""

echo "=== Test 9: 多个 memory 文件 + MEMORY.md + 冲突时保留主 ==="
setup "t9"
WT_PATH="/fake/worktree/t9"
WT_KEY="$(project_key "$WT_PATH")"
mkdir -p "$FAKE_HOME/.claude/projects/$WT_KEY/memory"
echo "feedback content" > "$FAKE_HOME/.claude/projects/$WT_KEY/memory/feedback_test.md"
echo "user content" > "$FAKE_HOME/.claude/projects/$WT_KEY/memory/user_pref.md"
echo "- [f](feedback_test.md)" > "$FAKE_HOME/.claude/projects/$WT_KEY/memory/MEMORY.md"
echo "original feedback" > "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/feedback_test.md"
run_merge "$WT_PATH" >/dev/null 2>&1
assert_file_exists "新文件应被复制" "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/user_pref.md"
actual="$(cat "$FAKE_HOME/.claude/projects/$MAIN_KEY/memory/feedback_test.md")"
assert_eq "冲突文件应保留主版本" "original feedback" "$actual"
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
