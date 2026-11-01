"""Data lake client (Landing/Bronze files) trên Azure Blob Storage.

Cùng một code chạy được với:
- **Azurite** (giả lập Azure Storage trong Docker, mặc định khi dev — offline, miễn phí);
- **Azure Storage account thật** (ADLS Gen2 / Blob) — chỉ cần đổi AZURE_STORAGE_CONNECTION_STRING trong .env.

Đường dẫn blob: landing/<source>/<dataset>/extract_date=YYYY-MM-DD/<file_name> trong container LAKE_CONTAINER.
"""
from __future__ import annotations

import logging
import os
import re

from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from azure.storage.blob import ContainerClient

from ingestion.config import Settings

# SDK Azure log mọi HTTP request/response header ở mức INFO → chỉ giữ cảnh báo
logging.getLogger("azure.core.pipeline.policies.http_logging_policy").setLevel(logging.WARNING)


def _resolve_connection_string(conn_str: str) -> str:
    """Trong container (Airflow), localhost của Azurite phải đổi thành tên service docker.

    docker-compose đặt AZURITE_HOST=azurite cho container; chỉ thay endpoint cổng 10000 của Azurite,
    connection string của Azure thật không bị ảnh hưởng.
    """
    host = os.getenv("AZURITE_HOST")
    if not host:
        return conn_str
    return re.sub(r"//(127\.0\.0\.1|localhost):10000", f"//{host}:10000", conn_str)


def container_client(settings: Settings) -> ContainerClient:
    return ContainerClient.from_connection_string(
        _resolve_connection_string(settings.lake_connection_string),
        container_name=settings.lake_container,
    )


def ensure_container(container: ContainerClient) -> None:
    try:
        container.create_container()
    except ResourceExistsError:
        pass


def blob_exists(container: ContainerClient, key: str) -> bool:
    return container.get_blob_client(key).exists()


def upload_file(container: ContainerClient, path: str, key: str) -> None:
    # overwrite=False: landing bất biến — blob đã có thì Azure trả lỗi thay vì ghi đè
    with open(path, "rb") as fh:
        container.upload_blob(name=key, data=fh, overwrite=False)


def list_keys(container: ContainerClient, prefix: str) -> list[str]:
    try:
        return sorted(b.name for b in container.list_blobs(name_starts_with=prefix))
    except ResourceNotFoundError:
        # Container chưa tồn tại (chưa chạy upload_to_lake)
        return []


def read_bytes(container: ContainerClient, key: str) -> bytes:
    return container.download_blob(key).readall()
