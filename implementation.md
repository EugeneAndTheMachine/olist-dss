# implementation.md — Olist Data Warehouse & Decision Support

> Tài liệu thiết kế kỹ thuật (single source of truth). **Đọc hết file này trước khi viết hoặc sửa code.**
> - Nếu code và file này mâu thuẫn → hỏi lại nhóm, đừng tự đoán.
> - Khi một quyết định thiết kế thay đổi, cập nhật file này (mục 14 Changelog) trong cùng commit.
> - Phạm vi bài toán: `docs/refactor_plan.md`. Cách làm lại phần nghiệp vụ: `docs/rebuild_guide.md`.
>   Quyết định nghiệp vụ đã chốt: `docs/business_rules.md`. KPI: `docs/kpi_dictionary.md`. Phân công: `docs/PROJECT_PLAN.md`.

**Trạng thái 2026-11-07.** Hạ tầng (môi trường, ingestion, raw, metadata, orchestration) đã chạy. Toàn bộ phần
nghiệp vụ (staging, warehouse, KPI, bi, ML, Power BI) **đang làm lại** theo `docs/rebuild_guide.md`; các mục
tương ứng bên dưới chỉ ghi quy ước chung, chi tiết được thêm khi từng rule được chốt.

---

## 0. TL;DR

| Mục | Giá trị |
| --- | --- |
| Loại dự án | Assignment môn Data Warehouse |
| Thời hạn | Nộp 13/11/2026 |
| Bài toán | 3 bài toán của sàn Olist (Brazil), mỗi bài có phần dashboard (mô tả) và phần ML (hỗ trợ quyết định): P1 giao trễ theo khu vực → đặt kho, tăng shipper; P2 quy mô thị trường theo zip của customer và seller → nên phát triển khu vực nào; P3 hạng mục sản phẩm bán chạy → nên phát triển hạng mục nào |
| Dữ liệu | 1 dataset: *Brazilian E-Commerce Public Dataset by Olist* (Kaggle, 9 bảng) |
| Kiến trúc | Medallion (Landing → Bronze → Silver → Gold → Serving) trên Kimball bus architecture |
| Stack | Docker Compose · Azure Blob Storage (Azurite local / ADLS Gen2) · PostgreSQL 16 · dbt-core + dbt-postgres · Airflow · Python 3.11 (uv) · Power BI Desktop |
| Lệnh chính | `make all` dựng lại toàn bộ từ file raw |

---

## 1. Bài toán

| # | Người ra quyết định | Dashboard (Intelligence) | ML / quyết định (Design, Choice) |
| --- | --- | --- | --- |
| P1 | Logistics Manager | Tỷ lệ giao trễ và mật độ giao trễ theo khu vực | Đặt kho / hub ở đâu, tăng cường shipper ở khu vực nào |
| P2 | Expansion / Commerce Manager | Theo khu vực (dựa trên zip của customer và seller): quy mô, số đơn, GMV, số customer, số seller, xu hướng | Nên phát triển khu vực nào |
| P3 | Category Manager | Hạng mục bán chạy, nhu cầu sản phẩm theo thời gian và khu vực | Nên phát triển hạng mục nào |

Thiết kế đích (warehouse, KPI, ML, trang Power BI): `docs/refactor_plan.md`. Phân công: `docs/PROJECT_PLAN.md`.
Đặc điểm dữ liệu ảnh hưởng thiết kế (lặp mua 3,12%, chuỗi thời gian ~20 tháng dùng được, late rate phụ thuộc cách
so sánh…): `docs/profiling.md`.

---

## 2. Nguồn dữ liệu — Kaggle `olistbr/brazilian-ecommerce` (9 file, ~100k đơn, 2016–2018)

| File | Bảng raw | Cột chính |
| --- | --- | --- |
| olist_orders_dataset.csv | raw.orders | order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at, order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date |
| olist_order_items_dataset.csv | raw.order_items | order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value |
| olist_order_payments_dataset.csv | raw.order_payments | order_id, payment_sequential, payment_type, payment_installments, payment_value |
| olist_order_reviews_dataset.csv | raw.order_reviews | review_id, order_id, review_score, review_comment_title, review_comment_message, review_creation_date, review_answer_timestamp |
| olist_customers_dataset.csv | raw.customers | customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state |
| olist_sellers_dataset.csv | raw.sellers | seller_id, seller_zip_code_prefix, seller_city, seller_state |
| olist_products_dataset.csv | raw.products | product_id, product_category_name, product_name_lenght, product_description_lenght (sai chính tả gốc), product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm |
| olist_geolocation_dataset.csv | raw.geolocation | geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state (~1M dòng, nhiều điểm / zip) |
| product_category_name_translation.csv | raw.product_category_name_translation | product_category_name, product_category_name_english |

CSV nằm sẵn trong `data/raw/ecom_dataset/` (commit trong repo). `download_kaggle.py` ưu tiên copy từ đây, chỉ gọi
Kaggle API khi thiếu file.

Không dùng nguồn ngoài dataset (đã bỏ 2026-11-06/07: Marketing Funnel, `br_states.csv`, `calendar_events.csv`,
ngày lễ từ package `holidays`, seed dân số theo bang, IBGE API). Thông tin như bang → vùng, ngày lễ, dân số nếu cần
thì là **quyết định nghiệp vụ**: chốt trong `docs/business_rules.md` rồi thêm dưới dạng seed dbt.

---

## 3. Kiến trúc & tech stack

### 3.1 Sơ đồ

```
 Kaggle / data/raw/ecom_dataset ──▶ LANDING / BRONZE FILES ── Azure Blob container `olist-lake`
                                     landing/kaggle/brazilian-ecommerce/extract_date=YYYY-MM-DD/<file>
                                     │  (file gốc, bất biến, không bao giờ sửa)
                                     ▼  Python load_raw.py (COPY, append-only)
 ┌──────────────────────────── PostgreSQL 16 (database olist_dw) ───────────────────────────┐
 │ raw  (Bronze, queryable) ─dbt▶ stg (Silver) ─dbt▶ dw (Gold: dims + facts) ─dbt▶ bi (views)│
 │                                                      │                       ▲            │
 │                                                      └──▶ Python ML ──▶ ml ──┘            │
 │ meta (run log, DQ results, dictionary, source-to-target, model registry, decision log)   │
 └────────────────────────────────────────────────────────────────────────────────────────────┘
                                     ▼  Import mode, CHỈ đọc schema `bi`
                       Power BI Desktop → 3 người ra quyết định

 Airflow (DAG `olist_pipeline`) điều phối toàn bộ chuỗi. Docker Compose đóng gói mọi service.
```

Ánh xạ Medallion ↔ schema: Landing/Bronze = Azure Blob container `olist-lake` + `raw`; Silver = `stg`; Gold = `dw`
(+ `bi` là logical data marts); ML ghi vào `ml`, **không ghi vào `dw`**.

### 3.2 Quyết định tech stack (đã chốt)

| Thành phần | Chọn | Thay vì | Lý do |
| --- | --- | --- | --- |
| Data lake | **Azure Blob Storage** qua `azure-storage-blob`: **Azurite** khi dev, **ADLS Gen2** (Azure for Students) khi demo | MinIO, local folder, S3 | MinIO ngừng phát hành image community (10/2025). Azurite miễn phí, offline, cùng API với Azure thật → đổi backend chỉ bằng `AZURE_STORAGE_CONNECTION_STRING`. Fallback: `data/landing/` |
| Warehouse | **PostgreSQL 16** | BigQuery | Dữ liệu nhỏ (<200 MB); chạy local cho mọi người; Power BI có connector sẵn |
| Transform | **dbt-core + dbt-postgres** | Spark | Spark là overkill cho ~100k đơn; dbt có sẵn test, docs, lineage, snapshot, incremental |
| Orchestration | **Airflow** | cron, Prefect | UI để demo DAG, retry, lịch batch. Airflow chỉ điều phối, không lưu dữ liệu |
| Ingestion / ML | **Python 3.11** | — | pandas, psycopg, azure-storage-blob, scikit-learn, LightGBM, statsmodels, PuLP |
| Serving | **Power BI Desktop** (Import mode) | Superset, Metabase | Phù hợp người dùng nghiệp vụ, có What-if parameters |
| Đóng gói | **Docker Compose**, **Makefile** | — | Một lệnh dựng lại môi trường |

---

## 4. Cấu trúc repo

```
olist-dss/
├── implementation.md             # file này
├── README.md                     # quickstart ngắn
├── docs/
│   ├── PROJECT_PLAN.md           # phân công theo 3 bài toán
│   ├── refactor_plan.md          # phạm vi & thiết kế đích (3 bài toán)
│   ├── rebuild_guide.md          # cách làm lại phần nghiệp vụ từng bước
│   ├── business_rules.md         # sổ quyết định nghiệp vụ BR-* (mỗi phần 1 mục, owner sửa)
│   ├── kpi_dictionary.md         # định nghĩa KPI (mục Chung / P1 / P2 / P3)
│   ├── SETUP.md, AZURE_SETUP.md  # cài đặt
│   ├── profiling.md, profiling.sql  # đặc điểm dữ liệu raw
│   └── report/, figures/
├── docker-compose.yml
├── docker/
│   ├── airflow/Dockerfile        # apache/airflow + requirements + venv riêng cho dbt
│   └── postgres/init/            # 00_databases.sql, 01_schemas.sql, 02_meta.sql (03_ml_*.sql thêm khi làm ML)
├── .env.example, Makefile, pyproject.toml, uv.lock, requirements*.txt
├── data/
│   ├── raw/ecom_dataset/         # 9 CSV nguồn, COMMIT
│   └── landing/                  # cache local trước khi upload lên Azure Blob (gitignored)
├── ingestion/
│   ├── config.py                 # đọc .env, danh mục RAW_SOURCES, kết nối
│   ├── download_kaggle.py        # data/raw hoặc Kaggle API → landing
│   ├── lake.py                   # client Azure Blob (Azurite / Azure thật)
│   ├── upload_to_lake.py         # landing → Azure Blob
│   ├── load_raw.py               # Azure Blob → raw.*, ghi meta.etl_run_log
│   └── meta_publish.py           # run_results → meta.dq_results, manifest → data_dictionary, source_to_target
├── dbt/olist_dw/
│   ├── dbt_project.yml, profiles.example.yml, packages.yml (dbt_utils)
│   ├── macros/                   # generate_schema_name, int_sk, grant_bi_reader
│   ├── seeds/                    # trống — thêm khi chốt rule (vd. order_status_map)
│   ├── models/
│   │   ├── staging/              # _sources.yml (raw + meta); stg_* → schema stg
│   │   ├── intermediate/         # int_* (vẫn vào schema stg)
│   │   ├── warehouse/dims/       # dim_* → schema dw
│   │   ├── warehouse/facts/      # fact_* → schema dw
│   │   └── bi/                   # v_* views → schema bi
│   ├── snapshots/
│   └── tests/                    # singular tests (business rules, reconciliation)
├── ml/
│   ├── common/                   # db.py, registry.py (model_run_id), features.py (time split)
│   └── notebooks/                # EDA, prototype (không chạy trong pipeline)
├── airflow/dags/olist_pipeline.py
├── scripts/replay_month.py       # demo incremental (chưa hiện thực)
└── powerbi/                      # olist_dw.pbip + README setup
```

---

## 5. Môi trường & setup

Chi tiết từng bước: `docs/SETUP.md`, `docs/AZURE_SETUP.md`.

### 5.1 Cần cài trên máy

| Công cụ | Ghi chú |
| --- | --- |
| Git | |
| Docker Desktop (hoặc Docker Engine + compose v2) | Cấp ≥ 6 GB RAM cho Docker. Windows: bật WSL2 |
| **uv** | Quản lý Python 3.11 + `.venv` (`uv sync`); Makefile gọi `uv run` |
| GNU make | Windows: WSL2 hoặc Git Bash |
| Kaggle API token (tuỳ chọn) | Chỉ khi `data/raw/` thiếu file |
| Power BI Desktop | **Chỉ chạy trên Windows** |
| DBeaver hoặc pgAdmin (tuỳ chọn) | Xem DB |

### 5.2 Python packages

Nguồn dependency là `pyproject.toml`; `uv.lock` khoá phiên bản cho mọi máy. Thêm thư viện: `uv add <pkg>` →
`make lock` (cập nhật `uv.lock` + `requirements.txt`) → commit cả ba. Windows cần `PYTHONUTF8=1` (đã có trong
`.env.example`) vì dbt đọc file bằng cp1252.

### 5.3 `.env.example` (các biến chính)

```
POSTGRES_HOST=localhost          # trong container: postgres
POSTGRES_PORT=5432
POSTGRES_USER=olist
POSTGRES_PASSWORD=olist
POSTGRES_DB=olist_dw
AZURE_STORAGE_CONNECTION_STRING=<Azurite mặc định | Azure thật>
LAKE_CONTAINER=olist-lake
KAGGLE_USERNAME=
KAGGLE_KEY=
ANALYSIS_START=2017-01-01
ANALYSIS_END=2018-08-31
```

### 5.4 Docker Compose services

| Service | Image | Port | Ghi chú |
| --- | --- | --- | --- |
| postgres | postgres:16 | 5432 | Init scripts tạo DB `olist_dw`, `airflow`; schema raw, stg, dw, bi, ml, meta; bảng `meta.*`; `shm_size: 512mb` |
| azurite | mcr.microsoft.com/azure-storage/azurite | 10000 | Container `olist-lake` do `upload_to_lake` tự tạo |
| airflow (profile `airflow`) | build từ `docker/airflow/Dockerfile` | 8080 | `airflow standalone`, LocalExecutor; dbt chạy trong venv riêng `/opt/airflow/dbt_venv` |

### 5.5 Makefile targets

| Target | Việc làm |
| --- | --- |
| `make up` / `make down` | docker compose up -d (postgres, azurite) / down |
| `make up-airflow` | Bật thêm Airflow |
| `make ingest` | download_kaggle + upload_to_lake |
| `make load-raw` | load_raw.py (batch mới, append) |
| `make dbt-deps` / `make seed` / `make build` | dbt deps / seed / build (run + test) |
| `make ml` | Các module ML (chưa có, thêm khi làm) |
| `make meta` | meta_publish.py |
| `make docs` / `make docs-serve` | dbt docs generate / serve ở cổng 8081 |
| `make all` | up → ingest → load-raw → dbt-deps → seed → build → ml → meta → docs |
| `make reset-db` | drop & recreate schemas (hỏi xác nhận) |

---

## 6. Layers & schemas

| Layer | Nơi lưu | Chứa | Build bởi | Quy tắc |
| --- | --- | --- | --- | --- |
| Landing / Bronze files | Azure Blob `olist-lake/landing/kaggle/brazilian-ecommerce/extract_date=YYYY-MM-DD/` | CSV Kaggle nguyên bản | Python ingestion | Không bao giờ sửa; mỗi lần trích xuất 1 thư mục ngày |
| Raw (Bronze, queryable) | schema `raw` | 9 bảng, **mọi cột text** + `_batch_id`, `_loaded_at`, `_source_file` | Python COPY | Append-only, không làm sạch |
| Staging (Silver) | schema `stg` | `stg_*`, `int_*`, seeds | dbt | Mọi rule làm sạch nằm trong SQL model + YAML, có mã rule `BR-*` |
| Warehouse (Gold) | schema `dw` | Dims + facts | dbt | Surrogate key, FK tests |
| Logical data marts | schema `bi` | Views cho Power BI | dbt | **Power BI chỉ đọc schema này** (user `powerbi_reader`) |
| Model outputs | schema `ml` | Output ML | Python | Mỗi dòng có `model_run_id`, `model_version`; append; view `bi` lấy run mới nhất |
| Metadata | schema `meta` | etl_run_log, dq_results, data_dictionary, source_to_target, model_registry, decision_log | Python + dbt | Ghi mỗi lần chạy |

**Lưu ý dbt**: macro `generate_schema_name` giữ đúng tên schema `stg`, `dw`, `bi`. `persist_docs` bật để mô tả
cột thành comment trong Postgres. Post-hook `analyze` sau mỗi bảng (bảng mới chưa có statistics làm planner chọn
join tệ).

---

## 7. Warehouse (Kimball) — đang làm lại

Thiết kế đích (bus matrix, grain, fact mới): `docs/refactor_plan.md` mục 4. Các câu hỏi cần chốt (BR-W*):
`docs/rebuild_guide.md` mục 4. Quy ước đã cố định:

- **Surrogate key**: bigint băm từ natural key bằng macro `int_sk(cols)`, ổn định giữa các lần build và khi load
  incremental.
- **Tỷ lệ không lưu dạng %**: mọi ratio lưu dưới dạng tử số + mẫu số cộng được.
- **Tiền tệ / thời gian**: giữ BRL; timestamp giữ nguyên, không đổi timezone.
- Mọi model có **file YAML riêng** đặt cạnh file SQL (`stg_orders.sql` + `stg_orders.yml`): description cho model và từng cột, test key (unique / not_null), relationships cho FK.

Các quy ước khác (unknown member, date key, primary seller, SCD…) ghi vào đây khi chốt trong `docs/business_rules.md`.

---

## 8. KPI dictionary — đang làm lại

Danh sách KPI đích: `docs/refactor_plan.md` mục 5. Điền `docs/kpi_dictionary.md` (định nghĩa, công thức tử /
mẫu, fact nguồn, rule liên quan) **trước** khi làm view `bi` và DAX measure. Mọi measure Power BI và mọi số trong
báo cáo dùng đúng định nghĩa đó.

---

## 9. Staging — đang làm lại

Câu hỏi làm sạch cho từng bảng nguồn (BR-S*), kèm số liệu profiling: `docs/rebuild_guide.md` mục 2. Rule đã chốt
ghi ở `docs/business_rules.md` và YAML của model.

---

## 10. Data quality & metadata

### 10.1 Tests

Ba loại, chạy mỗi lần `dbt build`, kết quả ghi `meta.dq_results`: schema (generic: unique, not_null,
relationships, accepted_values), business rule (singular, `tests/assert_*.sql`), reconciliation (row count raw →
stg → dw, tổng tiền giữa các layer). Danh sách cụ thể làm cùng từng model (`docs/rebuild_guide.md`).

### 10.2 Metadata

| Bảng | Nội dung | Ghi bởi |
| --- | --- | --- |
| meta.etl_run_log | run_id, batch_id, step, started_at, ended_at, rows_in, rows_out, status, message | load_raw.py, meta_publish.py (`dbt:<lệnh>`), Airflow callbacks |
| meta.dq_results | run_id, test_name, test_type, model, status, failures, executed_at | meta_publish.py đọc `target/run_results.json` |
| meta.data_dictionary | schema, table, column, data_type, description | meta_publish.py (manifest + information_schema) |
| meta.source_to_target | target_model, target_column, source_models, transformation_note | meta_publish.py (manifest depends_on) |
| meta.model_registry | model_run_id, model_name, model_version, trained_at, train_window, params_json, metrics_json | ml/common/registry.py |
| meta.decision_log (COULD) | rec_id, decided_by, decision, note, decided_at | nhập tay / script |

`meta_publish.py` chạy ngay sau `dbt build` (trước `dbt docs generate`, lệnh này ghi đè `run_results.json`).

---

## 11. Incremental load & replay (SHOULD)

- Mặc định: full refresh.
- Replay (`scripts/replay_month.py`, chưa hiện thực): tách các dòng nguồn có purchase month = tháng chỉ định →
  ghi vào landing với extract_date mới → `load_raw` append với `_batch_id` mới → `dbt build --select tag:incremental+`.
  Model nào incremental quyết định khi làm lại warehouse.

---

## 12. ML & decision support (schema `ml`)

Module theo bài toán: `docs/refactor_plan.md` mục 6. Quy tắc chung:

- Đọc từ `dw` / `bi`, ghi vào `ml`, **append** kèm `model_run_id` (uuid) và `model_version`; đăng ký vào
  `meta.model_registry` với metrics (`ml/common/registry.py`).
- DDL bảng `ml.*`: mỗi bài toán 1 file `docker/postgres/init/03_ml_p1.sql` / `_p2` / `_p3`, bảng dùng chung ở `03_ml_shared.sql`; dbt khai báo source riêng `ml_p1`, `ml_p2`, `ml_p3` (cùng schema `ml`). Thêm file mới vào vòng lặp `reset-db` trong Makefile.
- Split theo thời gian (`ml/common/features.py`), không random split. Feature chỉ dùng thông tin có tại thời điểm
  ra quyết định. Mỗi model có baseline đơn giản để so.

---

## 13. Serving, orchestration, quy ước code

### 13.1 Power BI

Import mode, đăng nhập bằng `powerbi_reader` (macro `grant_bi_reader`, on-run-end), chỉ đọc schema `bi`.
Measures DAX trong bảng `_Measures`, đúng KPI dictionary. Kế hoạch trang: `docs/refactor_plan.md` mục 7.2.
Setup: `powerbi/README.md`.

### 13.2 DAG `olist_pipeline`

```
download_kaggle → upload_to_lake → load_raw → dbt_deps → dbt_seed → dbt_build
  → (ML, thêm khi có) → meta_publish → dbt_docs_generate
```

BashOperator gọi đúng các lệnh như Makefile; callback ghi `meta.etl_run_log`; kết nối lấy từ env.

### 13.3 Quy ước code & guardrails

- **Không bao giờ** sửa file trong landing / data lake hay bảng `raw` ngoài append bởi load_raw.
- Mọi làm sạch nằm trong dbt model, có mô tả trong YAML và mã rule `BR-*`. Không sửa dữ liệu bằng tay.
- Mỗi rule nghiệp vụ được chốt trong `docs/business_rules.md` **trước** khi code.
- Không lưu tỷ lệ % trong fact; lưu tử số + mẫu số.
- Tên: snake_case; `stg_<source>`, `int_<desc>`, `dim_<name>`, `fact_<name>`, `v_<name>`; key `<name>_key`,
  date key `<role>_date_key`, cờ `is_` / `has_`.
- SQL: CTE style (import CTEs → logic CTEs → final select), không `select *` ở dw / bi.
- Python: type hints, đọc config từ `.env`, logging thay print, script idempotent, có `if __name__ == "__main__"`.
- Không commit `.env`, `.venv/`, `data/landing/`, `target/`, `logs/`. **Có** commit `data/raw/`, `uv.lock`.
- Branch: `feat/<task-id>-<mô-tả>`, PR vào `main`, CI tối thiểu = `dbt build` pass trên máy người review.
- Commit / PR: **không** thêm dòng `Co-Authored-By: Claude …` hay "Generated with Claude Code" (đã tắt bằng
  `.claude/settings.json`); commit message theo Conventional Commits.

---

## 14. Changelog thiết kế

- 2026-11-07: Bỏ mọi nguồn ngoài dataset Olist: `data/raw/events_brazilstates/` (`br_states.csv`, `calendar_events.csv`), `ingestion/copy_manual.py`, `ingestion/gen_holidays.py` (raw.br_holidays), seed `br_state_population`. raw còn 9 bảng. Viết lại file này theo hiện trạng (bản cũ ở commit `83891b5`). Bỏ `PROJECT_PLAN.md` cũ (4 vai trò, task P/S/F/M); phân công mới ở `docs/PROJECT_PLAN.md`.
- 2026-11-06: Reset phần nghiệp vụ: xoá mọi dbt model, singular tests, seed và macro nghiệp vụ, biến `date_spine_*` / `scd_*` / `seller_tier_rule_version`, ML stub và `03_ml.sql`, docs `kpi_dictionary`, `bi_layer`, `implementation_walkthrough`, `powerbi_guide`. Bỏ dataset Marketing Funnel. Cách làm lại: `docs/rebuild_guide.md`; code cũ ở commit `83891b5`.
- 2026-11-06: Phạm vi đổi sang 3 bài toán, 1 dataset: `docs/refactor_plan.md`.
- 2026-11-02: User `powerbi_reader` chỉ đọc schema `bi` (macro `grant_bi_reader`, on-run-end).
- 2026-11-01: `meta_publish` đọc kiểu dữ liệu từ information_schema và ghi 1 dòng `dbt:<lệnh>` vào etl_run_log. Postgres container `shm_size: 512mb`.
- 2026-11-01: Profiling (`docs/profiling.md`): xác nhận cửa sổ phân tích 2017-01-01 → 2018-08-31.
- 2026-11-01: Thay MinIO bằng Azure Blob Storage (Azurite khi dev, ADLS Gen2 khi demo). Bỏ IBGE Localidades API (chặn IP ngoài Brazil).
- 2026-10-30: Chốt PostgreSQL thay BigQuery; dbt thay Spark; Airflow chỉ điều phối. Surrogate key băm từ natural key.
- 2026-10-30: Môi trường Python dùng uv (`pyproject.toml` + `uv.lock`, Python 3.11); `data/raw/` commit lên repo; Airflow là compose profile `airflow`; dbt docs serve cổng 8081.
