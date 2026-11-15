"""ML-1c: Dự báo nhu cầu giao hàng và xếp hạng ưu tiên bổ sung shipper theo bang (Logistics Manager — P1).

Thiết kế (docs/refactor_plan.md mục 6.1):
- Dự báo số đơn giao (delivered_orders) theo bang cho 3 tháng kế tiếp (2018-09, 2018-10, 2018-11)
  bằng C-M1 (`ml/common/forecasting.py`: `MODELS = ('naive', 'seasonal_naive', 'moving_average', 'ets')`,
  `fit_predict`, `rolling_origin`, `smape` trên cửa sổ 20 tháng 2017-01 → 2018-08).
- Ước tính số đơn trễ dự kiến = forecast_orders × current_late_rate.
- Điều chỉnh theo tỷ trọng thời gian vận chuyển (transit_share = Σ transit_lag / Σ delivery_lag):
  khu vực có transit_share cao bị trễ ở khâu vận chuyển nên hưởng lợi trực tiếp từ việc tăng shipper / kho;
  khu vực có transit_share thấp bị trễ ở khâu seller chuẩn bị hàng (dispatch).
- Số lượng shipper cần thiết được tính động trên Power BI từ What-if parameter [Deliveries Per Courier Per Day].
"""
from __future__ import annotations

import logging
import sys
from pathlib import Path
from typing import Any

# Cho phép chạy trực tiếp bằng `python3 ml/p1_logistics/courier_plan.py`
_REPO_ROOT = str(Path(__file__).resolve().parents[2])
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

import numpy as np
import pandas as pd
from sqlalchemy import text

from ingestion.config import get_settings, setup_logging
from ml.common.db import append_df, get_engine, read_sql
from ml.common.forecasting import BASELINES, MODELS, fit_predict, rolling_origin, smape
from ml.common.registry import new_run, register, tag_output
from ml.p1_logistics import ensure_p1_tables

logger = logging.getLogger(__name__)

MODEL_NAME = "p1_courier_plan"
MODEL_VERSION = "1.0.0"
HORIZON_MONTHS = 3
TRAIN_END = "2018-05-01"
ORIGINS = ["2017-12-01", "2018-01-01", "2018-02-01"]


def _mape(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    y_true, y_pred = np.asarray(y_true, dtype=float), np.asarray(y_pred, dtype=float)
    mask = y_true > 0
    if not np.any(mask):
        return float("nan")
    return float(np.mean(np.abs((y_true[mask] - y_pred[mask]) / y_true[mask])))


def _safe_predict(series: pd.Series, horizon: int, model: str, fallback: str = "moving_average") -> np.ndarray:
    try:
        return fit_predict(series, horizon, model)
    except ValueError as exc:
        logger.warning("fit_predict(%s) lỗi (%s), fallback sang %s", model, exc, fallback)
        return fit_predict(series, horizon, fallback)


def _table_exists(schema: str, table: str) -> bool:
    with get_engine().connect() as conn:
        reg = conn.execute(text("select to_regclass(:rel)"), {"rel": f"{schema}.{table}"}).scalar()
        return reg is not None


def load_monthly_state_delivery() -> pd.DataFrame:
    settings = get_settings()
    if _table_exists("dw", "fact_order_fulfillment") and _table_exists("dw", "dim_geography"):
        query = """
            select
                date_trunc('month', d.full_date)::date as month,
                cg.state_code,
                sum(f.is_delivered)::double precision as delivered_orders,
                sum(f.is_late)::double precision as late_orders,
                sum(f.transit_lag)::double precision as transit_lag_sum,
                sum(f.delivery_lag)::double precision as delivery_lag_sum
            from dw.fact_order_fulfillment as f
            inner join dw.dim_date as d on f.purchase_date_key = d.date_key
            inner join dw.dim_geography as cg on f.customer_geo_key = cg.geo_key
            where f.is_delivered = 1
              and cg.state_code is not null
              and cg.geo_key <> -1
              and d.full_date between :start_date and :end_date
            group by 1, 2
            order by 1, 2
        """
    else:
        query = """
            with cust as (
                select distinct on (customer_id)
                    customer_id,
                    upper(trim(customer_state)) as state_code
                from raw.customers
            )
            select
                date_trunc('month', o.order_purchase_timestamp)::date as month,
                c.state_code,
                count(*)::double precision as delivered_orders,
                sum(o.is_late::int)::double precision as late_orders,
                sum(
                    case
                        when o.order_delivered_customer_date >= o.order_delivered_carrier_date
                            then extract(epoch from (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400.0
                    end
                )::double precision as transit_lag_sum,
                sum(
                    case
                        when o.order_delivered_customer_date >= o.order_purchase_timestamp
                            then extract(epoch from (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0
                    end
                )::double precision as delivery_lag_sum
            from stg.stg_orders as o
            inner join cust as c on o.customer_id = c.customer_id
            where o.is_delivered = true
              and o.order_purchase_timestamp::date between :start_date and :end_date
            group by 1, 2
            order by 1, 2
        """
    return read_sql(query, {"start_date": settings.analysis_start, "end_date": settings.analysis_end})


def run() -> dict[str, Any]:
    ensure_p1_tables()
    df = load_monthly_state_delivery()
    df["month"] = pd.to_datetime(df["month"])

    all_months = pd.date_range(
        start=pd.to_datetime(get_settings().analysis_start).replace(day=1),
        end=pd.to_datetime(get_settings().analysis_end).replace(day=1),
        freq="MS",
    )
    future_months = pd.date_range(
        start=all_months[-1] + pd.DateOffset(months=1),
        periods=HORIZON_MONTHS,
        freq="MS",
    )

    states = sorted(df["state_code"].dropna().unique())
    bt_frames: list[pd.DataFrame] = []
    holdout_rows: list[dict[str, Any]] = []
    plan_rows: list[dict[str, Any]] = []

    for st in states:
        sub = df[df["state_code"] == st].set_index("month").reindex(all_months).fillna(0.0)
        series = sub["delivered_orders"]

        # 1. Rolling-origin validation trên tập train (2017-01..2018-05) theo đúng quy ước C-M1
        train_s = series[series.index <= TRAIN_END]
        bt = rolling_origin(train_s, ORIGINS, HORIZON_MONTHS, MODELS)
        bt_frames.append(bt.assign(state_code=st))

        # 2. Đánh giá holdout trên 3 tháng cuối (2018-06..2018-08)
        test_vals = series[series.index > TRAIN_END].to_numpy(dtype=float)
        if float(np.sum(test_vals)) >= 10:
            for m_name in MODELS:
                pred_vals = _safe_predict(train_s, HORIZON_MONTHS, m_name)
                holdout_rows.append(
                    {
                        "state_code": st,
                        "model": m_name,
                        "mape": _mape(test_vals, pred_vals),
                        "smape": smape(test_vals, pred_vals),
                    }
                )

        # 3. Tính late rate và transit share trên 12 tháng gần nhất của bang
        recent = sub.iloc[-12:]
        tot_deliv = float(recent["delivered_orders"].sum())
        tot_late = float(recent["late_orders"].sum())
        tot_transit = float(recent["transit_lag_sum"].sum())
        tot_delivery = float(recent["delivery_lag_sum"].sum())

        curr_late_rate = tot_late / tot_deliv if tot_deliv > 0 else 0.0
        transit_share = min(1.0, max(0.0, tot_transit / tot_delivery)) if tot_delivery > 0 else 0.75

        # 4. Dự báo 3 tháng tới (2018-09..2018-11) trên toàn bộ chuỗi 20 tháng bằng C-M1 fit_predict
        f_hat = _safe_predict(series, HORIZON_MONTHS, "ets", fallback="moving_average")
        for m_dt, yhat in zip(future_months, f_hat):
            exp_late = float(yhat) * curr_late_rate
            priority_score = exp_late * transit_share
            if exp_late >= 20 and transit_share >= 0.70:
                focus = "Add Couriers & Last-mile Capacity"
            elif exp_late >= 20 and transit_share < 0.70:
                focus = "Fix Seller Dispatch & Carrier Handover"
            else:
                focus = "Maintain Standard Capacity"

            plan_rows.append(
                {
                    "month": m_dt.date(),
                    "state_code": st,
                    "forecast_orders": round(float(yhat), 2),
                    "current_late_rate": round(curr_late_rate, 5),
                    "forecast_late_orders": round(exp_late, 2),
                    "transit_share": round(transit_share, 5),
                    "priority_score": round(priority_score, 4),
                    "recommended_focus": focus,
                }
            )

    bt_all = pd.concat(bt_frames, ignore_index=True)
    bt_per_state = (
        bt_all.groupby(["state_code", "model"])
        .apply(lambda d: smape(d["y"], d["yhat"]), include_groups=False)
        .rename("smape")
        .reset_index()
    )
    val_smape_median = bt_per_state.groupby("model")["smape"].median().round(4).to_dict()

    holdout_df = pd.DataFrame(holdout_rows)
    holdout_mape_mean = holdout_df.groupby("model")["mape"].mean().round(4).to_dict()
    holdout_smape_mean = holdout_df.groupby("model")["smape"].mean().round(4).to_dict()

    plan_df = pd.DataFrame(plan_rows)
    plan_df["priority_rank"] = (
        plan_df.groupby("month")["priority_score"]
        .rank(ascending=False, method="first")
        .astype(int)
    )
    plan_df = plan_df.sort_values(["month", "priority_rank"]).reset_index(drop=True)

    metrics = {
        "n_states": int(len(states)),
        "horizon_months": HORIZON_MONTHS,
        "rolling_origin_rows": int(len(bt_all)),
        "validation_smape_median": val_smape_median,
        "holdout_mape_mean": holdout_mape_mean,
        "holdout_smape_mean": holdout_smape_mean,
        "ets_holdout_mape": holdout_mape_mean.get("ets"),
        "baseline_ma3_holdout_mape": holdout_mape_mean.get("moving_average"),
        "ets_holdout_smape": holdout_smape_mean.get("ets"),
    }
    logger.info("ML-1c metrics: %s", metrics)

    model_run = new_run(MODEL_NAME, MODEL_VERSION)
    append_df(tag_output(plan_df, model_run), "courier_plan")
    register(
        model_run,
        train_window=f"{get_settings().analysis_start}..{get_settings().analysis_end}",
        params={
            "horizon_months": HORIZON_MONTHS,
            "origins": ORIGINS,
            "models": list(MODELS),
            "baselines": list(BASELINES),
        },
        metrics=metrics,
    )

    print("\n" + "=" * 86)
    print(" [ML-1c] BENCHMARK DỰ BÁO ĐƠN GIAO (C-M1) & KẾ HOẠCH TĂNG CƯỜNG SHIPPER THEO BANG")
    print("=" * 86)
    print(f" Số bang: {metrics['n_states']} | Horizon: {metrics['horizon_months']} tháng | Rolling-origin rows: {metrics['rolling_origin_rows']}")
    print(" Rolling-Origin Validation sMAPE (trung vị 27 bang, origins 2017-12..2018-02):")
    for m_name in MODELS:
        print(f"   - {m_name:<16}: sMAPE median = {val_smape_median.get(m_name, float('nan')):.3f}")
    print(" Holdout Test (2018-06..2018-08):")
    for m_name in MODELS:
        print(
            f"   - {m_name:<16}: MAPE = {holdout_mape_mean.get(m_name, float('nan'))*100:6.2f}% | "
            f"sMAPE = {holdout_smape_mean.get(m_name, float('nan'))*100:6.2f}%"
        )
    print("-" * 86)
    first_month = plan_df["month"].min()
    print(f" Top 10 bang ưu tiên bổ sung Shipper tháng {first_month}:")
    top10 = plan_df[plan_df["month"] == first_month].head(10)
    print(
        top10[
            [
                "priority_rank",
                "state_code",
                "forecast_orders",
                "current_late_rate",
                "forecast_late_orders",
                "transit_share",
                "priority_score",
                "recommended_focus",
            ]
        ].to_string(index=False)
    )
    print("=" * 86 + "\n")
    return metrics


def main() -> None:
    setup_logging()
    run()


if __name__ == "__main__":
    main()
