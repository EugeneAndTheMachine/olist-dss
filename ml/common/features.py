"""Tiện ích feature dùng chung. Nguyên tắc: chia train/test theo thời gian, chỉ dùng thông tin có tại thời điểm quyết định."""
from __future__ import annotations

import pandas as pd


def time_split(df: pd.DataFrame, date_col: str, cutoff: str) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Train = date_col < cutoff, test = date_col >= cutoff. Không random split."""
    dates = pd.to_datetime(df[date_col])
    cut = pd.Timestamp(cutoff)
    return df.loc[dates < cut].copy(), df.loc[dates >= cut].copy()


def band(scores: pd.Series, cuts: tuple[float, float] = (0.33, 0.66), labels: tuple[str, str, str] = ("Low", "Medium", "High")) -> pd.Series:
    """Chia điểm rủi ro [0, 1] thành Low / Medium / High."""
    return pd.cut(scores, bins=[-0.001, cuts[0], cuts[1], 1.0], labels=list(labels)).astype(str)
