"""Đưa dataset Kaggle olistbr/brazilian-ecommerce vào landing local.

Thứ tự ưu tiên:
1. Nếu thư mục tải tay (LOCAL_RAW_DIR, mặc định data/raw/) có đủ file → copy sang landing.
2. Nếu không → tải bằng Kaggle API (cần KAGGLE_USERNAME/KAGGLE_KEY và đã accept rules trên web).

Kết quả: data/landing/kaggle/<dataset>/extract_date=YYYY-MM-DD/<file>.csv
"""
from __future__ import annotations

import argparse
import logging
import shutil
import tempfile
from pathlib import Path

from ingestion.config import ECOM, MANUAL_RAW_DIR, setup_logging, sources_for, today_extract_date

logger = logging.getLogger(__name__)

# dataset trong lake -> (Kaggle ref, thư mục con trong LOCAL_RAW_DIR)
KAGGLE_DATASETS: dict[str, tuple[str, str]] = {
    ECOM: ("olistbr/brazilian-ecommerce", "ecom_dataset"),
}


def _missing(files: list[str], folder: Path) -> list[str]:
    return [f for f in files if not (folder / f).is_file()]


def copy_from_manual(manual_dir: Path, files: list[str], target: Path) -> bool:
    if not manual_dir.is_dir() or _missing(files, manual_dir):
        return False
    target.mkdir(parents=True, exist_ok=True)
    for f in files:
        shutil.copy2(manual_dir / f, target / f)
    logger.info("Copy %d file từ %s → %s", len(files), manual_dir, target)
    return True


def download_from_kaggle(ref: str, files: list[str], target: Path) -> None:
    # Import muộn: package kaggle đòi credentials ngay khi import
    from kaggle.api.kaggle_api_extended import KaggleApi

    api = KaggleApi()
    api.authenticate()
    with tempfile.TemporaryDirectory() as tmp:
        logger.info("Tải %s từ Kaggle ...", ref)
        api.dataset_download_files(ref, path=tmp, unzip=True, quiet=True)
        tmp_path = Path(tmp)
        missing = _missing(files, tmp_path)
        if missing:
            raise FileNotFoundError(f"Dataset {ref} thiếu file: {missing}")
        target.mkdir(parents=True, exist_ok=True)
        for f in files:
            shutil.copy2(tmp_path / f, target / f)
    logger.info("Đã lưu %d file vào %s", len(files), target)


def run(extract_date: str, mode: str) -> None:
    for dataset, (ref, manual_sub) in KAGGLE_DATASETS.items():
        sources = sources_for("kaggle", dataset)
        files = [s.file_name for s in sources]
        target = sources[0].landing_dir(extract_date)
        if not _missing(files, target):
            logger.info("%s đã có trong landing (%s), bỏ qua", dataset, target)
            continue
        if mode in ("auto", "manual") and copy_from_manual(MANUAL_RAW_DIR / manual_sub, files, target):
            continue
        if mode == "manual":
            raise FileNotFoundError(f"Không đủ file trong {MANUAL_RAW_DIR / manual_sub}")
        download_from_kaggle(ref, files, target)


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--extract-date", default=today_extract_date())
    parser.add_argument("--mode", choices=["auto", "manual", "kaggle"], default="auto")
    args = parser.parse_args()
    run(args.extract_date, args.mode)


if __name__ == "__main__":
    main()
