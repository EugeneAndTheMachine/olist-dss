"""P4 — Sinh danh sách ngày lễ quốc gia Brazil 2016–2019 bằng package `holidays`.

Kết quả: data/landing/holidays/br_holidays/extract_date=YYYY-MM-DD/br_holidays.csv (holiday_date, holiday_name)
"""
from __future__ import annotations

import argparse
import csv
import logging

import holidays

from ingestion.config import setup_logging, sources_for, today_extract_date

logger = logging.getLogger(__name__)

YEARS = range(2016, 2020)


def run(extract_date: str) -> None:
    src = sources_for("holidays", "br_holidays")[0]
    target = src.landing_dir(extract_date) / src.file_name
    if target.is_file():
        logger.info("%s đã có trong landing, bỏ qua", target)
        return
    br = holidays.Brazil(years=YEARS)
    rows = sorted(br.items())
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["holiday_date", "holiday_name"])
        writer.writerows((d.isoformat(), name) for d, name in rows)
    logger.info("Ghi %d ngày lễ vào %s", len(rows), target)


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--extract-date", default=today_extract_date())
    args = parser.parse_args()
    run(args.extract_date)


if __name__ == "__main__":
    main()
