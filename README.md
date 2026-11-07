# Olist Data Warehouse & Decision Support

Assignment môn Data Warehouse. Kimball DW + Medallion (Azure Blob / Azurite → PostgreSQL raw/stg/dw/bi) + dbt + Airflow + ML + Power BI trên 1 dataset (*Brazilian E-Commerce Public Dataset by Olist*), trả lời 3 bài toán:

| # | Dashboard | → ML / quyết định |
| --- | --- | --- |
| P1 | Tỷ lệ và mật độ giao trễ theo khu vực | Đặt kho, tăng cường shipper ở khu vực nào |
| P2 | Quy mô, số đơn, GMV, số customer / seller theo khu vực (zip) | Nên phát triển khu vực nào |
| P3 | Hạng mục bán chạy, nhu cầu sản phẩm | Nên phát triển hạng mục nào |

> **Trạng thái:** hạ tầng (ingest → raw → meta, Airflow) đã chạy; phần nghiệp vụ (dbt staging / warehouse / bi, KPI, ML, Power BI) đang làm lại từ đầu.

- Thiết kế kỹ thuật (nguồn sự thật): [`implementation.md`](implementation.md)
- Phạm vi & thiết kế đích: [`docs/refactor_plan.md`](docs/refactor_plan.md)
- **Làm lại phần nghiệp vụ từng bước: [`docs/rebuild_guide.md`](docs/rebuild_guide.md)**
- Phân công: [`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md)
- Hướng dẫn setup chi tiết: [`docs/SETUP.md`](docs/SETUP.md) · Azure: [`docs/AZURE_SETUP.md`](docs/AZURE_SETUP.md) · Power BI: [`powerbi/README.md`](powerbi/README.md)

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

## Cấu trúc

```
ingestion/        Python: data/raw hoặc Kaggle → landing → Azure Blob → raw; meta_publish
dbt/olist_dw/     dbt: staging → intermediate → warehouse (dims, facts) → bi (đang làm lại)
ml/               common/ (db, model registry, time split); module theo bài toán làm sau
airflow/dags/     DAG olist_pipeline
docker/           Dockerfile Airflow, SQL init PostgreSQL (schemas, meta.*)
scripts/          replay_month.py (chưa hiện thực)
powerbi/          olist_dw.pbip
docs/             refactor plan, rebuild guide, phân công, setup, profiling, báo cáo
data/             raw/ecom_dataset/ (9 CSV nguồn, commit), landing/ (cache, gitignored)
pyproject.toml    dependency Python; uv.lock khoá phiên bản; requirements.txt sinh từ lock
```
