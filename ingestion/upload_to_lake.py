"""P5 — Upload toàn bộ data/landing/ lên data lake (Azure Blob / Azurite), giữ nguyên đường dẫn.

File đã có trên lake thì bỏ qua: landing là bất biến, không bao giờ ghi đè.
"""
from __future__ import annotations

import logging

from ingestion.config import LAKE_PREFIX, LANDING_DIR, get_settings, setup_logging
from ingestion.lake import blob_exists, container_client, ensure_container, upload_file

logger = logging.getLogger(__name__)


def run() -> None:
    settings = get_settings()
    container = container_client(settings)
    ensure_container(container)
    uploaded = skipped = 0
    for path in sorted(p for p in LANDING_DIR.rglob("*") if p.is_file() and p.name != ".gitkeep"):
        key = f"{LAKE_PREFIX}/{path.relative_to(LANDING_DIR).as_posix()}"
        if blob_exists(container, key):
            skipped += 1
            continue
        upload_file(container, str(path), key)
        uploaded += 1
        logger.info("Upload %s/%s", settings.lake_container, key)
    logger.info("Xong: %d file mới, %d file đã có", uploaded, skipped)


def main() -> None:
    setup_logging()
    run()


if __name__ == "__main__":
    main()
