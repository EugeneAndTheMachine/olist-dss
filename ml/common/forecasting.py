"""C-M1 — dự báo chuỗi tháng dùng chung cho ML-1c (P1), ML-2a (P2), ML-3a (P3).

Chỉ có hàm tính toán: không đọc / ghi DB (việc của từng bài toán).

Chuỗi đầu vào (`series`): `pd.Series` số, index là ngày đầu tháng (freq "MS"), không có tháng trống
(tháng không có dữ liệu phải được điền 0 trước khi gọi).

Model:
- `naive`          : lặp lại giá trị tháng cuối.
- `seasonal_naive` : giá trị cùng tháng năm trước (chu kỳ 12); cần ≥ 12 điểm.
- `moving_average` : trung bình `MA_WINDOW` tháng cuối, giữ phẳng.
- `ets`            : Holt (trend cộng, damped) của statsmodels, không có mùa vụ: chuỗi trong cửa sổ phân tích
                     chỉ có 20 tháng, không đủ 2 chu kỳ để ước lượng mùa vụ. Cần ≥ `ETS_MIN_POINTS` điểm.

Dự báo bị chặn dưới ở 0 (đơn, GMV không âm). Lỗi do thiếu dữ liệu ném `ValueError`; phía gọi tự chọn fallback.
"""
from __future__ import annotations

import logging
import warnings

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

BASELINES: tuple[str, ...] = ("naive", "seasonal_naive", "moving_average")
MODELS: tuple[str, ...] = BASELINES + ("ets",)

SEASON = 12
MA_WINDOW = 3
ETS_MIN_POINTS = 6


def _check_series(series: pd.Series) -> pd.Series:
    if not isinstance(series.index, pd.DatetimeIndex):
        raise ValueError("series phải có DatetimeIndex theo tháng")
    s = series.sort_index().astype(float)
    if len(s) == 0:
        raise ValueError("series rỗng")
    if not (s.index == s.index.to_period("M").to_timestamp()).all():
        raise ValueError("index phải là ngày đầu tháng")
    expected = pd.date_range(s.index[0], s.index[-1], freq="MS")
    if len(expected) != len(s):
        raise ValueError("series có tháng trống: điền 0 trước khi dự báo")
    if s.isna().any():
        raise ValueError("series có giá trị null")
    return s


def fit_predict(series: pd.Series, horizon: int, model: str) -> np.ndarray:
    """Fit `model` trên toàn bộ `series`, trả mảng `horizon` giá trị cho các tháng ngay sau tháng cuối."""
    if horizon < 1:
        raise ValueError("horizon phải ≥ 1")
    y = _check_series(series).to_numpy()
    n = len(y)

    if model == "naive":
        yhat = np.repeat(y[-1], horizon)
    elif model == "seasonal_naive":
        if n < SEASON:
            raise ValueError(f"seasonal_naive cần ≥ {SEASON} điểm, có {n}")
        # tháng thứ h sau tháng cuối ↔ cùng tháng năm trước; h > 12 thì lặp lại chu kỳ gần nhất
        yhat = np.array([y[n - SEASON + (h % SEASON)] for h in range(horizon)])
    elif model == "moving_average":
        yhat = np.repeat(y[-min(MA_WINDOW, n):].mean(), horizon)
    elif model == "ets":
        if n < ETS_MIN_POINTS:
            raise ValueError(f"ets cần ≥ {ETS_MIN_POINTS} điểm, có {n}")
        from statsmodels.tsa.holtwinters import ExponentialSmoothing

        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            fit = ExponentialSmoothing(y, trend="add", damped_trend=True, seasonal=None,
                                       initialization_method="estimated").fit()
        yhat = np.asarray(fit.forecast(horizon), dtype=float)
    else:
        raise ValueError(f"model không hỗ trợ: {model} (chọn trong {MODELS})")

    return np.clip(yhat.astype(float), 0.0, None)


def smape(y, yhat) -> float:
    """sMAPE dạng tỉ lệ (0 … 2): mean(2·|y − ŷ| / (|y| + |ŷ|)). Cặp y = ŷ = 0 tính lỗi 0; cặp có NaN bị bỏ."""
    y, yhat = np.asarray(y, dtype=float), np.asarray(yhat, dtype=float)
    ok = ~(np.isnan(y) | np.isnan(yhat))
    y, yhat = y[ok], yhat[ok]
    if len(y) == 0:
        return float("nan")
    denom = np.abs(y) + np.abs(yhat)
    err = np.where(denom == 0, 0.0, 2 * np.abs(y - yhat) / np.where(denom == 0, 1, denom))
    return float(err.mean())


def rolling_origin(series: pd.Series, origins, horizon: int, models=MODELS) -> pd.DataFrame:
    """Backtest rolling-origin.

    Với mỗi `origin` (tháng cuối cùng được nhìn thấy) và mỗi model: fit trên `series[: origin]`, dự báo
    `horizon` tháng sau, so với giá trị thật. Chỉ giữ các tháng dự báo có trong `series`.
    Model lỗi vì thiếu dữ liệu → `yhat` = NaN (có log), không làm hỏng cả lần chạy.

    Trả DataFrame cột [model, origin, step, month, y, yhat].
    """
    s = _check_series(series)
    rows = []
    for origin in pd.to_datetime(list(origins)):
        history = s[s.index <= origin]
        months = pd.date_range(origin, periods=horizon + 1, freq="MS")[1:]
        for model in models:
            try:
                yhat = fit_predict(history, horizon, model)
            except ValueError as exc:
                logger.warning("rolling_origin %s @ %s: %s", model, origin.date(), exc)
                yhat = np.full(horizon, np.nan)
            for step, (month, value) in enumerate(zip(months, yhat), start=1):
                if month in s.index:
                    rows.append({"model": model, "origin": origin, "step": step, "month": month,
                                 "y": float(s.loc[month]), "yhat": float(value)})
    return pd.DataFrame(rows, columns=["model", "origin", "step", "month", "y", "yhat"])
