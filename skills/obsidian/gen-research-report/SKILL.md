---
name: ob-gen-research-report
description: 当用户需要为指定月份生成研报周笔记框架时使用此 skill。
---

# ob-gen-research-report

根据年月参数，生成该月 W1~W5 研报周笔记文件框架，按 `YYYY/MM/` 目录组织。

## 文件组织

- 脚本：`scripts/gen_weekly.py`
- 模板（参考）：`vault/templates/研报周笔记模板.md`

## 输出结构

```
stock/调研笔记/
  YYYY/
    MM/
      研报阅读YYYYMM-W1.md
      研报阅读YYYYMM-W2.md
      ...
```

## 使用方式

### 命令行

```bash
# 生成指定月份的周笔记（如 202604）
bash scripts/gen_weekly.py 202604

# 预览（不创建文件）
bash scripts/gen_weekly.py 202604 --dry-run

# 指定 vault 路径
bash scripts/gen_weekly.py 202604 --vault-root /path/to/vault
```

### Skill 调用

用户说 `/ob-gen-research-report` 或 `/生成研报周笔记 202604` 时，加载此 skill 并执行脚本。

## 日期规则

- W1 从该月**第一个周一**开始，到周日结束
- 如果月首不是周一，W1 只包含该月实际存在的天
- 月末若不满一周，W5（最后一周）只包含实际天

## 依赖

- Python 3.10+
- 无外部包依赖
