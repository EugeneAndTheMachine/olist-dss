"""Sinh model_run_id và đăng ký vào meta.model_registry (CLAUDE.md mục 11.2, 13).

Cách dùng:
    run = new_run("late_risk", "0.1.0")
    out = tag_output(scores_df, run)
    append_df(out, "order_late_risk")
    register(run, train_window="2017-01-01..2018-05-31", params={...}, metrics={"roc_auc": 0.71})
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

import pandas as pd
from sqlalchemy import text

from ml.common.db import get_engine


@dataclass(frozen=True)
class ModelRun:
    model_name: str
    model_version: str
    model_run_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    trained_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


def new_run(model_name: str, model_version: str) -> ModelRun:
    return ModelRun(model_name=model_name, model_version=model_version)


def tag_output(df: pd.DataFrame, run: ModelRun) -> pd.DataFrame:
    return df.assign(model_run_id=run.model_run_id, model_version=run.model_version)


def register(run: ModelRun, train_window: str, params: dict[str, Any], metrics: dict[str, Any]) -> None:
    with get_engine().begin() as conn:
        conn.execute(
            text(
                """
                insert into meta.model_registry
                    (model_run_id, model_name, model_version, trained_at, train_window, params_json, metrics_json)
                values (:model_run_id, :model_name, :model_version, :trained_at, :train_window,
                        cast(:params as jsonb), cast(:metrics as jsonb))
                """
            ),
            {
                "model_run_id": run.model_run_id,
                "model_name": run.model_name,
                "model_version": run.model_version,
                "trained_at": run.trained_at,
                "train_window": train_window,
                "params": json.dumps(params, default=str),
                "metrics": json.dumps(metrics, default=str),
            },
        )
