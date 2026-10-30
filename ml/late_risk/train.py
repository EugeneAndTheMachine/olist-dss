"""M3 (MUST) — Rủi ro giao trễ + promise-date what-if. Người dùng: Logistics & CX Manager.

Các bước (CLAUDE.md mục 13):
1. Đọc dw.fact_order_fulfillment + dims; feature tại thời điểm mua: distance_km, seller late rate lịch sử
   (trước ngày mua), tuyến seller_state → customer_state, category_group, weight/volume, freight_value,
   promised_lag, tháng, is_black_friday_week. KHÔNG dùng delivered date (leakage).
2. time_split; baseline logistic regression vs LightGBM; metric ROC-AUC, PR-AUC, recall@top-10%.
3. Ghi ml.order_late_risk (risk_score, risk_band).
4. ml.promise_whatif: buffer_days ∈ [-5..+7], tính lại is_late nếu estimated + buffer, theo tuyến.
5. register() vào meta.model_registry.
"""
from __future__ import annotations

import logging

from ingestion.config import setup_logging

logger = logging.getLogger(__name__)

MODEL_NAME = "late_risk"
MODEL_VERSION = "0.1.0"


def main() -> None:
    setup_logging()
    logger.warning("M3 %s: chưa hiện thực — bỏ qua (xem docstring)", MODEL_NAME)


if __name__ == "__main__":
    main()
