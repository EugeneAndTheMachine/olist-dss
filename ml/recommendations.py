"""C-M2 — đề xuất hành động cho người ra quyết định (pha Choice), writer duy nhất của ml.recommendations.

Mỗi bài toán thêm một hàm rule vào RULES: đọc view bi của mình, trả DataFrame với các cột
decision_maker, subject_type, subject_id, action, rationale, score, source_version.
Bài toán chưa có output (view chưa tồn tại) thì rule trả rỗng, không làm hỏng lần chạy.

rec_id = <decision_maker>|<subject_id>|<action>|<source_version>: cùng đề xuất từ cùng phiên bản model
giữ nguyên rec_id qua các lần chạy, nên quyết định ghi vào meta.decision_log không mất liên kết.

Chạy: python -m ml.recommendations (make ml-recommendations), sau các ml_p*.
"""
from __future__ import annotations

import logging
import os
from collections.abc import Callable

import pandas as pd

from ingestion.config import setup_logging
from ml.common.db import append_df, read_sql
from ml.common.registry import new_run, register, tag_output

logger = logging.getLogger(__name__)

MODEL_NAME = "recommendations"
MODEL_VERSION = "0.1.0"
TABLE = "recommendations"
COLUMNS = ["decision_maker", "subject_type", "subject_id", "action", "rationale", "score", "source_version"]


def relation_exists(qualified_name: str) -> bool:
    return bool(read_sql("select to_regclass(:name) is not null as ok", {"name": qualified_name}).loc[0, "ok"])


def rule_category() -> pd.DataFrame:
    """P3: một đề xuất cho mỗi category đã xếp loại (BR-P3-10), từ run portfolio mới nhất."""
    view = "bi.v_category_opportunity"
    if not relation_exists(view):
        logger.info("%s chưa có, bỏ qua rule category", view)
        return pd.DataFrame(columns=COLUMNS)
    df = read_sql(
        f"""
        select category_code, portfolio_class, recommended_action, opportunity_score,
               quality_flag, recruit_sellers_flag, model_version
        from {view}
        where recommended_action is not null
        """
    )
    flags = (
        df["quality_flag"].eq(1).map({True: "; fix quality first", False: ""})
        + df["recruit_sellers_flag"].eq(1).map({True: "; recruit sellers", False: ""})
    )
    return pd.DataFrame(
        {
            "decision_maker": "category",
            "subject_type": "category",
            "subject_id": df["category_code"],
            "action": df["recommended_action"],
            "rationale": "class " + df["portfolio_class"].fillna("n/a") + flags,
            "score": df["opportunity_score"],
            "source_version": df["model_version"],
        }
    )


RULES: dict[str, Callable[[], pd.DataFrame]] = {
    "category": rule_category,
}


def build_recommendations(rules: dict[str, Callable[[], pd.DataFrame]] = RULES) -> pd.DataFrame:
    frames = [frame for frame in (rule() for rule in rules.values()) if not frame.empty]
    if not frames:
        return pd.DataFrame(columns=["rec_id", *COLUMNS])
    out = pd.concat(frames, ignore_index=True)
    out["rec_id"] = out[["decision_maker", "subject_id", "action", "source_version"]].astype(str).agg("|".join, axis=1)
    return out.drop_duplicates("rec_id")


def main() -> None:
    setup_logging()
    if not relation_exists(f"ml.{TABLE}"):
        raise RuntimeError(f"ml.{TABLE} chưa có: chạy make db-init (docker/postgres/init/03_ml_shared.sql)")
    run = new_run(MODEL_NAME, MODEL_VERSION)
    recs = build_recommendations()
    written = append_df(tag_output(recs.drop(columns="source_version"), run), TABLE)
    counts = recs.groupby("decision_maker").size().to_dict() if written else {}
    register(
        run,
        train_window=f"{os.environ.get('ANALYSIS_START', '2017-01-01')}..{os.environ.get('ANALYSIS_END', '2018-08-31')}",
        params={"rules": list(RULES)},
        metrics={"rows": written, "rows_by_decision_maker": counts},
    )
    logger.info("%s: %d đề xuất, run %s", MODEL_NAME, written, run.model_run_id)


if __name__ == "__main__":
    main()
