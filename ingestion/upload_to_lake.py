"""P5 — Upload toàn bộ data/landing/ lên MinIO bucket (giữ nguyên đường dẫn).

File đã có trên lake thì bỏ qua: landing là bất biến, không bao giờ ghi đè.
"""
from __future__ import annotations

import logging

import boto3
from botocore.client import BaseClient
from botocore.exceptions import ClientError

from ingestion.config import LAKE_PREFIX, LANDING_DIR, Settings, get_settings, setup_logging

logger = logging.getLogger(__name__)


def s3_client(settings: Settings) -> BaseClient:
    return boto3.client(
        "s3",
        endpoint_url=settings.minio_endpoint,
        aws_access_key_id=settings.minio_user,
        aws_secret_access_key=settings.minio_password,
        region_name="us-east-1",
    )


def ensure_bucket(s3: BaseClient, bucket: str) -> None:
    try:
        s3.head_bucket(Bucket=bucket)
    except ClientError:
        logger.info("Tạo bucket %s", bucket)
        s3.create_bucket(Bucket=bucket)


def object_exists(s3: BaseClient, bucket: str, key: str) -> bool:
    try:
        s3.head_object(Bucket=bucket, Key=key)
        return True
    except ClientError as exc:
        if exc.response["Error"]["Code"] in ("404", "NoSuchKey", "NotFound"):
            return False
        raise


def run() -> None:
    settings = get_settings()
    s3 = s3_client(settings)
    ensure_bucket(s3, settings.lake_bucket)
    uploaded = skipped = 0
    for path in sorted(p for p in LANDING_DIR.rglob("*") if p.is_file() and p.name != ".gitkeep"):
        key = f"{LAKE_PREFIX}/{path.relative_to(LANDING_DIR).as_posix()}"
        if object_exists(s3, settings.lake_bucket, key):
            skipped += 1
            continue
        s3.upload_file(str(path), settings.lake_bucket, key)
        uploaded += 1
        logger.info("Upload s3://%s/%s", settings.lake_bucket, key)
    logger.info("Xong: %d file mới, %d file đã có", uploaded, skipped)


def main() -> None:
    setup_logging()
    run()


if __name__ == "__main__":
    main()
