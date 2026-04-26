#!/usr/bin/env python3
"""
gen_article.py — 根据年月生成文章阅读周笔记框架

用法:
  python3 gen_article.py <年月> [options]
  python3 gen_article.py 202604
  python3 gen_article.py 202604 --dry-run
  python3 gen_article.py 202604 --vault-root /path/to/vault
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


def build_week_content(week_start: date, week_end: date, week_num: int) -> str:
    year = week_start.year
    month = week_start.month

    # 目录行
    toc_lines = []
    day = week_start
    while day <= week_end:
        toc_lines.append(f"- [{day.strftime('%m-%d')}](#{day.strftime('%Y-%m-%d')})")
        day += timedelta(days=1)

    # 每天的 section
    day_sections = []
    day = week_start
    while day <= week_end:
        day_sections.append(
            f"## {day.strftime('%Y-%m-%d')}\n\n"
            f"### \n\n"
            f"---\n"
        )
        day += timedelta(days=1)

    year_month = week_start.strftime("%Y%m")
    filename = f"文章阅读{year_month}-W{week_num}.md"

    return f"""---
title: 文章阅读{year_month}W{week_num}
date: {week_start.strftime('%Y-%m-%d')}
tags: []
category: 
cssclasses:
  - table-nowrap
---

# 文章阅读{year_month}-W{week_num}

## 目录

{chr(10).join(toc_lines)}

---

{chr(10).join(day_sections)}
"""


def main():
    parser = argparse.ArgumentParser(description="生成文章阅读周笔记框架")
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
    month_str = f"{month:02d}"
    output_dir = vault_root / "stock" / "文章笔记" / year_str / month_str

    print(f"Vault: {vault_root}")
    print(f"输出目录: {output_dir.relative_to(vault_root)}")
    print(f"月份: {year} 年 {month:02d} 月")
    print(f"周数: {len(weeks)}\n")

    for week_start, week_end, week_num in weeks:
        content = build_week_content(week_start, week_end, week_num)
        year_month = week_start.strftime("%Y%m")
        filename = f"文章阅读{year_month}-W{week_num}.md"
        target = output_dir / filename

        print(f"W{week_num}: {week_start.strftime('%m-%d')} ~ {week_end.strftime('%m-%d')} -> {year_str}/{month_str}/{filename}")

        if not args.dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
            print(f"  ✓ 已创建")
        else:
            print(f"  [DRY RUN] 未创建")

    print(f"\n完成: {'已创建' if not args.dry_run else '预览'}{len(weeks)} 个文件")


if __name__ == "__main__":
    main()
