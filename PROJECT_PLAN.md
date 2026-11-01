# Olist Data Warehouse — Mô tả dự án & Phân công

> Tài liệu cho 4 thành viên. Đọc phần 1–4 để nắm dự án, phần 5 để biết việc của mình, phần 6 để biết hạn chót.
> Chi tiết kỹ thuật (tên bảng, cột, rule, lệnh) nằm trong `CLAUDE.md` ở thư mục gốc repo — Claude Code trên terminal cũng đọc file đó. Task ID (P*, S*, F*, M*) dùng chung giữa hai file.
> Cài đặt môi trường từng bước: `docs/SETUP.md`.
> Thời gian: **31/10/2026 → nộp 13/11/2026** (14 ngày). Nếu deadline khác, dịch các mốc ở phần 6.

---

## 1. Dự án trong một trang

**Bối cảnh.** Olist là "marketplace của các marketplace" ở Brazil: seller đăng sản phẩm một lần, Olist đưa lên nhiều sàn TMĐT và lo vận chuyển.

**Vấn đề.** Sàn muốn tăng doanh số nhưng không làm giảm chất lượng giao hàng hay mất khách. Dữ liệu đơn hàng, thanh toán, giao hàng, đánh giá và người bán không được nối theo định nghĩa chung, nên hai quản lý có thể đưa ra hai tỷ lệ giao trễ khác nhau trong cùng một cuộc họp.

**Giải pháp.** Xây một Data Warehouse theo Kimball (6 fact + 10 dimension, có SCD Type 2), một bộ định nghĩa KPI dùng chung, dashboard Power BI và vài mô hình ML/what-if, hỗ trợ 4 người ra quyết định theo 3 pha Simon (Intelligence → Design → Choice).

**Dữ liệu.**
- Brazilian E-Commerce (Olist, Kaggle): ~100k đơn 2016–2018, 9 bảng.
- Marketing Funnel (Olist, Kaggle): ~8k lead, 842 deal chốt, 2 bảng.
- Bổ sung: bang & vùng Brazil (`br_states.csv` nhóm chuẩn bị), mã IBGE + dân số theo bang (seed), ngày lễ Brazil (package `holidays`).

**Sản phẩm nộp.** Repo code chạy được bằng một lệnh (`make all`), Power BI dashboard 8 trang, báo cáo, buổi demo.

---

## 2. Bài toán: ai quyết định gì

| Người ra quyết định | Câu hỏi cần trả lời | Hệ thống đưa cho họ |
| --- | --- | --- |
| **Head of Commerce** (chiến lược) | Đầu tư tăng trưởng vào nhóm ngành và khu vực nào? | GMV, AOV, tăng trưởng theo category × region; dự báo GMV; slider "nếu tăng X% ở nhóm này thì sao" |
| **Logistics & CX Manager** (chiến thuật) | Sửa tuyến giao / seller nào? Hứa ngày giao thế nào? | Late rate theo tuyến (bang bán → bang mua), lags; điểm rủi ro trễ cho từng đơn; slider "nới/thắt ngày hứa X ngày thì tỷ lệ trễ đổi ra sao" |
| **Seller Quality Manager** (chiến thuật) | Seller nào cần hỗ trợ, cảnh báo, khen thưởng? Kênh thu hút seller nào đáng đầu tư? | Tier seller (New/Bronze/Silver/Gold/At-risk) và lịch sử chuyển tier; conversion & giá trị seller theo kênh marketing |
| **CRM Manager** (vận hành) | Khách nào nhận voucher? Chia ngân sách cố định ra sao? | Phân khúc khách; danh sách phân bổ voucher tối ưu theo mức ngân sách |

**Ba pha Simon** được thể hiện như sau: *Intelligence* = các trang dashboard KPI; *Design* = what-if parameters trong Power BI dùng bảng kịch bản tính sẵn; *Choice* = bảng đề xuất (hành động + lý do + điểm) để con người chấp nhận hoặc bác bỏ.

**Lưu ý khả thi** (sẽ xác nhận bằng số liệu trong 2 ngày đầu):
- Khách Olist hầu như chỉ mua 1 lần → bài toán CRM không dự đoán "giữ chân" thuần tuý mà chuyển sang: ưu tiên khách có trải nghiệm xấu (giao trễ, review thấp) và khách giá trị cao, với mức hiệu quả voucher là **giả định** (người dùng chỉnh bằng slider).
- Thông tin hồ sơ lead chỉ có cho lead đã chốt → không dùng để dự đoán khả năng chốt; phân tích kênh chủ yếu là mô tả (conversion, giá trị 90 ngày đầu theo kênh).
- Chuỗi thời gian ngắn (~20 tháng dùng được) → dự báo dùng mô hình đơn giản, có baseline để so.

---

## 3. Kiến trúc & công nghệ

```
 Kaggle, CSV nhóm chuẩn bị, holidays
          │  Python
          ▼
 LANDING / BRONZE  ── Azure Blob Storage (data lake, file gốc bất biến; Azurite local / ADLS Gen2 cloud)
          │  Python COPY
          ▼
 PostgreSQL 16:  raw (Bronze) → stg (Silver) → dw (Gold) → bi (data marts)
                                           └→ ml (kết quả mô hình) ┘
                 meta (log, kiểm tra chất lượng, từ điển dữ liệu)
          │  (dbt làm toàn bộ biến đổi stg → dw → bi)
          ▼
 Power BI Desktop → 4 người ra quyết định
 Airflow điều phối cả chuỗi · Docker Compose đóng gói
```

| Thành phần | Chọn | Vì sao (so với phương án còn lại) |
| --- | --- | --- |
| Data lake | **Azure Blob Storage** (thay MinIO, 01/11) | MinIO ngừng phát hành image miễn phí. Dev bằng Azurite (giả lập Azure chạy local, miễn phí); demo trên ADLS Gen2 thật bằng Azure for Students. Dự phòng: thư mục local |
| Warehouse | **PostgreSQL** (thay vì BigQuery) | Dữ liệu nhỏ; cả 4 người chạy local, không cần tài khoản/billing GCP; Power BI kết nối sẵn |
| Biến đổi | **dbt** (thay vì Spark) | ~100k đơn không cần Spark; dbt cho sẵn test, tài liệu, lineage, snapshot, incremental — đúng những thứ môn DW chấm. Nếu giảng viên bắt buộc Spark: thêm 1 bước PySpark chuyển CSV → Parquet trên data lake (Azure Blob) |
| Điều phối | **Airflow** (đề xuất của Trường An) | Lịch batch, retry, UI để demo. Dữ liệu không cần realtime nên batch là đúng. Airflow chỉ điều phối, không lưu dữ liệu |
| ML | Python: scikit-learn, LightGBM, statsmodels, PuLP | |
| BI | **Power BI Desktop** | Có What-if parameters; lưu dạng `.pbip` để đưa lên git |

---

## 4. Những gì đã chỉnh so với bản mô tả gốc

1. **Timeline**: bản gốc chia Week 1/2/3 + Stretch → nén thành 14 ngày, chia việc theo mức ưu tiên MUST / SHOULD / COULD.
2. **Tech stack thống nhất**: sơ đồ ban đầu đặt Spark ở Silver nhưng phần ETL lại dùng dbt trong PostgreSQL → chốt dbt + PostgreSQL. Landing zone là nơi lưu (data lake: MinIO, từ 01/11 đổi sang Azure Blob), Airflow là bộ điều phối — hai thứ khác nhau.
3. **Không cho ML ghi vào Gold**: ML đọc `dw`, ghi `ml`; Power BI đọc `bi`. Segment khách được nối ở `bi`, tránh vòng phụ thuộc.
4. **Khoá thay thế ổn định**: dùng khoá số sinh từ hàm băm natural key, để load incremental không làm đổi key.
5. **Seller chốt deal nhưng chưa bán** vẫn có trong `dim_seller` (thay vì rơi vào "unknown").
6. **SCD2 tier seller**: tier tháng M có hiệu lực từ đầu tháng M+1; dùng cửa sổ 3 tháng để tier không nhảy liên tục; version đầu mở từ 1900-01-01.
7. **Bài toán CRM và funnel** đặt lại cho khả thi (mục 2).

---

## 5. Phân công

Phân công đã chốt (30/10/2026).

| Vai trò | Thành viên | Phạm vi | Trang Power BI |
| --- | --- | --- | --- |
| TV1 — Data Platform & Orchestration | **Ngọc Cẩn** | Docker, data lake (Azure Blob), PostgreSQL, ingestion, Airflow, metadata, replay | — |
| TV2 — Staging, Dimensions & Data Quality | **Minh Hiếu** | Profiling, dbt staging, 10 dimension, SCD2 seller, funnel, tests | — |
| TV3 — Facts, Data Marts & BI | **Xuân Vinh** | Fact chính, đối soát, schema `bi`, KPI dictionary, Power BI | 1, 3, 5, 6, 8 |
| TV4 — ML & Decision Support, trưởng báo cáo | **Trường An** | EDA khả thi, mô hình, what-if, đề xuất, ghép báo cáo | 2, 4, 7 |

Mọi người cùng: viết phần báo cáo của mình, review PR của người khác, tập dượt demo.

### Cài đặt chung (ai cũng làm, ngày 1) — chi tiết từng bước ở `docs/SETUP.md`

1. Cài Git, Docker Desktop (cấp ≥ 6 GB RAM; Windows bật WSL2), **uv** (tự lo Python 3.11), `make` (Windows dùng WSL2/Git Bash), DBeaver (tuỳ chọn).
2. Tạo Kaggle API token (Kaggle → Settings → Create New Token) và **bấm chấp nhận điều khoản** ở trang 2 dataset.
3. Clone repo → `cp .env.example .env`. Dữ liệu nguồn đã có sẵn trong `data/raw/` của repo, không cần Kaggle key.
4. `uv sync` (tạo `.venv` theo `uv.lock`, giống hệt trên 4 máy; không cần activate vì Makefile dùng `uv run`).
5. `make up` → `make ingest` → `make load-raw` → mở DBeaver kiểm tra schema `raw` có 11 bảng Kaggle + holidays + br_states + calendar_events (14 bảng).
6. Ai làm Power BI (TV3, TV4) cần máy **Windows** với Power BI Desktop; kết nối PostgreSQL `localhost:5432`, database `olist_dw`, chỉ chọn schema `bi`.

---

### TV1 — Data Platform & Orchestration (Ngọc Cẩn)

**Mục tiêu**: ai clone repo về cũng chạy được `make all`; dữ liệu đi từ Kaggle tới `raw` có nhật ký; Airflow chạy được cả chuỗi để demo.

**Cài thêm**: Docker images `postgres:16`, `mcr.microsoft.com/azure-storage/azurite`, `apache/airflow` (pin 1 version, python 3.11); Python: `kaggle`, `azure-storage-blob`, `psycopg[binary]`, `requests`, `holidays`.

| ID | Ưu tiên | Việc | Kết quả / Done khi |
| --- | --- | --- | --- |
| P1 | MUST | Khung repo (cấu trúc thư mục theo CLAUDE.md mục 4), `.gitignore`, `.env.example`, Makefile, README quickstart | Thành viên khác clone và làm theo README không cần hỏi |
| P2 | MUST | `docker-compose.yml`: postgres (script init tạo DB `olist_dw`, `airflow`, các schema raw/stg/dw/bi/ml/meta), azurite (Azure Blob giả lập) | `make up` chạy; `make ingest` tạo container `olist-lake` (xem bằng Azure Storage Explorer) |
| P3 | MUST | `download_kaggle.py`: tải 2 dataset, giải nén vào `landing/kaggle/<dataset>/extract_date=YYYY-MM-DD/` | 11 CSV đúng chỗ |
| P4 | MUST | `gen_holidays.py` (lễ Brazil 2016–2019 → CSV); bang & vùng lấy từ `br_states.csv` (không gọi IBGE API, xem CLAUDE.md mục 2.3) | File trong landing |
| P5 | MUST | `upload_to_lake.py` (local → Azure Blob); `load_raw.py` (Azure Blob → `raw.*`, mọi cột text, thêm `_batch_id`, `_loaded_at`, `_source_file`, ghi `meta.etl_run_log`) | Số dòng raw = số dòng CSV; log có bản ghi |
| P6 | SHOULD | Airflow: Dockerfile (cài dbt trong venv riêng), DAG `olist_pipeline` (thứ tự ở CLAUDE.md mục 15), callback ghi log | Trigger DAG trên UI :8080 chạy xanh từ đầu đến cuối |
| P7 | SHOULD | `scripts/replay_month.py --month YYYY-MM` (cùng TV3 làm F8) | Demo: nạp thêm 1 tháng, fact cập nhật, Power BI refresh thấy thay đổi |
| P8 | MUST | DDL bảng `meta.*`; `meta_publish.py`: đọc `run_results.json` → `meta.dq_results`, đọc manifest → `meta.data_dictionary`, `meta.source_to_target` | Trang DQ (trang 8) có dữ liệu |
| P9 | MUST | `dbt docs generate`, chụp lineage graph; chạy thử `make all` trên một máy sạch | Hình lineage cho báo cáo; `make all` không lỗi |

**Phụ thuộc**: không phụ thuộc ai — là người mở đường. P1–P5 phải xong **cuối ngày 2** để mọi người có dữ liệu.
**Báo cáo**: Kiến trúc hệ thống, ETL/ELT & các layer, orchestration, metadata, incremental load.

---

### TV2 — Staging, Dimensions & Data Quality (Minh Hiếu)

**Mục tiêu**: dữ liệu sạch theo rule có ghi chép; 10 dimension đúng thiết kế; SCD2 tier seller chạy đúng; bộ test chất lượng.

**Cài thêm**: `dbt-core`, `dbt-postgres` (cùng version cả nhóm), package dbt `dbt_utils`; Python `pandas`, `jupyter`, `unidecode`; extension Postgres `unaccent` (nếu dùng).

| ID | Ưu tiên | Việc | Kết quả / Done khi |
| --- | --- | --- | --- |
| S1 | MUST | **Profiling** (notebook trên `raw`): giá trị order_status, payment_type; review trùng; geolocation (điểm/zip, ngoài Brazil, dấu); category thiếu; zip mất số 0 đầu; chênh lệch tiền hàng vs thanh toán; tỷ lệ seller funnel khớp; khoảng thời gian dữ liệu | `docs/profiling.md` + cập nhật bảng giả định A1–A9 trong CLAUDE.md. **Xong ngày 2** |
| S2 | MUST | Khởi tạo dbt project, `sources.yml`, macro `generate_schema_name`, `int_sk`; seeds: `category_group`, `seller_tier_rules`, `br_state_population`, `order_status_map`, `instalment_band` | `dbt seed` chạy |
| S3 | MUST | Model `stg_*` cho 11 bảng + br_states + calendar_events + holidays theo rule CLAUDE.md mục 9; `int_customer_map` | `dbt build --select staging` xanh |
| S4 | MUST | `dim_date`, `dim_geography`, `dim_product`, `dim_customer`, `dim_order_status`, `dim_payment_type` (có dòng unknown -1) | Có test unique/not_null; TV3 join được |
| S5 | SHOULD | `dim_lead_origin`, `dim_lead_profile`, `dim_sales_rep`, `fact_lead_funnel` | Conversion theo origin tính được |
| S6 | SHOULD (bản tạm MUST) | Ngày 3: đưa ra `dim_seller` bản Type 1 tạm để TV3 không bị chặn. Sau đó: `int_seller_month_metrics` → `int_seller_tier_monthly` → `int_seller_tier_versions` → `dim_seller` SCD2 | Test: 1 version current / seller, không chồng thời gian, tra cứu theo ngày ra đúng 1 version |
| S7 | MUST | Test cho dims + test business rule; YAML mô tả mọi cột dims | Hiện trên dbt docs |

**Phụ thuộc**: cần raw của TV1 (ngày 2). TV3 cần S4 + dim_seller tạm trước **ngày 4**.
**Báo cáo**: 4 bước Kimball, thiết kế dimension, SCD Type 2, so sánh star vs snowflake (dim_geography), so sánh Kimball vs Inmon, profiling & quy tắc làm sạch.

---

### TV3 — Facts, Data Marts & BI (Xuân Vinh)

**Mục tiêu**: fact đúng grain và đối soát khớp; một bộ KPI dùng chung; dashboard cho 4 người.

**Cài thêm**: dbt (như TV2); **Power BI Desktop trên Windows**; DBeaver.

| ID | Ưu tiên | Việc | Kết quả / Done khi |
| --- | --- | --- | --- |
| F1 | MUST | `int_order_primary_seller` (seller của item giá cao nhất), `int_order_agg` | Đúng 1 dòng / order |
| F2 | MUST | `fact_order_item`, `fact_payment` | Test FK → dims xanh |
| F3 | MUST | `fact_order_fulfillment` (accumulating snapshot: 5 date roles, lags, is_late, is_dispatch_late, khoảng cách haversine), `fact_review` (is_latest_for_order) | 1 dòng / order; late rate khớp tính tay trên mẫu |
| F4 | SHOULD / COULD | `fact_seller_month` (SHOULD); `fact_seller_product_activity` (COULD) | Tổng theo tháng = tổng fact_order_item |
| F5 | MUST | Test đối soát (CLAUDE.md mục 11.1) + YAML mô tả cột facts | Kết quả vào `meta.dq_results` |
| F6 | MUST | Schema `bi` (views dims, facts, ML, DQ); viết `docs/kpi_dictionary.md` từ CLAUDE.md mục 8 | Power BI chỉ cần đọc `bi` |
| F7 | MUST | Power BI: semantic model, bảng `_Measures` (DAX đúng KPI dictionary), trang **1 Executive Overview, 3 Fulfillment, 5 Seller Quality & Tier Migration, 6 Lead Funnel, 8 Data Quality** | Mỗi trang trả lời được câu hỏi của người dùng tương ứng |
| F8 | SHOULD | Chuyển các fact/stg chính sang incremental (cùng TV1 làm P7) | Replay 1 tháng chạy được |

**Phụ thuộc**: cần dims của TV2 (ngày 4). Có thể bắt đầu F1 ngay khi `stg` có (ngày 3). **TV3 là chủ file Power BI**: TV4 làm trang 2, 4, 7 trên bản copy rồi gửi lại để TV3 ghép (copy-paste visual giữa 2 file Power BI được), hoặc dùng `.pbip` và chia trang để tránh đè nhau.
**Báo cáo**: thiết kế fact, bus matrix, tính cộng dồn (additive / semi / non-additive), ngoại lệ accumulating snapshot, đối soát & kiểm tra chất lượng, mô tả dashboard.

---

### TV4 — ML & Decision Support, trưởng báo cáo (Trường An)

**Mục tiêu**: mỗi người ra quyết định có ít nhất một công cụ what-if hoặc danh sách đề xuất; báo cáo hoàn chỉnh, thống nhất.

**Cài thêm**: Python `scikit-learn`, `lightgbm`, `statsmodels`, `pulp`, `shap` (tuỳ chọn), `jupyter`; Power BI Desktop (Windows) cho trang 2, 4, 7.

| ID | Ưu tiên | Việc | Kết quả / Done khi |
| --- | --- | --- | --- |
| M1 | MUST | EDA khả thi trên CSV (không chờ warehouse): tỷ lệ mua lặp, số seller funnel có đơn, độ dài chuỗi tháng, phân phối trễ | Kết luận khả thi cho từng bài toán, gửi nhóm **ngày 2** |
| M2 | MUST | `ml/common`: đọc/ghi DB, sinh `model_run_id`, ghi `meta.model_registry`; DDL các bảng `ml.*` | Model nào cũng ghi kết quả cùng một kiểu |
| M3 | MUST | Mô hình rủi ro giao trễ (LightGBM, baseline logistic; chia train/test theo thời gian, không dùng thông tin sau thời điểm mua) + bảng `ml.promise_whatif` (nới ngày hứa −5…+7 ngày theo tuyến) | AUC + so baseline; slider what-if trên trang 4 |
| M4 | MUST | Phân khúc khách (RFM + trải nghiệm) + tối ưu phân bổ voucher theo ngân sách bằng PuLP (uplift theo segment là giả định) | Bảng phân bổ cho nhiều mức ngân sách; trang 7 |
| M5 | SHOULD | Dự báo GMV theo category_group × region (seasonal-naive vs ETS/SARIMA; test 3 tháng cuối, MAPE) | Trang 2 có forecast + slider tăng trưởng |
| M6 | COULD | Điểm rủi ro seller; giá trị kênh marketing (conversion, GMV 90 ngày / lead theo origin) | Đưa vào trang 5, 6 (gửi TV3) |
| M7 | MUST | `ml.recommendations`: tuyến cần sửa, seller cần cảnh báo/khen thưởng, category × region nên đầu tư, danh sách khách nhận voucher — mỗi dòng có hành động, lý do, điểm | Pha *Choice* có bảng để chấp nhận / bác bỏ |
| M8 | MUST | Power BI trang **2 Growth, 4 Promise What-if, 7 CRM** | Gửi TV3 ghép |

**Phụ thuộc**: M1, M2 làm được ngay trên CSV. M3–M7 cần `dw` (ngày 6) — trước đó viết code trên dữ liệu CSV đã join bằng pandas theo đúng tên cột của CLAUDE.md mục 7, sau chỉ đổi nguồn đọc.
**Báo cáo**: chịu trách nhiệm ghép báo cáo; viết phần bài toán & người ra quyết định, 3 pha Simon, ML & what-if, hạn chế & hướng phát triển.

---

## 6. Timeline 14 ngày

| Ngày | Thời gian | TV1 Platform (Ngọc Cẩn) | TV2 Staging/Dims (Minh Hiếu) | TV3 Facts/BI (Xuân Vinh) | TV4 ML/Báo cáo (Trường An) |
| --- | --- | --- | --- | --- | --- |
| D1–D2 | T7 31/10 – CN 1/11 | P1–P5 | Cài đặt; S1 profiling (trên CSV trước, raw sau); S2 | Cài đặt; đọc thiết kế; nháp KPI dictionary | Cài đặt; M1; dàn ý báo cáo |
| **M0** | **CN 1/11** | **Mọi máy chạy được `make up/ingest/load-raw`; profiling + EDA khả thi xong; nhóm họp chốt giả định** | | | |
| D3–D6 | T2 2/11 – T5 5/11 | P8, P6 (Airflow) | S3, S4, dim_seller tạm (D3), S7 | F1, F2, F3, F5 | M2; M3, M4 prototype trên CSV |
| **M1** | **T5 5/11** | **stg + dims + 4 fact chính build xanh; Power BI kết nối được `bi`** | | | |
| D7–D10 | T6 6/11 – T2 9/11 | P7 + F8 (replay), hoàn thiện DAG | S6 SCD2, S5 funnel | F4, F6, F7 (trang 1, 3, 8) | M3, M4 chạy trên `dw`; M5; M7 |
| **M2** | **T2 9/11** | **`make all` và DAG Airflow chạy từ đầu đến cuối; bảng `ml.*` có dữ liệu** | | | |
| D11–D12 | T3 10/11 – T4 11/11 | P9 lineage; viết báo cáo phần mình | Viết báo cáo phần mình | F7 trang 5, 6; ghép trang 2, 4, 7 | M8; M6 nếu kịp; ghép báo cáo |
| **M3** | **T4 11/11** | **Dashboard đủ 8 trang; báo cáo bản nháp đầy đủ** | | | |
| D13 | T5 12/11 | **Code freeze**, chạy `make all` trên máy sạch | Rà báo cáo | Rà dashboard | Hoàn thiện báo cáo |
| D14 | T6 13/11 | Tập dượt demo lần cuối, **nộp bài** | | | |

**Nếu trễ tiến độ, cắt theo thứ tự**: fact_seller_product_activity → M6 → city-level enrichment → replay incremental (P7/F8) → M5 → Airflow (thay bằng `make all`, giữ ảnh chụp DAG nếu có). **Không cắt** MUST.

---

## 7. Cách làm việc chung

- **Git**: nhánh `main` luôn chạy được. Mỗi task một nhánh `feat/<ID>-<mô-tả>` (vd `feat/S6-seller-scd2`). PR nhỏ, cần 1 người review và `dbt build` xanh trên máy người review.
- **Hợp đồng dữ liệu**: tên bảng, cột, grain trong CLAUDE.md mục 7 là cố định. Muốn đổi → nhắn nhóm, sửa CLAUDE.md trong cùng PR. Nhờ vậy ai cũng có thể làm song song bằng dữ liệu giả đúng schema.
- **Một định nghĩa KPI**: mọi measure Power BI và mọi con số trong báo cáo dùng CLAUDE.md mục 8 / `docs/kpi_dictionary.md`. Đây chính là vấn đề dự án giải quyết — không được để hai trang dashboard ra hai late rate khác nhau.
- **Họp nhanh 15 phút mỗi tối**: hôm nay xong gì, mai làm gì, đang bị chặn bởi ai. Cập nhật checklist ở CLAUDE.md mục 17 (`[ ]` / `[~]` / `[x]`).
- **Dùng Claude Code**: mở terminal ở thư mục gốc repo, Claude tự đọc `CLAUDE.md`. Giao việc bằng task ID, ví dụ: *"Làm task S6 theo CLAUDE.md, viết kèm test"*.
- **Không commit**: `.env`, `.venv/`, `data/landing/`, `target/`, `logs/`. **Có commit**: `data/raw/`, `data/fallback/`, `uv.lock`.
- **Thêm thư viện Python**: `uv add <pkg>` → `make lock` → commit `pyproject.toml`, `uv.lock`, `requirements.txt` cùng PR.

---

## 8. Dàn ý báo cáo

TV1 = Ngọc Cẩn · TV2 = Minh Hiếu · TV3 = Xuân Vinh · TV4 = Trường An.

| # | Phần | Người viết |
| --- | --- | --- |
| 1 | Bối cảnh Olist, vấn đề, 4 người ra quyết định, 3 pha Simon | TV4 |
| 2 | Dữ liệu nguồn & profiling (kèm các giả định đã xác nhận) | TV2 |
| 3 | Kiến trúc hệ thống (Medallion, lý do chọn công nghệ) | TV1 |
| 4 | Thiết kế DW: 4 bước Kimball, grain, bus matrix | TV2 + TV3 |
| 5 | Dimensions, SCD Type 2 tier seller, star vs snowflake | TV2 |
| 6 | Facts, tính cộng dồn, accumulating snapshot và ngoại lệ "non-updatable" | TV3 |
| 7 | Kimball vs Inmon (lớp `stg` như lớp tích hợp) | TV2 |
| 8 | ETL/ELT, các layer, orchestration, incremental & replay | TV1 |
| 9 | Data quality, đối soát, metadata, lineage | TV1 + TV3 |
| 10 | KPI dictionary & dashboard Power BI | TV3 |
| 11 | ML, what-if, đề xuất | TV4 |
| 12 | Hạn chế, giả định, hướng phát triển | TV4 (mọi người góp) |

---

## 9. Kịch bản demo (~10 phút)

1. Sơ đồ kiến trúc (1 phút).
2. Airflow: trigger DAG `olist_pipeline`, giải thích các bước (1 phút).
3. dbt docs: lineage raw → stg → dw → bi; một dim, một fact, tests (2 phút).
4. Replay: nạp thêm 1 tháng → fact_order_fulfillment cập nhật mốc ngày → refresh Power BI (1 phút).
5. Power BI theo từng người ra quyết định: Intelligence (trang 1, 3, 5) → Design (slider ở trang 4, 7) → Choice (bảng đề xuất) (4 phút).
6. Trang Data Quality: tests và đối soát mới nhất (1 phút).

---

## 10. Rủi ro & dự phòng

| Rủi ro | Dự phòng |
| --- | --- |
| Máy yếu không chạy nổi Airflow + Postgres + Azurite | Chỉ cần Airflow trên 1 máy để demo; những máy khác chạy `make all`; Azurite rất nhẹ |
| Thành viên dùng macOS không có Power BI | Giao Power BI cho thành viên dùng Windows, hoặc dùng máy lab/VM |
| Kaggle tải lỗi | Tải zip thủ công trên web, giải nén vào `data/raw/ecom_dataset/` và `data/raw/marketing_funnel/` — `make ingest` tự ưu tiên file ở đây |
| Mô hình ML kết quả kém | Báo cáo trung thực, so với baseline, giải thích nguyên nhân từ dữ liệu — vẫn có điểm |
| Xung đột file Power BI | Một chủ file (TV3 — Xuân Vinh), dùng `.pbip`, chia trang rõ ràng |
| Thiết kế đổi giữa chừng | Mọi thay đổi đi qua CLAUDE.md và báo nhóm trước |

---

## 11. Cần nhóm chốt sớm

- [x] Điền tên TV1–TV4 (mục 5): Ngọc Cẩn, Minh Hiếu, Xuân Vinh, Trường An.
- [ ] Ngày nộp chính xác (đang giả định 13/11/2026).
- [ ] Giảng viên có bắt buộc Spark / BigQuery / công cụ BI cụ thể không.
- [ ] Ai có máy Windows để làm Power BI.
- [ ] Hình thức báo cáo (Word / LaTeX), độ dài, ngôn ngữ.
