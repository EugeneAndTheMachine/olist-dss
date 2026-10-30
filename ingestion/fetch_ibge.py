"""P4 — Lấy danh mục bang và municipality từ IBGE Localidades API.

Thành công → ghi landing + cập nhật bản dự phòng data/fallback/ibge_<name>.json (commit file này).
Lỗi mạng/API → dùng bản dự phòng.

Kết quả: data/landing/ibge/<name>/extract_date=YYYY-MM-DD/<name>.json
"""
from __future__ import annotations

import argparse
import json
import logging
from typing import Any

import requests

from ingestion.config import FALLBACK_DIR, setup_logging, sources_for, today_extract_date

logger = logging.getLogger(__name__)

IBGE_BASE = "https://servicodados.ibge.gov.br/api/v1/localidades"
ENDPOINTS: dict[str, str] = {
    "states": f"{IBGE_BASE}/estados",
    "municipalities": f"{IBGE_BASE}/municipios",
}


def fetch(url: str) -> Any:
    response = requests.get(url, timeout=60)
    response.raise_for_status()
    return response.json()


def run(extract_date: str) -> None:
    FALLBACK_DIR.mkdir(parents=True, exist_ok=True)
    for name, url in ENDPOINTS.items():
        src = sources_for("ibge", name)[0]
        target = src.landing_dir(extract_date) / src.file_name
        if target.is_file():
            logger.info("%s đã có trong landing, bỏ qua", target)
            continue
        fallback = FALLBACK_DIR / f"ibge_{name}.json"
        try:
            data = fetch(url)
            fallback.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
            logger.info("IBGE %s: %d bản ghi từ API", name, len(data))
        except (requests.RequestException, ValueError) as exc:
            if not fallback.is_file():
                raise RuntimeError(f"IBGE {name} lỗi và không có fallback {fallback}") from exc
            logger.warning("IBGE %s lỗi (%s) → dùng fallback %s", name, exc, fallback)
            data = json.loads(fallback.read_text(encoding="utf-8"))
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--extract-date", default=today_extract_date())
    args = parser.parse_args()
    run(args.extract_date)


if __name__ == "__main__":
    main()
