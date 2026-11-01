"""DAG olist_pipeline (P6) — điều phối toàn bộ chuỗi, gọi cùng script/command với Makefile.

[download_kaggle, copy_manual, gen_holidays] → upload_to_lake → load_raw
  → dbt_deps → dbt_seed → dbt_build
  → [ml_late_risk, ml_crm, ml_forecast, ml_seller_risk] → ml_recommendations
  → meta_publish → dbt_docs_generate

Repo được mount vào /opt/olist (docker-compose.yml). Kết nối lấy từ env, không hardcode.
"""
from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

import psycopg
from airflow import DAG
from airflow.operators.bash import BashOperator

OLIST_HOME = os.environ.get("OLIST_HOME", "/opt/olist")
DBT_DIR = "dbt/olist_dw"
# dbt >= 1.5 chỉ nhận --project-dir/--profiles-dir sau subcommand → truyền bằng env
DBT = f"DBT_PROJECT_DIR={DBT_DIR} DBT_PROFILES_DIR={DBT_DIR} /opt/airflow/dbt_venv/bin/dbt"
DBT_PROFILE = f"cp -n {DBT_DIR}/profiles.example.yml {DBT_DIR}/profiles.yml"


def _log_task(context: dict, status: str) -> None:
    """Ghi 1 dòng meta.etl_run_log cho mỗi task (callback). Lỗi ghi log không làm hỏng task."""
    ti = context["task_instance"]
    exc = context.get("exception")
    conninfo = (
        f"host={os.environ['POSTGRES_HOST']} port={os.environ.get('POSTGRES_PORT', '5432')} "
        f"dbname={os.environ['POSTGRES_DB']} user={os.environ['POSTGRES_USER']} "
        f"password={os.environ['POSTGRES_PASSWORD']}"
    )
    try:
        with psycopg.connect(conninfo, autocommit=True) as conn:
            conn.execute(
                """insert into meta.etl_run_log (run_id, step, started_at, ended_at, status, message)
                   values (%s, %s, %s, %s, %s, %s)""",
                (
                    context["dag_run"].run_id,
                    f"airflow:{ti.task_id}",
                    ti.start_date,
                    ti.end_date or datetime.now(timezone.utc),
                    status,
                    str(exc)[:2000] if exc else None,
                ),
            )
    except Exception as err:  # noqa: BLE001
        ti.log.warning("Không ghi được meta.etl_run_log: %s", err)


def on_success(context: dict) -> None:
    _log_task(context, "success")


def on_failure(context: dict) -> None:
    _log_task(context, "failed")


default_args = {
    "owner": "olist-dw",
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
    "on_success_callback": on_success,
    "on_failure_callback": on_failure,
}


def task(task_id: str, command: str) -> BashOperator:
    return BashOperator(task_id=task_id, bash_command=f"cd {OLIST_HOME} && {command}")


with DAG(
    dag_id="olist_pipeline",
    description="Kaggle/holidays → Azure Blob → raw → dbt (stg, dw, bi) → ML → meta",
    start_date=datetime(2026, 10, 1),
    schedule="@daily",
    catchup=False,
    is_paused_upon_creation=True,
    default_args=default_args,
    tags=["olist", "dw"],
) as dag:
    extract = [
        task("download_kaggle", "python -m ingestion.download_kaggle"),
        task("copy_manual", "python -m ingestion.copy_manual"),
        task("gen_holidays", "python -m ingestion.gen_holidays"),
    ]
    upload_to_lake = task("upload_to_lake", "python -m ingestion.upload_to_lake")
    load_raw = task("load_raw", "python -m ingestion.load_raw")

    dbt_deps = task("dbt_deps", f"{DBT_PROFILE}; {DBT} deps")
    dbt_seed = task("dbt_seed", f"{DBT_PROFILE}; {DBT} seed")
    dbt_build = task("dbt_build", f"{DBT_PROFILE}; {DBT} build")

    ml_models = [
        task("ml_late_risk", "python -m ml.late_risk.train"),
        task("ml_crm", "python -m ml.crm_segment_voucher.train"),
        task("ml_forecast", "python -m ml.gmv_forecast.train"),
        task("ml_seller_risk", "python -m ml.seller_risk.train"),
    ]
    ml_recommendations = task("ml_recommendations", "python -m ml.recommendations")

    meta_publish = task("meta_publish", "python -m ingestion.meta_publish")
    dbt_docs_generate = task("dbt_docs_generate", f"{DBT_PROFILE}; {DBT} docs generate")

    extract >> upload_to_lake >> load_raw >> dbt_deps >> dbt_seed >> dbt_build
    dbt_build >> ml_models >> ml_recommendations >> meta_publish >> dbt_docs_generate
