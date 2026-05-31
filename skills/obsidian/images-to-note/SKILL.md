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

### 流程

1. **使用 `question` 工具弹窗**，提供三个选项：
   - "处理默认目录（观点 + 研报）" (Recommended)
   - "手动输入目录路径"
   - "取消"
2. **用户选择"处理默认目录"** → 弹窗确认，列出将处理的目录：
   - `stock/Inbox/纸质笔记/观点/`
   - `stock/Inbox/纸质笔记/研报/`
   用户确认后，依次执行两个目录的脚本。
3. **用户选择"手动输入目录路径"** → 弹窗提示："请输入需要处理的图片目录路径（支持 vault 相对路径或绝对路径）"，获取输入后执行脚本。
4. **用户选择"取消"** → 终止操作。

### 默认目录

未提供路径时的默认处理目录（必须在处理前获得用户确认）：

| 目录 | 完整路径 |
|------|----------|
| 观点 | `stock/Inbox/纸质笔记/观点/` |
| 研报 | `stock/Inbox/纸质笔记/研报/` |

### 示例交互

**默认目录场景：**
```
用户: /ob-images-to-note
AI: [question 弹窗：处理默认目录 / 手动输入 / 取消]
用户: 处理默认目录
AI: [question 弹窗确认：将处理 观点 和 研报 两个目录]
用户: 确认
AI: 依次执行 to_vault.sh 处理两个目录
```

**手动输入场景：**
```
用户: /ob-images-to-note
AI: [question 弹窗：处理默认目录 / 手动输入 / 取消]
用户: 手动输入
AI: [question 弹窗：请输入路径]
用户: research/photos/my-photos
AI: 执行脚本处理该目录
```

当用户已提供目录路径时（如 `@stock/Inbox/纸质笔记/观点/`），直接执行脚本，无需弹窗。

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
