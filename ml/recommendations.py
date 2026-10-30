"""M7 (MUST) — Đề xuất cho 4 người ra quyết định (pha Choice).

Quy tắc trên output M3–M6 + KPI (CLAUDE.md mục 13):
- Logistics: tuyến cần sửa (late rate cao, volume lớn)
- Seller QM: seller cần cảnh báo / khen thưởng
- Commerce: category × region nên đầu tư
- CRM: danh sách khách nhận voucher
Ghi ml.recommendations(rec_id, decision_maker, subject_type, subject_id, action, rationale, score, status='proposed').
"""
from __future__ import annotations

import logging

from ingestion.config import setup_logging

logger = logging.getLogger(__name__)

MODEL_NAME = "recommendations"
MODEL_VERSION = "0.1.0"


def main() -> None:
    setup_logging()
    logger.warning("M7 %s: chưa hiện thực — bỏ qua (xem docstring)", MODEL_NAME)


if __name__ == "__main__":
    main()
