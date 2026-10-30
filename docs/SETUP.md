# Hướng dẫn setup môi trường

> Ai cũng làm mục 1–6 trong ngày 1. Mục 7 (Airflow) chỉ cần 1 máy (Ngọc Cẩn). Mục 8 (Power BI) cho người làm dashboard (Xuân Vinh, Trường An).
> Lệnh viết cho **Git Bash** trên Windows (macOS/Linux/WSL2 chạy y hệt, chỉ khác đường dẫn venv).

## 1. Cài phần mềm

| Công cụ | Cách cài | Kiểm tra |
| --- | --- | --- |
| Git (kèm Git Bash) | https://git-scm.com/download/win | `git --version` |
| Docker Desktop | https://www.docker.com/products/docker-desktop — bật **WSL2 backend**; *Settings → Resources* cấp ≥ 6 GB RAM | `docker compose version` |
| **uv** (quản lý Python + venv) | PowerShell: `winget install astral-sh.uv` (hoặc xem https://docs.astral.sh/uv/getting-started/installation/). macOS/Linux: `curl -LsSf https://astral.sh/uv/install.sh \| sh` | `uv --version` |
| GNU make | PowerShell: `winget install ezwinports.make` (mở lại Git Bash sau khi cài). Hoặc dùng WSL2 | `make --version` |
| DBeaver (tuỳ chọn) | https://dbeaver.io | — |
| Power BI Desktop (TV3, TV4) | Microsoft Store | — |

**Lưu ý Windows:**
- **Không cần tự cài Python.** uv tự tìm Python 3.11 trên máy, không có thì tự tải về (file `.python-version` ghi `3.11`). Nhờ vậy tránh được Python của MSYS2/MinGW/Anaconda, vốn không cài được wheel của pandas, lightgbm, dbt.
- Nếu cổng `5432` đã bị PostgreSQL cài sẵn trên máy chiếm, đổi `POSTGRES_PORT=5433` trong `.env`.

## 2. Lấy code và tạo `.env`

```bash
git clone <repo-url> olist-dss && cd olist-dss
cp .env.example .env
```

Mở `.env`, chỉ cần sửa khi:
- Muốn tải dữ liệu bằng Kaggle API → điền `KAGGLE_USERNAME`, `KAGGLE_KEY` (mục 4).
- Bị trùng cổng → đổi `POSTGRES_PORT`.

## 3. Môi trường Python (uv)

```bash
uv sync            # hoặc: make venv
```

Lệnh này tạo `.venv/` với Python 3.11 và cài đúng các phiên bản đã khoá trong `uv.lock` (cả 4 máy giống nhau). Lần đầu mất vài phút.

- **Không cần activate.** Makefile gọi mọi thứ qua `uv run` (`uv run python -m ...`, `uv run dbt ...`). Chạy tay cũng vậy: `uv run python -m ingestion.load_raw`, `uv run jupyter lab`.
- Muốn activate (VS Code, notebook): `source .venv/Scripts/activate` (Git Bash) hoặc `.venv\Scripts\activate` (PowerShell). VS Code: *Python: Select Interpreter* → `.venv`.
- **Thêm / đổi thư viện**: `uv add <package>` (hoặc sửa `pyproject.toml`), rồi `make lock` để cập nhật `uv.lock` + `requirements.txt`, commit cả 3 file. Người khác pull về chạy `uv sync`.
- Không có uv: `python -m venv .venv` + `pip install -r requirements.txt` (file này sinh từ `uv.lock`, không sửa tay).

## 4. Dữ liệu nguồn

`make ingest` lấy dữ liệu theo thứ tự ưu tiên:

**Cách A — dữ liệu có sẵn trong repo (mặc định).** `data/raw/` đã được commit, clone về là có, không cần Kaggle token. Cấu trúc:

```
data/raw/
├── ecom_dataset/            # 9 CSV của olistbr/brazilian-ecommerce
├── marketing_funnel/        # 2 CSV của olistbr/marketing-funnel-olist
└── events_brazilstates/     # br_states.csv, calendar_events.csv (file nhóm chuẩn bị)
```

Chỉ `data/raw/` và `data/fallback/` được commit; `data/landing/` là cache sinh lại bằng `make ingest` nên bị bỏ qua.
File lớn nhất (`olist_geolocation_dataset.csv`, ~61 MB) vượt mức cảnh báo 50 MB của GitHub nhưng dưới giới hạn cứng 100 MB → push vẫn được, chỉ hiện cảnh báo.

**Cách B — Kaggle API** (khi `data/raw/` thiếu file):
1. kaggle.com → *Settings → API → Create New Token* → lấy `username` và `key` trong `kaggle.json` điền vào `.env`.
2. Mở 2 trang dataset và bấm **accept rules / download** một lần trên web, nếu không API trả lỗi 403:
   - https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
   - https://www.kaggle.com/datasets/olistbr/marketing-funnel-olist

IBGE API lỗi mạng → script tự dùng `data/fallback/ibge_*.json` (được commit sau lần chạy thành công đầu tiên).

## 5. Dựng hạ tầng (PostgreSQL + MinIO)

```bash
make up
docker compose ps        # postgres, minio: healthy; minio-init: exited (0)
```

| Dịch vụ | Địa chỉ | Đăng nhập |
| --- | --- | --- |
| PostgreSQL | `localhost:5432`, DB `olist_dw` | `olist` / `olist` |
| MinIO console | http://localhost:9001 | `minioadmin` / `minioadmin` |
| MinIO API (S3) | http://localhost:9000 | như trên |

Script trong `docker/postgres/init/` **chỉ chạy lần đầu** khi volume trống. Đã sửa script init → `make down && docker volume rm olist-dss_pgdata && make up` (mất dữ liệu DB), hoặc `make reset-db`.

## 6. Chạy pipeline

```bash
make ingest      # data/raw hoặc Kaggle + IBGE + holidays → data/landing → MinIO
make load-raw    # MinIO → schema raw (+ meta.etl_run_log)
make dbt-deps    # tạo dbt/olist_dw/profiles.yml từ profiles.example.yml, cài dbt_utils
make seed
make build       # dbt build: stg → dw → bi (+ tests)
make docs-serve  # http://localhost:8081 — lineage graph
```

Hoặc một lệnh: `make all`.

Kiểm tra trong DBeaver/psql:

```sql
select table_name from information_schema.tables where table_schema = 'raw' order by 1;   -- 16 bảng
select count(*) from raw.orders;                                                          -- ~99 441
select step, status, rows_out, message from meta.etl_run_log order by log_id desc limit 20;
```

`load_raw` idempotent: chạy lại sẽ bỏ qua file đã nạp (theo `_source_file`).

Chạy dbt thủ công (không qua make) thì phải có biến môi trường của `.env` (gồm `PYTHONUTF8=1`, bắt buộc trên Windows):
`set -a; source .env; set +a; uv run dbt build --project-dir dbt/olist_dw --profiles-dir dbt/olist_dw`.

## 7. Airflow (1 máy — Ngọc Cẩn)

```bash
make up-airflow                         # build image lần đầu ~5–10 phút
docker compose logs -f airflow          # chờ "Airflow is ready"
```

- UI: http://localhost:8080 — đăng nhập `AIRFLOW_ADMIN_USER` / `AIRFLOW_ADMIN_PASSWORD` trong `.env` (mặc định `admin` / `admin`).
- DAG `olist_pipeline` mặc định **paused** → bật rồi bấm *Trigger DAG*.
- Container mount cả repo vào `/opt/olist`; trong container `POSTGRES_HOST=postgres`, `MINIO_ENDPOINT=http://minio:9000` (docker-compose ghi đè `.env`).
- dbt chạy trong venv riêng `/opt/airflow/dbt_venv`.
- Máy yếu: không cần Airflow, dùng `make all`.

## 8. Power BI (Xuân Vinh, Trường An)

Xem [`powerbi/README.md`](../powerbi/README.md).

## 9. Dùng Claude Code

Mở terminal ở thư mục gốc repo → `claude`. Claude tự đọc `CLAUDE.md`. Giao việc theo task ID, ví dụ:
*"Làm task S3 theo CLAUDE.md, viết kèm YAML và test"*.

## 10. Xử lý sự cố

| Triệu chứng | Cách xử lý |
| --- | --- |
| `make: command not found` | Cài make (mục 1) rồi mở lại Git Bash, hoặc chạy lệnh tương ứng trong `Makefile` bằng tay |
| `docker compose up` báo `pull access denied` / `manifest unknown` cho MinIO | Tag MinIO bị gỡ khỏi Docker Hub. Đổi `MINIO_IMAGE` / `MC_IMAGE` trong `.env` sang tag khác còn tồn tại (vd. `quay.io/minio/minio:<tag>`), hoặc `latest` |
| `unauthorized: authentication required` khi pull | `docker login` (tài khoản Docker Hub miễn phí) rồi chạy lại |
| `port is already allocated` (5432/9000/8080) | Đổi `POSTGRES_PORT` trong `.env`, hoặc tắt dịch vụ đang chiếm cổng |
| Kaggle `403 Forbidden` | Chưa accept rules của dataset trên web (mục 4) |
| `psycopg.OperationalError: connection refused` | `make up` chưa chạy, hoặc postgres chưa healthy (`docker compose ps`) |
| dbt `Env var required but not provided` | Chạy qua `make`, hoặc `set -a; source .env; set +a` trước |
| dbt `UnicodeDecodeError: 'charmap' codec` (Windows) | Thiếu `PYTHONUTF8=1` — có trong `.env.example`; chạy qua `make` hoặc `export PYTHONUTF8=1` |
| `uv sync` lỗi build `llvmlite` / `numba` | Đã chặn bằng `constraint-dependencies` trong `pyproject.toml`; kiểm tra đang dùng Python 3.11 (`uv run python --version`) |
| `uv: command not found` sau khi cài | Mở lại terminal (uv thêm thư mục cài vào PATH) |
| Bảng `ml.*`/`meta.*` không tồn tại | Volume pgdata được tạo trước khi có script init → `make reset-db` |
| Airflow container thoát ngay | `docker compose logs airflow`; thường do DB `airflow` chưa có (volume cũ) → tạo bằng `docker compose exec postgres createdb -U olist airflow` |
