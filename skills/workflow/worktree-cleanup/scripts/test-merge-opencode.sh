#!/bin/bash
set -euo pipefail

# Source merge_opencode_settings (and its deps: warn, pass, colors)
# from worktree-cleanup.sh. The source guard in that file prevents main
# execution when sourced.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/worktree-cleanup.sh"

PASSED=0; FAILED=0

# ─────────────────────────────────────────────────────
# 测试工具函数
# ─────────────────────────────────────────────────────
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "${GREEN}PASS${NC} %s\n" "$desc"
    PASSED=$((PASSED + 1))
  else
    printf "${RED}FAIL${NC} %s\n" "$desc"
    printf "  expected: %s\n" "$expected"
    printf "  actual:   %s\n" "$actual"
    FAILED=$((FAILED + 1))
  fi
}

assert_json_field() {
  local desc="$1" file="$2" path="$3" expected="$4"
  local actual
  actual="$(jq -r "$path" "$file" 2>/dev/null || echo "ERROR")"
  assert_eq "$desc" "$expected" "$actual"
}

reset() {
  rm -rf "$MAIN" "$WT"
  mkdir -p "$MAIN" "$WT"
}

# ─────────────────────────────────────────────────────
# 测试 Sandbox（自建 temp 目录，用后自清）
# ─────────────────────────────────────────────────────
SANDBOX="$(mktemp -d /tmp/opencode-merge-test.XXXXXX)"
cleanup_sandbox() { rm -rf "$SANDBOX"; }
trap cleanup_sandbox EXIT
MAIN="$SANDBOX/main"
WT="$SANDBOX/worktree"

echo "═══════════════════════════════════════════"
echo "  merge_opencode_settings 测试套件"
echo "  sourced from: $SCRIPT_DIR/worktree-cleanup.sh"
echo "  Sandbox: $SANDBOX"
echo "═══════════════════════════════════════════"
echo ""

# ── 测试 1: Main 无文件 → 直接复制 ──
echo "── 测试 1: Main 无 opencode.json，从 worktree 复制 ──"
reset
cat > "$WT/opencode.json" << 'EOF'
{"mcp":{"devtap":{"command":["npx","-y","devtap"],"type":"local"}},"plugin":["oh-my-openagent@latest"]}
EOF
merge_opencode_settings "$WT" "$MAIN"
assert_eq "1.1 Main 应存在文件" "0" "$(diff -q "$WT/opencode.json" "$MAIN/opencode.json" >/dev/null 2>&1; echo $?)"

# ── 测试 2: 内容一致 → 跳过 ──
echo ""
echo "── 测试 2: main 和 worktree 内容一致，跳过 ──"
reset
cat > "$MAIN/opencode.json" << 'EOF'
{"mcp":{"semi":{"command":["npx","-y","@douyinfe/semi-mcp"],"type":"local"}}}
EOF
cp "$MAIN/opencode.json" "$WT/opencode.json"
merge_opencode_settings "$WT" "$MAIN"
assert_eq "2.1 文件应不变（内容一致）" "0" "$(diff -q "$WT/opencode.json" "$MAIN/opencode.json" >/dev/null 2>&1; echo $?)"

# ── 测试 3: Worktree 无文件 → 静默跳过 ──
echo ""
echo "── 测试 3: Worktree 无 opencode.json，静默跳过 ──"
reset
cat > "$MAIN/opencode.json" << 'EOF'
{"mcp":{"semi":{"command":["npx","-y","@douyinfe/semi-mcp"],"type":"local"}}}
EOF
merge_opencode_settings "$WT" "$MAIN"
assert_eq "3.1 Main 应保持原样" '{"mcp":{"semi":{"command":["npx","-y","@douyinfe/semi-mcp"],"type":"local"}}}' "$(cat "$MAIN/opencode.json")"

# ── 测试 4: MCP 合并 — wt 新增 server ──
echo ""
echo "── 测试 4: MCP 合并 — worktree 新增 MCP server ──"
reset
cat > "$MAIN/opencode.json" << 'EOF'
{"$schema":"https://opencode.ai/config.json","mcp":{"semi":{"command":["npx","-y","@douyinfe/semi-mcp"],"type":"local"}}}
EOF
cat > "$WT/opencode.json" << 'EOF'
{"$schema":"https://opencode.ai/config.json","mcp":{"semi":{"command":["npx","-y","@douyinfe/semi-mcp"],"type":"local"},"devtap":{"command":["npx","-y","devtap"],"type":"local"}}}
EOF
merge_opencode_settings "$WT" "$MAIN"
assert_json_field "4.1 semi 应保留"     "$MAIN/opencode.json" '.mcp.semi.command[2]' '@douyinfe/semi-mcp'
assert_json_field "4.2 devtap 应合并入" "$MAIN/opencode.json" '.mcp.devtap.command[2]' 'devtap'
assert_json_field '4.3 应保留 $schema'  "$MAIN/opencode.json" '."$schema"' 'https://opencode.ai/config.json'

# ── 测试 5: MCP 覆盖 — wt 同名 server 覆盖 main ──
echo ""
echo "── 测试 5: MCP 覆盖 — worktree 同名 server 覆盖 main ──"
reset
cat > "$MAIN/opencode.json" << 'EOF'
{"mcp":{"semi":{"command":["npx","-y","@douyinfe/semi-mcp"],"type":"local","enabled":true}}}
EOF
cat > "$WT/opencode.json" << 'EOF'
{"mcp":{"semi":{"command":["npx","-y","@douyinfe/semi-mcp"],"type":"local","enabled":false}}}
EOF
merge_opencode_settings "$WT" "$MAIN"
assert_json_field "5.1 enabled 应为 false（wt 覆盖）" "$MAIN/opencode.json" '.mcp.semi.enabled' 'false'

# ── 测试 6: Plugin 合并 + 去重 ──
echo ""
echo "── 测试 6: Plugin 合并 + 去重 ──"
reset
cat > "$MAIN/opencode.json" << 'EOF'
{"plugin":["oh-my-openagent@latest","opencode-claude-auth@1.5.0"]}
EOF
cat > "$WT/opencode.json" << 'EOF'
{"plugin":["opencode-claude-auth@1.5.0","dev-browser@latest"]}
EOF
merge_opencode_settings "$WT" "$MAIN"
assert_json_field "6.1 plugin 数应为 3（去重后）" "$MAIN/opencode.json" '.plugin | length' '3'
assert_json_field "6.2 包含 oh-my-openagent"   "$MAIN/opencode.json" '.plugin[0]' 'dev-browser@latest'
assert_json_field "6.3 包含 opencode-claude-auth" "$MAIN/opencode.json" '.plugin[1]' 'oh-my-openagent@latest'
assert_json_field "6.4 包含 dev-browser"        "$MAIN/opencode.json" '.plugin[2]' 'opencode-claude-auth@1.5.0'

# ── 测试 7: MCP + Plugin 同时合并 ──
echo ""
echo "── 测试 7: MCP + Plugin 同时合并 ──"
reset
cat > "$MAIN/opencode.json" << 'EOF'
{"mcp":{"semi":{"command":["npx"],"type":"local"}},"plugin":["a@v1"]}
EOF
cat > "$WT/opencode.json" << 'EOF'
{"mcp":{"devtap":{"command":["npx"],"type":"local"}},"plugin":["b@v2"]}
EOF
merge_opencode_settings "$WT" "$MAIN"
assert_json_field "7.1 semi 应保留"  "$MAIN/opencode.json" '.mcp.semi.type'  'local'
assert_json_field "7.2 devtap 应合并" "$MAIN/opencode.json" '.mcp.devtap.type' 'local'
assert_json_field "7.3 plugin 应为 2"  "$MAIN/opencode.json" '.plugin | length' '2'

# ── 测试 8: 仅 Main 有 plugin，wt 无 plugin → 不丢失 ──
echo ""
echo "── 测试 8: 仅 main 有 plugin，wt 无 plugin → 不丢失 ──"
reset
cat > "$MAIN/opencode.json" << 'EOF'
{"plugin":["a@v1","b@v2"]}
EOF
cat > "$WT/opencode.json" << 'EOF'
{"mcp":{"devtap":{"type":"local"}}}
EOF
merge_opencode_settings "$WT" "$MAIN"
assert_json_field "8.1 plugin 应保留" "$MAIN/opencode.json" '.plugin | length' '2'
assert_json_field "8.2 mcp devtap 应存在" "$MAIN/opencode.json" '.mcp.devtap.type' 'local'

# ── 测试 9: 无效 JSON → 不污染 main ──
echo ""
echo "── 测试 9: worktree 有无效 JSON，不应污染 main ──"
reset
cat > "$MAIN/opencode.json" << 'EOF'
{"mcp":{"semi":{"type":"local"}}}
EOF
echo "not valid json {{{" > "$WT/opencode.json"
if merge_opencode_settings "$WT" "$MAIN"; then
  assert_json_field "9.1 main 应保持原样" "$MAIN/opencode.json" '.mcp.semi.type' 'local'
else
  printf "${GREEN}PASS${NC} %s\n" "9.1 merge 返回非 0，main 未被修改"
  PASSED=$((PASSED + 1))
fi

# ── 测试 10: 两边都无 plugin → plugin 字段不凭空出现 ──
echo ""
echo "── 测试 10: 两边无 plugin，结果不应凭空出现空 plugin ──"
reset
cat > "$MAIN/opencode.json" << 'EOF'
{"mcp":{"semi":{"type":"local"}}}
EOF
cat > "$WT/opencode.json" << 'EOF'
{"mcp":{"devtap":{"type":"local"}}}
EOF
merge_opencode_settings "$WT" "$MAIN"
assert_json_field "10.1 plugin 不应存在" "$MAIN/opencode.json" '.plugin' 'null'

# ── 汇总 ──
echo ""
echo "═══════════════════════════════════════════"
printf "  结果: ${GREEN}%d 通过${NC}, ${RED}%d 失败${NC}\n" "$PASSED" "$FAILED"
echo "═══════════════════════════════════════════"

[ "$FAILED" -eq 0 ] && exit 0 || exit 1
