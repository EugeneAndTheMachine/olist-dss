# Olist DW — Giải thích toàn bộ implementation (bản dành cho cả nhóm)

> **Mục đích:** đọc một file là hiểu được toàn bộ phần đã làm: dữ liệu đi đâu, mỗi công cụ để làm gì, mỗi model dbt biến đổi
> cái gì và **vì sao** lại làm như vậy. Dùng file này để giải thích lại cho đồng đội, hoặc để ôn trước buổi demo hay vấn đáp.
>
> Cập nhật: 03/11/2026. Viết dựa trên code thật trong repo và số liệu đọc trực tiếp từ database đang chạy.
> Khi file này và code khác nhau thì **code đúng**. Thiết kế gốc (nguồn sự thật) nằm ở `implementation.md`.
>
> **Phạm vi:** toàn bộ phần data platform và data warehouse. Module ML (M3–M7) và thiết kế Power BI (F7, M8) chỉ được
> nhắc tới ở mục *Việc chưa hoàn thành*.

---

## Mục lục

- [0. Tóm tắt: dự án đang ở đâu?](#0-tóm-tắt-dự-án-đang-ở-đâu)
- [1. Bức tranh tổng thể](#1-bức-tranh-tổng-thể)
- [2. Tech stack: mỗi công cụ là gì, dùng để làm gì](#2-tech-stack-mỗi-công-cụ-là-gì-dùng-để-làm-gì)
- [3. Nguyên lý thiết kế Data Warehouse](#3-nguyên-lý-thiết-kế-data-warehouse)
- [4. Hạ tầng: Docker, PostgreSQL, Makefile](#4-hạ-tầng-docker-postgresql-makefile)
- [5. Ingestion: từ CSV vào schema raw](#5-ingestion-từ-csv-vào-schema-raw)
- [6. dbt: khái niệm nền tảng](#6-dbt-khái-niệm-nền-tảng)
- [7. dbt: cấu hình, macro, seed](#7-dbt-cấu-hình-macro-seed)
- [8. dbt: Staging (Silver)](#8-dbt-staging-silver)
- [9. dbt: Intermediate và SCD Type 2 cho tier seller](#9-dbt-intermediate-và-scd-type-2-cho-tier-seller)
- [10. dbt: Dimensions (Gold)](#10-dbt-dimensions-gold)
- [11. dbt: Facts (Gold)](#11-dbt-facts-gold)
- [12. dbt: Lớp BI (serving) và lớp Quality](#12-dbt-lớp-bi-serving-và-lớp-quality)
- [13. Kiểm thử và đối soát](#13-kiểm-thử-và-đối-soát)
- [14. Metadata: meta_publish.py](#14-metadata-meta_publishpy)
- [15. Airflow: điều phối pipeline](#15-airflow-điều-phối-pipeline)
- [16. Số liệu kiểm chứng](#16-số-liệu-kiểm-chứng)
- [17. Tự chạy và tự kiểm tra](#17-tự-chạy-và-tự-kiểm-tra)
- [18. Câu hỏi hay gặp (dùng khi giải thích hoặc vấn đáp)](#18-câu-hỏi-hay-gặp-dùng-khi-giải-thích-hoặc-vấn-đáp)
- [19. Việc chưa hoàn thành](#19-việc-chưa-hoàn-thành)
- [20. Hướng phát triển sắp tới](#20-hướng-phát-triển-sắp-tới)
- [21. Bảng thuật ngữ](#21-bảng-thuật-ngữ)

---

## 0. Tóm tắt: dự án đang ở đâu?

**Trả lời ngắn:** nếu tạm bỏ qua ML và Power BI thì **phần data warehouse đã xong phần lớn**. Phần còn lại là vài việc
SHOULD/MUST nhỏ hơn: replay incremental, ảnh lineage, chạy thử trên máy sạch, chạy lại Airflow. Ngoài ra **cần commit
code ngay**. Xem chi tiết ở [mục 19](#19-việc-chưa-hoàn-thành).

Tuy vậy, xét **toàn bộ assignment** thì ML (M3, M4, M7 là MUST) và Power BI (F7, M8 là MUST) là phần lớn còn lại.
Hai phần này người dùng nhìn thấy trực tiếp khi demo, nên chưa thể coi là "gần xong cả dự án".

| Layer | Nơi lưu | Trạng thái | Ghi chú |
| --- | --- | :---: | --- |
| Landing (file gốc) | Azure Blob (Azurite) `olist-lake` | ✅ | 14 file CSV, không bao giờ sửa |
| Bronze | schema `raw` | ✅ | 14 bảng, mọi cột text, số dòng = CSV |
| Silver | schema `stg` | ✅ | 14 `stg_*` + 6 `int_*` + 5 seed |
| Gold | schema `dw` | ✅ | 10 dim (có SCD2) + 7 fact |
| Serving | schema `bi` | ✅ | 21 view (11 dim, 7 fact, 3 DQ); còn thiếu view ML |
| Metadata / DQ | schema `meta` | ✅ | dq_results, data_dictionary, source_to_target, etl_run_log, dq_issue_summary |
| ML output | schema `ml` | 🔴 | Bảng đã tạo nhưng rỗng; script ML mới là stub |
| Power BI | `powerbi/` | 🔴 | Có hướng dẫn (`docs/powerbi_guide.md`), chưa có file `.pbip` |
| Orchestration | Airflow | 🟡 | DAG chạy xanh 15/15 (01/11), nhưng lúc đó chưa có đủ model → cần chạy lại |
| Incremental / replay | `scripts/replay_month.py` | 🔴 | Chưa hiện thực |

Lần `dbt build` gần nhất (02/11): **334/334 PASS** (5 seed, 60 model, 269 test), mất khoảng 20 giây.

---

## 1. Bức tranh tổng thể

### 1.1 Bài toán trong 3 câu

1. Olist là sàn TMĐT ở Brazil: nhiều seller, nhiều khách, khoảng 100 nghìn đơn (2016–2018).
2. Dữ liệu đơn, thanh toán, giao hàng, review, seller nằm rời rạc và **chưa có định nghĩa chung**. Ví dụ, hai quản lý tính
   "tỷ lệ giao trễ" ra hai con số khác nhau (đã xảy ra thật: so theo *ngày* ra 6,77%, so theo *timestamp* ra 8,11%).
3. Giải pháp: xây một Data Warehouse có **một bộ định nghĩa KPI duy nhất**, cùng dashboard và ML, để hỗ trợ 4 người
   ra quyết định: Head of Commerce, Logistics Manager, Seller Quality Manager, CRM Manager.

### 1.2 Luồng dữ liệu (đọc từ trên xuống)

```
 data/raw/*.csv   (CSV Kaggle + 2 file nhóm tự làm, có commit trong repo)
      │  ① Python: download_kaggle · copy_manual · gen_holidays
      ▼
 data/landing/<source>/<dataset>/extract_date=YYYY-MM-DD/<file>.csv     (cache local)
      │  ② Python: upload_to_lake        — không ghi đè file đã có
      ▼
 Azure Blob (Azurite) container olist-lake/landing/...                  ◀── LANDING: file gốc bất biến
      │  ③ Python: load_raw (lệnh COPY của Postgres, append, bỏ qua file đã nạp)
      ▼
 ┌─────────────────────────── PostgreSQL 16, database olist_dw ───────────────────────────┐
 │                                                                                         │
 │  raw.*   14 bảng, MỌI CỘT TEXT + _batch_id, _loaded_at, _source_file   ◀── BRONZE       │
 │     │  ④ dbt (staging): ép kiểu, dedup, làm sạch, gắn cờ lỗi                            │
 │     ▼                                                                                   │
 │  stg.stg_*  +  stg.int_*  +  seed                                       ◀── SILVER       │
 │     │  ⑤ dbt (warehouse): star schema Kimball                                           │
 │     ▼                                                                                   │
 │  dw.dim_*  +  dw.fact_*                                                 ◀── GOLD         │
 │     │  ⑥ dbt (bi): view mỏng, tên cột thân thiện                                        │
 │     ▼                                                                                   │
 │  bi.v_*   ◀── Power BI CHỈ đọc schema này (user powerbi_reader)        ◀── SERVING      │
 │                                                                                         │
 │  ml.*    (Python ML đọc dw, ghi vào đây; chưa làm)                                      │
 │  meta.*  (log chạy, kết quả test, từ điển dữ liệu, lineage)                             │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
      ▼
 Power BI Desktop (Import) → 4 người ra quyết định

 Airflow (DAG olist_pipeline) bấm nút chạy cả chuỗi ①→⑥ + ML + meta. Docker Compose đóng gói mọi service.
```

### 1.3 Theo chân một đơn hàng qua các layer

Đây là cách dễ nhất để giải thích cho người mới. Lấy một đơn bất kỳ:

| Layer | Đơn hàng trông như thế nào |
| --- | --- |
| **CSV** | 1 dòng trong `olist_orders_dataset.csv`: `order_id="e481f5..."`, `order_purchase_timestamp="2017-10-02 10:56:33"`, … Tất cả đều là chữ |
| **Landing** | Cùng file đó, nằm ở `olist-lake/landing/kaggle/brazilian-ecommerce/extract_date=2026-11-01/olist_orders_dataset.csv` |
| **raw.orders** | 1 dòng, mọi cột `text`, thêm `_batch_id`, `_loaded_at`, `_source_file` (biết dòng này đến từ file nào, lúc nào) |
| **stg.stg_orders** | Timestamp đã là kiểu `timestamp`, `order_status` viết thường. Có thêm cờ `is_delivered`, `is_late`, `delay_days` và `_dq_issue` nếu mốc thời gian vô lý |
| **stg.int_order_agg** | Đơn đó có bao nhiêu item, tổng tiền hàng, tổng ship, bao nhiêu seller, hạn giao cho hãng muộn nhất |
| **dw.fact_order_fulfillment** | 1 dòng / đơn với 5 khoá ngày (`20171002`, …), khoá khách, khoá seller, khoá địa lý. Có các lag (số ngày từng chặng), cờ 0/1 và khoảng cách seller → khách (km) |
| **dw.fact_order_item** | Mỗi item của đơn là 1 dòng: giá, phí ship, khoá sản phẩm, khoá seller **đúng phiên bản tier lúc mua** |
| **bi.v_fact_fulfillment** | Giống fact nhưng cột đổi tên: `"Is Late"`, `"Delivery Lag (days)"`, … để Power BI hiển thị đẹp |
| **Power BI** | Measure `Late Rate = DIVIDE(SUM(Fulfillment[Is Late]), SUM(Fulfillment[Is Delivered]))` → 6,77% |

---

## 2. Tech stack: mỗi công cụ là gì, dùng để làm gì

| Công cụ | Là gì (1 câu) | Trong dự án dùng để | Vì sao chọn (thay vì gì) | File liên quan |
| --- | --- | --- | --- | --- |
| **Docker + Docker Compose** | Chạy phần mềm trong "container" đóng gói sẵn, giống nhau trên mọi máy | Bật Postgres, Azurite, Airflow bằng 1 lệnh | 4 máy khác nhau vẫn chạy y hệt, không phải cài tay Postgres | `docker-compose.yml`, `docker/` |
| **PostgreSQL 16** | Database quan hệ mã nguồn mở | Kho dữ liệu chính: 6 schema `raw, stg, dw, bi, ml, meta` | Dữ liệu nhỏ (< 200 MB), chạy local miễn phí, Power BI có connector sẵn. BigQuery thì cần billing/IAM GCP, không cần thiết | `docker/postgres/init/*.sql` |
| **Azure Blob Storage / Azurite** | Kho lưu file trên cloud của Microsoft. Azurite là bản giả lập chạy local | **Data lake**: giữ bản gốc bất biến của mọi file nguồn | MinIO ngừng phát hành image miễn phí (10/2025). Azurite offline, miễn phí, cùng API với Azure thật → đổi sang cloud chỉ cần đổi 1 connection string | `ingestion/lake.py`, `docs/AZURE_SETUP.md` |
| **Python 3.11** | Ngôn ngữ lập trình | Ingestion (tải, upload, nạp raw), metadata, ML (sau) | Thư viện dữ liệu mạnh (pandas, psycopg, azure SDK) | `ingestion/`, `ml/` |
| **uv** | Trình quản lý Python và thư viện (rất nhanh) | Tạo `.venv` giống hệt nhau trên 4 máy theo `uv.lock` | Khoá phiên bản chặt hơn pip; tự tải Python 3.11 | `pyproject.toml`, `uv.lock` |
| **dbt (dbt-core + dbt-postgres 1.9)** | Công cụ viết biến đổi dữ liệu bằng **SQL SELECT** + Jinja; tự lo tạo bảng, thứ tự chạy, test, tài liệu | **Toàn bộ biến đổi** raw → stg → dw → bi, test chất lượng, lineage | Spark là quá mức cho 100k đơn. dbt có sẵn test, docs, lineage, snapshot, incremental, đúng những thứ môn DW chấm | `dbt/olist_dw/` |
| **Airflow 2.10** | Công cụ lập lịch và điều phối các bước (task) theo thứ tự phụ thuộc (DAG) | Chạy cả pipeline theo lịch, retry khi lỗi, có UI để demo | Phổ biến, UI trực quan. Chỉ **điều phối**, không lưu dữ liệu | `airflow/dags/olist_pipeline.py`, `docker/airflow/Dockerfile` |
| **GNU make** | Chạy lệnh theo tên ngắn | `make all`, `make build`, `make meta`… | Một lệnh dựng lại toàn bộ; Airflow gọi cùng các lệnh này | `Makefile` |
| **Power BI Desktop** | Công cụ dashboard của Microsoft | Hiển thị KPI, what-if cho 4 người ra quyết định | Hợp người dùng nghiệp vụ, có What-if parameters; lưu `.pbip` dạng text để commit git | `powerbi/`, `docs/powerbi_guide.md` |
| **scikit-learn, LightGBM, statsmodels, PuLP** | Thư viện ML / dự báo / tối ưu | M3–M7 (chưa làm) | | `ml/` |

**Ẩn dụ để giải thích nhanh:**
- *Azure Blob* = **kho lưu trữ hồ sơ gốc**: chỉ cất vào, không ai được sửa.
- *raw* = **bản photo** hồ sơ gốc, xếp thành bảng để tra cứu được.
- *stg* = hồ sơ đã được **chuẩn hoá** (đúng định dạng, bỏ trùng, ghi chú lỗi).
- *dw* = hồ sơ được **sắp xếp theo chủ đề nghiệp vụ** (bán hàng, giao hàng, review…) để phân tích.
- *bi* = **quầy giao dịch**: khách (Power BI) chỉ được đứng ở đây, nhìn bản đã chuẩn bị sẵn.
- *dbt* = **dây chuyền** biến hồ sơ từ bước này sang bước kia, có kiểm tra chất lượng ở mỗi trạm.
- *Airflow* = **quản đốc** bấm nút cho dây chuyền chạy đúng thứ tự, đúng giờ.

---

## 3. Nguyên lý thiết kế Data Warehouse

### 3.1 Kiến trúc Medallion (Bronze → Silver → Gold)

Ý tưởng: dữ liệu đi qua nhiều tầng, **mỗi tầng một nhiệm vụ**, và tầng sau chỉ đọc tầng trước.

| Tầng | Ở dự án | Nhiệm vụ | Quy tắc vàng |
| --- | --- | --- | --- |
| Landing | Azure Blob | Giữ file gốc | **Không bao giờ sửa/xoá**. Mỗi lần trích xuất là 1 thư mục `extract_date=` mới |
| Bronze | `raw` | Đưa file vào DB để truy vấn được | **Không làm sạch**, mọi cột là text, chỉ append |
| Silver | `stg` | Làm sạch, ép kiểu, dedup, gắn cờ lỗi | Mọi rule làm sạch nằm trong SQL dbt (có mô tả YAML), **không sửa tay** |
| Gold | `dw` | Mô hình Kimball (dim + fact) | Surrogate key, unknown member -1, test FK |
| Serving | `bi` | Hợp đồng với Power BI | View mỏng, không đổi grain, không tính KPI |

**Vì sao phải nhiều tầng?** Nếu một rule làm sạch sai, ta sửa SQL rồi chạy lại từ `raw`, vì `raw` vẫn còn nguyên dữ liệu gốc.
Nếu làm sạch thẳng lên dữ liệu gốc thì một khi đã sai sẽ không quay lại được.

### 3.2 ELT chứ không phải ETL

- **ETL** (Extract → Transform → Load): biến đổi *bên ngoài* DB (bằng Python/Spark…) rồi mới nạp vào.
- **ELT** (Extract → Load → Transform): nạp dữ liệu thô vào DB trước, rồi biến đổi *bên trong* DB bằng SQL.

Dự án dùng **ELT**: Python chỉ nạp thô vào `raw` (E + L), còn mọi biến đổi (T) do dbt chạy SQL trong Postgres.
Lợi ích: SQL dễ đọc và review, chạy nhanh vì DB tự tối ưu, và lineage/test do dbt quản lý.

### 3.3 Kimball: mô hình chiều (dimensional modeling)

#### 4 bước Kimball (đã áp dụng)

1. **Chọn business process**: bán hàng, giao hàng, thanh toán, review, thu hút seller, hiệu suất seller.
2. **Khai báo grain** ("1 dòng của fact là gì"): ví dụ `fact_order_item` = 1 item của 1 đơn. Đây là bước **quan trọng nhất**.
   Grain sai thì mọi phép cộng sai theo.
3. **Chọn dimension**: ngữ cảnh để lọc/nhóm (ngày, khách, sản phẩm, seller, địa lý…).
4. **Chọn fact (measure)**: các con số đo được (giá, phí ship, cờ trễ, số ngày…).

#### Fact và Dimension

- **Dimension (dim)** = "danh từ": ai, cái gì, ở đâu, khi nào. Ví dụ `dim_product` có category, cân nặng.
- **Fact** = "động từ có số đo": sự kiện xảy ra, kèm con số. Ví dụ `fact_order_item` có giá, ship.
- **Star schema**: fact ở giữa, dim xung quanh, fact nối với dim bằng khoá → trông như ngôi sao.

```
                dim_date
                    │
  dim_customer ── fact_order_item ── dim_product
                 /        │       \
     dim_geography   dim_seller   dim_order_status
```

#### Bốn loại fact (dự án dùng đủ cả 4)

| Loại | Ý nghĩa | Ở dự án |
| --- | --- | --- |
| **Transaction** | 1 dòng = 1 sự kiện, không bao giờ sửa | `fact_order_item`, `fact_payment`, `fact_review` |
| **Periodic snapshot** | 1 dòng = trạng thái của 1 đối tượng trong 1 kỳ (tháng), dày đặc kể cả kỳ không có hoạt động | `fact_seller_month` |
| **Accumulating snapshot** | 1 dòng = 1 quy trình có nhiều mốc; dòng được **cập nhật** khi có mốc mới | `fact_order_fulfillment` (mua → duyệt → giao hãng → khách nhận), `fact_lead_funnel` (liên hệ → chốt → bán đầu tiên) |
| **Factless** | Không có measure, chỉ ghi nhận "có xảy ra" | `fact_seller_product_activity` (seller có bán sản phẩm X trong tháng) |

> **Ngoại lệ "non-updatable":** lý thuyết DW nói fact không nên bị sửa. Accumulating snapshot **cố ý vi phạm** điều đó
> (mốc giao hàng được điền dần). Vì vậy mỗi dòng có `_dw_loaded_at`, `_dw_updated_at` để audit. Nên nêu điểm này trong báo cáo.

#### Additivity: con số nào được cộng?

| Loại | Ý nghĩa | Ví dụ |
| --- | --- | --- |
| **Additive** | Cộng được qua mọi dim | `item_price`, `is_late`, `orders` |
| **Semi-additive** | Cộng được qua một số dim, không qua thời gian | `is_active` (cộng qua seller để ra số seller hoạt động trong 1 tháng, nhưng không cộng qua nhiều tháng) |
| **Non-additive** | Không cộng được | `review_score` đơn lẻ, `distinct_customers`, `seller_customer_distance_km`, mọi tỷ lệ % |

**Quy tắc quan trọng của dự án:** không lưu tỷ lệ % trong fact. Fact chỉ lưu **tử số và mẫu số** để cộng được, còn tỷ lệ
được tính lúc truy vấn: `late rate = Σ is_late / Σ is_delivered`. Không lấy trung bình các tỷ lệ theo tháng, vì tháng ít đơn
sẽ kéo lệch kết quả. Đây chính là cách giải quyết vấn đề "hai quản lý hai con số".

#### Các kỹ thuật dimension đã dùng

| Kỹ thuật | Giải thích | Ở dự án |
| --- | --- | --- |
| **Surrogate key** | Khoá số nguyên do DW tự sinh, thay cho khoá gốc (chuỗi dài) | Mọi dim: `*_key bigint` (băm từ natural key, xem [7.3](#73-macro-int_sk-surrogate-key-băm)) |
| **Natural key** | Khoá gốc từ nguồn | `seller_id`, `product_id`, `customer_unique_id` |
| **Unknown member** | Mỗi dim có 1 dòng key = `-1` ("không xác định") | Fact không tra được dim thì trỏ vào -1, **không mất dòng** |
| **Conformed dimension** | Một dim dùng chung cho nhiều fact → so sánh chéo được | `dim_date`, `dim_customer`, `dim_product`, `dim_seller`, `dim_geography`, `dim_order_status` |
| **Role-playing dimension** | Một dim đóng nhiều vai | `dim_date` cho 5 vai trò ngày của fulfillment; `dim_geography` cho địa chỉ khách và địa chỉ seller |
| **Junk dimension** | Gom các thuộc tính lặt vặt ít giá trị thành 1 dim | `dim_payment_type` (loại thanh toán × dải số kỳ), `dim_lead_profile` |
| **Degenerate dimension** | Mã giao dịch nằm luôn trong fact, không có dim riêng | `order_id`, `order_item_id`, `review_id`, `mql_id` |
| **SCD Type 1** | Thuộc tính đổi thì ghi đè, không giữ lịch sử | Mọi dim trừ tier seller |
| **SCD Type 2** | Thuộc tính đổi thì **thêm dòng mới (version)**, giữ lịch sử, có `valid_from`/`valid_to`/`is_current` | `dim_seller.seller_tier` (xem [mục 9](#9-dbt-intermediate-và-scd-type-2-cho-tier-seller)) |
| **Hybrid (Type 6)** | Vừa có giá trị tại thời điểm, vừa có giá trị hiện tại | `bi.v_dim_seller` có cả `Seller Tier` (lúc đó) và `Current Tier` (hôm nay) |

#### Bus matrix (fact nào dùng dim nào)

| Fact | date (vai trò) | customer | product | seller | geography (vai trò) | payment_type | order_status | lead dims |
| --- | --- | :---: | :---: | :---: | --- | :---: | :---: | :---: |
| fact_order_item | purchase, shipping_limit | ✔ | ✔ | ✔ | customer, seller | | ✔ | |
| fact_order_fulfillment | purchase, approved, carrier, delivered, estimated | ✔ | | primary seller | customer, seller | | ✔ | |
| fact_review | review_creation, review_answer | ✔ | | primary seller | customer | | ✔ | |
| fact_payment | purchase | ✔ | | | | ✔ | ✔ | |
| fact_lead_funnel | first_contact, won, first_sale | | | ✔ | | | | origin, profile, sales_rep |
| fact_seller_month | month | | | ✔ | seller | | | |
| fact_seller_product_activity | month | | ✔ | ✔ | | | | |

### 3.4 Kimball vs Inmon, Star vs Snowflake

- **Kimball** (bottom-up): xây theo từng business process, dim conformed nối các mart lại với nhau (bus architecture).
  **Inmon** (top-down): xây một kho tích hợp chuẩn hoá 3NF trước, mart sinh ra sau.
  Dự án theo Kimball, nhưng lớp `stg` đóng vai giống **lớp tích hợp kiểu Inmon**: mọi nguồn được làm sạch và chuẩn hoá
  ở đây trước khi lên mô hình chiều.
- **Star vs Snowflake**: `dim_geography` để dạng **star**, tức zip, city, state, region và dân số nằm chung một bảng.
  Phương án snowflake sẽ tách thành `dim_zip → dim_city → dim_state → dim_region`: ít dư thừa hơn nhưng nhiều join hơn
  và khó duyệt hơn trong Power BI. Chỉ trình bày phương án này trong báo cáo để so sánh, không hiện thực.

### 3.5 Các quy ước chung xuyên suốt dự án

1. **Không xoá dòng lỗi, gắn cờ.** Dòng có vấn đề được giữ và ghi vào cột `_dq_issue`. Sau đó được đếm lại ở `meta.dq_issue_summary`.
2. **Cờ trong fact là integer 0/1** (không phải boolean) để `SUM` trực tiếp.
3. **Date key = số nguyên `YYYYMMDD`**, sự kiện chưa xảy ra thì `-1`.
4. **Primary seller**: fact cấp đơn (fulfillment, review) cần 1 seller, nên lấy seller của item giá cao nhất; hoà thì lấy
   `seller_id` nhỏ nhất. Chỉ 1,3% đơn có > 1 seller nên ảnh hưởng nhỏ.
5. **Khách = `customer_unique_id`**, không phải `customer_id`, vì Olist cấp `customer_id` mới cho **mỗi đơn**.
6. **Tiền giữ nguyên BRL, timestamp giữ nguyên**, không đổi timezone.
7. **Cửa sổ phân tích** `2017-01-01 → 2018-08-31` (chứa 99,6% đơn). Năm 2016 và 09–10/2018 quá thưa.

---

## 4. Hạ tầng: Docker, PostgreSQL, Makefile

### 4.1 Docker Compose (`docker-compose.yml`)

| Service | Image | Cổng | Ghi chú |
| --- | --- | --- | --- |
| `postgres` | `postgres:16` | 5432 | Volume `pgdata` giữ dữ liệu; mount `docker/postgres/init/` để tạo schema lần đầu; `shm_size: 512mb` (mặc định 64 MB làm join song song lỗi *"could not resize shared memory segment"*) |
| `azurite` | `mcr.microsoft.com/azure-storage/azurite:3.37.0` | 10000 | Giả lập Azure Blob, volume `azuritedata` |
| `airflow` | build từ `docker/airflow/Dockerfile` | 8080 | Chỉ bật bằng `make up-airflow` (compose *profile*). Mount cả repo vào `/opt/olist` |

Trong container Airflow, `POSTGRES_HOST` được đổi thành `postgres`, còn `AZURITE_HOST=azurite`, vì trong mạng Docker các
service gọi nhau bằng tên, không dùng `localhost`.

### 4.2 Script khởi tạo Postgres (`docker/postgres/init/`), chỉ chạy khi volume còn trống

| File | Làm gì |
| --- | --- |
| `00_databases.sql` | Tạo DB `airflow` (metadata riêng của Airflow, tách khỏi dữ liệu) |
| `01_schemas.sql` | Tạo 6 schema `raw, stg, dw, bi, ml, meta` + extension `unaccent` (bỏ dấu tên city) |
| `02_meta.sql` | Tạo rỗng các bảng `meta.*`: `etl_run_log`, `dq_results`, `data_dictionary`, `source_to_target`, `model_registry`, `decision_log` |
| `03_ml.sql` | Tạo rỗng 8 bảng `ml.*` (late risk, what-if, segment, voucher, forecast, seller risk, channel value, recommendations) |

**Vì sao tạo bảng `ml`, `meta` rỗng sẵn?** Để view `bi` đọc chúng build được ngay lần đầu, trước khi ML chạy.
dbt khai báo chúng là `source`.

### 4.3 Dockerfile Airflow

- FROM `apache/airflow:2.10.5-python3.11`, cài `requirements-airflow.txt` theo *constraint* của Airflow để không phá dependency.
- **dbt cài trong venv riêng** `/opt/airflow/dbt_venv`, vì dbt và Airflow hay xung đột phiên bản thư viện.
- Cài `libgomp1` vì LightGBM cần.

### 4.4 Makefile: các lệnh chính

| Lệnh | Làm gì |
| --- | --- |
| `make venv` | `uv sync`: tạo `.venv` theo `uv.lock` |
| `make up` / `make down` | Bật / tắt postgres + azurite |
| `make up-airflow` | Bật thêm Airflow |
| `make ingest` | download_kaggle → copy_manual → gen_holidays → upload_to_lake |
| `make load-raw` | Nạp lake → `raw` |
| `make dbt-deps` / `make seed` | Cài package dbt (`dbt_utils`) / nạp seed |
| `make build` | `dbt build` = run + test toàn bộ model theo thứ tự phụ thuộc |
| `make ml` | Chạy 5 script ML (hiện chỉ in cảnh báo "chưa hiện thực") |
| `make meta` | `meta_publish.py`, đẩy kết quả test / từ điển / lineage vào `meta` |
| `make docs` / `make docs-serve` | Sinh / mở tài liệu dbt ở cổng 8081 |
| `make all` | `venv → up → ingest → load-raw → dbt-deps → seed → build → ml → meta → docs` |
| `make replay MONTH=2017-11` | Replay 1 tháng (**chưa hiện thực**) |
| `make reset-db` | Xoá và tạo lại toàn bộ schema (hỏi xác nhận) |

Chi tiết nhỏ: dòng `-include .env` + `export` ở đầu Makefile làm mọi biến trong `.env` thành biến môi trường cho Python và dbt.
Vì vậy **không viết comment cùng dòng với giá trị** trong `.env`, vì Makefile sẽ đọc cả phần comment vào giá trị.

---

## 5. Ingestion: từ CSV vào schema raw

Thư mục `ingestion/`. Mọi script đều **idempotent** (chạy lại nhiều lần không sinh dữ liệu trùng) và có `if __name__ == "__main__"`.

### 5.1 `config.py`: cấu hình dùng chung

- Đọc `.env`; biến môi trường của tiến trình (vd. trong Airflow) được **ưu tiên** hơn `.env` (`override=False`).
- `Settings`: thông tin kết nối Postgres, Azure, cửa sổ phân tích.
- `RAW_SOURCES`: **danh mục 14 nguồn**, mỗi nguồn = `(source, dataset, file_name, raw_table)`. Đây là nơi duy nhất khai báo
  "file nào vào bảng nào". Muốn thêm nguồn mới thì thêm 1 dòng ở đây.
- Đường dẫn landing chuẩn: `landing/<source>/<dataset>/extract_date=YYYY-MM-DD/<file>`.
  Kiểu đặt tên `key=value` là quy ước *Hive partition*, giúp biết file được trích xuất ngày nào.

### 5.2 Bốn script trích xuất (bước ①, ②)

| Script | Làm gì | Idempotent nhờ |
| --- | --- | --- |
| `download_kaggle.py` | Ưu tiên copy 11 CSV từ `data/raw/` (đã commit) sang landing; thiếu file mới gọi Kaggle API. Có `--mode auto/manual/kaggle` | File đã có ở landing → bỏ qua |
| `copy_manual.py` | Copy `br_states.csv`, `calendar_events.csv` (nhóm tự chuẩn bị) vào `landing/manual/...` | Như trên |
| `gen_holidays.py` | Dùng package `holidays` sinh ngày lễ Brazil 2016–2019 (36 ngày) → CSV | Như trên |
| `upload_to_lake.py` | Đẩy toàn bộ `data/landing/` lên Azure Blob, giữ nguyên đường dẫn | Blob đã có → bỏ qua; `overwrite=False` → Azure **từ chối ghi đè** (đảm bảo bất biến) |

`lake.py` là lớp bọc SDK `azure-storage-blob`. Hàm `_resolve_connection_string` tự đổi `127.0.0.1:10000` thành
`azurite:10000` khi chạy trong container. Connection string của Azure thật không bị ảnh hưởng.

### 5.3 `load_raw.py`: nạp lake vào `raw` (bước ③)

Từng bước:

1. Sinh `run_id` (uuid) và `batch_id` (`YYYYMMDDTHHMMSS_<8 ký tự>`).
2. Với mỗi nguồn trong `RAW_SOURCES`: liệt kê mọi blob có tên file đó (mọi `extract_date`).
3. **Bỏ qua blob đã nạp**: kiểm tra `raw.<table>._source_file = <blob key>`. Nhờ vậy, replay (thư mục `extract_date` mới)
   chỉ nạp phần mới.
4. Đọc CSV bằng pandas với `dtype=str` (giữ nguyên chữ, **không để pandas đoán kiểu**, nên zip `01001` không bị thành `1001`),
   `keep_default_na=False`, `utf-8-sig` (file translation có BOM).
5. Chuẩn hoá tên cột (`clean_column`: viết thường, ký tự lạ thành `_`).
6. Thêm 3 cột metadata: `_batch_id`, `_loaded_at`, `_source_file`.
7. Trong **một transaction**: `create table if not exists` (mọi cột `text`), `alter table add column if not exists`
   (nguồn thêm cột thì thêm, **không bao giờ xoá cột**), rồi `COPY ... FROM STDIN`. `COPY` là cách nạp hàng loạt nhanh nhất
   của Postgres: 1 triệu dòng geolocation chỉ mất vài giây.
8. Ghi 1 dòng vào `meta.etl_run_log` (rows_in, rows_out, success/failed). Lỗi thì vẫn ghi log `failed` rồi báo lỗi lên.

**Vì sao `raw` để mọi cột là text?** Để việc nạp **không bao giờ fail** vì dữ liệu bẩn (vd. ngày sai định dạng).
Việc ép kiểu và xử lý lỗi thuộc về dbt (Silver), nơi có test và ghi chép.

---

## 6. dbt: khái niệm nền tảng

> Phần này dành cho người chưa dùng dbt. Đã biết rồi thì nhảy sang [mục 7](#7-dbt-cấu-hình-macro-seed).

### 6.1 dbt làm gì?

Bạn chỉ viết **câu SELECT**. dbt lo phần còn lại:
- bọc SELECT thành `create table ... as select ...` (hoặc `create view`),
- tính thứ tự chạy dựa trên việc model nào tham chiếu model nào,
- chạy test, sinh tài liệu và sơ đồ lineage.

### 6.2 Các khái niệm

| Khái niệm | Giải thích | Ví dụ trong repo |
| --- | --- | --- |
| **Model** | 1 file `.sql` chứa 1 câu SELECT → 1 bảng/view trong DB, tên bảng = tên file | `models/staging/stg_orders.sql` → bảng `stg.stg_orders` |
| **`source()`** | Tham chiếu bảng **không do dbt tạo** (bảng raw, ml, meta) | `{{ source('raw', 'orders') }}` → `"olist_dw"."raw"."orders"` |
| **`ref()`** | Tham chiếu model/seed khác. dbt dùng `ref` để vẽ DAG và chạy đúng thứ tự | `{{ ref('stg_orders') }}` → `"olist_dw"."stg"."stg_orders"` |
| **Seed** | File CSV nhỏ trong `seeds/` → `dbt seed` nạp thành bảng. Dùng cho **bảng tham chiếu** do nhóm quản lý | `seeds/order_status_map.csv` |
| **Macro** | "Hàm" Jinja sinh đoạn SQL, viết 1 lần dùng nhiều nơi | `{{ zip5('customer_zip_code_prefix') }}` |
| **Jinja** | Ngôn ngữ template: `{{ ... }}` in ra giá trị, `{% ... %}` lệnh (if, for), `{# ... #}` comment | |
| **Materialization** | Model được tạo thành gì: `table`, `view`, `incremental`, `ephemeral` | `stg`/`dw` = table, `bi` = view |
| **Test** | Câu SQL **trả về dòng lỗi**; 0 dòng là pass | `unique`, `not_null`, `relationships`, file trong `tests/` |
| **`var()`** | Biến cấu hình dùng chung | `{{ var('analysis_end') }}` = `2018-08-31` |
| **YAML (`_*.yml`)** | Mô tả model, cột và khai báo test | `models/warehouse/facts/_facts.yml` |
| **DAG** | Đồ thị phụ thuộc giữa các model | Xem `make docs-serve` → Lineage graph |

### 6.3 Ví dụ: dbt biến một model thành SQL thật

Bạn viết (`dim_order_status.sql`, rút gọn):

```sql
select
    {{ int_sk(['order_status']) }} as order_status_key,
    order_status, status_group, counts_as_sale
from {{ ref('order_status_map') }}
union all
select {{ unknown_key() }}, 'unknown', 'Unknown', false
```

dbt **compile** (xem trong `target/compiled/...`) thành:

```sql
create table "olist_dw"."dw"."dim_order_status" as (
select
    ('x' || left(md5(concat_ws('|', coalesce(cast(order_status as text), ''))), 15))::bit(60)::bigint as order_status_key,
    order_status, status_group, counts_as_sale
from "olist_dw"."stg"."order_status_map"
union all
select -1, 'unknown', 'Unknown', false
);
```

Sau đó chạy post-hook `analyze "olist_dw"."dw"."dim_order_status"` và ghi comment mô tả cột vào Postgres.

### 6.4 `dbt build` làm gì?

`dbt build` = seed + run + test **theo thứ tự DAG**. Test của một model chạy **ngay sau** model đó. Nếu test có severity
`error` fail thì các model phụ thuộc phía sau bị **skip**, nên dữ liệu sai không lan tiếp xuống dưới.

---

## 7. dbt: cấu hình, macro, seed

### 7.1 `dbt_project.yml`: các cấu hình đáng chú ý

| Cấu hình | Giá trị | Vì sao |
| --- | --- | --- |
| `models.staging/intermediate` | `+schema: stg`, `table` | Silver |
| `models.warehouse` | `+schema: dw`, `table` | Gold |
| `models.bi` | `+schema: bi`, **`view`** | Power BI dùng Import, nên view chỉ được đọc khi Refresh; không cần bảng vật lý |
| `models.quality` | `+schema: meta`, `table` | Bảng tổng hợp lỗi nằm cạnh các bảng metadata khác |
| `+persist_docs` | relation + columns | Mô tả trong YAML được ghi thành **comment** trên bảng/cột Postgres, mở DBeaver là thấy |
| `+post-hook` | `analyze {{ this }}` (chỉ cho table/incremental) | Bảng vừa tạo chưa có statistics, planner chọn kế hoạch join tệ (`fact_order_fulfillment` từng treo hơn 9 phút; sau khi thêm `analyze` còn dưới 1 giây) |
| `on-run-end` | `{{ grant_bi_reader() }}` | Sau mỗi lệnh dbt, tạo/cập nhật user chỉ đọc `bi` cho Power BI |
| `vars` | `analysis_start/end` (đọc từ env), `date_spine_start/end`, `scd_open_end_date = 9999-12-31`, `scd_first_valid_from = 1900-01-01`, `seller_tier_rule_version = v1` | Tham số dùng chung, đổi 1 chỗ |
| `packages-install-path` | env `DBT_PACKAGES_INSTALL_PATH` | Trong Airflow trên Windows, giải nén package lên ổ NTFS mount bị thiếu file, nên cài vào thư mục trong container |

### 7.2 Macro `generate_schema_name`

Mặc định, dbt ghép schema thành `<schema trong profile>_<schema custom>`, ví dụ `stg_dw`. Macro này ghi đè để dùng
**đúng tên** `stg`, `dw`, `bi`, `meta`.

### 7.3 Macro `int_sk`: surrogate key băm

```sql
('x' || left(md5(concat_ws('|', coalesce(cast(col1 as text),''), coalesce(cast(col2 as text),''))), 15))::bit(60)::bigint
```

Đọc từ trong ra ngoài:

1. `coalesce(cast(col as text), '')`: đổi về chữ, null thành `''` (để vị trí cột không bị lệch).
2. `concat_ws('|', ...)`: nối các cột bằng `|`, ví dụ `seller_abc|2017-07-01`.
3. `md5(...)`: băm ra 32 ký tự hex, ví dụ `9f86d081884c7d65...`.
4. `left(..., 15)`: lấy 15 ký tự hex đầu = 60 bit.
5. `'x' || ...`: tiền tố `x` để Postgres hiểu đây là chuỗi bit dạng hex.
6. `::bit(60)::bigint`: đổi thành số nguyên 64 bit. 60 bit nên **luôn dương**, không bao giờ trùng với `-1`.

**Vì sao không dùng `row_number()` hay `serial`?** Vì `row_number` phụ thuộc thứ tự dòng. Thêm 1 sản phẩm mới hoặc load
incremental là mọi key phía sau bị đổi, và fact cũ trỏ sai dim. Key băm thì **cùng natural key luôn ra cùng một key**, ở mọi
lần build và trên mọi máy. Xác suất trùng với 60 bit là cực nhỏ (cỡ n²/2⁶¹; với 100 nghìn dòng ≈ 4·10⁻⁹).

### 7.4 Các macro khác

| Macro | File | Sinh ra | Dùng ở |
| --- | --- | --- | --- |
| `clean_text(col)` | `cleaning.sql` | `nullif(trim(col), '')`: chuỗi rỗng/toàn khoảng trắng thành null | Mọi `stg_*` |
| `zip5(col)` | `cleaning.sql` | `lpad(..., 5, '0')`: zip luôn 5 số, giữ số 0 đầu | customers, sellers, geolocation |
| `clean_city(col)` | `cleaning.sql` | `lower(unaccent(trim(col)))` + gộp khoảng trắng: `São Paulo` → `sao paulo` | customers, sellers, geolocation |
| `state_code(col)` | `cleaning.sql` | `upper(trim(col))` | |
| `to_bool(col)` | `cleaning.sql` | `'True'`/`'False'` → boolean | closed_deals |
| `unknown_key()` | `unknown_member.sql` | `-1` | Mọi dim |
| `coalesce_key(expr)` | `unknown_member.sql` | `coalesce(expr, -1)`: lookup trượt thì về -1 | Mọi fact |
| `date_key(expr)` | `unknown_member.sql` | `to_char(expr::date,'YYYYMMDD')::int`, null → -1 | Mọi fact, dim_date |
| `haversine_km(lat1,lng1,lat2,lng2)` | `haversine.sql` | Khoảng cách đường chim bay giữa 2 toạ độ (km), bán kính Trái Đất 6371 | fact_order_fulfillment |
| `lag_days(from, to)` | `haversine.sql` | Số ngày (có phần lẻ) giữa 2 timestamp; **âm thì null** | fact_order_fulfillment |
| `tier_sort(col)` | `tier_sort.sql` | Gold=1, Silver=2, Bronze=3, New=4, At-risk=5, Unscored=6 | v_dim_seller (sort trong Power BI) |
| `grant_bi_reader()` | `grant_bi_reader.sql` | Tạo/cập nhật role `powerbi_reader`, cấp `usage` + `select` trên `bi`, `alter default privileges` | on-run-end |

### 7.5 Seeds: bảng tham chiếu do nhóm quản lý (nằm ở schema `stg`)

| Seed | Nội dung | Vì sao là seed (không hard-code) |
| --- | --- | --- |
| `order_status_map` | 8 status → `status_group` (Completed/Open/Cancelled) + `counts_as_sale` | Định nghĩa "đơn tính là bán" là quyết định nghiệp vụ, phải nằm ở một chỗ duy nhất |
| `instalment_band` | Dải số kỳ trả góp: 1, 2-3, 4-6, 7-10, 11+ | Dùng cho junk dim `dim_payment_type` |
| `br_state_population` | 27 bang: mã IBGE + dân số 2018 | IBGE API chặn IP ngoài Brazil, nên nhóm tự nhập |
| `category_group` | 74 category (73 + `unknown`) → 12 nhóm ngành | Commerce phân tích theo nhóm, không theo 73 category lắt nhắt |
| `seller_tier_rules` | Ngưỡng chấm tier, có `rule_version` | Seller Quality Manager **đổi ngưỡng không cần sửa SQL**: thêm `rule_version` mới, đổi var `seller_tier_rule_version` |

---

## 8. dbt: Staging (Silver)

### 8.1 Khuôn mẫu chung của mọi `stg_*`

Mọi model staging đều theo 4 bước (viết dạng CTE: *import → logic → final select*):

```
source  (raw.*, mọi cột text)
  │ 1. DEDUP: row_number() over (partition by <natural key> order by _loaded_at desc) → giữ _rn = 1
  │          (raw là append: nạp lại / replay có thể có nhiều bản cùng 1 key → lấy bản mới nhất)
  │ 2. ÉP KIỂU: clean_text → ::timestamp / ::numeric(12,2) / ::int / to_bool
  │ 3. LÀM SẠCH theo rule (đã xác nhận bằng profiling S1, docs/profiling.md)
  │ 4. CỜ DẪN XUẤT + _dq_issue (ghi lỗi chất lượng, KHÔNG xoá dòng)
  ▼
stg.stg_<nguồn>
```

### 8.2 `stg_orders`: model mẫu, đọc kỹ

```sql
-- 1. dedup theo order_id, giữ bản mới nhất
row_number() over (partition by order_id order by _loaded_at desc) as _rn

-- 2. ép kiểu 5 timestamp
nullif(trim(order_purchase_timestamp), '')::timestamp as order_purchase_timestamp, ...

-- 3. phát hiện mốc thời gian vô lý → nối thành chuỗi, ví dụ 'carrier_before_purchase,carrier_before_approved'
nullif(concat_ws(',',
    case when delivered < purchase then 'delivered_before_purchase' end,
    case when carrier   < purchase then 'carrier_before_purchase' end,
    case when carrier   < approved then 'carrier_before_approved' end,
    case when delivered < carrier  then 'delivered_before_carrier' end
), '') as _dq_issue

-- chỉ lỗi nặng nhất (giao trước khi mua) mới null ngày giao; lỗi khác giữ timestamp
case when delivered < purchase then null else delivered end

-- 4. cờ dẫn xuất (định nghĩa KPI chung)
is_delivered = (status = 'delivered' AND có ngày giao)
is_late      = is_delivered AND delivered::date > estimated::date      -- SO THEO NGÀY
delay_days   = delivered::date - estimated::date                        -- âm = giao sớm
```

**Ba quyết định quan trọng trong model này:**
- **So theo ngày, không theo timestamp.** Ngày hứa giao luôn là 00:00, nên so timestamp sẽ coi đơn giao lúc 10h sáng đúng
  ngày hứa là "trễ". Theo ngày: 6,77%; theo timestamp: 8,11%. Dự án chốt **theo ngày**.
- **`is_delivered` cần cả status lẫn ngày giao**: 8 đơn `delivered` thiếu ngày giao, 6 đơn `canceled` lại có ngày giao.
  Định nghĩa này xử lý đúng cả hai trường hợp.
- **Lỗi được giữ lại và gắn cờ**: 1 359 đơn giao cho hãng trước khi duyệt, 166 đơn trước cả ngày mua, 23 đơn khách nhận
  trước khi giao hãng. Các lag âm tương ứng được null ở fact (macro `lag_days`).

### 8.3 Từng model staging

| Model | Grain (1 dòng là) | Biến đổi chính | Số dòng |
| --- | --- | --- | ---: |
| `stg_orders` | 1 order_id | Như 8.2 | 99 441 |
| `stg_order_items` | (order_id, order_item_id) | price/freight → `numeric(12,2)`; `item_total = price + freight`; `shipping_limit_date` ngoài 2016–2019 → null + `_dq_issue = shipping_limit_out_of_range` (4 item có hạn năm 2020, test FK tới dim_date đã bắt được lỗi này) | 112 650 |
| `stg_order_payments` | (order_id, payment_sequential) | `payment_type` viết thường; `installments` 0 → 1 (2 dòng, `_dq_issue = installments_fixed_to_1`); giữ `not_defined` (3 dòng, đơn huỷ, 0 BRL) | 103 886 |
| `stg_order_reviews` | (review_id, order_id) | `has_comment`, `comment_length`, `is_low_score` (≤ 2), `response_hours`; **`is_latest_for_order`**: 1 review / đơn dùng cho KPI (answer mới nhất → creation mới nhất → review_id). Khoá kép vì 789 review_id nằm ở > 1 đơn | 99 224 (98 673 latest) |
| `stg_customers` | 1 customer_id | zip5, clean_city, state upper | 99 441 |
| `stg_sellers` | 1 seller_id | Như trên | 3 095 |
| `stg_products` | 1 product_id | Sửa tên cột sai chính tả gốc `*_lenght` → `*_length`; category null → `unknown` (610 sp); weight 0 → null (4 sp); `product_volume_cm3 = L × H × W` | 32 951 |
| `stg_geolocation` | 1 zip prefix | **1 000 163 điểm → 19 015 zip**, xem 8.4 | 19 015 |
| `stg_product_category_name_translation` | 1 category | lower | 71 |
| `stg_mql` | 1 mql_id | `origin` null → `unknown` | 8 000 |
| `stg_closed_deals` | 1 mql_id | `has_company`, `has_gtin` → boolean; số tự khai → numeric | 842 |
| `stg_br_states` | 1 bang | upper mã bang | 27 |
| `stg_calendar_events` | (date, name) | Ép kiểu (chưa dùng ở downstream, COULD) | 52 |
| `stg_br_holidays` | 1 ngày | Gộp nhiều lễ trùng ngày bằng `string_agg` | 36 |

### 8.4 `stg_geolocation`: model phức tạp nhất ở staging

Vấn đề: 1 zip có trung bình 52,6 toạ độ, có điểm nằm ngoài Brazil, tên city viết nhiều kiểu (`são paulo` / `sao paulo`).

```
latest_batch : chỉ lấy batch mới nhất (_loaded_at = max) → nạp lại không nhân điểm
points       : zip5, ép lat/lng sang double, clean_city
flagged      : in_brazil = lat ∈ [-34, 5.5] VÀ lng ∈ [-74, -34]   (bounding box Brazil)
coords       : avg(lat), avg(lng) CHỈ trên điểm in_brazil; đếm n_points, n_points_outside_brazil
city_mode    : city xuất hiện nhiều nhất trong zip   (distinct on + order by count(*) desc)
state_mode   : state xuất hiện nhiều nhất trong zip  (8 zip có > 1 bang)
→ 1 dòng / zip
```

Kỹ thuật `distinct on (zip_prefix) ... order by zip_prefix, count(*) desc, city` là cách viết của Postgres để lấy
**dòng đầu tiên của mỗi nhóm**, ở đây là giá trị *mode* (xuất hiện nhiều nhất). Hoà thì lấy theo thứ tự chữ, đảm bảo kết quả xác định.

Hiệu quả: `são paulo` (24 918 điểm) và `sao paulo` (135 800 điểm) gộp thành một giá trị `sao paulo`; 8 011 tên city còn 5 969.

---

## 9. dbt: Intermediate và SCD Type 2 cho tier seller

Model `int_*` là bước trung gian, nằm ở schema `stg`. Chúng tồn tại để: (a) dùng lại logic ở nhiều fact,
(b) tách logic phức tạp thành các bước nhỏ dễ test.

### 9.1 Ba model intermediate cho đơn hàng

| Model | Làm gì | Số dòng |
| --- | --- | ---: |
| `int_customer_map` | `customer_id` (theo đơn) → `customer_unique_id` (người thật) + zip/city/state của **đơn đó** | 99 441 |
| `int_order_primary_seller` | `distinct on (order_id) ... order by order_id, price desc, seller_id` → seller của item đắt nhất, hoà thì seller_id nhỏ nhất | 98 666 |
| `int_order_agg` | Theo đơn: `item_count`, `order_value` (Σ price, **không gồm ship**, cùng cơ sở với GMV), `freight_total`, `seller_count`, `max_shipping_limit_date` | 98 666 |

98 666 = 99 441 − 775 đơn không có item nào (đơn hợp lệ trong nguồn, phần lớn là đơn huỷ/unavailable).

### 9.2 SCD Type 2 cho tier seller: bài toán

Seller Quality Manager muốn biết: *"Seller này **lúc đó** đang là Gold hay At-risk?"* và *"Bao nhiêu seller chuyển từ
Bronze lên Silver?"*. Tier thay đổi theo thời gian, nên phải **giữ lịch sử**. Đó là SCD Type 2.

Làm trong 3 bước, **đọc từ `stg` chứ không từ fact**. Lý do: fact cần `dim_seller` để lấy `seller_key`. Nếu `dim_seller`
lại tính từ fact thì sinh vòng lặp `dim_seller → fact → dim_seller`, và dbt sẽ báo lỗi chu trình.

```
stg_order_items + stg_orders + stg_order_reviews + seed order_status_map
      │
      ▼  Bước 1: int_seller_month_metrics   (seller × tháng: số đơn, giao, trễ, review + cửa sổ trượt 3 tháng)
      ▼  Bước 2: int_seller_tier_monthly    (chấm tier mỗi tháng theo seed seller_tier_rules)
      ▼  Bước 3: int_seller_tier_versions   (chỉ giữ tháng tier đổi → các version có valid_from / valid_to)
      ▼
   dim_seller  (version + thuộc tính Type 1)
```

### 9.3 Bước 1: `int_seller_month_metrics` (33 488 dòng)

1. `order_sellers`: các cặp (đơn, seller) phân biệt. Đơn có 2 seller thì **tính cho cả hai**.
2. Join `stg_orders` + `order_status_map` + review mới nhất.
3. `monthly`: gom theo seller × tháng mua:
   `orders` (counts_as_sale), `delivered_orders`, `late_orders`, `cancelled_orders`, `review_count`, `score_sum`.
4. `spine`: **dày đặc hoá**. Dùng `generate_series(first_month, analysis_end, '1 month')` sinh đủ mọi tháng từ tháng bán đầu
   tiên đến 2018-08, kể cả tháng không bán (số liệu = 0). Cần làm vậy vì cửa sổ trượt tính theo *số dòng*: thiếu tháng thì
   "3 dòng" không còn là "3 tháng".
5. `rolling`: cửa sổ trượt 3 tháng `rows between 2 preceding and current row`:
   `orders_3m`, `late_rate_3m = late_3m / delivered_3m`, `avg_score_3m = score_sum_3m / review_count_3m`,
   `months_since_first` (thâm niên tính theo tháng).

**Vì sao dùng cửa sổ 3 tháng?** Seller ít đơn chỉ cần 1 đơn trễ là late rate tháng đó vọt lên 100%. Gộp 3 tháng giúp tier
không nhảy lên xuống liên tục.

### 9.4 Bước 2: `int_seller_tier_monthly`: chấm tier

Ngưỡng lấy từ seed (`rule_version = v1`). Seed được **pivot** thành 1 dòng bằng `max(...) filter (where tier = ...)`.
Logic xét **theo thứ tự**, gặp điều kiện đúng đầu tiên thì dừng:

| Thứ tự | Tier | Điều kiện (v1) |
| :---: | --- | --- |
| – | *(null)* | Tháng không có đơn → chưa chấm, sẽ **kế thừa** tier tháng trước |
| 1 | **New** | `months_since_first < 3` (chỉ xét thâm niên) |
| 2 | **Bronze** | `orders_3m < 5`: đủ thâm niên nhưng quá ít đơn để chấm |
| 3 | **At-risk** | `late_rate_3m ≥ 0.15` **HOẶC** `avg_score_3m < 3.5` |
| 4 | **Gold** | `orders_3m ≥ 50` **VÀ** `late_rate_3m < 0.05` **VÀ** `avg_score_3m ≥ 4.5` |
| 5 | **Silver** | `orders_3m ≥ 15` **VÀ** `late_rate_3m < 0.08` **VÀ** `avg_score_3m ≥ 4.2` |
| 6 | **Bronze** | Còn lại |

Thiếu dữ liệu (chưa có đơn giao hoặc chưa có review) thì phép so sánh trả về null, và `coalesce(..., false)` biến nó thành
"không đạt" điều kiện đó.

**Kế thừa tier cho tháng không bán** (kỹ thuật *gaps and islands*):

```sql
count(tier_scored) over (partition by seller_id order by month_start) as tier_grp
```

`count(cột)` chỉ đếm giá trị khác null, nên chỉ tăng ở tháng có chấm tier. Các tháng null phía sau cùng `tier_grp` với tháng
có chấm gần nhất. Lấy `first_value(tier_scored)` trong nhóm là ra tier để kế thừa. Ngoại lệ: tier kế thừa là `New` mà đã quá
3 tháng thâm niên thì chuyển thành `Bronze` (để seller ngừng bán khi còn New không bị giữ nhãn New mãi).

> **Đã chỉnh rule 01/11:** rule gốc "New = < 3 tháng **HOẶC** orders_3m < 5" làm seller bán 22 tháng nhưng ít đơn bị gắn
> nhãn New (288 seller vào 08/2018). Đã sửa thành New chỉ theo thâm niên; ít đơn thì Bronze. Ngưỡng số trong seed giữ nguyên.

### 9.5 Bước 3: `int_seller_tier_versions`: từ tier tháng thành version SCD2

Quy tắc:
- Tier chấm cho tháng M **chỉ biết được khi tháng M kết thúc**, nên có hiệu lực từ **ngày đầu tháng M+1**
  (tránh "nhìn trước tương lai").
- **Version đầu** luôn có `valid_from = 1900-01-01`, tier `New`, để mọi sự kiện trước lần chấm đầu đều tra được.
- Chỉ tạo version mới khi tier **đổi** (so với `lag(seller_tier)`).
- `valid_to = valid_from của version kế − 1 ngày`; version cuối `valid_to = 9999-12-31`, `is_current = true`.

### 9.6 Ví dụ minh hoạ trọn vẹn (seller giả định X, bán từ 03/2017)

**Bước 1 + 2: chỉ số và tier từng tháng**

| Tháng | orders | orders_3m | late_rate_3m | avg_score_3m | months_since_first | Tier chấm | Tier cuối |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 2017-03 | 2 | 2 | 0,00 | 5,0 | 0 | New | New |
| 2017-04 | 4 | 6 | 0,00 | 4,7 | 1 | New | New |
| 2017-05 | 6 | 12 | 0,00 | 4,6 | 2 | New | New |
| 2017-06 | 8 | 18 | 0,06 | 4,4 | 3 | **Silver** (≥15 đơn, trễ < 8%, điểm ≥ 4,2) | Silver |
| 2017-07 | 0 | 14 | … | … | 4 | *(null)* | Silver (kế thừa) |
| 2017-08 | 5 | 13 | 0,20 | 3,9 | 5 | **At-risk** (trễ ≥ 15%) | At-risk |

**Bước 3: version (lùi 1 tháng vì tier tháng M hiệu lực từ đầu tháng M+1)**

| version_no | valid_from | valid_to | seller_tier | is_current |
| :---: | --- | --- | --- | :---: |
| 1 | 1900-01-01 | 2017-06-30 | New | false |
| 2 | 2017-07-01 | 2017-08-31 | Silver | false |
| 3 | 2017-09-01 | 9999-12-31 | At-risk | **true** |

**Tra cứu trong fact:** một đơn của X mua ngày **2017-08-15** thì `2017-08-15 between valid_from and valid_to` khớp
**version 2 (Silver)**. Nghĩa là lúc khách mua, seller đang là Silver, dựa trên kết quả đã biết đến hết tháng 7. Đây gọi là
**point-in-time lookup**.

### 9.7 `dim_seller`: ghép version với thuộc tính Type 1

- Tập seller = `stg_sellers` ∪ `stg_closed_deals.seller_id` (462 seller chốt deal nhưng chưa từng bán vẫn **có key**,
  không rơi vào unknown).
- Seller có trong `int_seller_tier_versions` dùng các version đó. Seller không có (chưa bán, hoặc chỉ bán sau 2018-08) nhận
  1 version mặc định 1900-01-01 → 9999-12-31, tier `Unscored` (chưa bán) hoặc `New`.
- `seller_key = int_sk(seller_id, valid_from)`. Vì version đầu luôn là 1900-01-01, key của version đầu **không đổi** so với
  bản `dim_seller` tạm (Type 1) trước đây, nên fact không phải sửa.
- Thuộc tính Type 1: `seller_geo_key`, `has_sales`, `is_from_funnel`.

Kết quả: 3 557 seller, 8 189 version (TB 2,3, tối đa 12). Tier hiện hành: Bronze 2 226 · New 536 · Unscored 462 · Silver 168 ·
At-risk 159 · Gold 6. Chuyển tier hay gặp nhất: New→Bronze 1 450, At-risk→Bronze 544, Bronze→At-risk 515, Bronze→Silver 447.

> **Vì sao không dùng `dbt snapshot`?** Snapshot chỉ ghi lại trạng thái **quan sát được lúc chạy**, nên không dựng lại được
> lịch sử 2017–2018 từ dữ liệu tĩnh. Backfill lịch sử vì vậy phải viết bằng SQL như trên. Snapshot (strategy `check` trên
> `seller_tier`) chỉ hợp lý khi hệ thống chạy live hằng ngày (xem [mục 20](#20-hướng-phát-triển-sắp-tới)).

---

## 10. dbt: Dimensions (Gold)

Mọi dim đều có: surrogate key băm, **1 dòng unknown key = -1** (thêm bằng `union all`), test `unique` + `not_null` trên key.

| Dim | Grain / natural key | Cách dựng | Điểm cần nhớ | Dòng |
| --- | --- | --- | --- | ---: |
| `dim_date` | 1 ngày 2016-01-01 → 2019-12-31; key `YYYYMMDD` | `dbt_utils.date_spine` sinh dãy ngày; join `stg_br_holidays` | `is_br_holiday`, `holiday_name`; **Black Friday** = thứ Sáu thứ 4 của tháng 11, tính bằng công thức: `ngày 1/11 + ((5 − thứ của 1/11 + 7) % 7) + 21`; `is_black_friday_week` = cùng tuần ISO | 1 462 |
| `dim_order_status` | 1 status | Từ seed `order_status_map` | `counts_as_sale` là điều kiện của GMV / Orders | 9 |
| `dim_geography` | 1 zip prefix 5 số | Tập zip = geolocation ∪ customers ∪ sellers (thêm 162 zip không có toạ độ) | city/state ưu tiên geolocation, thiếu thì lấy mode từ customers/sellers; join `stg_br_states` (tên bang, vùng) + seed dân số. Zip không có trong geolocation → lat/lng null. **Star**, không snowflake | 19 178 |
| `dim_product` | 1 product_id | `stg_products` + translation + seed `category_group` | `category_pt`, `category_en` (thiếu bản dịch thì giữ tên PT), `category_group`; `weight_band` (< 0.5 kg … ≥ 10 kg), `size_band` (< 1 L … ≥ 50 L) | 32 952 |
| `dim_customer` | 1 `customer_unique_id` | Đơn đầu tiên (`distinct on ... order by timestamp`) + đếm đơn | `first_order_date_key`, `first_order_state`, `customer_geo_key` (zip đơn đầu), `order_count_lifetime` (tối đa 17). **Không chứa segment ML**: segment sẽ nối ở `bi.v_dim_customer`, tránh vòng `dw ↔ ml` | 96 097 |
| `dim_payment_type` | Junk: payment_type × instalment_band | `cross join` mọi loại × mọi dải | Sinh **đủ mọi tổ hợp** (5 × 5) để fact luôn tra được, kể cả tổ hợp chưa xuất hiện | 26 |
| `dim_seller` | 1 **version** seller | Mục 9.7 | SCD2 trên tier | 8 190 |
| `dim_lead_origin` | origin + landing_page_id | distinct từ `stg_mql` | Kênh marketing | 1 183 |
| `dim_lead_profile` | Junk thuộc tính hồ sơ lead | distinct từ `stg_closed_deals` | **Chỉ có cho lead đã chốt**. Lead chưa chốt → key -1 (`not_won`), nên **không được dùng làm feature dự đoán conversion** (sẽ rò rỉ đáp án) | 503 |
| `dim_sales_rep` | sdr_id + sr_id | distinct từ `stg_closed_deals` | | 225 |

---

## 11. dbt: Facts (Gold)

### 11.1 Khuôn mẫu lookup chung của mọi fact

```sql
select
    {{ date_key('o.order_purchase_timestamp') }}  as purchase_date_key,   -- ngày → YYYYMMDD, null → -1
    {{ coalesce_key('c.customer_key') }}           as customer_key,        -- lookup trượt → -1
    ...
from <stg>
left join dim_customer c on <natural key> = c.customer_unique_id          -- LEFT JOIN: không mất dòng fact
left join dim_seller   s on i.seller_id = s.seller_id
                        and o.order_purchase_timestamp::date between s.valid_from and s.valid_to   -- point-in-time SCD2
```

Hai điểm cần nhớ: **luôn `left join` tới dim** để không mất dòng fact khi lookup trượt, và lookup seller luôn kèm điều kiện
**ngày nằm trong `[valid_from, valid_to]`**.

### 11.2 `fact_order_item`: Transaction (112 650 dòng)

- **Grain:** 1 item của 1 đơn. Degenerate: `order_id`, `order_item_id`.
- **Keys:** `purchase_date_key`, `shipping_limit_date_key`, `customer_key`, `product_key`, `seller_key` (version tại ngày mua),
  `customer_geo_key` (zip của đơn), `seller_geo_key`, `order_status_key`.
- **Measures (additive):** `item_price`, `freight_value`, `item_total`, `item_count = 1`.
- Là nguồn của **GMV** = Σ `item_price` với đơn `counts_as_sale`.

### 11.3 `fact_payment`: Transaction (103 886 dòng)

- **Grain:** 1 lần thanh toán (`order_id`, `payment_sequential`). Một đơn có thể trả bằng nhiều phương thức.
- `payment_type_key`: tra junk dim theo **loại + số kỳ nằm trong dải**
  (`payment_installments between min_instalments and max_instalments`).
- Measures: `payment_value`, `payment_count` (additive); `payment_installments` (non-additive, chỉ lấy trung bình).

### 11.4 `fact_order_fulfillment`: Accumulating snapshot (99 441 dòng = 1 dòng / đơn)

Fact quan trọng nhất cho Logistics.

| Nhóm | Cột | Cách tính |
| --- | --- | --- |
| 5 vai trò ngày | `purchase / approved / carrier / delivered / estimated _date_key` | `date_key(...)`, chưa xảy ra → -1 |
| Khoá | `customer_key`, `primary_seller_key`, `customer_geo_key`, `seller_geo_key`, `order_status_key` | Primary seller từ `int_order_primary_seller`, version tại ngày mua |
| Số lượng / tiền | `item_count`, `order_value`, `freight_total` | Từ `int_order_agg`; đơn không có item → 0 |
| Cờ 0/1 | `is_delivered`, `is_late` | Từ `stg_orders` |
| | `is_dispatch_late` | `carrier_date > max(shipping_limit_date)`: seller giao cho hãng vận chuyển trễ hạn |
| | `has_carrier_date` | Mẫu số của dispatch late rate |
| Lag (ngày, có phần lẻ) | `approval_lag` = approved − purchase | `lag_days`: **âm thì null** để không kéo lệch trung bình |
| | `dispatch_lag` = carrier − approved | |
| | `transit_lag` = delivered − carrier | |
| | `delivery_lag` = delivered − purchase | Chỉ khi `is_delivered` |
| | `promised_lag` = estimated − purchase | Số ngày Olist hứa |
| | `delay_days` | delivered::date − estimated::date (âm = sớm) |
| Non-additive | `seller_customer_distance_km` | `haversine_km(toạ độ seller, toạ độ khách)` |
| Audit | `_dq_issue`, `_dw_loaded_at`, `_dw_updated_at` | Vì accumulating snapshot được cập nhật |

Đơn hành trình theo thời gian:

```
purchase ──approval_lag──▶ approved ──dispatch_lag──▶ carrier ──transit_lag──▶ delivered
    └──────────────────────────────── delivery_lag ─────────────────────────────────┘
    └──────────────────────── promised_lag ─────────────▶ estimated
                                                 delay_days = delivered − estimated (theo ngày)
```

### 11.5 `fact_review`: Transaction (99 224 dòng)

- **Grain:** (review_id, order_id).
- `primary_seller_key` (version tại ngày mua của đơn), `review_creation_date_key`, `review_answer_date_key`.
- Measures: `review_count = 1`, `score_sum = review_score` (để tính trung bình = Σ score_sum / Σ review_count),
  `is_low_score`, `has_comment`, `comment_length`, `response_hours`.
- **`is_latest_for_order`**: KPI điểm review **chỉ** dùng dòng này (547 đơn có > 1 review, 202 đơn trong đó có các điểm khác nhau).

### 11.6 `fact_seller_month`: Periodic snapshot (33 488 dòng)

- **Grain:** 1 seller × 1 tháng, **dày đặc** từ tháng bán đầu tiên đến 2018-08 (tháng không bán vẫn có dòng, `is_active = 0`).
- Đơn/giao/trễ/huỷ/review lấy **từ `int_seller_month_metrics`**, tức cùng định nghĩa với tier SCD2, nên dashboard và tier
  không thể lệch nhau.
- `items`, `gmv`, `distinct_customers` lấy từ `fact_order_item` (đơn counts_as_sale).
- `seller_key` = version hiệu lực tại **ngày cuối tháng**.
- Additivity: hầu hết additive; `is_active` semi-additive; `distinct_customers` non-additive.

> **Seller late rate 6,69% khác late rate cấp đơn 6,77%, và điều đó đúng thiết kế:** fact này đếm theo cặp đơn × seller
> (đơn 2 seller được đếm 2 lần), chỉ đơn counts_as_sale, và cắt ở 2018-08. Trang seller dùng số seller, trang tổng quan dùng
> số cấp đơn. **Không trộn hai loại trên cùng một visual.**

### 11.7 `fact_lead_funnel`: Accumulating snapshot (8 000 dòng = 1 / MQL)

- Mốc: `first_contact_date_key` → `won_date_key` → `first_sale_date_key` (-1 nếu chưa xảy ra).
- Keys: `lead_origin_key`, `lead_profile_key` (-1 nếu chưa chốt), `sales_rep_key` (-1 nếu chưa chốt), `seller_key`
  (version tại ngày chốt).
- Measures: `lead_count = 1`, `is_won`, `has_first_sale`, `days_to_close` (null nếu won trước contact: 1 lead lỗi),
  `declared_*` (seller tự khai, độ tin thấp), `gmv_first_90_days` = Σ item_price của seller trong `[won_date, won_date + 90]`.
- **`has_full_90d_window`** = `won_date + 90 ≤ 2018-08-31`. Deal chốt tới 11/2018 nhưng dữ liệu đơn hết ở 08/2018, nên deal
  chốt muộn **chưa đủ 90 ngày quan sát**. So giá trị kênh chỉ dùng 667 deal có cờ này.
- Số liệu: conversion **10,53%** (842 / 8 000), chốt trung bình 48,5 ngày, GMV 90 ngày ~515 BRL / deal (deal đủ cửa sổ).

### 11.8 `fact_seller_product_activity`: Factless (62 067 dòng)

- `select distinct month_date_key, seller_key, product_key` từ `fact_order_item` (đơn counts_as_sale, trong cửa sổ phân tích).
- Không có measure: **đếm dòng = số listing đang hoạt động**, đo độ rộng danh mục của seller.

---

## 12. dbt: Lớp BI (serving) và lớp Quality

### 12.1 Vì sao cần lớp `bi`

`bi` là **hợp đồng (contract) với Power BI**. Báo cáo chỉ phụ thuộc tên cột ở `bi`, nên khi `dw` đổi chỉ cần sửa view,
báo cáo vẫn giữ nguyên.

Nguyên tắc (chi tiết: `docs/bi_layer.md`):
1. **View mỏng**: chỉ `select ... from ref(...)` và đổi tên cột. **Không `group by`, không đổi grain**: số dòng view = số dòng
   fact, có test `dbt_utils.equal_rowcount` kiểm tra.
2. **Không tính KPI trong SQL**: tỷ lệ là DAX measure theo `docs/kpi_dictionary.md`.
3. Cột khoá giữ `snake_case` (để ẩn trong Power BI); cột hiển thị dùng Title Case có dấu cách, ví dụ `"Item Price"`.

### 12.2 21 view

| Nhóm | View |
| --- | --- |
| Dim (11) | `v_dim_date`, `v_dim_customer`, `v_dim_product`, `v_dim_seller`, `v_dim_customer_geo`, `v_dim_seller_geo`, `v_dim_payment_type`, `v_dim_order_status`, `v_dim_lead_origin`, `v_dim_lead_profile`, `v_dim_sales_rep` |
| Fact (7) | `v_fact_sales`, `v_fact_fulfillment`, `v_fact_review`, `v_fact_payment`, `v_fact_seller_month`, `v_fact_lead_funnel`, `v_fact_seller_product_activity` |
| Data Quality (3) | `v_dq_latest` (test của lần chạy mới nhất), `v_etl_runs` (lịch sử chạy), `v_dq_issue_summary` |

### 12.3 Các quyết định đáng chú ý

| Quyết định | Lý do |
| --- | --- |
| `v_dim_date` **bỏ dòng -1** | Power BI chỉ cho "Mark as date table" khi cột ngày không trống, không trùng. Fact có key -1 sẽ hiện là *(Blank)*, đúng nghĩa "chưa xảy ra" |
| Geography tách **2 view** (customer / seller) | Ma trận tuyến bang seller × bang khách cần cả hai cùng lúc |
| Date **1 bảng** + relationship inactive | Slicer ngày dùng chung mọi trang; ngày khác ngày mua thì dùng `USERELATIONSHIP` trong DAX |
| `primary_seller_key` đổi tên → `seller_key` trong view | Chỉ cần 1 relationship tới `Seller` |
| `v_dim_seller` có `Seller Tier` / `Previous Tier` / `Current Tier` (+ cột sort) | Point-in-time, ma trận chuyển tier, tier hôm nay. `Previous Tier = lag(...)`, `Current Tier = max(case when is_current ...) over (partition by seller_id)` |
| User `powerbi_reader` | Chỉ có quyền `bi`. View Postgres chạy với quyền của **owner** (user `olist`), nên đọc được view mà không cần quyền trên `dw` (đã kiểm tra: `select ... from dw.fact_order_item` → *permission denied*) |
| Chưa có view ML | Bảng `ml.*` còn rỗng; làm khi có M3–M7 |

### 12.4 Lớp Quality: `meta.dq_issue_summary`

Model `models/quality/dq_issue_summary.sql`. Mỗi dòng = 1 loại lỗi trong 1 model: số dòng lỗi / tổng dòng / %. Gồm:
- Lỗi đã gắn cờ `_dq_issue` ở các stg (tách chuỗi bằng `unnest(string_to_array(_dq_issue, ','))`).
- Bất thường đã biết nhưng không gắn cờ trên dòng: điểm ngoài Brazil, zip không toạ độ, đơn không item, seller funnel chưa
  bán, đơn nhiều review.
- **Số đơn lệch tiền item vs payment vượt tolerance (249 đơn)**. Phải đếm lại ở đây vì test đối soát tương ứng là
  `warn_if > 1000`; khi dưới ngưỡng, dbt ghi `failures = 0`, làm mất con số thật.

---

## 13. Kiểm thử và đối soát

269 test, chạy mỗi lần `dbt build`; kết quả được đẩy vào `meta.dq_results`.

### 13.1 Generic test (khai báo trong YAML)

| Test | Kiểm tra | Áp dụng |
| --- | --- | --- |
| `unique`, `not_null` | Khoá không trùng, không rỗng | Mọi khoá stg/dim/fact, khoá grain của fact |
| `relationships` | Mọi FK fact → dim tồn tại | Mọi khoá trong 7 fact; một số stg → stg (items → orders, products, sellers) |
| `accepted_values` | Giá trị nằm trong danh sách | order_status, payment_type, review_score 1–5, seller_tier, weight/size band, cờ 0/1 |
| `dbt_utils.equal_rowcount` | Hai bảng cùng số dòng | stg ↔ fact; view bi ↔ fact |
| Range (`dbt_utils.accepted_range` …) | price > 0, freight ≥ 0, installments ≥ 1 | stg |

### 13.2 Singular test (file trong `tests/`, trả về dòng = lỗi)

| Test | Kiểm tra | Severity |
| --- | --- | --- |
| `assert_dim_seller_one_current_version` | Mỗi seller đúng 1 version `is_current` | error |
| `assert_dim_seller_no_overlapping_versions` | Các version không chồng thời gian, `valid_from ≤ valid_to` | error |
| `assert_dim_seller_versions_contiguous` | Version liên tục (kế tiếp đúng +1 ngày), đầu 1900-01-01, cuối 9999-12-31 → mọi ngày tra được **đúng 1** version | error |
| `assert_fact_seller_point_in_time` | Version seller gắn với mỗi item hiệu lực đúng ngày mua | error |
| `assert_fulfillment_dates_in_order` | Ngày khách nhận không trước ngày mua | error |
| `assert_reconcile_gmv_stg_vs_fact` | Σ price, Σ freight của fact = stg (không mất / nhân dòng khi join dim) | error |
| `assert_reconcile_seller_month_vs_items` | Σ items, Σ gmv `fact_seller_month` = `fact_order_item` **theo từng tháng** | error |
| `assert_reconcile_funnel_won` | Số lead chốt = số dòng closed_deals; mọi deal có seller_key | error |
| `assert_reconcile_item_vs_payment` | Σ item_total vs Σ payment_value theo đơn, tolerance `max(1 BRL, 1%)` | warn nếu > 1 000 đơn |
| `assert_fact_unknown_key_share` | Mọi fact có tỷ lệ key -1 < 1% (dùng vòng lặp Jinja `{% for %}` sinh 25 câu SELECT) | warn |

**Test đã bắt được lỗi thật:** FK `shipping_limit_date_key → dim_date` fail ở 4 dòng (hạn giao năm 2020), từ đó sinh ra rule
mới trong `stg_order_items`. Đây là ví dụ tốt để kể trong báo cáo hoặc demo.

---

## 14. Metadata: `meta_publish.py`

Chạy **ngay sau `dbt build`, trước `dbt docs generate`**, vì lệnh docs ghi đè `run_results.json`.

| Đọc | Ghi vào | Nội dung |
| --- | --- | --- |
| `target/run_results.json` + `manifest.json` | `meta.dq_results` | Mỗi test 1 dòng: tên, loại (generic/singular), model, status, failures. `run_id` = `invocation_id` của dbt |
| `run_results.json` | `meta.etl_run_log` | 1 dòng `dbt:build` tóm tắt (vd. `pass=269, success=65`) |
| `manifest.json` + `information_schema.columns` | `meta.data_dictionary` | Mọi cột của model/seed/source: schema, bảng, cột, **kiểu dữ liệu thật**, mô tả (603 cột) |
| `manifest.json` (`depends_on`) | `meta.source_to_target` | Lineage cấp model: model đích ← các model nguồn (59 model) |

Tính **idempotent**: xoá các dòng cùng `run_id` trước khi ghi; `data_dictionary` và `source_to_target` được `truncate` rồi
ghi lại toàn bộ.

5 loại metadata khớp với môn học: *structure* (data_dictionary), *source data* (etl_run_log), *transformation*
(source_to_target), *data model* (dbt docs), *history of extracts* (etl_run_log theo batch).

---

## 15. Airflow: điều phối pipeline

File `airflow/dags/olist_pipeline.py`, 15 task:

```
[download_kaggle, copy_manual, gen_holidays]  (song song)
        → upload_to_lake → load_raw
        → dbt_deps → dbt_seed → dbt_build
        → [ml_late_risk, ml_crm, ml_forecast, ml_seller_risk]  (song song)
        → ml_recommendations
        → meta_publish → dbt_docs_generate
```

- Mỗi task là một `BashOperator` gọi **đúng lệnh như Makefile** (một nguồn logic, không viết logic trùng lặp trong DAG).
- dbt gọi bằng `/opt/airflow/dbt_venv/bin/dbt` (venv riêng).
- `schedule="@daily"`, `catchup=False`, mặc định paused; `retries=1`, nghỉ 2 phút.
- Callback `on_success` / `on_failure`: mỗi task ghi 1 dòng `airflow:<task_id>` vào `meta.etl_run_log`. Lỗi ghi log
  **không làm hỏng task**.
- Đọc UI (http://localhost:8080, admin/admin): *Graph* = sơ đồ; *Grid* = mỗi cột 1 lần chạy, mỗi ô 1 task; bấm ô → *Logs*;
  *Gantt* = thời gian từng task.

---

## 16. Số liệu kiểm chứng

Đọc trực tiếp từ database ngày 03/11/2026.

### 16.1 Số đối tượng theo schema

| Schema | raw | stg | dw | bi | meta | ml |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Bảng / view | 14 | 25 | 17 | 21 | 7 | 8 (rỗng) |

### 16.2 KPI đã đối chiếu (tính trên toàn bộ dữ liệu)

| KPI | Giá trị | Đối chiếu |
| --- | --- | --- |
| GMV | 13 494 400,74 BRL | Σ fact_seller_month khớp từng tháng (≤ 2018-08) |
| Orders (counts_as_sale) | 98 207 | |
| AOV | 137,41 BRL | |
| Late rate | **6,77%** (6 534 / 96 470) | = profiling S1 tính tay trên raw ✅ |
| Avg delivery days | 12,56 ngày (Olist hứa TB 23,77 ngày) | = profiling ✅ |
| Dispatch late rate | 9,06% | |
| Avg review score | 4,086; low-score 14,69% | |
| Lead conversion | 10,53% | = S5 ✅ |
| Key -1 trong fact | 0 ở mọi nơi, trừ 775 đơn không item (primary_seller = -1, 0,78%) | Dưới ngưỡng 1% ✅ |

Toàn bộ KPI + DAX: `docs/kpi_dictionary.md`.

---

## 17. Tự chạy và tự kiểm tra

### 17.1 Lệnh

```bash
make up                     # postgres + azurite
make build                  # dbt build toàn bộ (~20 s)
make meta                   # đẩy kết quả test, dictionary, lineage vào meta
make docs-serve             # http://localhost:8081 → nút Lineage graph góc dưới phải

# chỉ build 1 model và mọi thứ phía sau nó
uv run dbt build --select stg_orders+          # (trong dbt/olist_dw, hoặc qua make vì Makefile export env)
# chỉ build lớp bi
uv run dbt build --select path:models/bi
# xem SQL đã compile
ls dbt/olist_dw/target/compiled/olist_dw/models/
```

### 17.2 Truy vấn mẫu (DBeaver: `localhost:5432`, `olist_dw`, `olist`/`olist`)

```sql
-- Late rate theo tuyến bang seller → bang khách
select sg.state_code seller_state, cg.state_code customer_state,
       sum(f.is_delivered) delivered,
       round(100.0 * sum(f.is_late) / nullif(sum(f.is_delivered), 0), 2) late_pct
from dw.fact_order_fulfillment f
join dw.dim_geography sg on f.seller_geo_key = sg.geo_key
join dw.dim_geography cg on f.customer_geo_key = cg.geo_key
group by 1, 2 order by delivered desc limit 10;

-- Lịch sử tier của 1 seller (SCD2)
select version_no, valid_from, valid_to, seller_tier, is_current
from dw.dim_seller where seller_id = '7e93a43ef30c4f03f38b393420bc753a' order by version_no;

-- Bảng lỗi chất lượng
select * from meta.dq_issue_summary order by issue_pct desc;

-- Kết quả test lần chạy mới nhất
select "Layer", "Status", count(*) from bi.v_dq_latest group by 1, 2;
```

### 17.3 Sự cố đã gặp và cách xử lý

| Triệu chứng | Nguyên nhân | Cách sửa |
| --- | --- | --- |
| `could not resize shared memory segment` | `/dev/shm` của Docker chỉ 64 MB | `shm_size: 512mb` (máy cũ: `docker compose up -d postgres` một lần) |
| `fact_order_fulfillment` treo > 9 phút | Bảng mới chưa có statistics | post-hook `analyze {{ this }}` |
| dbt lỗi đọc file trên Windows (cp1252) | File có tiếng Việt | `PYTHONUTF8=1` trong `.env` |
| `dbt deps` trong Airflow thiếu file | Giải nén lên ổ NTFS mount | `DBT_PACKAGES_INSTALL_PATH=/opt/airflow/dbt_packages` |
| IDE báo đỏ `docs/profiling.sql` | Linter dùng cú pháp SQL Server | Bỏ qua, file là PostgreSQL |

---

## 18. Câu hỏi hay gặp (dùng khi giải thích hoặc vấn đáp)

**H: Tại sao không làm sạch luôn lúc nạp vào raw cho nhanh?**
Đ: Để luôn còn bản gốc. Rule làm sạch sai thì sửa SQL rồi build lại từ `raw`. Nạp thô cũng không bao giờ fail vì dữ liệu bẩn.

**H: Tại sao surrogate key là số băm chứ không phải số tự tăng?**
Đ: Số tự tăng / `row_number` đổi mỗi lần thêm dữ liệu, làm fact cũ trỏ sai dim. Số băm từ natural key thì luôn giống nhau,
an toàn cho incremental load. Xem [7.3](#73-macro-int_sk-surrogate-key-băm).

**H: Tại sao `dim_customer` khoá theo `customer_unique_id`?**
Đ: Olist cấp `customer_id` mới cho **mỗi đơn**. Khoá theo `customer_id` thì mọi khách đều là "khách mới", và tỷ lệ mua lặp
luôn bằng 0.

**H: Tại sao tier tháng M lại có hiệu lực từ tháng M+1?**
Đ: Phải hết tháng M mới biết số đơn, trễ, điểm của tháng M. Gắn tier đó cho đơn **trong** tháng M nghĩa là dùng thông tin
tương lai (look-ahead bias).

**H: Tại sao version đầu tiên bắt đầu từ 1900-01-01?**
Đ: Để mọi sự kiện, kể cả trước lần chấm tier đầu tiên, đều tra được đúng 1 version. Không có thì đơn đầu tiên của seller
rơi vào key -1.

**H: Tại sao fact lưu cờ 0/1 thay vì lưu sẵn late rate?**
Đ: Tỷ lệ không cộng được. Late rate năm ≠ trung bình late rate 12 tháng. Lưu tử số + mẫu số thì cộng ở mọi mức lọc đều đúng.

**H: Tại sao seller late rate (6,69%) khác late rate (6,77%)?**
Đ: Khác cơ sở đếm: cặp đơn × seller so với đơn; chỉ đơn counts_as_sale; cắt ở 2018-08. Cả hai đều đúng theo định nghĩa riêng
của mình, chỉ không được trộn lẫn.

**H: Seller chốt deal nhưng chưa bán thì sao?**
Đ: Vẫn có trong `dim_seller` (`is_from_funnel = true`, `has_sales = false`, tier `Unscored`). Funnel vì vậy luôn có seller_key
cho deal đã chốt (có test kiểm tra).

**H: Tại sao không dùng thuộc tính `dim_lead_profile` để dự đoán lead nào sẽ chốt?**
Đ: Thuộc tính này **chỉ tồn tại cho lead đã chốt**. Dùng nó làm feature là để lộ đáp án (leakage).

**H: Dữ liệu lỗi đi đâu?**
Đ: Không xoá. Dòng lỗi được gắn cờ `_dq_issue`, lag âm được null, và tất cả được đếm ở `meta.dq_issue_summary`, hiển thị trên
trang Data Quality.

**H: Power BI có đọc được bảng `dw` không?**
Đ: Không. User `powerbi_reader` chỉ có quyền trên `bi`.

---

## 19. Việc chưa hoàn thành

Ký hiệu: **MUST** bắt buộc · **SHOULD** nên có · **COULD** có thì tốt. Task ID theo `implementation.md` mục 17.

### 19.1 Việc gấp nhất: commit code

`git status` cho thấy **phần lớn công việc từ S5, S6, F4, F6 đến nay chưa được commit**: các file `dim_lead_*`,
`dim_sales_rep`, `fact_lead_funnel`, `fact_seller_month`, `fact_seller_product_activity`, 3 model `int_seller_*`,
21 view `bi`, `models/quality/`, 4 test mới, 2 macro mới, `docs/bi_layer.md`, `docs/powerbi_guide.md`, cùng các file đã sửa.
Mất máy hoặc lỡ tay `git checkout` là mất toàn bộ. Nên commit theo nhóm task, ví dụ:
`feat(S5-S6): funnel và SCD2 tier seller` · `feat(F4-F5): seller month, factless, reconciliation` · `feat(F6): lớp bi + powerbi_reader`.

### 19.2 Phần data platform / warehouse (trong phạm vi file này)

| ID | Ưu tiên | Việc | Hiện trạng | Cần làm cụ thể |
| --- | --- | --- | --- | --- |
| **P9** | MUST | Lineage + `make all` trên máy sạch | Chưa làm | `make docs-serve` → chụp Lineage graph (đủ nhánh raw → stg → dw → bi) cho báo cáo; clone repo mới, xoá volume, chạy `make all` từ đầu, ghi lại lỗi nếu có |
| **P6** | SHOULD | Chạy lại DAG Airflow | Lần xanh 15/15 (01/11) chạy khi dbt mới có 4 model | Trigger lại với đủ 60 model; thêm `max_active_runs=1` (tránh 2 run chồng nhau như lần lỗi 01/11); cân nhắc `schedule=None` vì dữ liệu tĩnh; chụp Graph/Gantt cho báo cáo |
| **P7 + F8** | SHOULD | Replay 1 tháng + incremental | `scripts/replay_month.py` raise `NotImplementedError`; **chưa có model nào `tag:incremental`** nên `make replay` không build gì | (1) Bản load đầu cắt bớt các tháng cuối (`--cutoff`). (2) `replay_month.py` tách orders/items/payments/reviews/customers của tháng đó vào `extract_date=<hôm nay>-replay-<month>`. (3) Chuyển `stg_orders`, `stg_order_items`, `stg_order_payments`, `stg_order_reviews` và 4 fact chính sang `materialized='incremental'`, `unique_key='order_id'`, `incremental_strategy='delete+insert'`, `tags=['incremental']`. (4) Fulfillment: `_dw_updated_at` chỉ đổi khi dòng thật sự thay đổi |
| P3 | MUST (phần phụ) | Nhánh Kaggle API của `download_kaggle.py` | Đường `data/raw/` chạy tốt; nhánh API chưa test | Test 1 lần trên máy có token (`--mode kaggle`) |
| S6 | COULD | dbt snapshot cho tier khi chạy live | Thư mục `snapshots/` trống | Viết snapshot `check` trên `seller_tier` (chỉ có ý nghĩa nếu demo load live) |
| – | COULD | Dùng `stg_calendar_events` | Đã build nhưng chưa có model nào dùng | Thêm `is_retail_event`, `retail_event_name` vào `dim_date` (Mother's Day, Dia dos Namorados…), hữu ích cho M5 |
| – | COULD | `meta.decision_log` | Bảng có, chưa ai ghi | Script/form nhỏ ghi accept/reject cho `ml.recommendations` (pha Choice) |
| – | Nhỏ | Sửa link tài liệu | `README.md` trỏ `CLAUDE.md` (file thật là `implementation.md`) và `docs/PROJECT_PLAN.md` (file thật ở gốc repo) | Sửa 2 link, hoặc di chuyển file cho khớp |
| – | Nhỏ | `docs/NOTES_progress.md` | Chỉ có trên 1 máy (`.git/info/exclude`) | Nội dung đã có trong file này; có thể bỏ |

### 19.3 Ngoài phạm vi file này (ghi để không quên)

| ID | Ưu tiên | Việc | Ghi chú |
| --- | --- | --- | --- |
| M1 | MUST | Notebook EDA + kết luận khả thi từng bài toán | Số liệu đã có ở `docs/profiling.md` |
| M2 | MUST | `ml/common` | Đã có `db.py`, `registry.py`, `features.py`, cần chạy thử end-to-end |
| M3, M4, M7 | MUST | Late risk + promise what-if; CRM segment + voucher (PuLP); recommendations | Script hiện là stub, chỉ in cảnh báo |
| M5 / M6 | SHOULD / COULD | GMV forecast; seller risk + channel value | |
| F6 (phần ML) | MUST | View ML trong `bi` (`v_order_late_risk`, `v_promise_whatif`, `v_gmv_forecast`, `v_voucher_allocation`, `v_seller_risk`, `v_recommendations`) + nối segment vào `v_dim_customer` | Mỗi view chỉ lấy `model_run_id` mới nhất |
| F7, M8 | MUST | File Power BI `.pbip`, 8 trang | Hướng dẫn đã có: `docs/powerbi_guide.md` |
| R1, R2 | MUST | Báo cáo + demo | `docs/report/`, `docs/figures/` đang trống. Dàn ý ở `PROJECT_PLAN.md` mục 8 |

---

## 20. Hướng phát triển sắp tới

Sắp theo mức "đáng làm trước":

**Ngắn hạn (trong 10 ngày còn lại, phục vụ điểm và demo):**
1. **Incremental + replay (P7/F8)**: minh hoạ được accumulating snapshot cập nhật mốc ngày khi có dữ liệu mới. Đây là điểm
   nhấn lý thuyết DW rất tốt cho buổi demo.
2. **Chạy `dbt source freshness`** trên `raw._loaded_at` để trang Data Quality có thêm chỉ số "dữ liệu cũ bao lâu".
3. **Hình cho báo cáo**: lineage graph, star schema từng fact (vẽ từ bus matrix), sơ đồ SCD2 (dùng ví dụ ở mục 9.6).
4. **CI tối thiểu**: GitHub Actions bật Postgres service, chạy `dbt build` mỗi PR. `implementation.md` đã quy ước
   "CI = dbt build pass", nên đây là bước tự động hoá quy ước đó.

**Trung hạn (nếu dự án tiếp tục sau khi nộp):**
5. **Chuyển sang Azure thật (ADLS Gen2)**: đã sẵn, chỉ cần đổi `AZURE_STORAGE_CONNECTION_STRING` (`docs/AZURE_SETUP.md`).
6. **Lưu landing dạng Parquet** (nén, có kiểu dữ liệu) thay cho CSV, hoặc thêm bước PySpark nếu giảng viên yêu cầu Spark.
7. **dbt snapshot** cho tier seller và các dim Type 1 khi chạy live hằng ngày.
8. **Kiểm thử nâng cao** với `dbt_expectations` (phân phối giá trị, khoảng hợp lệ theo thời gian); **unit test** của dbt 1.8+
   cho logic tier (đưa input giả lập, kiểm tra tier đầu ra).
9. **Semantic layer** (dbt Semantic Layer / MetricFlow): định nghĩa KPI một lần, dùng cho cả Power BI lẫn SQL, đúng tinh thần
   "một định nghĩa KPI".
10. **City-level enrichment**: danh mục municipality (cần nguồn thay thế IBGE API).
11. **Phân quyền theo vai trò** (row-level security trong Power BI: mỗi quản lý chỉ thấy phần của mình).

---

## 21. Bảng thuật ngữ

| Thuật ngữ | Nghĩa |
| --- | --- |
| **Grain** | Ý nghĩa của 1 dòng trong fact. Câu hỏi đầu tiên luôn là "1 dòng là gì?" |
| **Natural key** | Khoá gốc từ nguồn (`seller_id`) |
| **Surrogate key** | Khoá do DW sinh (`seller_key`) |
| **Unknown member (-1)** | Dòng "không xác định" trong dim để fact không mất dòng |
| **SCD** | Slowly Changing Dimension: cách xử lý thuộc tính dim thay đổi theo thời gian (Type 1 ghi đè, Type 2 thêm version) |
| **Point-in-time lookup** | Tra version dim có hiệu lực tại đúng ngày sự kiện |
| **Conformed dimension** | Dim dùng chung giữa nhiều fact |
| **Role-playing** | Một dim dùng cho nhiều vai (ngày mua, ngày giao…) |
| **Junk dimension** | Dim gom các cờ / thuộc tính lặt vặt |
| **Degenerate dimension** | Mã giao dịch nằm trong fact, không có bảng dim |
| **Additive / semi / non-additive** | Cộng được qua mọi dim / một số dim / không cộng được |
| **Accumulating snapshot** | Fact 1 dòng / quy trình, cập nhật khi có mốc mới |
| **Periodic snapshot** | Fact 1 dòng / đối tượng / kỳ |
| **Factless fact** | Fact không có measure, chỉ ghi "có xảy ra" |
| **Medallion** | Kiến trúc nhiều tầng Bronze → Silver → Gold |
| **ELT** | Nạp trước, biến đổi sau, trong DB |
| **Idempotent** | Chạy lại bao nhiêu lần cũng ra cùng kết quả, không sinh trùng |
| **Lineage** | Sơ đồ dữ liệu đi từ đâu tới đâu |
| **DAG** | Đồ thị có hướng không chu trình: thứ tự phụ thuộc của task/model |
| **Materialization** | Model dbt được tạo thành table / view / incremental |
| **Tolerance** | Ngưỡng chênh lệch chấp nhận được khi đối soát (ở đây `max(1 BRL, 1%)`) |
| **Leakage** | Dùng thông tin không có tại thời điểm dự đoán → mô hình "ăn gian" |
| **counts_as_sale** | Cờ "đơn tính là bán" (mọi trạng thái trừ canceled, unavailable) |
| **Primary seller** | Seller đại diện cho đơn nhiều seller (item giá cao nhất) |

---

*Tài liệu liên quan:* `implementation.md` (thiết kế gốc, checklist) · `PROJECT_PLAN.md` (phân công, timeline) ·
`docs/SETUP.md` (cài đặt) · `docs/profiling.md` (số liệu nguồn) · `docs/kpi_dictionary.md` (KPI + DAX) ·
`docs/bi_layer.md` (lớp bi) · `docs/powerbi_guide.md` (dựng Power BI) · `docs/AZURE_SETUP.md` (Azure thật).
