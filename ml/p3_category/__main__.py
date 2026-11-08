"""Chạy P3: python -m ml.p3_category (make ml-p3). Forecast trước, portfolio dùng đúng run forecast vừa ghi."""
from __future__ import annotations

from ingestion.config import setup_logging
from ml.common.db import read_sql
from ml.p3_category import category_forecast, category_portfolio
from ml.p3_category.features import load_monthly, load_seller_gmv


def main() -> None:
    setup_logging()
    for table in ("category_forecast", "category_opportunity"):
        if not read_sql("select to_regclass(:t) is not null as ok", {"t": f"ml.{table}"}).loc[0, "ok"]:
            raise RuntimeError(f"ml.{table} chưa có: chạy make db-init (docker/postgres/init/03_ml_p3.sql)")
    monthly, seller_gmv = load_monthly(), load_seller_gmv()
    forecast_run = category_forecast.run(monthly)
    category_portfolio.run(monthly, seller_gmv, forecast_run.model_run_id)


if __name__ == "__main__":
    main()
