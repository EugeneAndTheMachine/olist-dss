"""Đọc/ghi PostgreSQL cho các module ML. Đọc từ dw/bi, chỉ ghi vào schema ml (implementation.md mục 12)."""
from __future__ import annotations

import logging
from functools import lru_cache
from typing import Any

import pandas as pd
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import Engine

from ingestion.config import get_settings

logger = logging.getLogger(__name__)

WRITABLE_SCHEMAS = {"ml"}


@lru_cache(maxsize=1)
def get_engine() -> Engine:
    return create_engine(get_settings().sqlalchemy_url, pool_pre_ping=True)


def read_sql(query: str, params: dict[str, Any] | None = None) -> pd.DataFrame:
    with get_engine().connect() as conn:
        return pd.read_sql(text(query), conn, params=params)


def append_df(df: pd.DataFrame, table: str, schema: str = "ml") -> int:
    """Append vào bảng có sẵn (DDL ở docker/postgres/init/03_ml_*.sql, áp bằng make db-init). Không tạo/đổi bảng."""
    if schema not in WRITABLE_SCHEMAS:
        raise ValueError(f"ML chỉ được ghi vào {WRITABLE_SCHEMAS}, không ghi {schema}")
    if df.empty:
        logger.warning("%s.%s: DataFrame rỗng, không ghi", schema, table)
        return 0
    insp = inspect(get_engine())
    # to_sql tự tạo bảng (kiểu sai) khi bảng chưa có, nên dừng ở đây
    if not insp.has_table(table, schema=schema):
        raise RuntimeError(f"{schema}.{table} chưa có: chạy make db-init")
    # Kiểu lấy từ bảng đích: pandas đoán VARCHAR cho cột chuỗi/toàn null, Postgres không tự đổi sang uuid/numeric
    dtype = {c["name"]: c["type"] for c in insp.get_columns(table, schema=schema) if c["name"] in df.columns}
    df.to_sql(table, get_engine(), schema=schema, if_exists="append", index=False, method="multi", chunksize=5000,
              dtype=dtype)
    logger.info("%s.%s: ghi %d dòng", schema, table, len(df))
    return len(df)
