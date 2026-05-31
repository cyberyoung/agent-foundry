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
import json
import os
import re
import sys
from datetime import date, timedelta
from pathlib import Path
from urllib.request import Request, urlopen


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


CACHE_DIR = Path.home() / ".cache" / "gen-trading-note"


def fetch_holidays(year: int, force_refresh: bool = False) -> tuple[dict, str]:
    cache_file = CACHE_DIR / f"holidays_{year}.json"

    if cache_file.exists() and not force_refresh:
        from datetime import datetime
        mtime = cache_file.stat().st_mtime
        cache_date = datetime.fromtimestamp(mtime)
        cutoff = datetime(year - 1, 10, 1)
        if cache_date < cutoff:
            force_refresh = True

    if cache_file.exists() and not force_refresh:
        holidays = json.loads(cache_file.read_text(encoding="utf-8"))
        from datetime import datetime
        mtime = cache_file.stat().st_mtime
        cached_at = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
        return holidays, f"(缓存于 {cached_at})"

    url = f"https://timor.tech/api/holiday/year/{year}"
    req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        resp = urlopen(req, timeout=10)
        data = json.loads(resp.read())
    except Exception as e:
        print(f"  警告：获取节假日数据失败 ({e})，将只跳过周末")
        return {}, ""

    holidays = data.get("holiday", {})
    cache_file.parent.mkdir(parents=True, exist_ok=True)
    cache_file.write_text(json.dumps(holidays, ensure_ascii=False), encoding="utf-8")
    return holidays, "(已更新)"


def is_trading_day(day: date, holidays: dict) -> bool:
    key = day.strftime("%m-%d")
    info = holidays.get(key)
    if info is not None:
        return not info.get("holiday", False)
    return day.weekday() not in (5, 6)


TABLE_1 = """| 时间 | 品种 | 类型 | 价格 | 数量 | 仓位 | 交易成本 |
| --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |"""

POSITION_LINES = """
清仓：
建仓：
加仓：
减仓：
做T：
"""

TABLE_2 = """| 标的 | 成本 | 数量 | 仓位 | 当日盈亏金额 |
| --- | --- | --- | --- | ---: |
|  |  |  |  |  |"""

TABLE_3 = """| 标的 | 理由 | 盈亏原因 | 反思与改进 |
| --- | --- | --- | --- |
|  |  |  |  |"""

TABLE_4 = """| 标的 | 理由 | 反思与改进 |
| --- | --- | --- |
|  |  |  |"""


def build_day_section(day: date, second_table_override: str | None = None) -> str:
    t2 = second_table_override if second_table_override is not None else TABLE_2
    return f"""## {day.strftime('%Y-%m-%d')}

### 一、基本信息

#### 交易信息

{TABLE_1}
{POSITION_LINES}
#### 持仓信息

{t2}

{TABLE_4}

### 二、交易原因与分析

#### 市场环境分析

#### 交易标的分析

{TABLE_3}

### 三、备注

- 宏观经济环境：
- 市场情绪：
- 技术分析图图表：
- 相关资讯：
- 交易成本：


---
"""


def build_week_section(
    week_start: date,
    week_end: date,
    week_num: int,
    prev_second_table: str | None = None,
    first_day: date | None = None,
    holidays: dict | None = None,
) -> str:
    day_sections = []
    day = week_start
    while day <= week_end:
        if is_trading_day(day, holidays or {}):
            t2 = prev_second_table if (prev_second_table and first_day and day == first_day) else None
            day_sections.append(build_day_section(day, second_table_override=t2))
        day += timedelta(days=1)

    if not day_sections:
        return ""

    return f"""## W{week_num}

{chr(10).join(day_sections)}
"""


def extract_second_table_from_last_day(prev_file: Path) -> str | None:
    if not prev_file.exists():
        return None

    content = prev_file.read_text(encoding="utf-8")
    lines = content.split("\n")

    last_day_idx = None
    for i, line in enumerate(lines):
        if re.match(r"^## \d{4}-\d{2}-\d{2}", line):
            last_day_idx = i

    if last_day_idx is None:
        return None

    table_start = None
    for i in range(last_day_idx, len(lines)):
        if "| 标的 | 成本 | 数量 | 仓位 | 当日盈亏金额 |" in lines[i]:
            table_start = i
            break

    if table_start is None:
        return None

    table_lines = [lines[table_start]]
    if table_start + 1 < len(lines) and lines[table_start + 1].startswith("| ---"):
        table_lines.append(lines[table_start + 1])

    for j in range(table_start + 2, len(lines)):
        line = lines[j]
        if line.strip() == "" or line.startswith("#"):
            break
        if line.startswith("| 标的 | 理由"):
            break
        if line.startswith("|"):
            parts = line.split("|")
            if len(parts) >= 2:
                parts[-2] = " "
            table_lines.append("|".join(parts))

    return "\n".join(table_lines)


def build_month_content(
    year: int, month: int, weeks: list, prev_second_table: str | None = None, holidays: dict | None = None
) -> str:
    year_month = f"{year}{month:02d}"
    first_day = date(year, month, 1)

    week_sections = []
    for week_start, week_end, week_num in weeks:
        ws = build_week_section(
            week_start,
            week_end,
            week_num,
            prev_second_table=prev_second_table,
            first_day=first_day,
            holidays=holidays,
        )
        if ws:
            week_sections.append(ws)

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
    parser.add_argument("--force", action="store_true", help="覆盖已存在的文件")
    parser.add_argument("--vault-root", default=None, help="Vault 根路径")
    parser.add_argument("--refresh-holidays", action="store_true", help="强制刷新节假日缓存")
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

    holidays, cache_info = fetch_holidays(year, force_refresh=args.refresh_holidays)
    if holidays:
        holiday_names = {v.get("name", "?") for v in holidays.values() if v.get("holiday")}
        print(f"  ℹ 已加载 {year} 年节假日 {cache_info}: {', '.join(sorted(holiday_names))}")

    year_str = str(year)
    output_dir = vault_root / "stock" / "交易笔记" / year_str

    year_month = f"{year}{month:02d}"
    filename = f"交易笔记{year_month}.md"
    target = output_dir / filename

    if month == 1:
        prev_year, prev_month = year - 1, 12
    else:
        prev_year, prev_month = year, month - 1
    prev_filename = f"交易笔记{prev_year}{prev_month:02d}.md"
    prev_file = output_dir.parent / str(prev_year) / prev_filename

    prev_second_table = extract_second_table_from_last_day(prev_file)
    if prev_second_table:
        print(f"  ℹ 从上月 {prev_file.relative_to(vault_root)} 复制第二个表格")

    print(f"Vault: {vault_root}")
    print(f"输出目录: {output_dir.relative_to(vault_root)}")
    print(f"文件: {filename}")

    if not args.dry_run:
        if target.exists() and not args.force:
            print(f"错误：文件已存在，不会被覆盖: {target.relative_to(vault_root)}")
            print(f"      使用 --force 强制覆盖")
            sys.exit(1)
        content = build_month_content(year, month, weeks, prev_second_table, holidays)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        print(f"  ✓ 已创建")
    else:
        print(f"  [DRY RUN] 未创建")


if __name__ == "__main__":
    main()
