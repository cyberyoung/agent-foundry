#!/usr/bin/env python3
"""
gen_trading.py — 根据年月生成交易笔记月度框架

用法:
  python3 gen_trading.py <年月> [options]
  python3 gen_trading.py 202604
  python3 gen_trading.py 202604 --dry-run
  python3 gen_trading.py 202604 --vault-root /path/to/vault
"""

import argparse
import calendar
import sys
from datetime import date, timedelta
from pathlib import Path


def get_month_weeks(year: int, month: int) -> list[tuple[date, date, int]]:
    first_day = date(year, month, 1)
    last_day = date(year, month, calendar.monthrange(year, month)[1])

    weeks = []
    current_monday = first_day - timedelta(days=first_day.weekday())

    week_num = 1
    while current_monday <= last_day:
        week_end = current_monday + timedelta(days=6)
        seg_start = max(current_monday, first_day)
        seg_end = min(week_end, last_day)

        weeks.append((seg_start, seg_end, week_num))
        week_num += 1
        current_monday = week_end + timedelta(days=1)

        if week_num > 6:
            break

    return weeks


TRADING_TABLE = """| 时间 | 品种 | 类型 | 价格 | 数量 | 仓位 | 交易成本 |
| --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |

清仓：
建仓：
加仓：
减仓：
做T：

| 标的 | 成本 | 数量 | 仓位 | 当日盈亏金额 |
| --- | --- | --- | --- | ---: |
|  |  |  |  |  |
|  |  |  |  |  |

| 标的 | 理由 | 盈亏原因 | 反思与改进 |
| --- | --- | --- | --- |
|  |  |  |  |

| 标的 | 理由 | 反思与改进 |
| --- | --- | --- |
|  |  |  |

#### 二、交易原因与分析

- 市场环境分析：
- 交易标的分析：


#### 三、备注

- 宏观经济环境：
- 市场情绪：
- 技术分析图图表：
- 相关资讯：
- 交易成本：
"""


def build_day_section(day: date) -> str:
    return f"""## {day.strftime('%Y-%m-%d')}

#### 一、基本信息

{TRADING_TABLE}

---
"""


def build_week_section(week_start: date, week_end: date, week_num: int) -> str:
    day_sections = []
    day = week_start
    while day <= week_end:
        day_sections.append(build_day_section(day))
        day += timedelta(days=1)

    return f"""## W{week_num}

{chr(10).join(day_sections)}
"""


def build_month_content(year: int, month: int, weeks: list) -> str:
    year_month = f"{year}{month:02d}"
    week_sections = []
    for week_start, week_end, week_num in weeks:
        week_sections.append(build_week_section(week_start, week_end, week_num))

    return f"""---
title: 交易笔记{year_month}
date: {date(year, month, 1).strftime('%Y-%m-%d')}
tags: []
category:
cssclasses:
  - table-nowrap
---

# 交易笔记{year_month}


该买的时候不买，该卖的时候不卖

主升期唯唯诺诺 退潮期重拳出击

死也要死在主线上

辨识度

两段式(缠论?)、右底

2个下影线、均线缠绕、极致缩量

MACD背离、MA5走平、次级别走势结构

KD(指数如果有个大点的反弹，k值怎么也得破掉50吧？) KDJ RSI MACD GMMA

---

{chr(10).join(week_sections)}
"""


def main():
    parser = argparse.ArgumentParser(description="生成交易笔记月度框架")
    parser.add_argument("yearmonth", help="年月，格式 YYYYMM，如 202604")
    parser.add_argument("--dry-run", action="store_true", help="预览但不创建文件")
    parser.add_argument("--vault-root", default=None, help="Vault 根路径")
    args = parser.parse_args()

    ym = args.yearmonth
    if len(ym) != 6 or not ym.isdigit():
        print(f"错误：年月格式应为 YYYYMM，如 202604")
        sys.exit(1)
    year, month = int(ym[:4]), int(ym[4:])

    if args.vault_root:
        vault_root = Path(args.vault_root).expanduser().resolve()
    else:
        vault_root = Path.home() / "Documents" / "Obsidian Vault"
        if not vault_root.exists():
            print("错误：无法找到 vault，请用 --vault-root 指定")
            sys.exit(1)

    weeks = get_month_weeks(year, month)
    if not weeks:
        print(f"错误：未找到 {year} 年 {month:02d} 月的周信息")
        sys.exit(1)

    year_str = str(year)
    output_dir = vault_root / "stock" / "交易笔记" / year_str

    year_month = f"{year}{month:02d}"
    filename = f"交易笔记{year_month}.md"
    target = output_dir / filename

    print(f"Vault: {vault_root}")
    print(f"输出目录: {output_dir.relative_to(vault_root)}")
    print(f"文件: {filename}")

    if not args.dry_run:
        content = build_month_content(year, month, weeks)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        print(f"  ✓ 已创建")
    else:
        print(f"  [DRY RUN] 未创建")


if __name__ == "__main__":
    main()
