---
name: ob-collect-images
description: "扫描指定目录下所有笔记中的图片，按主题分类汇总到 stock/逻辑技术沉淀/ 下。触发词：'收集图片到笔记'、'图片分类汇总'、'扫描图片归类'、'collect images'。当用户要求把某个目录下的图片按主题整理成 Obsidian 笔记时使用。"
---

# ob-collect-images

扫描指定目录下所有笔记中的 `![[...]]` 图片嵌入，按主题分类，汇总到 `stock/逻辑技术沉淀/` 下独立笔记中。

## 功能

- 递归扫描目录下所有 `.md` 笔记中的图片嵌入
- 提取每张图片的上下文（所在标题、前后文本、已有 caption）
- AI 按主题分类（合并相近主题，不要太散）
- 在 `stock/逻辑技术沉淀/` 创建/追加分类笔记
- 图片使用 `../` 相对路径引用

## 分类合并原则

分类时合并相近主题，避免太散：

| 可以合并的示例 | 合并后分类 |
|---|---|
| 光模块 + 光通信 + 光设备 + CPO + 硅光 | 光通信光模块设备 |
| 半导体设备 + 半导体材料 + 先进封装 + TGV | 半导体设备材料 |
| 液冷 + 电源 + 算力租赁 | 数据中心基础设施 |
| AI芯片 + 昇腾 + TPU + GTC产业链 | AI算力芯片产业链 |
| 煤化工 + 煤制油 + 铜 + 尿素 + 氦气 + 化工 | 能源化工资源品 |

如果某个分类只有 1-2 张图片，合并到最接近的大类或归入"其他产业图集"。

## Agent 工作流

### Step 1: 扫描提取

运行扫描脚本，提取目录下所有图片引用及上下文：

```bash
python3 scripts/scan_images.py <source-dir> --vault-root <vault-root> --dry-run
```

输出 JSON，每张图片包含：
- `source_file`: 来源笔记文件名
- `line_index`: 行号
- `image_target`: 图片原始引用路径（从来源笔记）
- `resolved`: 图片在 vault 中的绝对路径
- `relative_path`: 从输出目录引用图片的相对路径
- `context`: 上下文（标题层级 + 前后文本摘要）
- `context.existing_caption`: 已有 caption（如有）

### Step 2: AI 分类

Agent 根据上下文对每张图片分类。对无上下文或上下文不明确的图片，用 Read 工具读取图片内容判断主题。

分类输出格式：

```json
{
  "category": "分类名称",
  "subcategory": "子分类（可选）",
  "caption": "图片说明（一行中文）"
}
```

### Step 3: 写入笔记

对每个分类，检查 `stock/逻辑技术沉淀/<分类名>.md` 是否已存在：

- **不存在**：创建新笔记（含 YAML frontmatter）
- **已存在**：追加新图片到对应子分类 section 末尾

使用脚本写入：

```bash
python3 scripts/scan_images.py <source-dir> --vault-root <vault-root> --write <classified-json>
```

## 笔记格式

```markdown
---
title: <分类名>
date: YYYY-MM-DD
tags:
  - <tag1>
  - <tag2>
category: 逻辑技术沉淀
---

# <分类名>

<一句话说明>

---

## <子分类>

![[../<从逻辑技术沉淀到图片的相对路径>]]
> <图片说明> — 来源：[[<来源笔记文件名>]]
```

## 图片路径规则

从 `stock/逻辑技术沉淀/` 引用图片时，使用相对路径：

```
../调研笔记/2026/04/assets/研报阅读202604-W3/xxx.webp
```

脚本 `relative_path` 会计算正确的相对路径。

## 增量追加

笔记已存在时：

1. 提取已有 `![[...]]` 链接
2. 只追加尚未收录的新图片
3. 追加到对应子分类 section 末尾，不修改已有内容
4. 如果子分类 section 不存在，在 `---` 分隔线后追加新 section

## 脚本路径

- 核心脚本：`scripts/scan_images.py`
- 本地包装脚本：`scripts/to_vault.sh`

## 使用方式

```bash
# 扫描预览
python3 scripts/scan_images.py <source-dir> --vault-root <vault-root> --dry-run

# 扫描并写入
python3 scripts/scan_images.py <source-dir> --vault-root <vault-root> --write <classified-json>

# 包装脚本（自动检测 vault）
bash scripts/to_vault.sh <source-dir> --dry-run
```

## 可选参数

```
--dry-run         预览模式，只扫描不写入
--write <json>    提供分类 JSON 并执行写入
--output-dir      输出目录（默认 stock/逻辑技术沉淀/）
--vault-root      指定 vault 根目录
```

## 依赖

- Python 3.10+
- 无外部包依赖
