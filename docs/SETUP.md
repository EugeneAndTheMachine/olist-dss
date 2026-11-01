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

Chỉ `data/raw/` được commit; `data/landing/` là cache sinh lại bằng `make ingest` nên bị bỏ qua.
File lớn nhất (`olist_geolocation_dataset.csv`, ~61 MB) vượt mức cảnh báo 50 MB của GitHub nhưng dưới giới hạn cứng 100 MB → push vẫn được, chỉ hiện cảnh báo.

**Cách B — Kaggle API** (khi `data/raw/` thiếu file):
1. kaggle.com → *Settings → API → Create New Token* → lấy `username` và `key` trong `kaggle.json` điền vào `.env`.
2. Mở 2 trang dataset và bấm **accept rules / download** một lần trên web, nếu không API trả lỗi 403:
   - https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
   - https://www.kaggle.com/datasets/olistbr/marketing-funnel-olist

Bang & vùng Brazil lấy từ `data/raw/events_brazilstates/br_states.csv`; mã IBGE và dân số theo bang nằm trong seed dbt `br_state_population`. Không gọi API IBGE (API này chặn IP ngoài Brazil).

## 5. Dựng hạ tầng (PostgreSQL + data lake Azure Blob)

> Data lake trước đây là MinIO. MinIO đã ngừng phát hành Docker image bản community (10/2025) và repo chuyển sang maintenance mode,
> nên nhóm đổi sang **Azure Blob Storage**. Code dùng SDK `azure-storage-blob` và chạy được với 2 backend, chỉ khác `AZURE_STORAGE_CONNECTION_STRING` trong `.env`:
>
> | Backend | Dùng khi | Chi phí |
> | --- | --- | --- |
> | **Azurite** (mặc định): giả lập Azure Storage chính chủ Microsoft, chạy trong Docker | Dev hằng ngày trên cả 4 máy, offline | 0 |
> | **Azure Storage account thật** (ADLS Gen2) | 1 máy demo / Airflow, chụp hình cho báo cáo | Vài cent trong $100 credit Azure for Students |

```bash
make up
docker compose ps        # postgres, azurite: healthy
```

| Dịch vụ | Địa chỉ | Đăng nhập |
| --- | --- | --- |
| PostgreSQL | `localhost:5432`, DB `olist_dw` | `olist` / `olist` |
| Azurite Blob | `http://127.0.0.1:10000/devstoreaccount1`, container `olist-lake` | connection string mặc định trong `.env.example` |

Xem file trên lake (Azurite hoặc Azure thật): cài [Azure Storage Explorer](https://azure.microsoft.com/products/storage/storage-explorer/) → *Connect* → *Local storage emulator* (Azurite) hoặc *Storage account → Connection string* (Azure thật). Container `olist-lake` do `upload_to_lake` tự tạo ở lần chạy đầu.

Script trong `docker/postgres/init/` **chỉ chạy lần đầu** khi volume trống. Đã sửa script init → `make down && docker volume rm olist-dss_pgdata && make up` (mất dữ liệu DB), hoặc `make reset-db`.

## 5b. (Tuỳ chọn) Dùng Azure Storage thật với Azure for Students

Hướng dẫn từng bước (tạo Storage account ADLS Gen2, lấy connection string / SAS cho nhóm, kiểm tra, chi phí, Azure CLI, xử lý sự cố): **[`docs/AZURE_SETUP.md`](AZURE_SETUP.md)**.

Tóm tắt: 1 người tạo Storage account → mỗi máy dán connection string vào `AZURE_STORAGE_CONNECTION_STRING` trong `.env` → 1 máy `make ingest`, mọi máy `make load-raw`. Quay về Azurite: lấy lại dòng đó từ `.env.example`.

## 6. Chạy pipeline

```bash
make ingest      # data/raw hoặc Kaggle + holidays → data/landing → Azure Blob (Azurite)
make load-raw    # Azure Blob → schema raw (+ meta.etl_run_log)
make dbt-deps    # tạo dbt/olist_dw/profiles.yml từ profiles.example.yml, cài dbt_utils
make seed
make build       # dbt build: stg → dw → bi (+ tests)
make docs-serve  # http://localhost:8081 — lineage graph
```

Hoặc một lệnh: `make all`.

Kiểm tra trong DBeaver/psql:

```sql
select table_name from information_schema.tables where table_schema = 'raw' order by 1;   -- 14 bảng
select count(*) from raw.orders;                                                          -- ~99 441
select step, status, rows_out, message from meta.etl_run_log order by log_id desc limit 20;
```

`load_raw` idempotent: chạy lại sẽ bỏ qua file đã nạp (theo `_source_file`).

Chạy dbt thủ công (không qua make) thì phải có biến môi trường của `.env` (gồm `PYTHONUTF8=1`, bắt buộc trên Windows):
`set -a; source .env; set +a; uv run dbt build --project-dir dbt/olist_dw --profiles-dir dbt/olist_dw`.

## 7. Airflow (1 máy — Ngọc Cẩn)

```bash
make up-airflow                         # build image lần đầu ~5–10 phút, image ~3 GB (cần ≥ 25 GB trống ở ổ chứa dữ liệu Docker)
docker compose logs -f airflow          # chờ "Airflow is ready"
```

- UI: http://localhost:8080 — đăng nhập `AIRFLOW_ADMIN_USER` / `AIRFLOW_ADMIN_PASSWORD` trong `.env` (mặc định `admin` / `admin`).
- DAG `olist_pipeline` mặc định **paused** → bật rồi bấm *Trigger DAG*.
- Container mount cả repo vào `/opt/olist`; trong container `POSTGRES_HOST=postgres`, `AZURITE_HOST=azurite` (docker-compose ghi đè `.env`; `ingestion/lake.py` tự đổi `127.0.0.1:10000` → `azurite:10000`, connection string Azure thật giữ nguyên).
- dbt chạy trong venv riêng `/opt/airflow/dbt_venv`; package dbt cài vào `/opt/airflow/dbt_packages` trong container (biến `DBT_PACKAGES_INSTALL_PATH`), không ghi lên `dbt/olist_dw/dbt_packages` của máy host. Lý do: trên Windows, giải nén lên thư mục mount bị thiếu file mà dbt không báo lỗi.
- Không cần UI cũng chạy được bằng CLI: `docker compose exec airflow airflow dags trigger olist_pipeline`, xem kết quả: `docker compose exec airflow airflow tasks states-for-dag-run olist_pipeline <run_id>`.
- Log từng task: UI → DAG → Grid → chọn task → *Logs*; callback cũng ghi mỗi task 1 dòng `airflow:<task_id>` vào `meta.etl_run_log`.
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
| `docker compose up` không pull được Azurite | Đổi `AZURITE_IMAGE` trong `.env` sang tag khác ở `mcr.microsoft.com/azure-storage/azurite` (vd. `latest`) |
| `ResourceNotFoundError` / `AuthenticationFailed` khi upload | Sai connection string; Azurite chưa chạy (`docker compose ps`); SAS hết hạn hoặc thiếu quyền Create/Write |
| `The API version ... is not supported by Azurite` | Đã chặn bằng `--skipApiVersionCheck` trong docker-compose; nếu vẫn lỗi, nâng `AZURITE_IMAGE` |
| `RequestDisallowedByAzure` khi tạo storage account | Subscription sinh viên giới hạn region, xem mục 5b bước 3 |
| `unauthorized: authentication required` khi pull | `docker login` (tài khoản Docker Hub miễn phí) rồi chạy lại |
| `port is already allocated` (5432/9000/8080) | Đổi `POSTGRES_PORT` trong `.env`, hoặc tắt dịch vụ đang chiếm cổng |
| Kaggle `403 Forbidden` | Chưa accept rules của dataset trên web (mục 4) |
| `psycopg.OperationalError: connection refused` | `make up` chưa chạy, hoặc postgres chưa healthy (`docker compose ps`) |
| dbt `Env var required but not provided` | Chạy qua `make`, hoặc `set -a; source .env; set +a` trước |
| dbt `UnicodeDecodeError: 'charmap' codec` (Windows) | Thiếu `PYTHONUTF8=1` — có trong `.env.example`; chạy qua `make` hoặc `export PYTHONUTF8=1` |
| `uv sync` lỗi build `llvmlite` / `numba` | Đã chặn bằng `constraint-dependencies` trong `pyproject.toml`; kiểm tra đang dùng Python 3.11 (`uv run python --version`) |
| `uv: command not found` sau khi cài | Mở lại terminal (uv thêm thư mục cài vào PATH) |
| Bảng `ml.*`/`meta.*` không tồn tại | Volume pgdata được tạo trước khi có script init → `make reset-db` |
| Không đăng nhập được Airflow bằng `admin` / `admin` | `airflow standalone` đã tự tạo admin với mật khẩu ngẫu nhiên → `docker compose exec airflow airflow users reset-password --username admin --password admin` |
| Task ML lỗi `libgomp.so.1: cannot open shared object file` | Image cũ chưa có `libgomp1` (LightGBM cần) → `make up-airflow` (build lại, Dockerfile đã cài) |
| `dbt_seed`/`dbt_build` trong Airflow lỗi `No dbt_project.yml found at expected path .../dbt_packages/dbt_utils` | Package bị giải nén thiếu trên thư mục mount → DAG đã dùng `DBT_PACKAGES_INSTALL_PATH`; trên máy host chạy lại `rm -rf dbt/olist_dw/dbt_packages && make dbt-deps` |
| Build image lỗi `no space left on device` | Ổ C: đầy (dữ liệu Docker mặc định ở `%LOCALAPPDATA%\Docker\wsl`) → `docker builder prune` để xoá build cache, hoặc Docker Desktop → *Settings → Resources → Advanced → Disk image location* chuyển sang ổ khác |
| dbt lỗi `could not resize shared memory segment ... No space left on device` | Container postgres tạo trước khi có `shm_size: 512mb` → `docker compose up -d postgres` (tạo lại container, dữ liệu trong volume giữ nguyên) |
| Airflow container thoát ngay | `docker compose logs airflow`; thường do DB `airflow` chưa có (volume cũ) → tạo bằng `docker compose exec postgres createdb -U olist airflow` |
