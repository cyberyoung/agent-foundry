---
name: wf-infra-pr-split
description: Use when a feature branch contains infrastructure changes (AGENTS.md, scripts, hooks, CI checks, docs tooling, .gitignore, package.json scripts) mixed with feature code. Splits infra changes into a separate PR to merge to main ahead of the feature PR. Triggers include 'split infra PR', 'extract infrastructure changes', 'merge infra first', or when a feature branch has accumulated non-src improvements.
---

# Infrastructure PR Split

## Overview

从功能分支中提取基础设施变更（规范、脚本、CI 检查、hook、文档工具等），创建独立 PR 提前合入 main。避免功能 PR 夹带基础设施改动，保持 PR 职责单一。

## When to Use

- 功能分支积累了和功能无关的基础设施改动
- AGENTS.md/CLAUDE.md 规范更新
- 新增/修改 CI 检查脚本
- Hook 配置变更
- 文档工具/索引脚本
- package.json 新增非功能性 scripts

## The Flow

```
分析 diff → 分类文件 → 创建 infra 分支 → cherry-pick/checkout 文件 → CI 验证 → 创建 PR → 合入 main → 功能分支 merge main
```

## Phase 1: 分析

对比功能分支和 main 的 diff，将文件分为两类：

**基础设施文件（提取到 infra PR）：**
- `AGENTS.md`、`CLAUDE.md` — 规范更新
- `scripts/` — CI 检查脚本、文档工具脚本
- `.claude/settings.json` — hook 配置
- `package.json` — 仅 scripts/devDependencies 变更（不含功能依赖）
- `.gitignore` — 忽略规则
- `docs/README.md` — 索引结构
- `docs/TODO.md` — 技术债务跟踪
- `docs/prds/*.md` — 仅 frontmatter 变更（索引用）
- 语言检查白名单（`scripts/check-agents-language.mjs`）
- 组件 README 白名单（`scripts/component-readme-allowlist.txt`）
- `src/utils/renderHelpers.tsx` — 新增共享渲染函数（被 CI 检查要求，非功能代码）

**功能文件（留在功能 PR）：**
- `src/` 下的业务代码（pages、atoms、api、components/enum、hooks、routes）
- `docs/designs/`、`docs/plans/` — 功能设计和计划文档

**注意：** `package.json` 可能同时包含基础设施和功能变更。如果 infra 改了 `check:ci` 命令而功能 PR 也改了路由 import，需要手动拆分或在两边都保留。

## Phase 2: 创建 infra 分支

```bash
# 从 main 创建 infra 分支
git checkout main
git pull origin main
git checkout -b chore/infra-sync-from-<feature-branch>

# 从功能分支 checkout 基础设施文件
git checkout <feature-branch> -- AGENTS.md .claude/settings.json scripts/ .gitignore docs/README.md docs/TODO.md package.json ...

# 验证
pnpm check:ci
```

## Phase 3: 创建 PR

```bash
git add -A
git commit -m "chore: 同步基础设施改动（AGENTS/scripts/CI/hooks/docs）"
git push origin chore/infra-sync-from-<feature-branch>
gh pr create --title "chore: 同步基础设施改动" --body "从 <feature-branch> 提取的基础设施变更..."
```

## Phase 4: 合入后同步

infra PR 合入 main 后，功能分支需要 merge main 解决文件重复：

```bash
git checkout <feature-branch>
git fetch origin main
git merge origin/main
# 冲突通常是 package.json、AGENTS.md 等，选择 main 的版本（infra PR 已包含）
git push
```

## Red Flags

| 错误做法 | 正确做法 |
|---------|---------|
| 把功能代码放进 infra PR | infra PR 只包含工具/规范/配置 |
| infra PR 依赖功能代码才能构建 | infra PR 必须独立通过 CI |
| 忘记功能分支 merge main | infra 合入后必须同步 |
| package.json 只 checkout 不检查 | 检查是否混入了功能依赖变更 |
