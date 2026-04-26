---
name: ob-images-to-note
description: "Generate an Obsidian note from all images in a directory, sorted by filename. Use this skill when the user asks to collect images into a note, create a photo index, or embed a folder of images into Obsidian. Triggers include: '把图片整理成笔记', '图片目录生成笔记', 'images to note', 'embed images from folder', or any request to create a note from a directory of photos/images. Handles HEIC conversion to JPG via macOS sips."
---

# Obsidian Images to Note

扫描目录下的所有图片，按文件名排序后嵌入到一篇 Obsidian 笔记中。

## 功能

- 扫描目录下所有图片文件（jpg, png, gif, webp, heic 等）
- 按文件名排序（不区分大小写）
- HEIC 文件默认通过 macOS `sips` 转换为 JPG
- 生成带 YAML frontmatter 的 `.md` 笔记
- 笔记文件名 = 目录名
- **增量追加**：已有笔记只追加新图片，保留原有内容和顺序
- 自动生成图片标题（从文件名提取时间戳或使用文件名）

## 增量追加策略

当笔记已存在时：

1. **提取已有图片**：识别笔记中已嵌入的 `![[filename]]` 链接
2. **计算新增图片**：对比目录图片与已有图片，筛选新增
3. **追加到末尾**：新图片追加到文件末尾，不修改已有内容
4. **无新图片时跳过**：提示用户所有图片已嵌入

新图片追加格式：

```markdown
## 2026-02-11 16:04:42
![[IMG_20260211_160442.jpg]]
```

标题自动提取：
- `IMG_YYYYMMDD_HHMMSS.jpg` → `YYYY-MM-DD HH:MM:SS`
- `IMG_YYYYMMDD.jpg` → `YYYY-MM-DD`
- 其他文件名 → 使用文件名 stem

## Agent 工作流

当用户调用此 skill 但未提供目录路径参数时：

1. **使用 `question` 工具弹窗提示用户输入目录路径**
2. 提示信息示例："请输入需要处理的图片目录路径（支持 vault 相对路径或绝对路径）"
3. 获取用户输入后，继续执行脚本

示例交互：
```
用户: /ob-images-to-note
AI: [使用 question 工具弹窗]
用户输入: research/photos/my-photos
AI: 执行脚本处理该目录
```

当用户已提供目录路径时，直接执行脚本，无需弹窗。

## 脚本路径

`scripts/images_to_note.py`

快捷包装脚本：

`scripts/to_vault.sh`

## 使用方式

```bash
python3 scripts/images_to_note.py <目录路径> [选项]
```

## 本地方便包装脚本

```bash
bash scripts/to_vault.sh <目录路径> [选项]
```

示例：

```bash
bash scripts/to_vault.sh "research/photos/report-images"

bash scripts/to_vault.sh "research/photos/report-images" --dry-run

bash scripts/to_vault.sh "research/photos/report-images" --keep-heic
```

说明：

- 输出基准库目录：优先使用 `$OBSIDIAN_VAULT`，否则 wrapper 使用本地默认 vault 路径
- 支持 vault 相对路径和绝对路径

## 可选参数

```
--keep-heic       直接嵌入 HEIC 文件，不转换为 JPG（需 Obsidian 插件支持）
--remove-heic     转换后删除 HEIC 原始文件
--dry-run         预览模式，不写入任何文件
```

## 输出格式

- 文件名：`<目录名>.md`
- Frontmatter 字段：`title`、`date`、`tags`、`category`
- 新建笔记：每张图片包含 H2 标题 + 嵌入链接
- 追加图片：在文件末尾追加 H2 标题 + 嵌入链接

示例：

```markdown
---
title: 研报
date: 2026-03-09
tags:
  - paper-notes
category: 纸质笔记
---

# 研报

## 2026-02-11 16:04:42
![[IMG_20260211_160442.jpg]]

## IMG_9609
![[IMG_9609.jpg]]
```

## HEIC 处理策略

默认行为：HEIC → JPG 转换（使用 macOS 原生 `sips` 命令）

- `--keep-heic`：跳过转换，直接嵌入 `.HEIC`（依赖 image-converter 插件）
- `--remove-heic`：转换后删除 `.HEIC` 原始文件

## 依赖

- Python 3.10+
- macOS `sips`（HEIC 转换，系统自带）

## Public Release Notes

- The core public interface is `scripts/images_to_note.py`.
- `scripts/to_vault.sh` is a local convenience wrapper for vault-relative paths.
- Public-facing docs should state clearly that HEIC conversion currently depends on macOS `sips`.
