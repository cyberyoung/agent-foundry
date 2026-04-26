---
name: ob-gen-trading-note
description: 当用户需要为指定月份生成交易笔记框架时使用此 skill。
---

# ob-gen-trading-note

根据年月参数，生成交易笔记月度框架，按 `YYYY/` 目录组织。

## 文件组织

- 脚本：`scripts/gen_trading.py`
- 模板（参考）：`vault/templates/交易笔记模板.md`

## 输出结构

```
stock/交易笔记/
  YYYY/
    交易笔记YYYYMM.md
```

## 使用方式

### 命令行

```bash
# 生成指定月份的交易笔记（如 202604）
bash scripts/gen_trading.py 202604

# 预览（不创建文件）
bash scripts/gen_trading.py 202604 --dry-run

# 指定 vault 路径
bash scripts/gen_trading.py 202604 --vault-root /path/to/vault
```

### Skill 调用

用户说 `/ob-gen-trading-note` 或 `/生成交易笔记 202604` 时，加载此 skill 并执行脚本。

## 日期规则

- W1 从该月**第一个周一**开始，到周日结束
- 如果月首不是周一，W1 只包含该月实际存在的天
- 月末若不满一周，W5（最后一周）只包含实际天

## 依赖

- Python 3.10+
- 无外部包依赖
