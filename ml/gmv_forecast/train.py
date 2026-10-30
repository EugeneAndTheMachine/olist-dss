"""M5 (SHOULD) — Dự báo GMV theo category_group × region_name. Người dùng: Head of Commerce.

Các bước (CLAUDE.md mục 13):
1. GMV tháng từ dw.fact_order_item (counts_as_sale) join dim_product, dim_geography (customer).
2. Train 2017-01 → 2018-05, test 3 tháng cuối; baseline seasonal-naive vs ETS/SARIMA (statsmodels); MAPE.
3. Ghi ml.gmv_forecast (yhat, yhat_lower, yhat_upper); register().
Growth what-if = forecast × (1 + growth%) làm trong Power BI.
"""
from __future__ import annotations

import logging

from ingestion.config import setup_logging

logger = logging.getLogger(__name__)

MODEL_NAME = "gmv_forecast"
MODEL_VERSION = "0.1.0"


def main() -> None:
    setup_logging()
    logger.warning("M5 %s: chưa hiện thực — bỏ qua (xem docstring)", MODEL_NAME)


if __name__ == "__main__":
    main()
