"""P8 — Đẩy metadata của dbt vào schema meta.

- target/run_results.json → meta.dq_results (append, mỗi lần chạy 1 run_id = invocation_id của dbt)
- target/manifest.json (+ catalog.json nếu có) → meta.data_dictionary, meta.source_to_target (ghi lại toàn bộ)

Chạy sau `dbt build` (và tốt nhất sau `dbt docs generate` để có data_type thật từ catalog).
"""
from __future__ import annotations

import json
import logging
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


def dictionary_rows(manifest: dict[str, Any], catalog: dict[str, Any] | None) -> list[dict[str, Any]]:
    catalog_nodes = {**(catalog or {}).get("nodes", {}), **(catalog or {}).get("sources", {})}
    rows = []
    items = [n for n in manifest["nodes"].values() if n["resource_type"] in DOC_RESOURCE_TYPES]
    items += list(manifest.get("sources", {}).values())
    for node in items:
        table = node.get("alias") or node.get("identifier") or node["name"]
        cat_cols = {k.lower(): v for k, v in catalog_nodes.get(node["unique_id"], {}).get("columns", {}).items()}
        for col_name, col in node.get("columns", {}).items():
            rows.append({
                "schema_name": node["schema"],
                "table_name": table,
                "column_name": col_name,
                "data_type": cat_cols.get(col_name.lower(), {}).get("type") or col.get("data_type"),
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
    catalog = load_json(TARGET_DIR / "catalog.json")

    with psycopg.connect(get_settings().pg_conninfo) as conn:
        if run_results:
            rows = dq_rows(run_results, manifest)
            with conn.cursor() as cur:
                cur.execute("delete from meta.dq_results where run_id = %s", (run_results["metadata"]["invocation_id"],))
                cur.executemany(
                    """insert into meta.dq_results (run_id, test_name, test_type, model, status, failures, message, executed_at)
                       values (%(run_id)s, %(test_name)s, %(test_type)s, %(model)s, %(status)s, %(failures)s,
                               %(message)s, %(executed_at)s)""",
                    rows,
                )
            logger.info("meta.dq_results: %d test", len(rows))

        dictionary = dictionary_rows(manifest, catalog)
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
