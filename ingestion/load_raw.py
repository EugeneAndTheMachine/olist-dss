"""P5 — Nạp file từ MinIO vào schema raw (Bronze, queryable).

- Mỗi file nguồn ↔ 1 bảng raw.<table> (danh mục ở config.RAW_SOURCES).
- Mọi cột kiểu text + _batch_id, _loaded_at, _source_file. Không làm sạch.
- Append-only và idempotent: file (object key) đã có trong raw.<table>._source_file thì bỏ qua.
  Nhờ vậy replay (extract_date mới) chỉ nạp phần mới.
- Mỗi file ghi 1 dòng vào meta.etl_run_log.
"""
from __future__ import annotations

import argparse
import io
import json
import logging
import re
import uuid
from datetime import datetime, timezone

import pandas as pd
import psycopg
from botocore.client import BaseClient
from psycopg import sql

from ingestion.config import RAW_SOURCES, RawSource, get_settings, setup_logging
from ingestion.upload_to_lake import s3_client

logger = logging.getLogger(__name__)

RAW_SCHEMA = "raw"
META_COLUMNS = ["_batch_id", "_loaded_at", "_source_file"]


def clean_column(name: str) -> str:
    col = re.sub(r"[^a-z0-9_]+", "_", name.strip().lower()).strip("_")
    return col[:63] or "col"


def list_keys(s3: BaseClient, bucket: str, src: RawSource) -> list[str]:
    keys: list[str] = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=src.lake_prefix):
        keys += [o["Key"] for o in page.get("Contents", []) if o["Key"].endswith("/" + src.file_name)]
    return sorted(keys)


def read_object(s3: BaseClient, bucket: str, key: str) -> pd.DataFrame:
    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    if key.endswith(".json"):
        df = pd.json_normalize(json.loads(body.decode("utf-8")), sep="_")
        df = df.astype("string")
    else:
        # utf-8-sig: file translation có BOM ở header
        df = pd.read_csv(io.BytesIO(body), dtype=str, keep_default_na=False, encoding="utf-8-sig")
    df.columns = [clean_column(c) for c in df.columns]
    return df


def ensure_table(conn: psycopg.Connection, table: str, columns: list[str]) -> None:
    ident = sql.Identifier(RAW_SCHEMA, table)
    col_defs = sql.SQL(", ").join(sql.SQL("{} text").format(sql.Identifier(c)) for c in columns + META_COLUMNS)
    conn.execute(sql.SQL("create table if not exists {} ({})").format(ident, col_defs))
    # Nguồn thêm cột ở lần trích xuất sau → thêm cột, không bao giờ xoá
    for c in columns:
        conn.execute(sql.SQL("alter table {} add column if not exists {} text").format(ident, sql.Identifier(c)))


def already_loaded(conn: psycopg.Connection, table: str, key: str) -> bool:
    exists = conn.execute("select to_regclass(%s)", (f"{RAW_SCHEMA}.{table}",)).fetchone()[0]
    if exists is None:
        return False
    query = sql.SQL("select 1 from {} where _source_file = %s limit 1").format(sql.Identifier(RAW_SCHEMA, table))
    return conn.execute(query, (key,)).fetchone() is not None


def copy_df(conn: psycopg.Connection, table: str, df: pd.DataFrame) -> int:
    query = sql.SQL("copy {} ({}) from stdin with (format csv)").format(
        sql.Identifier(RAW_SCHEMA, table),
        sql.SQL(", ").join(sql.Identifier(c) for c in df.columns),
    )
    with conn.cursor() as cur:
        with cur.copy(query) as copy:
            copy.write(df.to_csv(index=False, header=False))
        return cur.rowcount


def log_run(conn: psycopg.Connection, **fields: object) -> None:
    conn.execute(
        """
        insert into meta.etl_run_log (run_id, batch_id, step, started_at, ended_at, rows_in, rows_out, status, message)
        values (%(run_id)s, %(batch_id)s, %(step)s, %(started_at)s, %(ended_at)s,
                %(rows_in)s, %(rows_out)s, %(status)s, %(message)s)
        """,
        fields,
    )


def load_file(conn: psycopg.Connection, s3: BaseClient, bucket: str, src: RawSource, key: str,
              run_id: str, batch_id: str) -> None:
    started = datetime.now(timezone.utc)
    rows_in = 0
    try:
        df = read_object(s3, bucket, key)
        rows_in = len(df)
        df["_batch_id"] = batch_id
        df["_loaded_at"] = started.isoformat()
        df["_source_file"] = key
        with conn.transaction():
            ensure_table(conn, src.raw_table, [c for c in df.columns if c not in META_COLUMNS])
            rows_out = copy_df(conn, src.raw_table, df)
            log_run(conn, run_id=run_id, batch_id=batch_id, step=f"load_raw:{src.raw_table}", started_at=started,
                    ended_at=datetime.now(timezone.utc), rows_in=rows_in, rows_out=rows_out,
                    status="success", message=key)
        logger.info("raw.%s ← %s: %d dòng", src.raw_table, key, rows_out)
    except Exception as exc:
        log_run(conn, run_id=run_id, batch_id=batch_id, step=f"load_raw:{src.raw_table}", started_at=started,
                ended_at=datetime.now(timezone.utc), rows_in=rows_in, rows_out=0,
                status="failed", message=f"{key}: {exc}"[:2000])
        raise


def run(tables: list[str] | None = None) -> None:
    settings = get_settings()
    s3 = s3_client(settings)
    run_id = str(uuid.uuid4())
    batch_id = f"{datetime.now(timezone.utc):%Y%m%dT%H%M%S}_{run_id[:8]}"
    selected = [s for s in RAW_SOURCES if not tables or s.raw_table in tables]
    loaded = 0
    with psycopg.connect(settings.pg_conninfo, autocommit=True) as conn:
        for src in selected:
            keys = list_keys(s3, settings.lake_bucket, src)
            if not keys:
                logger.warning("Không có file nào cho raw.%s trên lake (%s)", src.raw_table, src.lake_prefix)
                continue
            for key in keys:
                if already_loaded(conn, src.raw_table, key):
                    logger.info("raw.%s: %s đã nạp, bỏ qua", src.raw_table, key)
                    continue
                load_file(conn, s3, settings.lake_bucket, src, key, run_id, batch_id)
                loaded += 1
    logger.info("Batch %s: nạp %d file", batch_id, loaded)


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tables", nargs="*", help="Chỉ nạp các bảng raw này (mặc định: tất cả)")
    args = parser.parse_args()
    run(args.tables)


if __name__ == "__main__":
    main()
