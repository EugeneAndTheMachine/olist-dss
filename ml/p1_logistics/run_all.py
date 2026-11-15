"""Chạy trọn bộ 3 module ML của bài toán P1 (Logistics Manager): ML-1a → ML-1b → ML-1c."""
from __future__ import annotations

import logging
import sys
from pathlib import Path

# Cho phép chạy trực tiếp bằng `python3 ml/p1_logistics/run_all.py`
_REPO_ROOT = str(Path(__file__).resolve().parents[2])
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

from ingestion.config import setup_logging
from ml.p1_logistics import courier_plan, hub_placement, late_risk

logger = logging.getLogger(__name__)


def run() -> None:
    logger.info("=== [P1] Bắt đầu ML-1a: Late-delivery risk model ===")
    lgbm_model, df_orders, m1a = late_risk.run()

    logger.info("=== [P1] Bắt đầu ML-1b: Hub placement (K-Means + PuLP p-median MILP) ===")
    m1b = hub_placement.run(lgbm_model=lgbm_model, df_orders=df_orders)

    logger.info("=== [P1] Bắt đầu ML-1c: Courier capacity plan ===")
    m1c = courier_plan.run()

    logger.info("=== [P1] Hoàn tất cả 3 module ML: ML-1a=%s | ML-1b=%s | ML-1c=%s ===", m1a, m1b, m1c)


def main() -> None:
    setup_logging()
    run()


if __name__ == "__main__":
    main()

