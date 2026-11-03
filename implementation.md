# CLAUDE.md — Olist Data Warehouse & Decision Support

> File ngữ cảnh cho Claude Code. **Đọc hết file này trước khi viết hoặc sửa code.**
> - Đây là nguồn sự thật (single source of truth) cho thiết kế. Nếu code và file này mâu thuẫn → hỏi lại người dùng, đừng tự đoán.
> - Khi một quyết định thiết kế thay đổi, cập nhật file này (mục 19 Changelog) trong cùng commit.
> - Kế hoạch phân công cho con người nằm ở `docs/PROJECT_PLAN.md`. Task ID (P*, S*, F*, M*) dùng chung giữa hai file.

---

## 0. TL;DR

| Mục | Giá trị |
| --- | --- |
| Loại dự án | Assignment môn Data Warehouse, nhóm 4 người |
| Thời hạn | 2 tuần: bắt đầu 31/10/2026, nộp 13/11/2026 (giả định, chỉnh nếu khác) |
| Bài toán | Sàn TMĐT đa người bán (mô phỏng Olist, Brazil) cần tăng doanh số mà không giảm chất lượng giao hàng / mất khách. Dữ liệu đơn, thanh toán, giao hàng, đánh giá, người bán chưa có định nghĩa chung → xây DW Kimball + BI + ML hỗ trợ 4 người ra quyết định theo 3 pha Simon |
| Kiến trúc | Medallion (Landing → Bronze → Silver → Gold → Serving) trên Kimball bus architecture |
| Stack | Docker Compose · Azure Blob Storage: Azurite local / ADLS Gen2 trên cloud (data lake) · PostgreSQL 16 (warehouse) · dbt-core + dbt-postgres (ELT) · Airflow (điều phối) · Python 3.11 (ingestion, ML) · Power BI Desktop (serving) |
| Không dùng | Spark, BigQuery (lý do ở mục 3.2) |
| Lệnh chính | `make all` dựng lại toàn bộ từ file raw |

---

## 1. Bối cảnh nghiệp vụ

Olist là "marketplace của các marketplace" ở Brazil: seller đăng sản phẩm một lần lên Olist, Olist phân phối lên nhiều sàn TMĐT và lo logistics qua đối tác.

### 1.1 Bốn người ra quyết định (giả định)

| Vai trò | Quyết định cần hỗ trợ | Fact chính | Module ML / what-if |
| --- | --- | --- | --- |
| Head of Commerce (chiến lược) | Đầu tư tăng trưởng vào nhóm ngành và khu vực nào | fact_order_item, fact_seller_month | M5 GMV forecast + growth what-if |
| Logistics & CX Manager (chiến thuật) | Sửa tuyến giao hàng / người bán nào; hứa ngày giao thế nào | fact_order_fulfillment, fact_review | M3 late-risk + promise-date what-if |
| Seller Quality Manager (chiến thuật) | Seller nào cần hỗ trợ / cảnh báo / khen thưởng; kênh thu hút seller nào đáng đầu tư | fact_seller_month, fact_lead_funnel, dim_seller (SCD2 tier) | M6 seller risk + channel value |
| CRM Manager (vận hành) | Khách nào nhận voucher, chia ngân sách cố định ra sao | fact_order_item, fact_review, fact_payment | M4 segmentation + voucher allocation |

### 1.2 Ba pha Simon → cách hệ thống hỗ trợ

| Pha | Ý nghĩa | Hiện thực |
| --- | --- | --- |
| Intelligence | Cái gì đang sai / đang tăng | Dashboard KPI theo định nghĩa chung (mục 8), drill theo dim |
| Design | Thử phương án bằng what-if | Power BI What-if parameters + bảng kịch bản tính sẵn trong schema `ml` |
| Choice | Đề xuất để con người chấp nhận / bác bỏ | `ml.recommendations` (action + rationale + score), trang Recommendations trên Power BI; ghi nhận quyết định ở `meta.decision_log` (COULD) |

### 1.3 Lưu ý khả thi (đã xác nhận ở profiling S1 ngày 01/11, số liệu: `docs/profiling.md`)

- **Lặp mua rất thấp** (đã đo: 3,12% khách có ≥ 2 đơn): phần lớn `customer_unique_id` chỉ có 1 đơn → mô hình "giữ chân khách" sẽ yếu. CRM được đặt lại thành: phân khúc theo RFM + trải nghiệm (giao trễ, review thấp) và phân bổ voucher theo **giả định uplift** (tham số what-if), không phải uplift học từ dữ liệu.
- **Funnel** (đã đo: 380 / 842 seller chốt deal có đơn hàng; won_date kéo tới 2018-11-14, chỉ 667 deal có đủ cửa sổ 90 ngày trước ANALYSIS_END): chỉ ~842 deal chốt trên ~8k MQL. Thuộc tính profile (business_segment, lead_type, …) **chỉ tồn tại cho lead đã chốt** → không được dùng làm feature dự đoán conversion. Số seller chốt deal có đơn hàng trong dataset e-commerce có thể ít, cửa sổ quan sát sau khi chốt ngắn → `gmv_first_90_days` có thể thưa.
- **Chuỗi thời gian**: đơn hàng 2016 rất thưa (329 đơn, tháng 11/2016 trống), 09–10/2018 chỉ 20 đơn. Cửa sổ phân tích 2017-01-01 → 2018-08-31 (đã xác nhận ở S1, chứa 99,6% đơn). Forecast chỉ có ~20 điểm tháng → dùng mô hình đơn giản + baseline.

---

## 2. Nguồn dữ liệu

### 2.1 Kaggle — `olistbr/brazilian-ecommerce` (9 file, ~100k đơn, 2016–2018)

| File | Bảng raw | Cột chính |
| --- | --- | --- |
| olist_orders_dataset.csv | raw.orders | order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at, order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date |
| olist_order_items_dataset.csv | raw.order_items | order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value |
| olist_order_payments_dataset.csv | raw.order_payments | order_id, payment_sequential, payment_type, payment_installments, payment_value |
| olist_order_reviews_dataset.csv | raw.order_reviews | review_id, order_id, review_score, review_comment_title, review_comment_message, review_creation_date, review_answer_timestamp |
| olist_customers_dataset.csv | raw.customers | customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state |
| olist_sellers_dataset.csv | raw.sellers | seller_id, seller_zip_code_prefix, seller_city, seller_state |
| olist_products_dataset.csv | raw.products | product_id, product_category_name, product_name_lenght, product_description_lenght (sai chính tả gốc), product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm |
| olist_geolocation_dataset.csv | raw.geolocation | geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state (~1M dòng, nhiều điểm/zip) |
| product_category_name_translation.csv | raw.product_category_name_translation | product_category_name, product_category_name_english |

### 2.2 Kaggle — `olistbr/marketing-funnel-olist` (2 file)

| File | Bảng raw | Cột chính |
| --- | --- | --- |
| olist_marketing_qualified_leads_dataset.csv | raw.mql | mql_id, first_contact_date, landing_page_id, origin |
| olist_closed_deals_dataset.csv | raw.closed_deals | mql_id, seller_id, sdr_id, sr_id, won_date, business_segment, lead_type, lead_behaviour_profile, has_company, has_gtin, average_stock, business_type, declared_product_catalog_size, declared_monthly_revenue |

Nối: `closed_deals.mql_id → mql.mql_id`; `closed_deals.seller_id → sellers.seller_id` (tỷ lệ khớp phải đo ở S1).

### 2.3 Nguồn bổ sung

| Nguồn | Cách lấy | Bảng raw | Dùng cho |
| --- | --- | --- | --- |
| Mã IBGE & dân số theo bang | CSV tự tạo (seed) từ số liệu IBGE: mã bang 2 chữ số + dân số ước tính ~2018 | seed `br_state_population` (state_code, ibge_state_id, population_2018) | dim_geography.ibge_state_id, state_population, KPI per capita |
| Ngày lễ Brazil | Python package `holidays` (`holidays.Brazil(years=2016..2019)`) → CSV | raw.br_holidays | dim_date.is_br_holiday, holiday_name |
| Black Friday | Tính trong dbt: thứ Sáu thứ 4 của tháng 11 (2016-11-25, 2017-11-24, 2018-11-23) | — | dim_date.is_black_friday_week (tuần ISO chứa Black Friday) |
| Bang & vùng (nhóm tự chuẩn bị) | `data/raw/events_brazilstates/br_states.csv` (state_code, state_name, region_name) | raw.br_states | dim_geography: state_name, region_name |
| Lịch sự kiện (nhóm tự chuẩn bị) | `data/raw/events_brazilstates/calendar_events.csv` (event_date, event_name, event_type ∈ national_holiday, retail_event) | raw.calendar_events | Đối chiếu holidays; sự kiện bán lẻ (Mother's Day, Dia dos Namorados, Black Friday…) cho dim_date (COULD) |

**Không dùng IBGE Localidades API** (2026-11-01): API chặn IP ngoài Brazil (timeout / 403 từ Việt Nam). Thông tin cấp bang đã đủ trong `br_states.csv` + seed; danh mục municipality (chỉ cho city-level enrichment, COULD) bị bỏ.

**File tải tay**: `data/raw/` (gitignored) là nơi đặt CSV tải thủ công — `ecom_dataset/` (9 file), `marketing_funnel/` (2 file), `events_brazilstates/` (2 file). `download_kaggle.py` ưu tiên copy từ đây, chỉ gọi Kaggle API khi thiếu file; `copy_manual.py` đưa `events_brazilstates/` vào landing (`landing/manual/events_brazilstates/`).

---

## 3. Kiến trúc & tech stack

### 3.1 Sơ đồ

```
 Kaggle (2 datasets) ──┐
 CSV nhóm chuẩn bị ────┼──▶ LANDING / BRONZE FILES ── Azure Blob container `olist-lake`
 holidays (Python) ────┘      landing/<source>/<dataset>/extract_date=YYYY-MM-DD/<file>
                                     │  (file gốc, bất biến, không bao giờ sửa)
                                     ▼  Python load_raw.py (COPY, append-only)
 ┌──────────────────────────── PostgreSQL 16 (database olist_dw) ───────────────────────────┐
 │ raw  (Bronze, queryable) ─dbt▶ stg (Silver) ─dbt▶ dw (Gold: dims + facts) ─dbt▶ bi (views)│
 │                                                      │                       ▲            │
 │                                                      └──▶ Python ML ──▶ ml ──┘            │
 │ meta (run log, DQ results, dictionary, source-to-target, model registry, decision log)   │
 └────────────────────────────────────────────────────────────────────────────────────────────┘
                                     ▼  Import mode, CHỈ đọc schema `bi`
                       Power BI Desktop → 4 decision makers

 Airflow (DAG `olist_pipeline`) điều phối toàn bộ chuỗi. Docker Compose đóng gói mọi service.
```

Ánh xạ Medallion ↔ schema: Landing/Bronze = Azure Blob container `olist-lake` + `raw`; Silver = `stg`; Gold = `dw` (+ `bi` là logical data marts); ML ghi vào `ml`, **không ghi vào `dw`**.

### 3.2 Quyết định tech stack (đã chốt)

| Thành phần | Chọn | Thay vì | Lý do |
| --- | --- | --- | --- |
| Data lake (Landing/Bronze files) | **Azure Blob Storage** qua SDK `azure-storage-blob`: **Azurite** (emulator của Microsoft, Docker) khi dev; **ADLS Gen2** (Azure for Students) khi demo | MinIO, local folder, S3 | MinIO ngừng phát hành image community (10/2025) nên bỏ. Azurite miễn phí, offline, cùng API với Azure thật → đổi backend chỉ bằng `AZURE_STORAGE_CONNECTION_STRING`. Fallback: thư mục `data/landing/` |
| Warehouse (Silver/Gold) | **PostgreSQL 16** | BigQuery | Dữ liệu nhỏ (<200 MB); chạy local cho cả 4 người, không cần billing/IAM GCP; Power BI có connector sẵn; dbt-postgres ổn định; môn học tập trung vào khái niệm DW, không cần MPP |
| Transform | **dbt-core + dbt-postgres** (ELT trong DB) | Spark | Spark là overkill cho ~100k đơn, thêm JVM/cluster; phần thiết kế ETL đã viết theo dbt (test, docs, lineage, snapshot, incremental có sẵn). Nếu giảng viên **bắt buộc** Spark: dùng PySpark local chỉ ở bước CSV → Parquet trên data lake (Azure Blob), không đụng dbt |
| Orchestration | **Airflow** (đề xuất của Trường An) | cron, Prefect | Phổ biến, có UI để demo DAG, retry, lịch batch. Dữ liệu không cần realtime → batch là đúng. Airflow chỉ điều phối, **không** phải nơi lưu dữ liệu |
| Ingestion / ML | **Python 3.11** | — | pandas, psycopg, azure-storage-blob, scikit-learn, LightGBM, statsmodels, PuLP |
| Serving | **Power BI Desktop** (Import mode) | Superset, Metabase | Phù hợp người dùng nghiệp vụ, có What-if parameters |
| Đóng gói | **Docker Compose**, **Makefile** | — | Một lệnh dựng lại môi trường |

---

## 4. Cấu trúc repo (mục tiêu)

```
olist-dss/
├── CLAUDE.md                     # file này
├── README.md                     # quickstart ngắn
├── docs/
│   ├── PROJECT_PLAN.md           # phân công cho người
│   ├── SETUP.md                  # hướng dẫn cài đặt từng bước
│   ├── profiling.md              # kết quả S1, xác nhận giả định
│   ├── kpi_dictionary.md         # bản đọc được của mục 8
│   ├── report/                   # báo cáo + hình (lineage, star schema, bus matrix)
│   └── figures/
├── docker-compose.yml
├── docker/
│   ├── airflow/Dockerfile        # apache/airflow + requirements + venv riêng cho dbt
│   └── postgres/init/            # 00_databases.sql, 01_schemas.sql, 02_meta.sql, 03_ml.sql
├── .env.example                  # copy → .env (không commit .env)
├── Makefile
├── pyproject.toml                # dependency Python (uv), .python-version = 3.11
├── uv.lock                       # khoá phiên bản cho cả nhóm (commit)
├── requirements.txt              # sinh từ uv.lock (`make lock`), chỉ cho ai không dùng uv
├── requirements-airflow.txt
├── data/
│   ├── raw/                      # CSV nguồn, COMMIT (ecom_dataset/, marketing_funnel/, events_brazilstates/)
│   ├── landing/                  # cache local trước khi upload lên Azure Blob (gitignored)
├── ingestion/
│   ├── config.py                 # đọc .env, tên bucket, kết nối
│   ├── download_kaggle.py        # P3 (ưu tiên data/raw/, thiếu mới gọi Kaggle API)
│   ├── copy_manual.py            # P3: data/raw/events_brazilstates → landing/manual
│   ├── gen_holidays.py           # P4
│   ├── lake.py                   # client Azure Blob (Azurite / Azure thật)
│   ├── upload_to_lake.py         # P5
│   ├── load_raw.py               # P5: Azure Blob → raw.*, ghi meta.etl_run_log
│   └── meta_publish.py           # P8: run_results → meta.dq_results, manifest → source_to_target
├── dbt/olist_dw/
│   ├── dbt_project.yml
│   ├── profiles.example.yml
│   ├── packages.yml              # dbt_utils (+ dbt_expectations nếu cần)
│   ├── macros/                   # generate_schema_name, int_sk, unknown_member
│   ├── seeds/                    # category_group, seller_tier_rules, br_state_population, order_status_map, instalment_band
│   ├── models/
│   │   ├── staging/              # stg_* (1 model / nguồn) → schema stg
│   │   ├── intermediate/         # int_* (vẫn vào schema stg)
│   │   ├── warehouse/dims/       # dim_* → schema dw
│   │   ├── warehouse/facts/      # fact_* → schema dw
│   │   └── bi/                   # v_* views → schema bi
│   ├── snapshots/                # dbt snapshot cho seller tier khi load live (sau backfill)
│   └── tests/                    # singular tests (business rules, reconciliation)
├── ml/
│   ├── common/                   # db.py, registry.py (model_run_id), features.py
│   ├── late_risk/                # M3
│   ├── crm_segment_voucher/      # M4
│   ├── gmv_forecast/             # M5
│   ├── seller_risk/              # M6
│   ├── recommendations.py        # M7
│   └── notebooks/                # EDA, prototype (không chạy trong pipeline)
├── airflow/dags/olist_pipeline.py  # P6
├── scripts/replay_month.py       # P7
└── powerbi/                      # olist_dw.pbip (Power BI Project, text, git-friendly) + README setup
```

---

## 5. Môi trường & setup

### 5.1 Cần cài trên máy

| Công cụ | Ghi chú |
| --- | --- |
| Git | |
| Docker Desktop (hoặc Docker Engine + compose v2) | Cấp ≥ 6 GB RAM cho Docker. Windows: bật WSL2 |
| **uv** | Quản lý Python 3.11 + `.venv` (`uv sync`); Makefile gọi `uv run`. Không cần cài Python riêng |
| GNU make | Windows: chạy trong WSL2 hoặc Git Bash |
| Kaggle API token | kaggle.com → Settings → Create New Token → `~/.kaggle/kaggle.json` hoặc đặt `KAGGLE_USERNAME`, `KAGGLE_KEY` trong `.env`. Phải bấm accept rules của 2 dataset trên web trước khi tải |
| Power BI Desktop | **Chỉ chạy trên Windows**. Thành viên dùng macOS dùng máy Windows/VM/phòng lab |
| DBeaver hoặc pgAdmin (tuỳ chọn) | Xem DB |

### 5.2 Python packages (`pyproject.toml` + `uv.lock`)

```
pandas, pyarrow, psycopg[binary]>=3.1, sqlalchemy>=2, python-dotenv,
azure-storage-blob, kaggle, requests, holidays, unidecode,
dbt-core, dbt-postgres,            # pin cùng một minor version cho cả nhóm (>=1.8)
scikit-learn, lightgbm, statsmodels, pulp, shap (tuỳ chọn),
jupyter, matplotlib, seaborn
```

Nguồn dependency là `pyproject.toml` (notebook ở dependency-group `dev`); `uv.lock` khoá phiên bản cho 4 máy. Thêm thư viện: `uv add <pkg>` → `make lock` (cập nhật `uv.lock` + xuất `requirements.txt`) → commit cả ba. `pyproject.toml` có `constraint-dependencies` chặn numba/llvmlite cũ (shap kéo vào, không build được trên 3.11). Windows cần `PYTHONUTF8=1` (đã có trong `.env.example`) vì dbt đọc file bằng cp1252.

### 5.3 `.env.example`

```
POSTGRES_HOST=localhost          # trong container: postgres
POSTGRES_PORT=5432
POSTGRES_USER=olist
POSTGRES_PASSWORD=olist
POSTGRES_DB=olist_dw
AIRFLOW_DB=airflow
AZURE_STORAGE_CONNECTION_STRING=<Azurite mặc định | Azure thật>   # trong container: 127.0.0.1 → azurite (tự đổi)
LAKE_CONTAINER=olist-lake
KAGGLE_USERNAME=
KAGGLE_KEY=
AIRFLOW_UID=50000
ANALYSIS_START=2017-01-01
ANALYSIS_END=2018-08-31
```

### 5.4 Docker Compose services

| Service | Image | Port | Ghi chú |
| --- | --- | --- | --- |
| postgres | postgres:16 | 5432 | Mount `docker/postgres/init/` vào `/docker-entrypoint-initdb.d/`; tạo DB `olist_dw` và `airflow`; tạo schema raw, stg, dw, bi, ml, meta; volume `pgdata` |
| azurite | mcr.microsoft.com/azure-storage/azurite (pin) | 10000 (Blob) | `azurite-blob --loose --skipApiVersionCheck`, volume `azuritedata`; container `olist-lake` do `upload_to_lake` tự tạo |
| airflow | build từ `docker/airflow/Dockerfile` | 8080 | Dev mode: `airflow standalone` với `AIRFLOW__CORE__EXECUTOR=LocalExecutor`, metadata DB = postgres/airflow. Mount `airflow/dags`, `ingestion`, `dbt`, `ml`, `data` |

`docker/airflow/Dockerfile`: FROM `apache/airflow:<2.10.x>-python3.11` (pin), cài `requirements-airflow.txt`, tạo **venv riêng cho dbt** (`/opt/airflow/dbt_venv`) để tránh xung đột dependency giữa Airflow và dbt. Task dbt gọi `/opt/airflow/dbt_venv/bin/dbt`.

Fallback nếu máy yếu không chạy nổi Airflow: chạy `make all` (cùng các script) — Airflow chỉ cần có trên 1 máy để demo.

### 5.5 Makefile targets

| Target | Việc làm |
| --- | --- |
| `make up` / `make down` | docker compose up -d (postgres, azurite) / down |
| `make up-airflow` | Bật thêm service Airflow (compose profile `airflow`) |
| `make ingest` | download_kaggle + copy_manual + gen_holidays + upload_to_lake |
| `make load-raw` | load_raw.py (batch mới, append) |
| `make dbt-deps` / `make seed` | dbt deps / dbt seed |
| `make build` | dbt build (run + test) toàn bộ stg → dw → bi |
| `make ml` | chạy M3 → M7 theo thứ tự, ghi `ml.*` và `meta.model_registry` |
| `make meta` | meta_publish.py (DQ results, source-to-target, dictionary) |
| `make docs` / `make docs-serve` | dbt docs generate / serve ở cổng 8081 (8080 dành cho Airflow) |
| `make all` | up → ingest → load-raw → dbt-deps → seed → build → ml → meta → docs |
| `make replay MONTH=2017-11` | scripts/replay_month.py cho 1 tháng mua + dbt build incremental |
| `make reset-db` | drop & recreate schemas (nguy hiểm, hỏi xác nhận) |

dbt profile: `profiles.example.yml` đọc host/port/user từ env (`{{ env_var('POSTGRES_HOST') }}`), target `dev`.

---

## 6. Layers & schemas

| Layer | Nơi lưu | Chứa | Build bởi | Quy tắc |
| --- | --- | --- | --- | --- |
| Landing / Bronze files | Azure Blob container `olist-lake/landing/<source>/<dataset>/extract_date=YYYY-MM-DD/` | CSV Kaggle, JSON API, CSV holidays nguyên bản | Python ingestion | Không bao giờ sửa; mỗi lần trích xuất 1 thư mục ngày |
| Raw (Bronze, queryable) | schema `raw` | 1 bảng / file nguồn, **mọi cột kiểu text** + `_batch_id`, `_loaded_at`, `_source_file` | Python COPY | Append-only, không làm sạch |
| Staging (Silver) | schema `stg` | Bảng đã ép kiểu, dedup, đổi tên, chuẩn hoá, cờ dẫn xuất; `int_*` models; seeds | dbt | Mọi rule làm sạch nằm trong SQL model + mô tả YAML |
| Warehouse (Gold) | schema `dw` | Dims + facts mục 7 | dbt | Surrogate key, unknown member -1, FK tests |
| Logical data marts | schema `bi` | Views theo chủ đề + view nối kết quả ML | dbt | **Power BI chỉ đọc schema này** |
| Model outputs | schema `ml` | Forecast, risk score, segment, allocation, recommendations | Python | Mỗi dòng có `model_run_id`, `model_version`; append, view `bi` lấy run mới nhất |
| Metadata | schema `meta` | etl_run_log, dq_results, data_dictionary, source_to_target, model_registry, decision_log | Python + dbt | Ghi mỗi lần chạy |

Bảng `ml.*` và `meta.*` được tạo rỗng bằng DDL trong `docker/postgres/init/` để view `bi` build được ngay lần đầu (trước khi ML chạy). Khai báo chúng là dbt `sources`.

**Lưu ý dbt**: override macro `generate_schema_name` để schema đúng tên `stg`, `dw`, `bi` (mặc định dbt sẽ ghép thành `<target_schema>_stg`). Bật `persist_docs` (relation + columns) để mô tả cột được ghi thành comment trong Postgres.

---

## 7. Thiết kế warehouse (Kimball)

Bốn bước Kimball: chọn business process → khai báo grain → chọn dimension → xác định fact. 6 fact + 1 factless (COULD), 10 dimensions (6 conformed: date, customer, product, seller, geography, order_status).

### 7.1 Grain

| Fact | Business process | Loại | 1 dòng là | Nguồn | Ưu tiên |
| --- | --- | --- | --- | --- | --- |
| fact_order_item | Bán hàng | Transaction | 1 item của 1 đơn (order_id + order_item_id) | orders, order_items | MUST |
| fact_order_fulfillment | Giao đơn | Accumulating snapshot | 1 đơn; mốc ngày được điền dần | orders, order_items | MUST |
| fact_review | Phản hồi khách | Transaction | 1 review của 1 đơn (review_id + order_id) | order_reviews | MUST |
| fact_payment | Thanh toán | Transaction | 1 lần thanh toán (order_id + payment_sequential) | order_payments | MUST |
| fact_lead_funnel | Thu hút seller | Accumulating snapshot | 1 MQL | mql, closed_deals | SHOULD |
| fact_seller_month | Hiệu suất seller | Periodic snapshot | 1 seller × 1 tháng | stg + các fact trên | SHOULD |
| fact_seller_product_activity | Độ rộng danh mục seller | Factless | 1 seller bán 1 product trong 1 tháng | fact_order_item | COULD |

### 7.2 Bus matrix

| Fact | dim_date (roles) | dim_customer | dim_product | dim_seller | dim_geography (roles) | dim_payment_type | dim_order_status | Lead dims |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fact_order_item | purchase, shipping_limit | ✔ | ✔ | ✔ | customer, seller | | ✔ | |
| fact_order_fulfillment | purchase, approved, carrier, delivered, estimated | ✔ | | primary seller | customer, seller | | ✔ | |
| fact_review | review_creation, review_answer | ✔ | | primary seller | customer | | ✔ | |
| fact_payment | purchase | ✔ | | | | ✔ | ✔ | |
| fact_lead_funnel | first_contact, won, first_sale | | | ✔ (won deals) | | | | origin, profile, sales_rep |
| fact_seller_month | month | | | ✔ | seller | | | |
| fact_seller_product_activity | month | | ✔ | ✔ | | | | |

### 7.3 Quy ước chung

- **Surrogate key**: số nguyên (bigint) **xác định từ natural key** bằng macro `int_sk(cols)` = `('x' || left(md5(concat_ws('|', cols...)), 15))::bit(60)::bigint`. Lý do: ổn định giữa các lần build và khi load incremental (row_number sẽ đổi key). Mỗi dim có **unknown member key = -1**.
- **Date key**: integer `YYYYMMDD`; `-1` khi sự kiện chưa xảy ra / null.
- **Customer grain**: Olist cấp `customer_id` mới cho mỗi đơn → `dim_customer` khoá theo `customer_unique_id`; staging dựng map `customer_id → customer_unique_id`.
- **Nhiều seller trong 1 đơn**: fact cấp item giữ seller thật; fact cấp đơn (fulfillment, review) dùng **primary seller = seller của item có `price` cao nhất; hoà → `seller_id` nhỏ nhất theo thứ tự chữ**. Ghi vào metadata và báo cáo.
- **Tỷ lệ không lưu dạng %**: mọi ratio (late rate, avg score, conversion) lưu dưới dạng tử số + mẫu số cộng được.
- **Tiền tệ / thời gian**: giữ BRL; timestamp dùng nguyên, không đổi timezone.
- **Dual granularity**: chi tiết cấp item + snapshot tháng. Dữ liệu dẫn xuất (late flag, delay days) tính trong warehouse, không sửa tay.
- **Accumulating snapshot** cố ý vi phạm tính "non-updatable" → mỗi dòng có `_dw_loaded_at`, `_dw_updated_at` để audit.
- **Approach**: Kimball bottom-up bus architecture; `stg` đóng vai lớp tích hợp kiểu Inmon (so sánh trong báo cáo).

### 7.4 Dimensions

| Dimension | Grain & key | Thuộc tính | Hierarchy | Thay đổi |
| --- | --- | --- | --- | --- |
| dim_date | 1 ngày, 2016-01-01 → 2019-12-31; `date_key` YYYYMMDD | full_date, day_name, day_of_week_no, is_weekend, iso_week, month_no, month_name, quarter, year, year_month, is_br_holiday, holiday_name, is_black_friday_week | day → week; day → month → quarter → year | Sinh 1 lần bằng `dbt_utils.date_spine`; holiday join từ `stg_br_holidays` |
| dim_customer | 1 người: NK `customer_unique_id` | first_order_date_key, first_order_state, customer_geo_key (zip của đơn đầu), order_count_lifetime | none | Type 1. **Không** chứa segment (segment ở `bi.v_dim_customer` join `ml`, tránh vòng phụ thuộc dw ↔ ml) |
| dim_product | 1 product_id | category_pt, category_en, category_group (~10 nhóm, seed), photos_qty, name_length, description_length, weight_g, length_cm, height_cm, width_cm, volume_cm3, weight_band, size_band | product → category → category_group | Type 1 |
| dim_seller | 1 phiên bản seller: NK seller_id + valid_from | seller_id, seller_geo_key, seller_tier (New, Bronze, Silver, Gold, At-risk, Unscored), tier_rule_version, valid_from, valid_to, is_current, has_sales, is_from_funnel | seller → state → region (qua geography) | **Type 2 trên seller_tier**; Type 1 trên các cột khác. Tập seller = sellers ∪ closed_deals.seller_id (seller chốt deal nhưng chưa bán vẫn có key) |
| dim_geography | 1 zip prefix 5 số | zip_prefix, city (bỏ dấu), state_code, state_name, region_name (5 vùng), latitude, longitude (trung bình điểm), ibge_state_id, state_population | zip → city → state → region | Type 1. Role-playing: customer geo, seller geo. Tập zip = geolocation ∪ customers ∪ sellers; zip thiếu toạ độ → lat/lng null, state lấy từ bảng customer/seller |
| dim_payment_type | Junk: payment_type × instalment_band | payment_type, instalment_band (1, 2–3, 4–6, 7–10, 11+), is_instalment | none | Static (seed `instalment_band`) |
| dim_order_status | 1 status | order_status, status_group, counts_as_sale | status → group | Static (seed `order_status_map`) |
| dim_lead_origin | 1 cặp origin + landing_page_id | origin, landing_page_id | none | Type 1 |
| dim_lead_profile | Junk thuộc tính lead (chỉ lead đã chốt) | business_segment, lead_type, lead_behaviour_profile, business_type, has_company, has_gtin, stock_band | none | Type 1. Lead chưa chốt → -1 |
| dim_sales_rep | 1 cặp sdr_id + sr_id | sdr_id, sr_id | none | Type 1 |

Seed `order_status_map` (xác nhận giá trị ở S1):

| order_status | status_group | counts_as_sale |
| --- | --- | --- |
| delivered | Completed | true |
| shipped, invoiced, processing, approved, created | Open | true |
| canceled, unavailable | Cancelled | false |

Snowflake comparison (chỉ trong báo cáo): giữ `dim_geography` dạng star; trình bày phương án snowflake (dim_zip, dim_city, dim_state, dim_region) với trade-off: ít dư thừa hơn, nhiều join hơn, khó browse hơn.

### 7.5 Facts

| Fact | Dimension keys | Degenerate | Measures & additivity |
| --- | --- | --- | --- |
| fact_order_item | purchase_date_key, shipping_limit_date_key, customer_key, product_key, seller_key (version hợp lệ tại purchase), customer_geo_key, seller_geo_key, order_status_key | order_id, order_item_id | item_price, freight_value, item_total (= price + freight), item_count (=1): additive |
| fact_order_fulfillment | purchase_date_key, approved_date_key, carrier_date_key, delivered_date_key, estimated_date_key, customer_key, primary_seller_key, customer_geo_key, seller_geo_key, order_status_key | order_id | Additive: item_count, order_value, freight_total, is_delivered, is_late, is_dispatch_late. Lags (ngày): approval_lag, dispatch_lag, transit_lag, delivery_lag, promised_lag, delay_days — additive nhưng luôn báo cáo = tổng / số đơn đã giao. Non-additive: seller_customer_distance_km (haversine) |
| fact_review | review_creation_date_key, review_answer_date_key, customer_key, primary_seller_key, customer_geo_key, order_status_key | review_id, order_id | review_count, score_sum (additive; avg = score_sum/review_count), is_low_score (≤2), has_comment, comment_length, response_hours. review_score đơn lẻ non-additive. `is_latest_for_order` = review dùng cho KPI |
| fact_payment | purchase_date_key, customer_key, payment_type_key, order_status_key | order_id, payment_sequential | payment_value, payment_count: additive; instalments: non-additive |
| fact_lead_funnel | first_contact_date_key, won_date_key, first_sale_date_key, lead_origin_key, lead_profile_key, sales_rep_key, seller_key | mql_id | lead_count, is_won, days_to_close, declared_catalog_size, declared_monthly_revenue (additive, tự khai → độ tin thấp), gmv_first_90_days (Σ item_price của seller trong 90 ngày kể từ won_date), has_full_90d_window (won_date + 90 ≤ ANALYSIS_END; chỉ so kênh trên các lead có cờ này). Key = -1 khi sự kiện chưa xảy ra |
| fact_seller_month | month_date_key (ngày đầu tháng), seller_key (version hợp lệ cuối tháng), seller_geo_key | — | Additive: orders, items, gmv, delivered_orders, late_orders, cancelled_orders, review_count, score_sum. Semi-additive: is_active (cộng qua seller, không cộng qua tháng). Non-additive: distinct_customers. Dòng dày đặc từ tháng bán đầu tiên của seller đến ANALYSIS_END |
| fact_seller_product_activity | month_date_key, seller_key, product_key | — | Không measure; đếm dòng = số listing hoạt động |

---

## 8. Business rules & KPI dictionary (định nghĩa chung — giải quyết vấn đề "hai quản lý hai con số")

Mọi DAX measure trong Power BI và mọi query phải dùng đúng định nghĩa này. Bản đọc được: `docs/kpi_dictionary.md`.

| KPI | Định nghĩa | Công thức |
| --- | --- | --- |
| GMV | Giá trị hàng bán, không gồm phí ship, chỉ đơn counts_as_sale | Σ fact_order_item.item_price (status counts_as_sale) |
| Revenue incl. freight | | Σ item_total |
| Orders | Số đơn tính là bán | COUNT fact_order_fulfillment (counts_as_sale) |
| AOV | | Σ order_value / Orders |
| is_delivered | order_status = delivered và có delivered_customer_date | cờ trong fact_order_fulfillment |
| is_late | is_delivered và `delivered_customer_date::date > estimated_delivery_date::date` | cờ |
| delay_days | `delivered::date − estimated::date` (âm = sớm) | chỉ khi is_delivered |
| Late rate | | Σ is_late / Σ is_delivered |
| Avg delivery days | | Σ delivery_lag / Σ is_delivered |
| is_dispatch_late | carrier_date > max(shipping_limit_date) của các item trong đơn | cờ |
| Dispatch late rate | | Σ is_dispatch_late / số đơn có carrier_date |
| Avg review score | Chỉ review `is_latest_for_order` | Σ score_sum / Σ review_count |
| Low-score rate | | Σ is_low_score / Σ review_count |
| Cancel rate | | đơn status_group = Cancelled / tổng đơn |
| Repeat customer rate | Khách có ≥2 đơn counts_as_sale / tổng khách | |
| Lead conversion | | Σ is_won / Σ lead_count |
| Days to close | won_date − first_contact_date | Σ days_to_close / số lead đã chốt có days_to_close (bỏ lead lỗi won_before_contact) |
| Seller late rate | | Σ late_orders / Σ delivered_orders (fact_seller_month) |
| Active sellers | Seller có ≥1 đơn trong tháng | Σ is_active trong 1 tháng; nhiều tháng → trung bình theo tháng, không cộng dồn |

Lags (ngày, dạng numeric có phần lẻ): approval_lag = approved − purchase; dispatch_lag = carrier − approved; transit_lag = delivered − carrier; delivery_lag = delivered − purchase; promised_lag = estimated − purchase.

---

## 9. Staging rules (S3) — xác nhận từng rule ở profiling S1

- **Chung**: trim text, chuẩn hoá chuỗi rỗng → null, ép kiểu, zip prefix `lpad(zip, 5, '0')`, dedup theo natural key lấy `_loaded_at` mới nhất (hỗ trợ replay/append).
- **Orders**: parse timestamps; dẫn xuất is_delivered, is_late, delay_days; delivered date < purchase date → set null và log vào `stg.dq_rejects` (hoặc cờ `_dq_issue`). S1: không có dòng nào delivered < purchase, nhưng 1 359 đơn carrier < approved, 166 đơn carrier < purchase, 23 đơn delivered < carrier → giữ timestamp, gắn `_dq_issue`, lag âm tương ứng = null.
- **Order items**: ép numeric price/freight; shipping_limit_date timestamp.
- **Reviews**: giữ mọi dòng; `is_latest_for_order` theo review_answer_timestamp (hoà → review_creation_date, rồi review_id); review_id xuất hiện ở nhiều đơn → giữ, khoá fact là (review_id, order_id).
- **Payments**: payment_installments 0 → 1; ghi nhận các dòng payment_type `not_defined`.
- **Customers**: map customer_id → customer_unique_id (`int_customer_map`).
- **Geolocation**: gộp về 1 dòng / zip prefix (mean lat/lng, city & state xuất hiện nhiều nhất), bỏ dấu (unidecode/`unaccent` extension) + lower case, loại điểm ngoài bounding box Brazil (lat −34 → 5.5; lng −74 → −34).
- **Products**: category null → `unknown`; join translation (category thiếu bản dịch → giữ tên PT); weight_g = 0 → null; sửa cột `lenght` → `length`; volume_cm3 = L×H×W; weight_band, size_band theo seed hoặc CASE.
- **States/cities**: khớp mã bang 2 ký tự Olist với `state_code` của `br_states` và seed `br_state_population`; bỏ dấu tên city (city lấy từ geolocation/customers/sellers, không có danh mục municipality).
- **Funnel**: parse dates, dedup theo mql_id, test tỷ lệ khớp seller_id với sellers (S1: 45,1%); origin null → `unknown`; average_stock → stock_band.
- **Holidays**: `stg_br_holidays(date, holiday_name)`.

Intermediate models (schema `stg`): `int_customer_map`, `int_order_primary_seller`, `int_order_agg` (item_count, order_value, freight_total, max shipping_limit), `int_seller_month_metrics`, `int_seller_tier_monthly`, `int_seller_tier_versions`.

---

## 10. Seller tier — SCD Type 2 (S6)

1. `int_seller_month_metrics` (từ **stg**, không từ fact, để tránh vòng phụ thuộc): mỗi seller × tháng: orders, delivered, late, review_count, score_sum, tính thêm cửa sổ trượt 3 tháng (orders_3m, late_rate_3m, avg_score_3m) để tier không nhảy lung tung.
2. `int_seller_tier_monthly`: áp rule từ seed `seller_tier_rules` (Seller Quality Manager sửa được; có `rule_version`, chọn bằng var `seller_tier_rule_version`). Rule v1 (đã chỉnh 01/11, xem changelog):
   - New: < 3 tháng kể từ đơn đầu (chỉ theo thâm niên)
   - Bronze (ít đơn): đủ thâm niên nhưng orders_3m < 5 → chưa đủ dữ liệu chấm At-risk/Silver/Gold
   - At-risk: late_rate_3m ≥ 0.15 hoặc avg_score_3m < 3.5 (với orders_3m ≥ 5)
   - Gold: orders_3m ≥ 50, late_rate_3m < 0.05, avg_score_3m ≥ 4.5
   - Silver: orders_3m ≥ 15, late_rate_3m < 0.08, avg_score_3m ≥ 4.2
   - Bronze: còn lại
   - Tháng không có đơn: giữ tier tháng trước (không tạo version mới); riêng New hết 3 tháng → Bronze
   - Thiếu dữ liệu (chưa có đơn giao / review trong 3 tháng) → điều kiện tương ứng coi là false
3. `int_seller_tier_versions`: so tier tháng này với tháng trước (`lag`), đánh số version (`sum(changed) over`), `valid_from` = ngày cuối tháng tier được chấm + 1 ngày (tier chỉ "biết" khi tháng kết thúc), `valid_to` = valid_from của version kế − 1 ngày, version cuối `valid_to = 9999-12-31`, `is_current = true`. **Version đầu tiên**: `valid_from = 1900-01-01`, tier = New (để mọi sự kiện trước lần chấm đầu đều tra được). Seller không có doanh số: 1 version tier = Unscored.
4. `dim_seller` = versions + thuộc tính Type 1.
5. Lookup trong fact: `event_date between valid_from and valid_to`.
6. Tests bắt buộc: đúng 1 dòng is_current / seller; không chồng lấn khoảng thời gian; point-in-time lookup trả đúng 1 version cho mọi ngày (`tests/assert_dim_seller_*`, `assert_fact_seller_point_in_time`).
   Kết quả 01/11: 3 557 seller, 8 189 version (tối đa 12 / seller); tier hiện hành: Bronze 2 226, New 536, Unscored 462, Silver 168, At-risk 159, Gold 6.
7. Load live (sau backfill): dbt snapshot (strategy `check` trên seller_tier) — snapshot chỉ ghi trạng thái quan sát khi chạy, không dựng lại lịch sử, nên backfill dùng SQL như trên. Ghi điều này trong báo cáo.

---

## 11. Data quality, reconciliation, metadata (S7, F5, P8)

### 11.1 Tests (chạy mỗi lần build, kết quả ghi `meta.dq_results`)

| Loại | Ví dụ |
| --- | --- |
| Schema (dbt generic) | unique + not_null mọi key; relationships từ mọi FK fact → dim; accepted_values cho order_status, payment_type, seller_tier |
| Business rule (singular) | delivered không trước purchase; review_score ∈ [1,5]; đúng 1 version current / seller; không chồng version; mọi fact có key -1 < 1% (warn) |
| Reconciliation | row count raw → stg → dw (chênh lệch giải thích bằng filter có ghi chép); Σ item_total theo đơn ≈ Σ payment_value (ngưỡng tolerance đặt theo profiling, severity warn); fact_order_fulfillment đúng 1 dòng / order trong orders; Σ fact_seller_month = Σ fact_order_item cùng tháng |

### 11.2 Metadata

| Bảng | Nội dung | Ghi bởi |
| --- | --- | --- |
| meta.etl_run_log | run_id, batch_id, step, started_at, ended_at, rows_in, rows_out, status, message | load_raw.py, Airflow callbacks |
| meta.dq_results | run_id, test_name, test_type, model, status, failures, executed_at | meta_publish.py parse `target/run_results.json` |
| meta.data_dictionary | schema, table, column, data_type, description | từ dbt manifest/catalog |
| meta.source_to_target | target_model, target_column, source_models, transformation_note | từ dbt manifest (depends_on) |
| meta.model_registry | model_run_id, model_name, model_version, trained_at, train_window, params_json, metrics_json | ml/common/registry.py |
| meta.decision_log (COULD) | rec_id, decided_by, decision (accept/reject), note, decided_at | nhập tay / script |
| meta.dq_issue_summary | layer, model_name, issue, issue_rows, total_rows, issue_pct | dbt model `models/quality/` — lỗi được giữ lại và gắn cờ (`_dq_issue`) + bất thường đã biết + số đơn lệch tiền vượt tolerance (dbt ghi failures = 0 khi test warn dưới ngưỡng) |

`meta_publish.py` chạy ngay sau `dbt build` (trước `dbt docs generate`, lệnh này ghi đè `run_results.json`): ghi `meta.dq_results`, 1 dòng `dbt:<lệnh>` vào `meta.etl_run_log`, `meta.data_dictionary` (kiểu dữ liệu đọc từ `information_schema`), `meta.source_to_target` (lineage cấp model).

Lineage graph từ `dbt docs` chụp làm hình trong báo cáo. Các loại metadata khớp môn học: structure, source data, transformation, data model, history of extracts.

---

## 12. Incremental load & replay (P7 + F8, SHOULD)

- Mặc định: full refresh.
- Replay: `scripts/replay_month.py --month 2017-11` tách các dòng nguồn có purchase month = tháng đó (orders + items, payments, reviews, customers liên quan) → ghi file vào landing với extract_date mới → load_raw append với `_batch_id` mới → `dbt build --select tag:incremental+`.
- Models incremental: stg_orders, stg_order_items, stg_order_payments, stg_order_reviews, fact_order_item, fact_payment, fact_review, fact_order_fulfillment (`unique_key=order_id`, strategy `delete+insert`; `merge` nếu dbt-postgres + PG ≥15 hỗ trợ). Dims dùng key băm nên ổn định.
- Demo: tháng mới đến → dòng accumulating snapshot cập nhật mốc ngày → Power BI refresh. Minh hoạ periodic extraction và độ trễ giữa sự kiện vận hành và warehouse.

---

## 13. ML & decision support (schema `ml`)

Quy tắc chung:
- Đọc từ `dw` (hoặc `bi`), ghi vào `ml`, **append** kèm `model_run_id` (uuid) và `model_version`; đăng ký vào `meta.model_registry` với metrics.
- Split theo thời gian (train trước, test sau), không random split.
- Feature chỉ dùng thông tin có tại thời điểm ra quyết định (tránh leakage, ví dụ late-risk không được dùng delivered date).
- Mỗi model có baseline đơn giản để so.

| ID | Module | Người dùng | Target / phương pháp | Output |
| --- | --- | --- | --- | --- |
| M3 | Late-delivery risk + promise what-if (MUST) | Logistics | Classifier LightGBM (baseline: logistic regression) dự đoán is_late tại thời điểm mua. Features: distance_km, seller late rate lịch sử (trước ngày mua), seller_state→customer_state, category_group, weight/volume, freight_value, promised_lag, tháng, is_black_friday_week. Metric: ROC-AUC, PR-AUC, recall@top-10% | `ml.order_late_risk(order_id, risk_score, risk_band, model_run_id, …)`; `ml.promise_whatif(route_seller_state, route_customer_state, buffer_days ∈ [-5..+7], orders, late_orders, late_rate, avg_promised_days)` tính lại is_late nếu estimated + buffer — Power BI what-if slider |
| M4 | CRM segmentation + voucher allocation (MUST) | CRM | Segment RFM + trải nghiệm (đã bị giao trễ, review ≤2) bằng quy tắc hoặc KMeans; propensity mua lại (nếu đủ positive) hoặc điểm ưu tiên theo quy tắc; tối ưu phân bổ ngân sách cố định bằng PuLP (max Σ p_i × uplift_seg × value_i − cost, ràng buộc tổng ngân sách, trần mỗi segment). uplift là **giả định** theo segment, là tham số what-if | `ml.customer_segment_history(customer_unique_id, as_of_date, segment, r, f, m, had_late, low_review, model_run_id)`; `ml.voucher_allocation(scenario_id, budget, customer_unique_id, segment, expected_value, voucher_value, model_run_id)` cho nhiều mức budget |
| M5 | GMV forecast theo category_group × region (SHOULD) | Commerce | Monthly, baseline seasonal-naive vs ETS/SARIMA (statsmodels); train 2017-01 → 2018-05, test 3 tháng cuối; MAPE | `ml.gmv_forecast(month, category_group, region_name, yhat, yhat_lower, yhat_upper, model_run_id)`; growth what-if = forecast × (1 + growth%) trong Power BI |
| M6 | Seller risk + channel value (COULD) | Seller QM | Xác suất seller thành At-risk hoặc ngừng bán 2 tháng tới (logistic/LightGBM trên fact_seller_month). Channel value: conversion và gmv_first_90_days theo origin (mô tả, không ML nếu dữ liệu thưa) | `ml.seller_risk_score(seller_id, as_of_month, risk_score, risk_band, top_drivers, model_run_id)`; `ml.channel_value(origin, leads, won, conversion, gmv_90d_per_lead)` |
| M7 | Recommendations (MUST, phần nào có thì làm) | Cả 4 | Quy tắc trên output M3–M6 + KPI: tuyến cần sửa (late rate cao, volume lớn), seller cần cảnh báo/khen thưởng, category×region nên đầu tư, danh sách khách nhận voucher | `ml.recommendations(rec_id, decision_maker, subject_type, subject_id, action, rationale, score, model_run_id, status='proposed')` |

---

## 14. Serving: schema `bi` + Power BI

### 14.1 Views `bi` (F6)

- Conformed dims: `v_dim_date`, `v_dim_customer` (join segment mới nhất từ `ml.customer_segment_history`), `v_dim_product`, `v_dim_seller` (cả lịch sử và cờ current), `v_dim_customer_geo`, `v_dim_seller_geo`, `v_dim_payment_type`, `v_dim_order_status`, `v_dim_lead_*`.
- Facts theo chủ đề: `v_fact_sales` (order_item), `v_fact_fulfillment`, `v_fact_review`, `v_fact_payment`, `v_fact_seller_month`, `v_fact_lead_funnel`.
- ML: `v_order_late_risk`, `v_promise_whatif`, `v_gmv_forecast`, `v_voucher_allocation`, `v_seller_risk`, `v_recommendations` — mỗi view chỉ lấy `model_run_id` mới nhất.
- DQ: `v_dq_latest`, `v_etl_runs`.
- Tên cột thân thiện, không đổi grain.

### 14.2 Power BI (Import mode, file `.pbip`)

Semantic model dạng galaxy: conformed dims dùng chung; role-playing date/geography bằng view riêng hoặc inactive relationship + USERELATIONSHIP. Measures DAX đặt trong một bảng `_Measures`, đúng định nghĩa mục 8.

| # | Trang | Người dùng | Pha Simon | Owner |
| --- | --- | --- | --- | --- |
| 1 | Executive Overview | Commerce | Intelligence | F (TV3 — Xuân Vinh) |
| 2 | Growth: Category × Region + Forecast + growth what-if | Commerce | Design / Choice | M (TV4 — Trường An) |
| 3 | Fulfillment & Late Delivery (route map, lags) | Logistics | Intelligence | F (TV3 — Xuân Vinh) |
| 4 | Promise-date What-if & Routes to fix | Logistics | Design / Choice | M (TV4 — Trường An) |
| 5 | Seller Quality & Tier Migration | Seller QM | Intelligence / Choice | F (TV3 — Xuân Vinh) |
| 6 | Lead Funnel & Channel Value | Seller QM | Intelligence / Choice | F (TV3 — Xuân Vinh) |
| 7 | CRM Segments & Voucher Allocation | CRM | Design / Choice | M (TV4 — Trường An) |
| 8 | Data Quality & Pipeline Health | Tất cả | Trust | F (TV3 — Xuân Vinh) |

---

## 15. Orchestration — DAG `olist_pipeline` (P6)

```
[download_kaggle, copy_manual, gen_holidays] → upload_to_lake → load_raw
  → dbt_deps → dbt_seed → dbt_build (stg, dw, bi)
  → [ml_late_risk, ml_crm, ml_forecast, ml_seller_risk] → ml_recommendations
  → meta_publish → dbt_docs_generate
```

- `schedule`: `@daily` (hoặc `None` + trigger tay khi demo), `catchup=False`, retries=1.
- Dùng BashOperator gọi đúng các script/command như Makefile (một nguồn logic).
- Callback on_failure/on_success ghi `meta.etl_run_log`.
- Biến kết nối lấy từ env, không hardcode.

---

## 16. Quy ước code & guardrails cho Claude

- **Không bao giờ** sửa file trong landing/data lake hay bảng `raw` ngoài append bởi load_raw.
- Mọi làm sạch nằm trong dbt model, có mô tả trong YAML. Không sửa dữ liệu bằng tay.
- Mọi model mới phải có YAML: description cho model và từng cột, test key (unique/not_null), relationships cho FK.
- Không lưu tỷ lệ % trong fact; lưu tử số + mẫu số.
- Tên: snake_case; `stg_<source>`, `int_<desc>`, `dim_<name>`, `fact_<name>`, `v_<name>`; key `<name>_key`, date key `<role>_date_key`, cờ `is_`/`has_`.
- SQL: CTE style (import CTEs → logic CTEs → final select), không `select *` ở dw/bi.
- Python: type hints, đọc config từ `.env`, logging thay print, script idempotent và có `if __name__ == "__main__"`.
- Không commit `.env`, `.venv/`, `data/landing/`, `target/`, `logs/`. **Có** commit `data/raw/` (CSV nguồn dùng chung), `data/fallback/`, `uv.lock`.
- Khi đổi grain / thêm cột fact / đổi định nghĩa KPI: cập nhật mục 7–8 của file này và `docs/kpi_dictionary.md`.
- Ưu tiên MUST trước SHOULD/COULD. Nếu một task phụ thuộc thứ chưa có, tạo stub/mock đúng schema mục 7 thay vì đổi thiết kế.
- Branch: `feat/<task-id>-<mô-tả>` (vd `feat/S6-seller-scd2`), PR vào `main`, CI tối thiểu = `dbt build` pass trên máy người review.
- Commit / PR: **không** thêm dòng `Co-Authored-By: Claude …` hay "Generated with Claude Code" — Claude không được xuất hiện trong danh sách contributor. Đã tắt sẵn bằng `.claude/settings.json` (`attribution.commit = ""`, `attribution.pr = ""`); commit message theo Conventional Commits.

---

## 17. Checklist module / task (cập nhật trạng thái khi làm)

Trạng thái: `[ ]` chưa làm · `[~]` đang làm · `[x]` xong. Ưu tiên: MUST / SHOULD / COULD.

Ghi chú 30/10: khung code (`[~]`) đã có nhưng chưa chạy thử end-to-end; người phụ trách chạy, sửa lỗi rồi đánh `[x]`.

### P — Data Platform, Ingestion, Orchestration (TV1 — Ngọc Cẩn)
- [x] P1 MUST Repo skeleton, .gitignore, .env.example, Makefile, README quickstart
- [x] P2 MUST docker-compose (postgres + init SQL schemas/meta/ml, azurite); Airflow service (SHOULD)
- [~] P3 MUST download_kaggle.py (2 dataset → landing local, extract_date) — đường data/raw chạy được; nhánh Kaggle API chưa test
- [x] P4 MUST gen_holidays.py (IBGE API đã bỏ, bang/vùng từ br_states.csv)
- [x] P5 MUST upload_to_lake.py, load_raw.py (COPY text + metadata cols + etl_run_log)
- [x] P6 SHOULD Airflow DAG olist_pipeline + Dockerfile (dbt venv) — 15/15 task success (01/11); chạy lại khi có model/ML thật
- [ ] P7 SHOULD replay_month.py (+ cùng F8)
- [x] P8 MUST meta_publish.py (dq_results, data_dictionary, source_to_target), DDL meta.* — 01/11: 234 test, 383 cột, 39 model; thêm log dbt vào etl_run_log, dq_issue_summary
- [ ] P9 MUST dbt docs + lineage figure; `make all` chạy sạch trên máy mới

### S — Staging, Dimensions, Data Quality (TV2 — Minh Hiếu)
- [x] S1 MUST Profiling → docs/profiling.md (xác nhận mục 1.3, 7.4 seed, 9, tolerance item vs payment) — 01/11, query ở docs/profiling.sql
- [x] S2 MUST dbt project init, sources.yml, macros (generate_schema_name, int_sk, cleaning, haversine/lag_days), seeds
- [x] S3 MUST stg_* cho 11 file + br_states + calendar_events + holidays; int_customer_map — 01/11
- [x] S4 MUST dim_date, dim_geography, dim_product, dim_customer, dim_order_status, dim_payment_type — 01/11
- [x] S5 SHOULD dim_lead_origin, dim_lead_profile, dim_sales_rep, fact_lead_funnel — 01/11; conversion 10,53%, có has_full_90d_window
- [x] S6 SHOULD int_seller_month_metrics, int_seller_tier_monthly, int_seller_tier_versions, dim_seller SCD2 — 01/11 (rule New chỉnh theo thâm niên, xem mục 10)
- [x] S7 MUST tests dims + business-rule tests + YAML dictionary cho dims — 01/11; SCD2: 1 version current, không chồng lấn, liên tục, point-in-time

### F — Facts, BI marts, Power BI (TV3 — Xuân Vinh)
- [x] F1 MUST int_order_primary_seller, int_order_agg — 01/11
- [x] F2 MUST fact_order_item, fact_payment — 01/11
- [x] F3 MUST fact_order_fulfillment (accumulating, lags, distance), fact_review — 01/11; late rate 6,77% khớp profiling
- [x] F4 SHOULD fact_seller_month; COULD fact_seller_product_activity — 01/11, cả hai
- [x] F5 MUST reconciliation tests + YAML facts — 01/11: equal_rowcount stg↔fact, Σ tiền stg = fact, item vs payment (tolerance A5), key -1 < 1%, Σ fact_seller_month = Σ fact_order_item theo tháng, funnel won = closed_deals
- [x] F6 MUST schema bi views + docs/kpi_dictionary.md — 02/11: 21 view (11 dim, 7 fact, 3 DQ), user chỉ đọc `powerbi_reader`, giải thích ở docs/bi_layer.md; view ML để khi làm nhóm M
- [ ] F7 MUST Power BI semantic model + DAX measures + trang 1, 3, 5, 6, 8
- [ ] F8 SHOULD incremental models (cùng P7)

### M — ML & Decision Support (TV4 — Trường An)
- [~] M1 MUST EDA + kiểm tra khả thi trên CSV (repeat rate, funnel match, chuỗi thời gian) — số liệu khả thi đã có trong docs/profiling.md (A6–A8, phát hiện 1, 4); còn notebook EDA + kết luận cho từng bài toán ML
- [~] M2 MUST ml/common (db io, registry, model_run_id), DDL ml.*
- [ ] M3 MUST late-risk model + ml.promise_whatif
- [ ] M4 MUST CRM segmentation + voucher allocation (PuLP)
- [ ] M5 SHOULD GMV forecast
- [ ] M6 COULD seller risk + channel value
- [ ] M7 MUST ml.recommendations
- [ ] M8 MUST Power BI trang 2, 4, 7 (what-if parameters)

### R — Báo cáo & demo (cả nhóm)
- [ ] R1 Báo cáo hoàn chỉnh (outline trong PROJECT_PLAN.md)
- [ ] R2 Demo script + tập dượt

---

## 18. Giả định cần xác nhận (cập nhật sau S1)

| # | Giả định | Trạng thái |
| --- | --- | --- |
Đã đo ở S1 (01/11/2026), chi tiết và query: `docs/profiling.md`, `docs/profiling.sql`.

| # | Giả định | Trạng thái |
| --- | --- | --- |
| A1 | Danh sách order_status và payment_type như mục 7.4 / 9 | **xác nhận**: 8 status khớp seed; 5 payment_type gồm `not_defined` (3 dòng, đơn canceled, value 0); installments 0 ở 2 dòng → 1; tối đa 24 kỳ |
| A2 | review_id trùng trên nhiều order và order có nhiều review | **xác nhận**: 789 review_id trên > 1 đơn; 547 đơn > 1 review (202 khác điểm); 768 đơn không review |
| A3 | Geolocation nhiều điểm / zip, có điểm ngoài Brazil, city có dấu không đồng nhất | **xác nhận**: ~52,6 điểm/zip; 42 điểm (21 zip) ngoài bbox, 5 zip toàn bộ ngoài → lat/lng null; 8 zip > 1 bang → mode; 8 011 → 5 969 city sau unaccent; 157 zip khách + 7 seller không có trong geolocation |
| A4 | Có product thiếu category / thiếu bản dịch | **xác nhận**: 610 product (1 603 item) thiếu category → `unknown`; 13 product thuộc 2 category thiếu bản dịch → giữ tên PT; 4 product weight 0 → null |
| A5 | Chênh lệch Σ item_total vs Σ payment_value theo đơn → tolerance | **chốt tolerance** max(1 BRL, 1% item_total), severity warn → 99,75% đơn đạt; 775 đơn không có item, 1 đơn không có payment |
| A6 | Tỷ lệ seller_id closed_deals khớp sellers | **45,1%** (380 / 842), cả 380 có đơn; 667 deal đủ cửa sổ 90 ngày → thêm `has_full_90d_window` |
| A7 | Tỷ lệ khách mua lặp lại | **3,12%** (2 997 / 96 096) → giữ hướng CRM mục 1.3 |
| A8 | Cửa sổ phân tích 2017-01-01 → 2018-08-31 | **xác nhận**: 20 tháng liên tục, 99 092 đơn (99,6%) |
| A9 | Zip prefix trong CSV có mất số 0 đầu hay không | **không mất** (raw là text, 23 995 zip khách bắt đầu bằng 0); vẫn giữ `lpad` phòng hờ |

---

## 19. Changelog thiết kế (so với bản mô tả gốc)

- 2026-10-30: Nén timeline từ "Week 1/2/3 + Stretch" thành 14 ngày, phân MUST/SHOULD/COULD.
- 2026-10-30: Chốt PostgreSQL thay BigQuery; dbt thay Spark; thêm MinIO làm data lake; Airflow chỉ điều phối.
- 2026-11-01: Thay MinIO (ngừng phát hành image community) bằng Azure Blob Storage: Azurite khi dev, ADLS Gen2 (Azure for Students) khi demo. boto3 → azure-storage-blob; env `MINIO_*`/`LAKE_BUCKET` → `AZURE_STORAGE_CONNECTION_STRING`/`LAKE_CONTAINER`.
- 2026-11-01: Bỏ IBGE Localidades API (chặn IP ngoài Brazil). Bang & vùng từ `data/raw/events_brazilstates/br_states.csv`; `ibge_state_id` thêm vào seed `br_state_population`; bỏ `raw.ibge_states`, `raw.ibge_municipalities`, `fetch_ibge.py`, `data/fallback/`. raw còn 14 bảng.
- 2026-11-02: F6 lớp `bi`: view mỏng, cột khoá snake_case + cột hiển thị Title Case; `v_dim_date` bỏ dòng -1 (để Mark as date table); role-playing date = 1 bảng Date + relationship inactive, geography = 2 view; `primary_seller_key` → `seller_key` trong view fulfillment/review; `v_dim_seller` thêm Current Tier / Previous Tier. User `powerbi_reader` (macro `grant_bi_reader`, on-run-end) chỉ đọc `bi`. Days to close = AVERAGE (bỏ 1 lead won_before_contact). View ML hoãn tới nhóm M. Chi tiết: docs/bi_layer.md.
- 2026-11-01: Rule tier v1 chỉnh: New chỉ theo thâm niên (< 3 tháng); đủ thâm niên mà orders_3m < 5 → Bronze; New hết 3 tháng không bán → Bronze. Lý do: vế "HOẶC orders_3m < 5" gốc làm seller bán 22 tháng bị nhãn New (08/2018: 288 seller) và seller ngừng bán giữ New mãi. Ngưỡng số trong seed giữ nguyên.
- 2026-11-01: Thêm model `meta.dq_issue_summary` (thư mục `models/quality/`); `meta_publish` đọc kiểu dữ liệu từ information_schema và ghi 1 dòng `dbt:<lệnh>` vào etl_run_log.
- 2026-11-01: Cờ trong fact (is_delivered, is_late, is_dispatch_late, is_low_score, has_comment) lưu dạng integer 0/1 để cộng trực tiếp; thêm `fact_order_fulfillment.has_carrier_date` làm mẫu số dispatch late rate. `order_value` = Σ price (không gồm ship), cùng cơ sở với GMV. Postgres container `shm_size: 512mb` (mặc định 64 MB làm lỗi join song song khi build fact).
- 2026-11-01: Sau profiling S1: chốt tolerance đối soát item vs payment = max(1 BRL, 1%); lag âm → null + `_dq_issue`; weight 0 → null; origin null → `unknown`; thêm `fact_lead_funnel.has_full_90d_window` (won_date kéo dài sau ANALYSIS_END).
- 2026-10-30: Segment khách chuyển từ dw.dim_customer sang bi.v_dim_customer (tránh vòng dw ↔ ml).
- 2026-10-30: Surrogate key băm từ natural key (ổn định cho incremental).
- 2026-10-30: dim_seller gồm cả seller từ closed_deals chưa có doanh số (has_sales, is_from_funnel); thêm tier Unscored.
- 2026-10-30: SCD2 version đầu valid_from = 1900-01-01; tier tháng M hiệu lực từ đầu tháng M+1; tier dùng cửa sổ trượt 3 tháng.
- 2026-10-30: fact_lead_funnel thêm first_sale_date_key vào bus matrix; lead_profile chỉ cho lead đã chốt, không dùng làm feature conversion.
- 2026-10-30: CRM đặt lại bài toán (segment theo trải nghiệm + uplift giả định) do tỷ lệ mua lặp thấp.
- 2026-10-30: dim_geography lấy hợp tập zip từ geolocation, customers, sellers.
- 2026-10-30: Chốt phân công: TV1 Ngọc Cẩn, TV2 Minh Hiếu, TV3 Xuân Vinh, TV4 Trường An (Trường An chuyển từ TV1 gợi ý sang TV4).
- 2026-10-30: Thêm `data/raw/` làm nơi đặt CSV tải tay (ingestion ưu tiên trước Kaggle API); thêm nguồn raw.br_states, raw.calendar_events (`copy_manual.py`).
- 2026-10-30: Dựng khung repo (P1) + khung P2–P6, P8, S2, M2; Airflow là compose profile `airflow` (bật bằng `make up-airflow`); dbt docs serve cổng 8081.
- 2026-10-30: Chuyển môi trường Python sang uv (`pyproject.toml` + `uv.lock`, `.python-version` 3.11); Makefile gọi `uv run`; `requirements.txt` sinh từ lock. Thêm `PYTHONUTF8=1` cho dbt trên Windows.
- 2026-10-30: `data/raw/` được commit lên repo để cả nhóm dùng chung (chỉ `data/landing/` bị ignore).
