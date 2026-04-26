---
name: lark-workflow-pins-to-doc
version: 1.0.0
description: "将飞书群聊的 Pin（置顶）消息汇总成表格并插入指定文档。当用户需要汇总群聊 Pin 消息、整理群内重要信息到飞书文档时使用。"
metadata:
  requires:
    bins: ["lark-cli"]
---

# Pin 消息汇总到文档

> **前置条件：** 先用 Read 工具读取 [`../lark-shared/SKILL.md`](../lark-shared/SKILL.md)，了解认证、权限处理。

## 适用场景

- "把群里的 Pin 消息整理到文档"
- "汇总群聊置顶消息到表格"
- "把微仁产品业务对接群的 pin 消息同步到文档"

## 前置条件

仅支持 **user 身份**（需要以用户身份访问群聊和文档）。

```bash
lark-cli auth login --domain im,docs,contact
```

## 权限

| 操作 | 所需 scope |
|------|-----------|
| 搜索群聊 | `im:chat:read` |
| 获取 Pin 列表 | `im:message.pins:read` |
| 批量读取消息内容 | `im:message:readonly` |
| 解析发送者姓名 | `contact:user.base:readonly` |
| 读取文档内容 | `docx:document:readonly` |
| 更新文档内容 | `docx:document` |

## 工作流

```
群名关键词 ─► im +chat-search ──► chat_id
                                     │
                                     ▼
                              im pins list ──► message_ids (分页收集全部)
                                     │
                                     ▼
                           im +messages-mget ──► 消息内容 (每批最多 50)
                                     │
                                     ▼
                              组装 Markdown 表格
                                     │
                                     ▼
                    docs +fetch ──► 确认插入锚点存在
                                     │
                                     ▼
                 docs +update (insert_after) ──► 插入表格
```

### Step 1: 搜索群聊获取 chat_id

```bash
lark-cli im +chat-search --query "<群名关键词>" --format json
```

从返回的 `data.chats` 中匹配目标群，取 `chat_id`（`oc_xxx`）。

> 如果用户直接提供了 `chat_id`，跳过此步。

### Step 2: 获取所有 Pin 消息 ID

```bash
# 首次请求
lark-cli im pins list --params '{"chat_id":"<chat_id>","page_size":"50"}'

# 如果 has_more=true，用 page_token 翻页
lark-cli im pins list --params '{"chat_id":"<chat_id>","page_size":"50","page_token":"<token>"}'
```

**收集所有 `items[].message_id`**（`om_xxx` 格式）。同时记录每条 pin 的 `create_time`（可用于排序）。

### Step 3: 批量获取消息内容

```bash
# 每批最多 50 条
lark-cli im +messages-mget --message-ids "om_aaa,om_bbb,om_ccc,..." --format json
```

**解析每条消息**（根据 `msg_type` 提取可读文本）：

| msg_type | 提取方式 |
|----------|---------|
| `text` | `content.text`（纯文本） |
| `post` | `content.title` + 遍历 `content.content[][]` 提取 `tag=text` 的 `.text` |
| `image` | 显示为 `[图片]` |
| `file` | 显示为 `[文件: {file_name}]` |
| `interactive` | 显示为 `[卡片消息]`，尝试提取 `header.title.content` |
| 其他 | 显示为 `[{msg_type} 消息]` |

### Step 4: 组装 Markdown 表格

从目标文档 URL 提取飞书域名（如 `bpl3y8iw2y.feishu.cn`），构造消息深链接：

```
https://{domain}/messenger/{chat_id}?messageId={message_id}
```

> **注意**：此链接格式为飞书 Web 端跳转格式，在浏览器中可跳转到对应消息位置。如果无法确认域名，可省略链接，只保留文本。

**表格 Markdown 格式**（使用标准 Markdown 表格）：

```markdown
| Pin 消息 |
|----------|
| [消息摘要文本](https://{domain}/messenger/{chat_id}?messageId=om_xxx) |
| [消息摘要文本](https://{domain}/messenger/{chat_id}?messageId=om_yyy) |
```

- 每行一条 Pin 消息
- 按 pin 创建时间倒序排列（最新在前）
- 消息文本过长时截取前 200 字符并加 `...`
- 文本中的 `|` 替换为 `\|`，换行替换为空格，避免破坏表格结构

### Step 5: 确认文档插入锚点

```bash
lark-cli docs +fetch --doc "<doc_url_or_token>"
```

检查返回的 Markdown 中是否存在目标标题（如 `# 2026`）。如不存在，告知用户并询问新的插入位置。

### Step 6: 插入表格到文档

```bash
lark-cli docs +update \
  --doc "<doc_url_or_token>" \
  --mode insert_after \
  --selection-by-title "# <目标标题>" \
  --markdown "<组装好的表格 Markdown>"
```

> **模式选择**：
> - 首次插入用 `insert_after`（追加到标题章节末尾）
> - 如果标题下已有旧表格需要替换，用 `replace_range` + `--selection-by-title`

## 默认配置（当前用例）

| 配置项 | 值 |
|--------|---|
| 群名 | 微仁产品业务对接群 |
| 目标文档 | `https://bpl3y8iw2y.feishu.cn/docx/DtfEdgwzmo0hIAxQYLkcCvulnOc` |
| 插入锚点标题 | `# 2026` |
| 飞书域名 | `bpl3y8iw2y.feishu.cn` |

## 注意事项

- **身份选择**：全流程使用 `--as user`（默认），确保用户在目标群内且有文档编辑权限
- **消息类型**：Pin 消息可能包含图片、文件等非文本类型，表格中以占位符标注
- **大量 Pin**：Pin 数量超过 50 时需分批 mget，超过 200 条建议分表或截取最近 N 条
- **重复执行**：多次执行会重复插入。如需更新而非追加，应先用 `replace_range` 删除旧表格再插入

## 参考

- [lark-shared](../lark-shared/SKILL.md) — 认证、权限（必读）
- [lark-im](../lark-im/SKILL.md) — `+chat-search`、`+messages-mget`、pins API
- [lark-doc](../lark-doc/SKILL.md) — `+fetch`、`+update` 详细用法
