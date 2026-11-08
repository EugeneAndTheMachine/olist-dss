"""Feature theo category cho P3, tính một lần cho mọi nơi dùng (ML-3b, backtest, dashboard qua ml.category_opportunity).

category_features(as_of) dùng các cửa sổ kết thúc ở tháng của as_of:
12 tháng gần nhất (quy mô, chất lượng, HHI), 3 tháng gần nhất và cùng 3 tháng năm trước (growth, BR-K5).
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from ml.common.db import read_sql

GROWTH_MIN_ORDERS = 30  # BR-P3-4: dưới ngưỡng ở một trong hai cửa sổ thì growth = null
MIN_DELIVERED_12M = 100  # BR-P3-5


def load_monthly() -> pd.DataFrame:
    """Category × tháng (toàn quốc) từ view bi của P3."""
    df = read_sql(
        """
        select m.category_key, c.category_pt, c.category_group, c.is_rankable, m.month_date,
               sum(m.orders) as orders, sum(m.gmv) as gmv, sum(m.freight) as freight,
               sum(m.review_count) as review_count, sum(m.score_sum) as score_sum,
               sum(m.low_score_count) as low_score_count,
               sum(m.delivered_orders) as delivered_orders, sum(m.late_orders) as late_orders
        from bi.v_fact_category_month as m
        join bi.v_dim_category as c using (category_key)
        group by 1, 2, 3, 4, 5
        """
    )
    df["month_date"] = pd.to_datetime(df["month_date"])
    return df


def load_seller_gmv() -> pd.DataFrame:
    """GMV theo category × seller_id × tháng, đơn bán, cho HHI (BR-P3-8; seller_id để không tách theo phiên bản SCD2)."""
    df = read_sql(
        """
        select p.category_key, f.seller_id,
               to_date((f.purchase_date_key / 100 * 100 + 1)::text, 'YYYYMMDD') as month_date,
               sum(f.item_price) as gmv
        from dw.fact_order_item as f
        join dw.dim_order_status as st on st.order_status_key = f.order_status_key
        join dw.dim_product as p on p.product_key = f.product_key
        where st.counts_as_sale = 1 and f.purchase_date_key <> -1
        group by 1, 2, 3
        """
    )
    df["month_date"] = pd.to_datetime(df["month_date"])
    return df


def windows(as_of: str) -> dict[str, tuple[pd.Timestamp, pd.Timestamp]]:
    end = pd.Timestamp(as_of).to_period("M").to_timestamp()
    return {
        "w12": (end - pd.DateOffset(months=11), end),
        "w3": (end - pd.DateOffset(months=2), end),
        "w3_ly": (end - pd.DateOffset(months=14), end - pd.DateOffset(months=12)),
    }


def _sum_in(df: pd.DataFrame, window: tuple[pd.Timestamp, pd.Timestamp], cols: list[str]) -> pd.DataFrame:
    lo, hi = window
    return df[(df["month_date"] >= lo) & (df["month_date"] <= hi)].groupby("category_key")[cols].sum()


def _ratio(num: pd.Series, den: pd.Series) -> pd.Series:
    return num / den.where(den > 0)


def hhi(seller_gmv: pd.DataFrame, window: tuple[pd.Timestamp, pd.Timestamp]) -> pd.Series:
    lo, hi = window
    s = seller_gmv[(seller_gmv["month_date"] >= lo) & (seller_gmv["month_date"] <= hi)]
    by_seller = s.groupby(["category_key", "seller_id"])["gmv"].sum()
    shares = by_seller / by_seller.groupby(level=0).transform("sum")
    return (shares**2).groupby(level=0).sum()


def platform_rates(monthly: pd.DataFrame, as_of: str) -> dict[str, float]:
    """Trung bình sàn trong 12 tháng gần nhất, dùng làm mốc cho cờ quality (BR-P3-8)."""
    lo, hi = windows(as_of)["w12"]
    t = monthly[(monthly["month_date"] >= lo) & (monthly["month_date"] <= hi)][
        ["score_sum", "review_count", "low_score_count", "late_orders", "delivered_orders"]
    ].sum()
    return {
        "avg_score": t["score_sum"] / t["review_count"],
        "low_score_rate": t["low_score_count"] / t["review_count"],
        "late_rate": t["late_orders"] / t["delivered_orders"],
    }


def category_features(as_of: str, monthly: pd.DataFrame, seller_gmv: pd.DataFrame) -> pd.DataFrame:
    w = windows(as_of)
    cats = monthly.drop_duplicates("category_key").set_index("category_key")[["category_pt", "category_group", "is_rankable"]]
    m12 = _sum_in(monthly, w["w12"], ["orders", "gmv", "freight", "review_count", "score_sum", "low_score_count",
                                      "delivered_orders", "late_orders"])
    m3 = _sum_in(monthly, w["w3"], ["orders", "gmv"]).add_suffix("_3m")
    ly = _sum_in(monthly, w["w3_ly"], ["orders", "gmv"]).add_suffix("_3m_ly")

    f = cats.join(m12, how="left").join(m3, how="left").join(ly, how="left").fillna(
        {c: 0 for c in ["orders", "gmv", "freight", "review_count", "score_sum", "low_score_count", "delivered_orders",
                        "late_orders", "orders_3m", "gmv_3m", "orders_3m_ly", "gmv_3m_ly"]}
    )
    f = f.rename(columns={"gmv": "gmv_12m", "orders": "orders_12m", "delivered_orders": "delivered_12m"})
    f["gmv_share"] = f["gmv_12m"] / f["gmv_12m"].sum()
    enough = (f["orders_3m"] >= GROWTH_MIN_ORDERS) & (f["orders_3m_ly"] >= GROWTH_MIN_ORDERS)
    f["yoy_growth"] = (f["gmv_3m"] / f["gmv_3m_ly"].where(f["gmv_3m_ly"] > 0) - 1).where(enough)
    g_platform = f["gmv_3m"].sum() / f["gmv_3m_ly"].sum() - 1
    f["relative_growth"] = (1 + f["yoy_growth"]) / (1 + g_platform) - 1
    f["avg_score"] = _ratio(f["score_sum"], f["review_count"])
    f["low_score_rate"] = _ratio(f["low_score_count"], f["review_count"])
    f["late_rate"] = _ratio(f["late_orders"], f["delivered_12m"])
    f["freight_ratio"] = _ratio(f["freight"], f["gmv_12m"])
    f["hhi"] = hhi(seller_gmv, w["w12"]).reindex(f.index)
    f["low_volume_flag"] = (f["delivered_12m"] < MIN_DELIVERED_12M).astype(int)
    f.attrs["platform_growth"] = float(g_platform)
    return f.replace([np.inf, -np.inf], np.nan)


def share_change(monthly: pd.DataFrame, before: tuple[str, str], after: tuple[str, str]) -> pd.Series:
    """Thay đổi GMV share (điểm %) giữa hai cửa sổ, cho backtest BR-P3-12."""
    def share(lo: str, hi: str) -> pd.Series:
        g = _sum_in(monthly, (pd.Timestamp(lo), pd.Timestamp(hi)), ["gmv"])["gmv"]
        return g / g.sum()

    b, a = share(*before), share(*after)
    return a.reindex(b.index.union(a.index)).fillna(0) - b.reindex(b.index.union(a.index)).fillna(0)
