---
name: ob-image-captioner
description: Use when a user wants to add missing captions to embedded images in a single Obsidian note.
---

# Obsidian Image Captioner

给一篇 Obsidian 笔记里尚无说明的嵌入图片补充一行中文图片说明。

## 功能

- 扫描单篇 Obsidian `.md` 笔记中的 `![[...]]` 图片嵌入
- 只处理“没有说明”的图片，已有说明默认跳过
- 保守判断已有说明，避免覆盖用户原文
- 仅对缺失说明的图片做视觉识别
- 将生成的说明插入图片下方，并保留原有 Markdown 缩进和列表层级
- 支持 `--dry-run` 预览和 `--force` 强制重做

## 适用场景

- “给这篇笔记里的图片补说明”
- “把 Obsidian 笔记里没 caption 的图补一下”
- “补图片说明”
- “add captions to missing images in this note”

## 默认行为

- **默认只补缺失说明**
- 图片下方若已存在紧邻的说明性 bullet 或短段落，则视为已有说明，跳过
- 若图片内容模糊，使用保守描述，不编造细节

## 脚本入口

- 核心脚本：`scripts/caption_images_in_note.py`
- 包装脚本：`scripts/to_vault.sh`

## 工作流

### Step 1: 扫描目标笔记

先运行脚本扫描图片，找出：

- 已有说明的图片
- 缺失说明的图片
- 找不到文件的图片

推荐：

```bash
bash scripts/to_vault.sh "research/review-note.md" --dry-run
```

### Step 2: 仅对缺失说明图片做视觉识别

对 `pending-caption` 的图片逐张调用视觉工具，生成一行中文说明，格式如下：

```markdown
- <图片主题>：<1句结构化摘要。>
```

### Step 3: 通过 JSON 批量写回

将生成好的 caption 组织为 JSON 数组，再通过脚本 apply：

```json
[
  {
    "line_index": 948,
    "caption": "- 煤制油产业链全景图：主线是能源安全驱动下的煤制油价值重估。",
    "indent": ""
  }
]
```

然后执行：

```bash
bash scripts/to_vault.sh "research/review-note.md" --captions-json /tmp/captions.json
```

## 使用方式

### 直接扫描

```bash
python3 scripts/caption_images_in_note.py <note.md> --vault-root <vault-root> --dry-run
```

### 直接 apply

```bash
python3 scripts/caption_images_in_note.py <note.md> --vault-root <vault-root> --captions-json /tmp/captions.json
```

### 常用参数

- `--dry-run`：只扫描/预览，不写文件
- `--force`：即使已有说明，也将图片重新标记为待补说明
- `--vault-root <path>`：显式指定 vault 根目录
- `--captions-json <path>`：提供生成好的 caption 数据并执行写回

## 输出语义

扫描模式输出 JSON，至少包含：

- `summary.total_images`
- `summary.already_captioned`
- `summary.pending_captions`
- `summary.missing_images`
- `items[]`：逐图状态，含 `line_index`、`target`、`indent`、`image_path`

## 边界情况

- 图片文件不存在：跳过，并标记为 `missing-image`
- 同一张图片在同一笔记多次出现：按每个嵌入位置独立处理
- 图片位于编号列表/嵌套列表中：保留原缩进层级
- 已有较长说明：默认不改写
- 图像模糊或无法稳定识别：写保守说明，不虚构细节

## 注意事项

- 这个 skill 的**文件解析与写回是确定性的**，视觉识别只负责生成说明文本
- 不会移动图片，也不会修复图片路径；这类问题应交给 `ob-fix-image-paths`
- 不会总结整篇笔记，只处理缺失图片说明

## 回归测试

```bash
python3 -m unittest discover -s tests -v
```

当前覆盖重点：

- 常见 Obsidian 图片嵌入解析
- 已有说明/缺失说明判断
- 图片解析顺序与缺图处理
- 普通插入与嵌套列表缩进保留
- 默认幂等行为
- `--dry-run` 与 `--force`

## Public Release Notes

- The core public interface is `scripts/caption_images_in_note.py`.
- `scripts/to_vault.sh` is a local convenience wrapper for vault-relative note paths.
- Public-facing docs should describe this skill as a conservative single-note captioning workflow, not as a general image-analysis system.
