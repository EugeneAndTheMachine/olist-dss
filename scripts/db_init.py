"""Áp lại DDL docker/postgres/init/0[1-9]*.sql lên DB đang có (make db-init, task db_init trong DAG).

Init script của Postgres chỉ chạy khi volume trống; các file đều idempotent (if not exists) nên chạy lại an toàn.
"""
from __future__ import annotations

import logging
from pathlib import Path

from ingestion.config import setup_logging
from ml.common.db import get_engine

logger = logging.getLogger(__name__)

INIT_DIR = Path(__file__).resolve().parent.parent / "docker" / "postgres" / "init"


def init_files() -> list[Path]:
    """00_databases.sql tạo database/role ở mức cluster, chỉ chạy lúc khởi tạo volume."""
    return sorted(p for p in INIT_DIR.glob("0[1-9]*.sql"))


def main() -> None:
    setup_logging()
    raw = get_engine().raw_connection()
    try:
        with raw.cursor() as cur:
            for path in init_files():
                cur.execute(path.read_text(encoding="utf-8"))
                logger.info("db-init: %s", path.name)
        raw.commit()
    finally:
        raw.close()


if __name__ == "__main__":
    main()
