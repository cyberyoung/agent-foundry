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
- 正文：每张图片一行 `![[filename]]`

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
