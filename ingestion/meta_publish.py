"""P8 — Đẩy metadata của dbt vào schema meta.

- target/run_results.json → meta.dq_results (append, mỗi lần chạy 1 run_id = invocation_id của dbt)
  + 1 dòng `dbt:<lệnh>` vào meta.etl_run_log (history of extracts / transformations)
- target/manifest.json → meta.data_dictionary (kiểu dữ liệu đọc từ information_schema của Postgres),
  meta.source_to_target (ghi lại toàn bộ)

Chạy NGAY SAU `dbt build`, trước `dbt docs generate` (lệnh docs ghi đè run_results.json bằng kết quả compile).
"""
from __future__ import annotations

import json
import logging
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import psycopg

from ingestion.config import DBT_PROJECT_DIR, get_settings, setup_logging

logger = logging.getLogger(__name__)

TARGET_DIR = DBT_PROJECT_DIR / "target"
DOC_RESOURCE_TYPES = {"model", "seed", "snapshot"}


def load_json(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        logger.warning("Không thấy %s", path)
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def dq_rows(run_results: dict[str, Any], manifest: dict[str, Any]) -> list[dict[str, Any]]:
    run_id = run_results["metadata"]["invocation_id"]
    nodes = manifest["nodes"]
    rows = []
    for result in run_results["results"]:
        uid = result["unique_id"]
        if not uid.startswith("test."):
            continue
        node = nodes.get(uid, {})
        depends = [n for n in node.get("depends_on", {}).get("nodes", []) if not n.startswith("macro.")]
        completed = next((t["completed_at"] for t in result.get("timing", []) if t["name"] == "execute"), None)
        rows.append({
            "run_id": run_id,
            "test_name": node.get("name", uid),
            "test_type": "generic" if node.get("test_metadata") else "singular",
            "model": depends[0].split(".")[-1] if depends else None,
            "status": result["status"],
            "failures": result.get("failures"),
            "message": (result.get("message") or "")[:2000],
            "executed_at": completed,
        })
    return rows


def run_log_row(run_results: dict[str, Any]) -> dict[str, Any]:
    """1 dòng meta.etl_run_log tóm tắt lần chạy dbt: số node theo trạng thái, failed nếu có error/fail."""
    meta = run_results["metadata"]
    ended = datetime.fromisoformat(meta["generated_at"].replace("Z", "+00:00"))
    started = ended - timedelta(seconds=float(run_results.get("elapsed_time") or 0))
    counts = Counter(r["status"] for r in run_results["results"])
    failed = counts.get("error", 0) + counts.get("fail", 0) + counts.get("runtime error", 0)
    command = (run_results.get("args") or {}).get("which", "run")
    return {
        "run_id": meta["invocation_id"],
        "batch_id": None,
        "step": f"dbt:{command}",
        "started_at": started,
        "ended_at": ended,
        "rows_in": None,
        "rows_out": len(run_results["results"]),
        "status": "failed" if failed else "success",
        "message": ", ".join(f"{k}={v}" for k, v in sorted(counts.items())),
    }


def column_types(conn: psycopg.Connection) -> dict[tuple[str, str, str], str]:
    """Kiểu dữ liệu thật của mọi cột trong các schema của warehouse (không phụ thuộc catalog.json)."""
    rows = conn.execute(
        """select table_schema, table_name, column_name, data_type
           from information_schema.columns
           where table_schema in ('raw', 'stg', 'dw', 'bi', 'ml', 'meta')"""
    ).fetchall()
    return {(s, t, c.lower()): dt for s, t, c, dt in rows}


def dictionary_rows(manifest: dict[str, Any], types: dict[tuple[str, str, str], str]) -> list[dict[str, Any]]:
    rows = []
    items = [n for n in manifest["nodes"].values() if n["resource_type"] in DOC_RESOURCE_TYPES]
    items += list(manifest.get("sources", {}).values())
    for node in items:
        table = node.get("alias") or node.get("identifier") or node["name"]
        for col_name, col in node.get("columns", {}).items():
            rows.append({
                "schema_name": node["schema"],
                "table_name": table,
                "column_name": col_name,
                "data_type": types.get((node["schema"], table, col_name.lower())) or col.get("data_type"),
                "description": col.get("description") or None,
            })
    return rows


def lineage_rows(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    rows = []
    for node in manifest["nodes"].values():
        if node["resource_type"] != "model":
            continue
        parents = [n.split(".", 2)[-1] for n in node.get("depends_on", {}).get("nodes", [])]
        rows.append({
            "target_model": f"{node['schema']}.{node['alias']}",
            "target_column": None,
            "source_models": ", ".join(sorted(parents)),
            "transformation_note": node.get("description") or None,
        })
    return rows


def run() -> None:
    manifest = load_json(TARGET_DIR / "manifest.json")
    if manifest is None:
        raise FileNotFoundError("Chưa có manifest.json — chạy `make build` trước")
    run_results = load_json(TARGET_DIR / "run_results.json")

    with psycopg.connect(get_settings().pg_conninfo) as conn:
        if run_results:
            run_id = run_results["metadata"]["invocation_id"]
            rows = dq_rows(run_results, manifest)
            log = run_log_row(run_results)
            with conn.cursor() as cur:
                # Idempotent: chạy lại meta_publish cho cùng 1 lần dbt không nhân dòng
                cur.execute("delete from meta.dq_results where run_id = %s", (run_id,))
                cur.execute("delete from meta.etl_run_log where run_id = %s and step like 'dbt:%%'", (run_id,))
                if rows:
                    cur.executemany(
                        """insert into meta.dq_results (run_id, test_name, test_type, model, status, failures, message, executed_at)
                           values (%(run_id)s, %(test_name)s, %(test_type)s, %(model)s, %(status)s, %(failures)s,
                                   %(message)s, %(executed_at)s)""",
                        rows,
                    )
                cur.execute(
                    """insert into meta.etl_run_log (run_id, batch_id, step, started_at, ended_at, rows_in, rows_out, status, message)
                       values (%(run_id)s, %(batch_id)s, %(step)s, %(started_at)s, %(ended_at)s,
                               %(rows_in)s, %(rows_out)s, %(status)s, %(message)s)""",
                    log,
                )
            logger.info("meta.dq_results: %d test; meta.etl_run_log: %s %s (%s)",
                        len(rows), log["step"], log["status"], log["message"])

        dictionary = dictionary_rows(manifest, column_types(conn))
        lineage = lineage_rows(manifest)
        with conn.cursor() as cur:
            cur.execute("truncate meta.data_dictionary, meta.source_to_target")
            cur.executemany(
                """insert into meta.data_dictionary (schema_name, table_name, column_name, data_type, description)
                   values (%(schema_name)s, %(table_name)s, %(column_name)s, %(data_type)s, %(description)s)
                   on conflict do nothing""",
                dictionary,
            )
            cur.executemany(
                """insert into meta.source_to_target (target_model, target_column, source_models, transformation_note)
                   values (%(target_model)s, %(target_column)s, %(source_models)s, %(transformation_note)s)""",
                lineage,
            )
        logger.info("meta.data_dictionary: %d cột; meta.source_to_target: %d model", len(dictionary), len(lineage))


def main() -> None:
    setup_logging()
    run()


if __name__ == "__main__":
    main()
