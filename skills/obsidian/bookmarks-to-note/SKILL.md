---
name: ob-bookmarks-to-note
description: "Convert a Chrome bookmark folder into an Obsidian markdown note. Use this skill when the user asks to export browser bookmarks/favorites into a note, especially requests like '把收藏夹某个目录转成笔记', 'Chrome bookmarks to Obsidian', or '导出某个书签文件夹为 Markdown'."
---

# Obsidian Bookmark Folder to Note

将 Chrome 收藏夹中的某个目录导出为一篇 Obsidian 笔记。

## 功能

- 读取 Chrome `Bookmarks` JSON 文件
- 支持按目录名或完整路径定位目录（例如 `股票-文章` 或 `Bookmarks Bar/股票-文章`）
- 递归导出目录下所有网址（包含子目录）
- 对纯平铺链接目录支持按主题自动分组（默认开启，可关闭）
- 支持 `rules` / `llm` / `hybrid` 三种分组模式
- 支持把 LLM 分组产出的关键词自动回写到规则配置（默认开启）
- 自动跳过分隔符书签（如 `────` 或 `separator.mayastudios.com`）
- 生成带 YAML frontmatter 的 `.md` 笔记

## 脚本路径

`scripts/chrome_bookmarks_to_note.py`

主题规则配置：

`config/topic_rules.json`

本地便捷包装脚本（默认写入个人 vault 目录，不是公共主入口）：

`scripts/to_stock_inbox.sh`

## 使用方式

```bash
python3 scripts/chrome_bookmarks_to_note.py "<收藏夹目录>" "<输出目录>"
```

## 快捷方式（推荐）

```bash
bash scripts/to_stock_inbox.sh "<收藏夹目录>" [输出相对路径]

# 跳过确认弹窗（批处理/脚本场景）
bash scripts/to_stock_inbox.sh "<收藏夹目录>" [输出相对路径] --yes
```

示例：

```bash
# 默认输出到 wrapper 预设目录
bash scripts/to_stock_inbox.sh "AI Tools"

# 指定输出到自定义目录
bash scripts/to_stock_inbox.sh "Bookmarks Bar/AI Tools" "research/bookmarks"
```

说明：

- 输出基准库目录：`$OBSIDIAN_VAULT`，未设置时默认 `~/Documents/Obsidian Vault`
- 自动把 `category` 设为输出目录名（可用 `--category` 覆盖）
- 未显式传入时，wrapper 默认注入 `--group-mode hybrid --learn-rules`
- 默认会在执行前弹出预览并要求确认（`[1] Yes [2] No`）
- 可用 `--yes` / `--no-confirm` 跳过确认，`--confirm` 强制开启确认

示例：

```bash
python3 scripts/chrome_bookmarks_to_note.py \
  "Bookmarks Bar/AI Tools" \
  "/Users/liyang/Documents/Obsidian Vault/research/bookmarks"
```

可选参数：

```bash
--bookmarks-file <path>   # 默认: ~/Library/Application Support/Google/Chrome/Default/Bookmarks
--note-name <name>        # 覆盖输出文件名（不含 .md）
--category <name>         # frontmatter category，默认取输出目录名
--tags "a,b,c"            # frontmatter tags，默认: 收藏夹,chrome-bookmarks
--group-by-topic          # 按主题分组（默认开启）
--no-group-by-topic       # 关闭主题分组，使用单一“链接列表”
--group-mode <mode>       # rules|llm|hybrid，默认 hybrid
--learn-rules             # 从 LLM 输出学习并补充规则（默认开启）
--no-learn-rules          # 关闭自动回写规则
--topic-rules-file <path> # 自定义主题规则配置文件
--llm-model <name>        # LLM 模型名（llm/hybrid 模式）
--llm-base-url <url>      # OpenAI 兼容接口地址
--llm-api-key <key>       # OpenAI 兼容 API Key
--llm-timeout-sec <n>     # LLM 请求超时秒数（默认 60）
--llm-response-file <p>   # 本地 JSON 响应（离线测试/回放）
--dry-run-llm             # 跑 rules 后输出未分类条目 JSON 并退出（agent-as-LLM 用）
```

## 主题规则抽离

- 主题分组规则不再写死在脚本，统一放在 `config/topic_rules.json`
- 可按需修改：`series_patterns`（正则优先匹配）和 `topic_rules`（关键词匹配）
- 未命中规则的链接会落到 `unclassified_topic`（默认 `未分类`）
- 当使用 `llm`/`hybrid` 且开启 `--learn-rules` 时，会把 LLM 提供的关键词合并回 `topic_rules.json`

## 输出格式

- 文件名：`<目录名>.md`（可用 `--note-name` 覆盖）
- Frontmatter 字段：`title`、`date`、`tags`、`category`
- 正文结构：
  - 根目录链接：`## 链接列表`
  - 子目录链接：按层级生成 `##/###/####` 标题

## Agent-as-LLM 流程（默认，无需 API Key）

当 agent 调用此 skill 进行 hybrid/llm 分组时，**不需要外部 LLM API Key**。Agent 自己充当 LLM 完成分组。

### 流程

```
Step 1: 获取未分类条目
python3 scripts/chrome_bookmarks_to_note.py "<目录>" "<输出目录>" \
  --group-mode hybrid --dry-run-llm

输出 JSON 包含：
- items: [{id: 1, title: "..."}, ...] — 需要分组的条目
- existing_topics: [...] — 已有主题（优先归入）
- expected_response_schema — 响应格式模板

Step 2: Agent 生成分组 JSON
Agent 分析 items，生成响应写入临时文件 /tmp/agent_grouping.json：
{
  "groups": [
    {"topic": "主题名", "item_ids": [1,2], "keywords": ["关键词1","关键词2"]}
  ],
  "unclassified_item_ids": [3]
}

Step 3: 执行导出
python3 scripts/chrome_bookmarks_to_note.py "<目录>" "<输出目录>" \
  --group-mode hybrid --llm-response-file /tmp/agent_grouping.json --learn-rules
```

### Agent 分组原则

- 优先使用 `existing_topics` 中已有的主题名
- 只在确实无法归入已有主题时创建新主题
- `keywords` 应为确定性的子串匹配关键词（短、精确），用于规则学习
- 实在无法分类的放入 `unclassified_item_ids`

## Agent 确认流程（必须遵守）

调用此 skill 前，agent 必须用 **一次** mcp_question 调用收集全部参数，用户填完一起提交：

```
mcp_question({
  questions: [
    { header: "输入", question: "Chrome 收藏夹目录", options: [{label: "<推断的目录名>", description: "..."}] },
    { header: "输出", question: "输出目录", options: [{label: "<默认目录>", description: "..."}] },
    { header: "模式", question: "分组模式", options: [
      {label: "hybrid（推荐）", description: "规则 + Agent 智能分组 + 自动学习"},
      {label: "rules", description: "纯规则匹配"}
    ]}
  ]
})
```

禁止：拆成多次 mcp_question 调用（每次都有 LLM round-trip 延迟）。
禁止：使用 --yes 跳过确认。

## 注意事项

- 本技能默认针对 **Google Chrome** 本地收藏夹文件。
- 若目录名重复，建议传完整路径避免歧义。
- 这是导出链接清单，不抓取网页正文内容。

## Public Release Notes

- The core public interface is `scripts/chrome_bookmarks_to_note.py`.
- `scripts/to_stock_inbox.sh` is a local convenience wrapper and should not be the primary public entrypoint.
- Public-facing docs should present generic bookmark export workflows rather than private output-folder conventions.
