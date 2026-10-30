"""P7 (SHOULD) — Replay 1 tháng mua hàng để demo incremental load (cùng F8).

Kế hoạch (CLAUDE.md mục 12):
1. Lấy từ landing gốc các dòng có purchase month = --month: orders, order_items, order_payments,
   order_reviews và customers liên quan.
2. Ghi thành file cùng tên vào data/landing/kaggle/brazilian-ecommerce/extract_date=<hôm nay>-replay-<month>/
   (thư mục mới → load_raw nạp như một batch mới, append).
3. Makefile `replay` chạy tiếp: upload_to_lake → load_raw → dbt build --select tag:incremental+

Để demo có ý nghĩa: bản load đầu nên cắt bỏ các tháng cuối (vd. --cutoff), rồi replay từng tháng.
"""
from __future__ import annotations

import argparse
import logging
import re

from ingestion.config import setup_logging

logger = logging.getLogger(__name__)


def run(month: str) -> None:
    if not re.fullmatch(r"\d{4}-\d{2}", month):
        raise ValueError("--month phải có dạng YYYY-MM")
    raise NotImplementedError(f"P7 replay_month chưa hiện thực (month={month}) — xem docstring")


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--month", required=True, help="Tháng mua hàng YYYY-MM")
    args = parser.parse_args()
    run(args.month)


if __name__ == "__main__":
    main()
