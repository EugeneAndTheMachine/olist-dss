# Olist Data Warehouse & Decision Support

Assignment môn Data Warehouse — nhóm 4 người. Kimball DW + Medallion (Azure Blob / Azurite → PostgreSQL raw/stg/dw/bi) + dbt + Airflow + ML/what-if + Power BI, hỗ trợ 4 người ra quyết định của sàn Olist theo 3 pha Simon.

- Thiết kế kỹ thuật (nguồn sự thật): [`CLAUDE.md`](CLAUDE.md)
- Mô tả dự án & phân công: [`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md)
- **Hướng dẫn setup chi tiết: [`docs/SETUP.md`](docs/SETUP.md)**
- Data lake trên Azure (Azure for Students): [`docs/AZURE_SETUP.md`](docs/AZURE_SETUP.md)
- Power BI: [`powerbi/README.md`](powerbi/README.md)

## Quickstart

Cần: Docker Desktop, [uv](https://docs.astral.sh/uv/), GNU make, Git Bash (Windows). Không cần tự cài Python — uv lo. Chi tiết ở `docs/SETUP.md`.

```bash
cp .env.example .env                 # dữ liệu nguồn đã có trong data/raw/, không cần Kaggle key
uv sync                              # tạo .venv (Python 3.11) theo uv.lock
make all                             # up → ingest → load-raw → dbt → ml → meta → docs
```

| Dịch vụ | Địa chỉ |
| --- | --- |
| PostgreSQL | `localhost:5432` / `olist_dw` (olist / olist) |
| Azurite (Azure Blob giả lập) | `http://127.0.0.1:10000/devstoreaccount1`, container `olist-lake`, xem bằng Azure Storage Explorer |
| Airflow (`make up-airflow`) | http://localhost:8080 (admin / admin) |
| dbt docs (`make docs-serve`) | http://localhost:8081 |

## Thành viên

| Vai trò | Thành viên | Task |
| --- | --- | --- |
| TV1 — Data Platform & Orchestration | Ngọc Cẩn | P1–P9 |
| TV2 — Staging, Dimensions & Data Quality | Minh Hiếu | S1–S7 |
| TV3 — Facts, Data Marts & BI | Xuân Vinh | F1–F8 |
| TV4 — ML & Decision Support, trưởng báo cáo | Trường An | M1–M8 |

## Cấu trúc

```
ingestion/        Python: Kaggle/CSV nhóm/holidays → landing → Azure Blob → raw; meta_publish
dbt/olist_dw/     dbt: staging → intermediate → warehouse (dims, facts) → bi
ml/               M3–M7: late risk, CRM voucher, GMV forecast, seller risk, recommendations
airflow/dags/     DAG olist_pipeline
docker/           Dockerfile Airflow, SQL init PostgreSQL (schemas, meta.*, ml.*)
scripts/          replay_month.py
powerbi/          olist_dw.pbip
docs/             plan, setup, profiling, KPI dictionary, báo cáo
data/             raw/ (CSV nguồn, commit), landing/ (cache, gitignored)
pyproject.toml    dependency Python; uv.lock khoá phiên bản; requirements.txt sinh từ lock
```
