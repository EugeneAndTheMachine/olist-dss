"""ML-1a: Mô hình dự đoán rủi ro giao trễ tại thời điểm đặt đơn (Logistics Manager — P1).

- Target: is_late (trên các đơn đã giao trong cửa sổ phân tích 2017-01-01 → 2018-08-31).
- Features chỉ dùng thông tin biết tại thời điểm mua (không dùng ngày giao hay ngày carrier thực tế):
  khoảng cách seller–customer, promised_lag, giá trị đơn, phí ship, tỷ lệ phí ship, số item,
  cùng bang (same_state), tỷ lệ giao trễ lịch sử của seller và của tuyến (tính chặt trước ngày mua),
  tháng mua, thứ trong tuần, tuần Black Friday.
- Chia train/test theo thời gian: train < 2018-06-01, test >= 2018-06-01 (BR-W4).
- So sánh Gradient Boosted Trees (LightGBM / HistGradientBoosting) với baseline Logistic Regression
  (ROC-AUC, PR-AUC, Recall@Top-10%).
- Ghi kết quả vào ml.order_late_risk và ml.late_risk_drivers; đăng ký vào meta.model_registry.
"""
from __future__ import annotations

import logging
import sys
import warnings
from pathlib import Path
from typing import Any

# Cho phép chạy trực tiếp bằng `python3 ml/p1_logistics/late_risk.py` hoặc `python3 -m ml.p1_logistics.late_risk`
_REPO_ROOT = str(Path(__file__).resolve().parents[2])
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.inspection import permutation_importance
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sqlalchemy import text

try:
    from lightgbm import LGBMClassifier

    HAS_LGBM = True
except (ImportError, OSError):
    LGBMClassifier = None  # type: ignore[assignment,misc]
    HAS_LGBM = False

from ingestion.config import get_settings, setup_logging
from ml.common.db import append_df, get_engine, read_sql
from ml.common.features import band, time_split
from ml.common.registry import new_run, register, tag_output
from ml.p1_logistics import ensure_p1_tables

logger = logging.getLogger(__name__)

MODEL_NAME = "p1_late_risk"
MODEL_VERSION = "1.0.0"
CUTOFF_DATE = "2018-06-01"

NUMERIC_FEATURES = [
    "seller_customer_distance_km",
    "promised_lag",
    "order_value",
    "freight_total",
    "freight_share",
    "item_count",
    "same_state",
    "seller_hist_late_rate",
    "route_hist_late_rate",
    "purchase_month",
    "purchase_dow",
    "is_black_friday_week",
]
CAT_FEATURES = ["seller_state", "customer_state"]
ALL_FEATURES = NUMERIC_FEATURES + CAT_FEATURES


def _table_exists(schema: str, table: str) -> bool:
    with get_engine().connect() as conn:
        reg = conn.execute(text("select to_regclass(:rel)"), {"rel": f"{schema}.{table}"}).scalar()
        return reg is not None


def load_order_dataset() -> pd.DataFrame:
    """Đọc dữ liệu đơn hàng từ dw.fact_order_fulfillment (hoặc fallback từ stg/raw nếu dw chưa build đủ)."""
    settings = get_settings()
    if _table_exists("dw", "fact_order_fulfillment") and _table_exists("dw", "dim_geography"):
        query = """
            select
                f.order_id,
                d.full_date as purchase_date,
                f.is_delivered,
                f.is_late,
                f.item_count,
                f.order_value::double precision as order_value,
                f.freight_total::double precision as freight_total,
                f.promised_lag::double precision as promised_lag,
                f.seller_customer_distance_km::double precision as seller_customer_distance_km,
                coalesce(sg.state_code, 'UNK') as seller_state,
                coalesce(cg.state_code, 'UNK') as customer_state,
                cg.latitude::double precision as customer_lat,
                cg.longitude::double precision as customer_lng,
                sg.latitude::double precision as seller_lat,
                sg.longitude::double precision as seller_lng,
                f.primary_seller_key::text as seller_id,
                coalesce(d.is_black_friday_week, false)::int as is_black_friday_week
            from dw.fact_order_fulfillment as f
            inner join dw.dim_date as d on f.purchase_date_key = d.date_key
            left join dw.dim_geography as cg on f.customer_geo_key = cg.geo_key
            left join dw.dim_geography as sg on f.seller_geo_key = sg.geo_key
            where f.is_delivered = 1
              and d.full_date between :start_date and :end_date
            order by d.full_date, f.order_id
        """
    else:
        logger.info("dw.fact_order_fulfillment chưa có, đọc trực tiếp từ stg_orders + stg_geolocation + raw")
        query = """
            with items as (
                select
                    order_id,
                    count(*) as item_count,
                    sum(nullif(trim(price), '')::double precision) as order_value,
                    sum(nullif(trim(freight_value), '')::double precision) as freight_total,
                    (array_agg(seller_id order by nullif(trim(price), '')::double precision desc, seller_id))[1] as seller_id
                from raw.order_items
                group by order_id
            ),
            cust as (
                select distinct on (customer_id)
                    customer_id,
                    lpad(trim(customer_zip_code_prefix), 5, '0') as customer_zip,
                    upper(trim(customer_state)) as customer_state
                from raw.customers
            ),
            sell as (
                select distinct on (seller_id)
                    seller_id,
                    lpad(trim(seller_zip_code_prefix), 5, '0') as seller_zip,
                    upper(trim(seller_state)) as seller_state
                from raw.sellers
            )
            select
                o.order_id,
                o.order_purchase_timestamp::date as purchase_date,
                o.is_delivered::int as is_delivered,
                o.is_late::int as is_late,
                coalesce(i.item_count, 1) as item_count,
                coalesce(i.order_value, 0.0) as order_value,
                coalesce(i.freight_total, 0.0) as freight_total,
                extract(epoch from (o.order_estimated_delivery_date - o.order_purchase_timestamp)) / 86400.0 as promised_lag,
                (2 * 6371 * asin(sqrt(
                    power(sin(radians(cg.latitude - sg.latitude) / 2), 2)
                    + cos(radians(sg.latitude)) * cos(radians(cg.latitude))
                    * power(sin(radians(cg.longitude - sg.longitude) / 2), 2)
                ))) as seller_customer_distance_km,
                coalesce(s.seller_state, sg.state_code, 'UNK') as seller_state,
                coalesce(c.customer_state, cg.state_code, 'UNK') as customer_state,
                cg.latitude as customer_lat,
                cg.longitude as customer_lng,
                sg.latitude as seller_lat,
                sg.longitude as seller_lng,
                coalesce(i.seller_id, 'UNK') as seller_id,
                (o.order_purchase_timestamp::date between '2017-11-20'::date and '2017-11-26'::date)::int as is_black_friday_week
            from stg.stg_orders as o
            left join items as i on o.order_id = i.order_id
            left join cust as c on o.customer_id = c.customer_id
            left join sell as s on i.seller_id = s.seller_id
            left join stg.stg_geolocation as cg on c.customer_zip = cg.zip_prefix
            left join stg.stg_geolocation as sg on s.seller_zip = sg.zip_prefix
            where o.is_delivered = true
              and o.order_purchase_timestamp::date between :start_date and :end_date
            order by o.order_purchase_timestamp, o.order_id
        """
    return read_sql(query, {"start_date": settings.analysis_start, "end_date": settings.analysis_end})


def engineer_features(df: pd.DataFrame) -> pd.DataFrame:
    """Tính các đặc trưng tại thời điểm mua (expanding mean có làm trơn Bayes, tránh data leakage)."""
    out = df.sort_values(["purchase_date", "order_id"]).reset_index(drop=True).copy()
    pdate = pd.to_datetime(out["purchase_date"])
    out["purchase_month"] = pdate.dt.month.astype(int)
    out["purchase_dow"] = pdate.dt.dayofweek.astype(int) + 1
    out["same_state"] = (out["seller_state"] == out["customer_state"]).astype(int)
    out["freight_share"] = np.where(
        out["order_value"] > 0,
        out["freight_total"] / (out["order_value"] + out["freight_total"]),
        0.0,
    )

    # Tỷ lệ giao trễ lịch sử (smoothed expanding mean trước đơn hiện tại, prior = 6.77%, weight = 10)
    prior_rate = float(out["is_late"].mean()) if len(out) else 0.0677
    prior_weight = 10.0

    seller_cum_orders = out.groupby("seller_id").cumcount().astype(float)
    seller_cum_late = out.groupby("seller_id")["is_late"].cumsum().astype(float) - out["is_late"].astype(float)
    out["seller_hist_late_rate"] = (seller_cum_late + prior_weight * prior_rate) / (seller_cum_orders + prior_weight)

    out["route_key"] = out["seller_state"].astype(str) + "_" + out["customer_state"].astype(str)
    route_cum_orders = out.groupby("route_key").cumcount().astype(float)
    route_cum_late = out.groupby("route_key")["is_late"].cumsum().astype(float) - out["is_late"].astype(float)
    out["route_hist_late_rate"] = (route_cum_late + prior_weight * prior_rate) / (route_cum_orders + prior_weight)
    return out


def recall_at_top_k(y_true: np.ndarray, y_score: np.ndarray, top_frac: float = 0.10) -> float:
    total_pos = float(np.sum(y_true))
    if total_pos == 0:
        return 0.0
    k = max(1, int(len(y_true) * top_frac))
    top_idx = np.argsort(y_score)[::-1][:k]
    return float(np.sum(y_true[top_idx]) / total_pos)


def build_pipelines() -> tuple[Pipeline, Pipeline]:
    preprocessor = ColumnTransformer(
        transformers=[
            ("num", Pipeline([("imputer", SimpleImputer(strategy="median")), ("scaler", StandardScaler())]), NUMERIC_FEATURES),
            ("cat", OneHotEncoder(handle_unknown="ignore", sparse_output=False), CAT_FEATURES),
        ]
    )
    baseline = Pipeline(
        [
            ("prep", preprocessor),
            ("clf", LogisticRegression(max_iter=500, class_weight="balanced", random_state=42)),
        ]
    )

    gbt_prep = ColumnTransformer(
        transformers=[
            ("num", SimpleImputer(strategy="median"), NUMERIC_FEATURES),
            ("cat", OneHotEncoder(handle_unknown="ignore", sparse_output=False), CAT_FEATURES),
        ]
    )
    if HAS_LGBM and LGBMClassifier is not None:
        clf = LGBMClassifier(
            n_estimators=200,
            learning_rate=0.05,
            num_leaves=31,
            min_child_samples=50,
            subsample=0.8,
            colsample_bytree=0.8,
            random_state=42,
            verbose=-1,
        )
    else:
        logger.info("macOS thiếu libomp.dylib cho lightgbm → dùng HistGradientBoostingClassifier (cùng thuật toán LightGBM)")
        clf = HistGradientBoostingClassifier(
            max_iter=200,
            learning_rate=0.05,
            max_leaf_nodes=31,
            min_samples_leaf=50,
            random_state=42,
        )

    gbt = Pipeline([("prep", gbt_prep), ("clf", clf)])
    return baseline, gbt


def _aggregate_feature_importance(gbt_pipe: Pipeline, X_val: pd.DataFrame, y_val: np.ndarray) -> pd.DataFrame:
    clf = gbt_pipe.named_steps["clf"]
    if HAS_LGBM and hasattr(clf, "booster_"):
        prep: ColumnTransformer = gbt_pipe.named_steps["prep"]
        raw_names = prep.get_feature_names_out()
        gains = clf.booster_.feature_importance(importance_type="gain").astype(float)
        grouped: dict[str, float] = {}
        for name, val in zip(raw_names, gains):
            if name.startswith("num__"):
                base_name = name.replace("num__", "")
            elif name.startswith("cat__seller_state"):
                base_name = "seller_state"
            elif name.startswith("cat__customer_state"):
                base_name = "customer_state"
            else:
                base_name = name
            grouped[base_name] = grouped.get(base_name, 0.0) + float(val)
    else:
        # Tính permutation importance trực tiếp trên từng cột gốc của X_val (lấy mẫu tối đa 5000 dòng để chạy nhanh)
        if len(X_val) > 5000:
            rng = np.random.default_rng(42)
            idx = rng.choice(len(X_val), size=5000, replace=False)
            X_sub = X_val.iloc[idx]
            y_sub = y_val[idx]
        else:
            X_sub = X_val
            y_sub = y_val
        perm = permutation_importance(gbt_pipe, X_sub, y_sub, scoring="roc_auc", n_repeats=3, random_state=42)
        grouped = {col: max(0.0, float(imp)) for col, imp in zip(ALL_FEATURES, perm.importances_mean)}

    df_imp = pd.DataFrame(
        [{"feature": k, "importance": round(v, 5)} for k, v in grouped.items()]
    ).sort_values("importance", ascending=False)
    total = float(df_imp["importance"].sum()) or 1.0
    df_imp["importance_pct"] = (df_imp["importance"] / total).round(5)
    return df_imp.reset_index(drop=True)


def run() -> tuple[Pipeline, pd.DataFrame, dict[str, Any]]:
    """Huấn luyện ML-1a, ghi ml.order_late_risk & ml.late_risk_drivers, trả về (model, df_features, metrics)."""
    warnings.filterwarnings("ignore", message="X does not have valid feature names")
    ensure_p1_tables()
    raw_df = load_order_dataset()
    df = engineer_features(raw_df)

    train_df, test_df = time_split(df, "purchase_date", CUTOFF_DATE)
    X_train, y_train = train_df[ALL_FEATURES], train_df["is_late"].to_numpy(dtype=int)
    X_test, y_test = test_df[ALL_FEATURES], test_df["is_late"].to_numpy(dtype=int)

    baseline, gbt = build_pipelines()
    baseline.fit(X_train, y_train)
    gbt.fit(X_train, y_train)

    base_prob = baseline.predict_proba(X_test)[:, 1]
    gbt_prob = gbt.predict_proba(X_test)[:, 1]

    metrics = {
        "engine": "lightgbm" if HAS_LGBM else "hist_gradient_boosting",
        "n_train": int(len(train_df)),
        "n_test": int(len(test_df)),
        "train_late_rate": round(float(y_train.mean()), 5),
        "test_late_rate": round(float(y_test.mean()), 5),
        "baseline_logistic_roc_auc": round(float(roc_auc_score(y_test, base_prob)), 4),
        "baseline_logistic_pr_auc": round(float(average_precision_score(y_test, base_prob)), 4),
        "baseline_recall_at_top10pct": round(recall_at_top_k(y_test, base_prob, 0.10), 4),
        "lgbm_roc_auc": round(float(roc_auc_score(y_test, gbt_prob)), 4),
        "lgbm_pr_auc": round(float(average_precision_score(y_test, gbt_prob)), 4),
        "lgbm_recall_at_top10pct": round(recall_at_top_k(y_test, gbt_prob, 0.10), 4),
    }
    logger.info("ML-1a metrics: %s", metrics)

    # Chấm điểm toàn bộ tập phân tích và ghi bảng ml.order_late_risk + ml.late_risk_drivers
    all_scores = gbt.predict_proba(df[ALL_FEATURES])[:, 1]
    q50, q85 = float(np.quantile(all_scores, 0.50)), float(np.quantile(all_scores, 0.85))
    scores_df = pd.DataFrame(
        {
            "order_id": df["order_id"],
            "risk_score": np.round(all_scores, 5),
            "risk_band": band(pd.Series(all_scores), cuts=(q50, q85)),
        }
    )
    drivers_df = _aggregate_feature_importance(gbt, X_test, y_test)

    model_run = new_run(MODEL_NAME, MODEL_VERSION)
    append_df(tag_output(scores_df, model_run), "order_late_risk")
    append_df(tag_output(drivers_df, model_run), "late_risk_drivers")
    register(
        model_run,
        train_window=f"{get_settings().analysis_start}..{CUTOFF_DATE} (test -> {get_settings().analysis_end})",
        params={"cutoff": CUTOFF_DATE, "n_estimators": 200, "learning_rate": 0.05, "num_leaves": 31},
        metrics=metrics,
    )

    print("\n" + "=" * 76)
    print(" [ML-1a] BENCHMARK DỰ ĐOÁN RỦI RO GIAO TRỄ TẠI THỜI ĐIỂM ĐẶT ĐƠN")
    print("=" * 76)
    print(f" Tập Train (< {CUTOFF_DATE}) : {metrics['n_train']:,} đơn (Tỷ lệ trễ: {metrics['train_late_rate']*100:.2f}%)")
    print(f" Tập Test  (>= {CUTOFF_DATE}): {metrics['n_test']:,} đơn (Tỷ lệ trễ: {metrics['test_late_rate']*100:.2f}%)")
    print("-" * 76)
    print(f" {'Mô hình':<36} | {'ROC-AUC':>9} | {'PR-AUC':>9} | {'Recall@Top10%':>13}")
    print("-" * 76)
    print(
        f" {'Baseline: Logistic Regression':<36} | "
        f"{metrics['baseline_logistic_roc_auc']:>9.4f} | "
        f"{metrics['baseline_logistic_pr_auc']:>9.4f} | "
        f"{metrics['baseline_recall_at_top10pct']*100:>12.2f}%"
    )
    print(
        f" {'Chính: Gradient Boosted Trees':<36} | "
        f"{metrics['lgbm_roc_auc']:>9.4f} | "
        f"{metrics['lgbm_pr_auc']:>9.4f} | "
        f"{metrics['lgbm_recall_at_top10pct']*100:>12.2f}%"
    )
    print("-" * 76)
    print(" Top 8 yếu tố gây giao trễ (Feature Importance):")
    print(drivers_df.head(8).to_string(index=False))
    print("=" * 76 + "\n")
    return gbt, df, metrics


def main() -> None:
    setup_logging()
    run()


if __name__ == "__main__":
    main()
