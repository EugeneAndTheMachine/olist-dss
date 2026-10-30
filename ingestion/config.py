"""Cấu hình chung: đọc .env, đường dẫn, kết nối và danh mục nguồn raw.

Biến môi trường của tiến trình (vd. trong container Airflow) luôn được ưu tiên hơn .env.
"""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT = Path(os.getenv("OLIST_HOME", Path(__file__).resolve().parents[1]))
load_dotenv(PROJECT_ROOT / ".env", override=False)

DATA_DIR = PROJECT_ROOT / "data"
LANDING_DIR = DATA_DIR / "landing"
FALLBACK_DIR = DATA_DIR / "fallback"
MANUAL_RAW_DIR = PROJECT_ROOT / os.getenv("LOCAL_RAW_DIR", "data/raw")
DBT_PROJECT_DIR = PROJECT_ROOT / "dbt" / "olist_dw"

LAKE_PREFIX = "landing"


def setup_logging(level: int = logging.INFO) -> None:
    logging.basicConfig(level=level, format="%(asctime)s %(levelname)s %(name)s - %(message)s")


def env(name: str, default: str | None = None) -> str:
    value = os.getenv(name, default)
    if value is None or value == "":
        raise RuntimeError(f"Thiếu biến môi trường {name} (xem .env.example)")
    return value


@dataclass(frozen=True)
class Settings:
    postgres_host: str
    postgres_port: int
    postgres_user: str
    postgres_password: str
    postgres_db: str
    minio_endpoint: str
    minio_user: str
    minio_password: str
    lake_bucket: str
    analysis_start: str
    analysis_end: str

    @property
    def pg_conninfo(self) -> str:
        return (
            f"host={self.postgres_host} port={self.postgres_port} dbname={self.postgres_db} "
            f"user={self.postgres_user} password={self.postgres_password}"
        )

    @property
    def sqlalchemy_url(self) -> str:
        # SQLAlchemy 2 (local) dùng psycopg 3; image Airflow 2.x còn SQLAlchemy 1.4 → psycopg2
        import sqlalchemy

        driver = "psycopg" if int(sqlalchemy.__version__.split(".")[0]) >= 2 else "psycopg2"
        return (
            f"postgresql+{driver}://{self.postgres_user}:{self.postgres_password}"
            f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
        )


def get_settings() -> Settings:
    return Settings(
        postgres_host=env("POSTGRES_HOST", "localhost"),
        postgres_port=int(env("POSTGRES_PORT", "5432")),
        postgres_user=env("POSTGRES_USER", "olist"),
        postgres_password=env("POSTGRES_PASSWORD", "olist"),
        postgres_db=env("POSTGRES_DB", "olist_dw"),
        minio_endpoint=env("MINIO_ENDPOINT", "http://localhost:9000"),
        minio_user=env("MINIO_ROOT_USER", "minioadmin"),
        minio_password=env("MINIO_ROOT_PASSWORD", "minioadmin"),
        lake_bucket=env("LAKE_BUCKET", "olist-lake"),
        analysis_start=env("ANALYSIS_START", "2017-01-01"),
        analysis_end=env("ANALYSIS_END", "2018-08-31"),
    )


def today_extract_date() -> str:
    return date.today().isoformat()


@dataclass(frozen=True)
class RawSource:
    """Một file nguồn ↔ một bảng raw. Đường dẫn lake: landing/<source>/<dataset>/extract_date=YYYY-MM-DD/<file_name>."""

    source: str
    dataset: str
    file_name: str
    raw_table: str

    def landing_dir(self, extract_date: str) -> Path:
        return LANDING_DIR / self.source / self.dataset / f"extract_date={extract_date}"

    @property
    def lake_prefix(self) -> str:
        return f"{LAKE_PREFIX}/{self.source}/{self.dataset}/"


ECOM = "brazilian-ecommerce"
FUNNEL = "marketing-funnel-olist"

RAW_SOURCES: list[RawSource] = [
    # Kaggle olistbr/brazilian-ecommerce
    RawSource("kaggle", ECOM, "olist_orders_dataset.csv", "orders"),
    RawSource("kaggle", ECOM, "olist_order_items_dataset.csv", "order_items"),
    RawSource("kaggle", ECOM, "olist_order_payments_dataset.csv", "order_payments"),
    RawSource("kaggle", ECOM, "olist_order_reviews_dataset.csv", "order_reviews"),
    RawSource("kaggle", ECOM, "olist_customers_dataset.csv", "customers"),
    RawSource("kaggle", ECOM, "olist_sellers_dataset.csv", "sellers"),
    RawSource("kaggle", ECOM, "olist_products_dataset.csv", "products"),
    RawSource("kaggle", ECOM, "olist_geolocation_dataset.csv", "geolocation"),
    RawSource("kaggle", ECOM, "product_category_name_translation.csv", "product_category_name_translation"),
    # Kaggle olistbr/marketing-funnel-olist
    RawSource("kaggle", FUNNEL, "olist_marketing_qualified_leads_dataset.csv", "mql"),
    RawSource("kaggle", FUNNEL, "olist_closed_deals_dataset.csv", "closed_deals"),
    # IBGE API
    RawSource("ibge", "states", "states.json", "ibge_states"),
    RawSource("ibge", "municipalities", "municipalities.json", "ibge_municipalities"),
    # Python holidays
    RawSource("holidays", "br_holidays", "br_holidays.csv", "br_holidays"),
    # File nhóm tự chuẩn bị (data/raw/events_brazilstates)
    RawSource("manual", "events_brazilstates", "br_states.csv", "br_states"),
    RawSource("manual", "events_brazilstates", "calendar_events.csv", "calendar_events"),
]


def sources_for(source: str, dataset: str | None = None) -> list[RawSource]:
    return [s for s in RAW_SOURCES if s.source == source and (dataset is None or s.dataset == dataset)]
