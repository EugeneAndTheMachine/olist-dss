"""Đưa các file nhóm tự chuẩn bị (data/raw/events_brazilstates/) vào landing.

- br_states.csv: state_code, state_name, region_name (nguồn bang & vùng cho dim_geography)
- calendar_events.csv: event_date, event_name, event_type (lễ quốc gia + sự kiện bán lẻ)

Kết quả: data/landing/manual/events_brazilstates/extract_date=YYYY-MM-DD/<file>.csv
"""
from __future__ import annotations

import argparse
import logging
import shutil

from ingestion.config import MANUAL_RAW_DIR, setup_logging, sources_for, today_extract_date

logger = logging.getLogger(__name__)


def run(extract_date: str) -> None:
    for src in sources_for("manual"):
        source_file = MANUAL_RAW_DIR / src.dataset / src.file_name
        target = src.landing_dir(extract_date) / src.file_name
        if target.is_file():
            logger.info("%s đã có trong landing, bỏ qua", target)
            continue
        if not source_file.is_file():
            logger.warning("Không thấy %s — bỏ qua nguồn %s", source_file, src.raw_table)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_file, target)
        logger.info("Copy %s → %s", source_file, target)


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--extract-date", default=today_extract_date())
    args = parser.parse_args()
    run(args.extract_date)


if __name__ == "__main__":
    main()
