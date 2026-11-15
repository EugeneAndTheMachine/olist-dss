"""P1 — Logistics Manager: ML modules (ML-1a late risk, ML-1b hub placement, ML-1c courier plan)."""
from __future__ import annotations

from pathlib import Path
from sqlalchemy import text

from ingestion.config import PROJECT_ROOT
from ml.common.db import get_engine


def ensure_p1_tables() -> None:
    """Đảm bảo các bảng ml.* của P1 đã được tạo từ docker/postgres/init/03_ml_p1.sql."""
    ddl_path = Path(PROJECT_ROOT) / "docker" / "postgres" / "init" / "03_ml_p1.sql"
    sql_text = ddl_path.read_text(encoding="utf-8")
    with get_engine().begin() as conn:
        conn.execute(text(sql_text))

