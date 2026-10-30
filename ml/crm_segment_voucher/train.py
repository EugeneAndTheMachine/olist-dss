"""M4 (MUST) — Phân khúc khách + phân bổ voucher. Người dùng: CRM Manager.

Các bước (CLAUDE.md mục 13):
1. RFM theo customer_unique_id + trải nghiệm (had_late, low_review ≤ 2) → segment bằng quy tắc hoặc KMeans.
2. Điểm ưu tiên / propensity (nếu đủ positive — tỷ lệ mua lặp rất thấp, xem A7).
3. PuLP: max Σ p_i × uplift_seg × value_i − cost, ràng buộc tổng ngân sách + trần mỗi segment.
   uplift_seg là GIẢ ĐỊNH (tham số what-if), chạy cho nhiều mức budget → scenario_id.
4. Ghi ml.customer_segment_history, ml.voucher_allocation; register().
"""
from __future__ import annotations

import logging

from ingestion.config import setup_logging

logger = logging.getLogger(__name__)

MODEL_NAME = "crm_segment_voucher"
MODEL_VERSION = "0.1.0"


def main() -> None:
    setup_logging()
    logger.warning("M4 %s: chưa hiện thực — bỏ qua (xem docstring)", MODEL_NAME)


if __name__ == "__main__":
    main()
