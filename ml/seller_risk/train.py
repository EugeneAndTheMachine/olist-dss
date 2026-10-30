"""M6 (COULD) — Rủi ro seller + giá trị kênh. Người dùng: Seller Quality Manager.

Các bước (CLAUDE.md mục 13):
1. Xác suất seller thành At-risk hoặc ngừng bán trong 2 tháng tới (logistic/LightGBM trên dw.fact_seller_month).
2. Channel value (mô tả): conversion và gmv_first_90_days theo origin từ dw.fact_lead_funnel.
3. Ghi ml.seller_risk_score, ml.channel_value; register().
"""
from __future__ import annotations

import logging

from ingestion.config import setup_logging

logger = logging.getLogger(__name__)

MODEL_NAME = "seller_risk"
MODEL_VERSION = "0.1.0"


def main() -> None:
    setup_logging()
    logger.warning("M6 %s: chưa hiện thực — bỏ qua (xem docstring)", MODEL_NAME)


if __name__ == "__main__":
    main()
