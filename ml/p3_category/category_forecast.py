"""ML-3a — dự báo GMV 3 tháng cho category đủ dày và cho nhóm category (BR-P3-7).

Model mỗi level chọn bằng rolling-origin trong train (origin 2017-12, 2018-01, 2018-02, horizon 3, mọi tháng dự báo
≤ 2018-05). Test 2018-06..08 chấm model chọn và từng baseline một lần. Quy tắc định trước (phase 5): model chọn không
thắng baseline tốt nhất theo validation trên test thì level đó dự báo bằng baseline ấy; khi đó sMAPE test của model
đang dùng không còn là holdout sạch. Khoảng = quantile 10/90 của actual / yhat trong rolling-origin, theo bước.
"""
from __future__ import annotations

import logging

import numpy as np
import pandas as pd

from ml.common.forecasting import BASELINES, MODELS, fit_predict, rolling_origin, smape
from ml.common.registry import ModelRun, new_run, register, tag_output
from ml.common.db import append_df

logger = logging.getLogger(__name__)

MODEL_NAME = "p3_category_forecast"
MODEL_VERSION = "0.1.0"
TRAIN_START, TRAIN_END = "2017-01-01", "2018-05-01"
TEST_END = "2018-08-01"
ORIGINS = ["2017-12-01", "2018-01-01", "2018-02-01"]
HORIZON = 3
MIN_MONTHLY_ORDERS = 10  # BR-P3-7


def build_series(monthly: pd.DataFrame) -> list[dict]:
    """Series GMV theo tháng: category có ≥ 10 đơn mọi tháng train, và 11 nhóm (không dự báo Unknown)."""
    window = monthly[(monthly["month_date"] >= TRAIN_START) & (monthly["month_date"] <= TEST_END)]
    months = pd.date_range(TRAIN_START, TEST_END, freq="MS")
    train_months = months[months <= TRAIN_END]
    out = []

    rankable = window[window["is_rankable"] == 1]
    for key, g in rankable.groupby("category_key"):
        orders = g.set_index("month_date")["orders"].reindex(months, fill_value=0)
        if (orders.loc[train_months] >= MIN_MONTHLY_ORDERS).all():
            out.append({
                "category_level": "category", "category_code": g["category_pt"].iat[0], "category_key": int(key),
                "category_group": g["category_group"].iat[0], "sparse": False,
                "y": g.set_index("month_date")["gmv"].reindex(months, fill_value=0).astype(float),
            })

    grouped = window[window["category_group"] != "Unknown"].groupby(["category_group", "month_date"])[["gmv", "orders"]].sum()
    for group, g in grouped.groupby(level=0):
        g = g.droplevel(0)
        orders = g["orders"].reindex(months, fill_value=0)
        out.append({
            "category_level": "group", "category_code": group, "category_key": -1, "category_group": group,
            "sparse": bool((orders.loc[train_months] < MIN_MONTHLY_ORDERS).any()),
            "y": g["gmv"].reindex(months, fill_value=0).astype(float),
        })
    return out


def mape(y, yhat) -> float:
    y, yhat = np.asarray(y, float), np.asarray(yhat, float)
    ok = y > 0
    return float(np.mean(np.abs(y[ok] - yhat[ok]) / y[ok])) if ok.any() else float("nan")


def select_models(series: list[dict]) -> tuple[dict[str, str], pd.DataFrame, pd.DataFrame]:
    """Model theo level từ rolling-origin trong train; trả kèm lỗi validation để dựng khoảng tin cậy."""
    rows = []
    for s in series:
        train = s["y"][s["y"].index <= TRAIN_END]
        bt = rolling_origin(train, ORIGINS, HORIZON, MODELS)
        rows.append(bt.assign(category_level=s["category_level"], category_code=s["category_code"]))
    val = pd.concat(rows, ignore_index=True)
    per_series = val.groupby(["category_level", "category_code", "model"]).apply(
        lambda d: smape(d["y"], d["yhat"]), include_groups=False
    ).rename("smape").reset_index()
    by_level = per_series.groupby(["category_level", "model"])["smape"].mean().unstack()
    chosen = by_level.idxmin(axis=1).to_dict()
    return chosen, by_level, val


def interval_ratios(val: pd.DataFrame, model: str) -> pd.DataFrame:
    v = val[(val["model"] == model) & (val["yhat"] > 0)].assign(ratio=lambda d: d["y"] / d["yhat"])
    return v.groupby(["category_level", "step"])["ratio"].quantile([0.1, 0.9]).unstack()


def model_for(s: dict, level_models: dict[str, str], best_baseline: dict[str, str]) -> str:
    """Chuỗi thưa (có tháng train < 10 đơn) không dùng model có trend; dùng baseline tốt nhất theo validation."""
    model = level_models[s["category_level"]]
    if s["sparse"] and model not in BASELINES:
        return best_baseline[s["category_level"]]
    return model


def safe_predict(history: pd.Series, horizon: int, model: str, fallback: str, code: str) -> tuple[np.ndarray, str]:
    try:
        return fit_predict(history, horizon, model), model
    except Exception:
        logger.warning("%s: %s lỗi, dùng %s", code, model, fallback, exc_info=True)
        return fit_predict(history, horizon, fallback), fallback


def forecast_rows(s: dict, history: pd.Series, months: pd.DatetimeIndex, model: str, fallback: str,
                  ratios_by_model: dict[str, pd.DataFrame], is_backtest: int) -> list[dict]:
    yhat, used = safe_predict(history, len(months), model, fallback, s["category_code"])
    ratios = ratios_by_model[used]
    out = []
    for step, (month, value) in enumerate(zip(months, yhat), start=1):
        q = ratios.loc[(s["category_level"], step)] if (s["category_level"], step) in ratios.index else None
        out.append({
            "month": month.date(), "category_level": s["category_level"], "category_code": s["category_code"],
            "category_key": s["category_key"], "category_group": s["category_group"], "metric": "gmv",
            "yhat": float(value),
            "yhat_lower": float(value * q[0.1]) if q is not None else None,
            "yhat_upper": float(value * q[0.9]) if q is not None else None,
            "model_name": used, "is_backtest": is_backtest, "is_sparse": int(s["sparse"]),
            "actual": float(s["y"].loc[month]) if is_backtest else None,
        })
    return out


def test_scores(series: list[dict], chosen: dict[str, str], best_baseline: dict[str, str],
                ratios_by_model: dict[str, pd.DataFrame]) -> pd.DataFrame:
    """sMAPE / MAPE / độ phủ khoảng trên 2018-06..08 cho model chọn và từng baseline (chấm một lần)."""
    rows = []
    for s in series:
        train, test = s["y"][s["y"].index <= TRAIN_END], s["y"][s["y"].index > TRAIN_END]
        picked = model_for(s, chosen, best_baseline)
        for model in sorted(set(BASELINES) | {picked}):
            yhat, used = safe_predict(train, len(test), model, best_baseline[s["category_level"]], s["category_code"])
            ratios = ratios_by_model[used]
            bands = [ratios.loc[(s["category_level"], h)] for h in range(1, len(test) + 1)]
            inside = [b[0.1] * v <= y <= b[0.9] * v for b, v, y in zip(bands, yhat, test)]
            rows.append({"category_level": s["category_level"], "category_code": s["category_code"], "model": model,
                         "is_chosen": model == picked, "smape": smape(test, yhat), "mape": mape(test, yhat),
                         "coverage": float(np.mean(inside))})
    return pd.DataFrame(rows)


def production_models(chosen: dict[str, str], best_baseline: dict[str, str], scores: pd.DataFrame) -> tuple[dict, dict]:
    med = scores.groupby(["category_level", "model"])["smape"].median()
    beats = {lvl: bool(med[(lvl, m)] < med[(lvl, best_baseline[lvl])]) if m not in BASELINES else True
             for lvl, m in chosen.items()}
    return {lvl: (m if beats[lvl] else best_baseline[lvl]) for lvl, m in chosen.items()}, {
        "validation_best_baseline": best_baseline, "chosen_beats_validation_best_baseline_on_test": beats}


def run(monthly: pd.DataFrame) -> ModelRun:
    series = build_series(monthly)
    chosen, by_level, val = select_models(series)
    best_baseline = by_level[list(BASELINES)].idxmin(axis=1).to_dict()
    ratios_by_model = {m: interval_ratios(val, m) for m in MODELS}
    scores = test_scores(series, chosen, best_baseline, ratios_by_model)
    used, decision = production_models(chosen, best_baseline, scores)

    test_months = pd.date_range("2018-06-01", TEST_END, freq="MS")
    future = pd.date_range("2018-09-01", periods=HORIZON, freq="MS")
    rows = []
    for s in series:
        model, fallback = model_for(s, used, best_baseline), best_baseline[s["category_level"]]
        rows += forecast_rows(s, s["y"][s["y"].index <= TRAIN_END], test_months, model, fallback, ratios_by_model, 1)
        rows += forecast_rows(s, s["y"], future, model, fallback, ratios_by_model, 0)
    out = pd.DataFrame(rows)

    test_median = scores.groupby(["category_level", "model"])[["smape", "mape", "coverage"]].median()
    metrics = {
        "n_series": {lvl: int(sum(s["category_level"] == lvl for s in series)) for lvl in ("category", "group")},
        "n_sparse_series": int(sum(s["sparse"] for s in series)),
        "validation_smape_mean": by_level.round(4).to_dict(orient="index"),
        "test_smape_median": test_median["smape"].unstack().round(4).to_dict(orient="index"),
        "test_mape_median": test_median["mape"].unstack().round(4).to_dict(orient="index"),
        "test_interval_coverage_median": test_median["coverage"].unstack().round(4).to_dict(orient="index"),
        "rows_by_model": out[out["is_backtest"] == 0]["model_name"].value_counts().to_dict(),
        **decision,
    }
    run_ = new_run(MODEL_NAME, MODEL_VERSION)
    append_df(tag_output(out, run_), "category_forecast")
    register(
        run_,
        train_window=f"{TRAIN_START}..{TRAIN_END} (test 2018-06..08)",
        params={"origins": ORIGINS, "horizon": HORIZON, "models": list(MODELS), "min_monthly_orders": MIN_MONTHLY_ORDERS,
                "selected_by_validation": chosen, "model_used_by_level": used,
                "interval": "nominal 80%: quantile 10/90 of actual/yhat in rolling-origin"},
        metrics=metrics,
    )
    logger.info("%s: %d series, chọn %s, dùng %s, run %s", MODEL_NAME, len(series), chosen, used, run_.model_run_id)
    return run_
