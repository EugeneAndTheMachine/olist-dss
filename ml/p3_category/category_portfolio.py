"""ML-3b — phân loại danh mục, cờ chất lượng / tuyển seller, điểm cơ hội và hành động đề xuất (BR-P3-8, BR-P3-10).

Class chỉ dùng thị phần 12 tháng (Pareto) và relative growth; điểm dùng percentile rank để một category
tăng ×500 không đè bẹp các thành phần khác. Backtest BR-P3-12 chạy cùng hàm feature với as_of = 2018-05-31.
"""
from __future__ import annotations

import logging

import numpy as np
import pandas as pd

from ml.common.db import append_df, read_sql
from ml.common.registry import ModelRun, new_run, register, tag_output
from ml.p3_category.features import category_features, platform_rates, share_change

logger = logging.getLogger(__name__)

MODEL_NAME = "p3_category_portfolio"
MODEL_VERSION = "0.1.0"
AS_OF = "2018-08-31"
BACKTEST_AS_OF = "2018-05-31"

PARAMS = {
    "pareto_share": 0.80,
    "growth_band": 0.05,
    "score_gap": 0.2,
    "low_score_gap": 0.05,
    "late_gap": 0.02,
    "hhi_recruit": 0.25,
    "weights": {"c_size": 0.25, "c_growth": 0.25, "c_forecast": 0.10, "c_satisfaction": 0.15, "c_ontime": 0.15,
                "c_freight": 0.10},
}
ACTION_BY_CLASS = {
    "Grow": "Invest to grow",
    "Invest selectively": "Test and scale",
    "Maintain": "Maintain",
    "Review": "Review / deprioritise",
}


def rankable(f: pd.DataFrame) -> pd.Series:
    return (f["is_rankable"] == 1) & (f["low_volume_flag"] == 0)


def classify(f: pd.DataFrame, pareto_share: float, growth_band: float) -> pd.Series:
    """Pareto 80% GMV của tập xếp loại + dead band quanh relative growth; growth null (thiếu đơn) coi là ổn định."""
    r = f[rankable(f)].sort_values("gmv_12m", ascending=False)
    share_before = r["gmv_12m"].cumsum().shift(fill_value=0) / r["gmv_12m"].sum()
    high = share_before < pareto_share
    up = r["relative_growth"] > growth_band
    cls = np.select([high & up, ~high & up, high], ["Grow", "Invest selectively", "Maintain"], "Review")
    return pd.Series(cls, index=r.index).reindex(f.index)


def flags(f: pd.DataFrame, platform: dict[str, float], p: dict) -> pd.DataFrame:
    quality = (
        (f["avg_score"] < platform["avg_score"] - p["score_gap"])
        | (f["low_score_rate"] > platform["low_score_rate"] + p["low_score_gap"])
        | (f["late_rate"] > platform["late_rate"] + p["late_gap"])
    )
    return pd.DataFrame({
        "quality_flag": (quality & (f["low_volume_flag"] == 0)).astype(int),
        "recruit_sellers_flag": ((f["hhi"] >= p["hhi_recruit"]) & (f["low_volume_flag"] == 0)).astype(int),
    }, index=f.index)


def components(f: pd.DataFrame) -> pd.DataFrame:
    r = rankable(f)
    raw = pd.DataFrame({
        "c_size": f["gmv_12m"],
        "c_growth": f["relative_growth"],
        "c_forecast": f["relative_forecast_growth"],
        "c_satisfaction": f["avg_score"],
        "c_ontime": 1 - f["late_rate"],
        "c_freight": 1 - f["freight_ratio"],
    })
    return raw[r].rank(pct=True).reindex(f.index)


def score(comp: pd.DataFrame, weights: dict[str, float]) -> pd.Series:
    """Σ w·c / Σ w trên các thành phần khác null, để category thiếu forecast / growth không bị phạt về 0."""
    w = pd.Series(weights)
    mask = comp[w.index].notna()
    return (comp[w.index].fillna(0) * w).sum(axis=1) / (mask * w).sum(axis=1).where(mask.any(axis=1))


def action(cls: pd.Series, fl: pd.DataFrame) -> pd.Series:
    """Cùng luật với measure DAX P3 Action: cờ quality trước, rồi tuyển seller cho nhóm tăng, rồi theo class."""
    act = cls.map(ACTION_BY_CLASS)
    grow_like = cls.isin(["Grow", "Invest selectively"])
    act = act.mask(grow_like & (fl["recruit_sellers_flag"] == 1), "Recruit sellers")
    return act.mask(cls.notna() & (fl["quality_flag"] == 1), "Fix quality first")


def forecast_growth(forecast_run_id: str) -> tuple[pd.Series, float]:
    """Σ yhat 2018-09..11 / Σ GMV cùng tháng 2017 − 1, theo category và cho cả sàn (tổng 11 nhóm): so cùng mùa."""
    fc = read_sql(
        """
        select category_level, category_code, category_key, sum(yhat) as yhat
        from ml.category_forecast
        where model_run_id = cast(:run as uuid) and is_backtest = 0 and metric = 'gmv'
        group by 1, 2, 3
        """,
        {"run": forecast_run_id},
    )
    base = read_sql(
        """
        select m.category_key, c.category_group, sum(m.gmv) as gmv
        from bi.v_fact_category_month as m
        join bi.v_dim_category as c using (category_key)
        where m.month_date between '2017-09-01' and '2017-11-01'
        group by 1, 2
        """
    )
    cat = fc[fc["category_level"] == "category"].set_index("category_key")["yhat"]
    growth = cat / base.set_index("category_key")["gmv"].reindex(cat.index) - 1
    groups = fc[fc["category_level"] == "group"]["yhat"].sum()
    platform = groups / base[base["category_group"] != "Unknown"]["gmv"].sum() - 1
    return growth, float(platform)


def backtest(monthly: pd.DataFrame, seller_gmv: pd.DataFrame) -> dict:
    """BR-P3-12: class tại as-of 2018-05 so với thay đổi share 2018-06..08 vs 2018-03..05."""
    f = category_features(BACKTEST_AS_OF, monthly, seller_gmv)
    cls = classify(f, PARAMS["pareto_share"], PARAMS["growth_band"])
    change = share_change(monthly, ("2018-03-01", "2018-05-01"), ("2018-06-01", "2018-08-01"))
    d = pd.DataFrame({"cls": cls, "change": change.reindex(f.index)}).dropna(subset=["cls"])
    med = d.groupby("cls")["change"].median()
    grow = d[d["cls"].isin(["Grow", "Invest selectively"])]["change"].median()
    review = med.get("Review", np.nan)
    return {
        "as_of": BACKTEST_AS_OF,
        "n_by_class": d["cls"].value_counts().to_dict(),
        "median_share_change_pp_by_class": (med * 100).round(4).to_dict(),
        "grow_invest_beats_review": bool(grow > review) if pd.notna(grow) and pd.notna(review) else None,
        "beats_review_by_class": {c: bool(med[c] > review) for c in ("Grow", "Invest selectively")
                                  if c in med.index and pd.notna(review)},
    }


def stability(f: pd.DataFrame) -> dict:
    """Số category đổi class khi đổi ngưỡng Pareto 75/85% và dead band ±3/±7% (BR-P3-10)."""
    base = classify(f, PARAMS["pareto_share"], PARAMS["growth_band"])
    out = {}
    for name, (ps, gb) in {"pareto_75": (0.75, 0.05), "pareto_85": (0.85, 0.05), "band_3": (0.80, 0.03),
                           "band_7": (0.80, 0.07)}.items():
        out[name] = int((classify(f, ps, gb) != base)[base.notna()].sum())
    return out


def run(monthly: pd.DataFrame, seller_gmv: pd.DataFrame, forecast_run_id: str) -> ModelRun:
    f = category_features(AS_OF, monthly, seller_gmv)
    fg, platform_fg = forecast_growth(forecast_run_id)
    f["forecast_growth"] = fg.reindex(f.index)
    f["relative_forecast_growth"] = (1 + f["forecast_growth"]) / (1 + platform_fg) - 1

    platform = platform_rates(monthly, AS_OF)
    cls = classify(f, PARAMS["pareto_share"], PARAMS["growth_band"])
    fl = flags(f, platform, PARAMS)
    comp = components(f)
    opp = score(comp, PARAMS["weights"])

    out = pd.DataFrame({
        "category_code": f["category_pt"],
        "gmv_share": f["gmv_share"],
        "forecast_growth": f["forecast_growth"],
        "avg_score": f["avg_score"],
        "late_rate": f["late_rate"],
        "hhi": f["hhi"],
        "portfolio_class": cls,
        "quality_flag": fl["quality_flag"],
        "opportunity_score": opp,
        "rank": opp.rank(ascending=False, method="min").astype("Int64"),
        "category_key": f.index.astype("int64"),
        "category_group": f["category_group"],
        "gmv_12m": f["gmv_12m"],
        "yoy_growth": f["yoy_growth"],
        "relative_growth": f["relative_growth"],
        "relative_forecast_growth": f["relative_forecast_growth"],
        "low_score_rate": f["low_score_rate"],
        "freight_ratio": f["freight_ratio"],
        **{c: comp[c] for c in comp.columns},
        "recruit_sellers_flag": fl["recruit_sellers_flag"],
        "low_volume_flag": f["low_volume_flag"],
        "recommended_action": action(cls, fl),
        "forecast_model_run_id": forecast_run_id,
    })

    run_ = new_run(MODEL_NAME, MODEL_VERSION)
    append_df(tag_output(out.reset_index(drop=True), run_), "category_opportunity")
    ranked = out[out["portfolio_class"].notna()]
    register(
        run_,
        train_window=f"features as of {AS_OF} (12m + 3m vs same 3m last year)",
        params={**PARAMS, "forecast_model_run_id": forecast_run_id, "platform_forecast_growth": round(platform_fg, 4),
                "platform_growth": round(f.attrs["platform_growth"], 4), "platform_rates": platform,
                "growth_null_counts_as_stable": True},
        metrics={
            "n_ranked": int(len(ranked)),
            "n_by_class": ranked["portfolio_class"].value_counts().to_dict(),
            "n_growth_null_ranked": int(ranked["relative_growth"].isna().sum()),
            "n_quality_flag": int(ranked["quality_flag"].sum()),
            "n_recruit_sellers_flag": int(ranked["recruit_sellers_flag"].sum()),
            "class_changes_under_threshold_shifts": stability(f),
            "backtest": backtest(monthly, seller_gmv),
        },
    )
    logger.info("%s: %d category xếp loại, run %s", MODEL_NAME, len(ranked), run_.model_run_id)
    return run_
