#!/bin/bash
set -euo pipefail

# Source merge_claude_settings from worktree-cleanup.sh so tests exercise the
# production function directly instead of maintaining a duplicate copy.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/worktree-cleanup.sh"

PASSED=0
FAILED=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "${GREEN}PASS${NC} %s\n" "$desc"
    PASSED=$((PASSED + 1))
    return
  fi
  printf "${RED}FAIL${NC} %s\n" "$desc"
  printf "  expected: %s\n" "$expected"
  printf "  actual:   %s\n" "$actual"
  FAILED=$((FAILED + 1))
}

assert_file_exists() {
  local desc="$1" file="$2"
  if [ -f "$file" ]; then
    printf "${GREEN}PASS${NC} %s\n" "$desc"
    PASSED=$((PASSED + 1))
    return
  fi
  printf "${RED}FAIL${NC} %s — expected file to exist: %s\n" "$desc" "$file"
  FAILED=$((FAILED + 1))
}

assert_path_absent() {
  local desc="$1" path="$2"
  if [ ! -e "$path" ]; then
    printf "${GREEN}PASS${NC} %s\n" "$desc"
    PASSED=$((PASSED + 1))
    return
  fi
  printf "${RED}FAIL${NC} %s — expected absent: %s\n" "$desc" "$path"
  FAILED=$((FAILED + 1))
}

assert_json_field() {
  local desc="$1" file="$2" path="$3" expected="$4"
  local actual
  actual="$(jq -r "$path" "$file" 2>/dev/null || echo "ERROR")"
  assert_eq "$desc" "$expected" "$actual"
}

assert_json_eq() {
  local desc="$1" expected_json="$2" file="$3"
  local expected actual
  expected="$(printf '%s' "$expected_json" | jq -cS '.')"
  actual="$(jq -cS '.' "$file")"
  assert_eq "$desc" "$expected" "$actual"
}

reset() {
  rm -rf "$MAIN" "$WT"
  mkdir -p "$MAIN" "$WT"
}

write_main_settings() {
  mkdir -p "$MAIN/.claude"
  cat > "$MAIN/.claude/$1"
}

write_wt_settings() {
  mkdir -p "$WT/.claude"
  cat > "$WT/.claude/$1"
}

SANDBOX="$(mktemp -d /tmp/claude-merge-test.XXXXXX)"
cleanup_sandbox() { rm -rf "$SANDBOX"; }
trap cleanup_sandbox EXIT
MAIN="$SANDBOX/main"
WT="$SANDBOX/worktree"

echo "═══════════════════════════════════════════"
echo "  merge_claude_settings 测试套件"
echo "  sourced from: $SCRIPT_DIR/worktree-cleanup.sh"
echo "  Sandbox: $SANDBOX"
echo "═══════════════════════════════════════════"
echo ""

echo "── 测试 1: Worktree 无 settings.local.json，静默跳过 ──"
reset
merge_claude_settings "$WT" "$MAIN"
assert_path_absent "1.1 不应创建 main .claude 目录" "$MAIN/.claude"

echo ""
echo "── 测试 2: Main 无 settings.local.json，从 worktree 复制 ──"
reset
write_wt_settings settings.local.json << 'EOF'
{"hooks":{"PostToolUse":[{"matcher":"Write"}]}}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_file_exists "2.1 settings.local.json 应被复制" "$MAIN/.claude/settings.local.json"
assert_eq "2.2 复制内容应一致" "0" "$(diff -q "$WT/.claude/settings.local.json" "$MAIN/.claude/settings.local.json" >/dev/null 2>&1; echo $?)"

echo ""
echo "── 测试 3: Worktree 有 settings.local.json（permissions）, 复制保留 ──"
reset
write_wt_settings settings.local.json << 'EOF'
{"permissions":{"allow":["Bash(git:*)"]}}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_file_exists "3.1 settings.local.json 应被复制" "$MAIN/.claude/settings.local.json"
assert_json_field "3.2 allow 权限应保留" "$MAIN/.claude/settings.local.json" '.permissions.allow[0]' 'Bash(git:*)'

echo ""
echo "── 测试 4: 内容一致时跳过，不改变文件 ──"
reset
write_main_settings settings.local.json << 'EOF'
{"env":{"A":"1"}}
EOF
mkdir -p "$WT/.claude"
cp "$MAIN/.claude/settings.local.json" "$WT/.claude/settings.local.json"
before="$(shasum "$MAIN/.claude/settings.local.json" | awk '{print $1}')"
merge_claude_settings "$WT" "$MAIN"
after="$(shasum "$MAIN/.claude/settings.local.json" | awk '{print $1}')"
assert_eq "4.1 文件 hash 应保持不变" "$before" "$after"

echo ""
echo "── 测试 5: 普通字段合并，worktree 覆盖同名字段 ──"
reset
write_main_settings settings.local.json << 'EOF'
{"env":{"A":"main","KEEP":"yes"},"statusLine":{"type":"command","command":"main"}}
EOF
write_wt_settings settings.local.json << 'EOF'
{"env":{"A":"wt","B":"2"},"statusLine":{"type":"command","command":"wt"}}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_json_field "5.1 env.A 应由 wt 覆盖" "$MAIN/.claude/settings.local.json" '.env.A' 'wt'
assert_json_field "5.2 env.KEEP 应保留" "$MAIN/.claude/settings.local.json" '.env.KEEP' 'yes'
assert_json_field "5.3 env.B 应新增" "$MAIN/.claude/settings.local.json" '.env.B' '2'
assert_json_field "5.4 statusLine.command 应由 wt 覆盖" "$MAIN/.claude/settings.local.json" '.statusLine.command' 'wt'

echo ""
echo "── 测试 6: permissions.allow 两边合并并去重 ──"
reset
write_main_settings settings.local.json << 'EOF'
{"permissions":{"allow":["Bash(git:*)","Read(/tmp/**)"]}}
EOF
write_wt_settings settings.local.json << 'EOF'
{"permissions":{"allow":["Read(/tmp/**)","Bash(pnpm:*)"]}}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_json_field "6.1 allow 应为 3 项" "$MAIN/.claude/settings.local.json" '.permissions.allow | length' '3'
assert_json_field "6.2 allow[0] 按 unique 排序" "$MAIN/.claude/settings.local.json" '.permissions.allow[0]' 'Bash(git:*)'
assert_json_field "6.3 allow[1] 按 unique 排序" "$MAIN/.claude/settings.local.json" '.permissions.allow[1]' 'Bash(pnpm:*)'
assert_json_field "6.4 allow[2] 按 unique 排序" "$MAIN/.claude/settings.local.json" '.permissions.allow[2]' 'Read(/tmp/**)'

echo ""
echo "── 测试 7: permissions.deny 两边合并并去重 ──"
reset
write_main_settings settings.local.json << 'EOF'
{"permissions":{"deny":["Bash(rm -rf:*)","Write(/etc/**)"]}}
EOF
write_wt_settings settings.local.json << 'EOF'
{"permissions":{"deny":["Write(/etc/**)","Bash(curl:*)"]}}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_json_field "7.1 deny 应为 3 项" "$MAIN/.claude/settings.local.json" '.permissions.deny | length' '3'
assert_json_field "7.2 deny 包含 curl" "$MAIN/.claude/settings.local.json" '.permissions.deny[0]' 'Bash(curl:*)'
assert_json_field "7.3 deny 包含 rm" "$MAIN/.claude/settings.local.json" '.permissions.deny[1]' 'Bash(rm -rf:*)'
assert_json_field "7.4 deny 包含 Write" "$MAIN/.claude/settings.local.json" '.permissions.deny[2]' 'Write(/etc/**)'

echo ""
echo "── 测试 8: 仅 main 有 permissions，worktree 无 permissions，不丢失 ──"
reset
write_main_settings settings.local.json << 'EOF'
{"permissions":{"allow":["Bash(git:*)"],"deny":["Write(/etc/**)"]}}
EOF
write_wt_settings settings.local.json << 'EOF'
{"env":{"WT":"1"}}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_json_field "8.1 main allow 应保留" "$MAIN/.claude/settings.local.json" '.permissions.allow[0]' 'Bash(git:*)'
assert_json_field "8.2 main deny 应保留" "$MAIN/.claude/settings.local.json" '.permissions.deny[0]' 'Write(/etc/**)'
assert_json_field "8.3 wt env 应新增" "$MAIN/.claude/settings.local.json" '.env.WT' '1'

echo ""
echo "── 测试 9: 仅 worktree 有 permissions，main 无 permissions，应新增 ──"
reset
write_main_settings settings.local.json << 'EOF'
{"env":{"MAIN":"1"}}
EOF
write_wt_settings settings.local.json << 'EOF'
{"permissions":{"allow":["Bash(git:*)"],"deny":["Bash(rm:*)"]}}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_json_field "9.1 wt allow 应新增" "$MAIN/.claude/settings.local.json" '.permissions.allow[0]' 'Bash(git:*)'
assert_json_field "9.2 wt deny 应新增" "$MAIN/.claude/settings.local.json" '.permissions.deny[0]' 'Bash(rm:*)'
assert_json_field "9.3 main env 应保留" "$MAIN/.claude/settings.local.json" '.env.MAIN' '1'

echo ""
echo "── 测试 10: 两边无 permissions，不应凭空创建 permissions ──"
reset
write_main_settings settings.local.json << 'EOF'
{"env":{"A":"1"}}
EOF
write_wt_settings settings.local.json << 'EOF'
{"env":{"B":"2"}}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_json_field "10.1 permissions 不应存在" "$MAIN/.claude/settings.local.json" '.permissions' 'null'

echo ""
echo "── 测试 11: hooks 数组同名事件由 worktree 覆盖，其他事件保留 ──"
reset
write_main_settings settings.local.json << 'EOF'
{"hooks":{"PostToolUse":[{"matcher":"main"}],"Stop":[{"hooks":[{"type":"command","command":"stop"}]}]}}
EOF
write_wt_settings settings.local.json << 'EOF'
{"hooks":{"PostToolUse":[{"matcher":"wt"}]}}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_json_field "11.1 同名 PostToolUse 应由 wt 覆盖" "$MAIN/.claude/settings.local.json" '.hooks.PostToolUse[0].matcher' 'wt'
assert_json_field "11.2 main Stop 应保留" "$MAIN/.claude/settings.local.json" '.hooks.Stop[0].hooks[0].command' 'stop'

echo ""
echo "── 测试 12: worktree JSON 无效时返回非零且 main 不变 ──"
reset
write_main_settings settings.local.json << 'EOF'
{"env":{"SAFE":"main"}}
EOF
mkdir -p "$WT/.claude"
printf 'not valid json {{{\n' > "$WT/.claude/settings.local.json"
before="$(cat "$MAIN/.claude/settings.local.json")"
if merge_claude_settings "$WT" "$MAIN"; then
  assert_eq "12.1 无效 JSON 应导致失败" "nonzero" "zero"
else
  after="$(cat "$MAIN/.claude/settings.local.json")"
  assert_eq "12.1 main 文件不应被污染" "$before" "$after"
fi

echo ""
echo "── 测试 13: main JSON 无效时返回非零且 main 不变 ──"
reset
mkdir -p "$MAIN/.claude" "$WT/.claude"
printf 'bad main json {{{\n' > "$MAIN/.claude/settings.local.json"
write_wt_settings settings.local.json << 'EOF'
{"env":{"WT":"1"}}
EOF
before="$(cat "$MAIN/.claude/settings.local.json")"
if merge_claude_settings "$WT" "$MAIN"; then
  assert_eq "13.1 无效 main JSON 应导致失败" "nonzero" "zero"
else
  after="$(cat "$MAIN/.claude/settings.local.json")"
  assert_eq "13.1 main 文件不应被污染" "$before" "$after"
fi

echo ""
echo "── 测试 14: 保留复杂嵌套字段并覆盖同名子字段 ──"
reset
write_main_settings settings.local.json << 'EOF'
{"extraKnownMarketplaces":{"omc":{"source":{"source":"git","url":"old"}},"keep":{"enabled":true}}}
EOF
write_wt_settings settings.local.json << 'EOF'
{"extraKnownMarketplaces":{"omc":{"source":{"url":"new"}},"newMarket":{"source":{"source":"github"}}}}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_json_field "14.1 嵌套 url 应覆盖" "$MAIN/.claude/settings.local.json" '.extraKnownMarketplaces.omc.source.url' 'new'
assert_json_field "14.2 嵌套 source 应保留" "$MAIN/.claude/settings.local.json" '.extraKnownMarketplaces.omc.source.source' 'git'
assert_json_field "14.3 main 独有对象应保留" "$MAIN/.claude/settings.local.json" '.extraKnownMarketplaces.keep.enabled' 'true'
assert_json_field "14.4 wt 新对象应新增" "$MAIN/.claude/settings.local.json" '.extraKnownMarketplaces.newMarket.source.source' 'github'

echo ""
echo "── 测试 15: 复制模式保持原 JSON，不强制格式化 ──"
reset
write_wt_settings settings.local.json << 'EOF'
{"z":1,"a":2}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_eq "15.1 复制模式内容完全一致" "$(cat "$WT/.claude/settings.local.json")" "$(cat "$MAIN/.claude/settings.local.json")"

echo ""
echo "── 测试 16: 合并后 JSON 结构符合预期 ──"
reset
write_main_settings settings.local.json << 'EOF'
{"env":{"A":"main"},"permissions":{"allow":["Read(/main/**)"]}}
EOF
write_wt_settings settings.local.json << 'EOF'
{"env":{"A":"wt","B":"wt"},"permissions":{"allow":["Read(/wt/**)"]}}
EOF
merge_claude_settings "$WT" "$MAIN"
assert_json_eq "16.1 合并结果完整匹配" '{"env":{"A":"wt","B":"wt"},"permissions":{"allow":["Read(/main/**)","Read(/wt/**)"]}}' "$MAIN/.claude/settings.local.json"

echo ""
echo "═══════════════════════════════════════════"
printf "  结果: ${GREEN}%d 通过${NC}, ${RED}%d 失败${NC}\n" "$PASSED" "$FAILED"
echo "═══════════════════════════════════════════"

[ "$FAILED" -eq 0 ] && exit 0 || exit 1
