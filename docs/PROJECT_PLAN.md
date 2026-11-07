# Phân công & cách làm việc song song

> Cập nhật 2026-11-07. Hạn nộp **13/11/2026**.
> Đọc kèm: `docs/refactor_plan.md` (làm **cái gì**), `docs/rebuild_guide.md` (làm **thế nào**, câu hỏi nghiệp vụ BR-*),
> `docs/business_rules.md` (nghiệp vụ **đã chốt**), `implementation.md` (quy ước kỹ thuật).

---

## 1. Ai làm bài toán nào

| Thành viên | Bài toán | Người ra quyết định | Sản phẩm cuối của bài toán |
| --- | --- | --- | --- |
| **Ngọc Cẩn** | P1: giao trễ theo khu vực → đặt kho, tăng shipper | Logistics Manager | KPI P1, view `bi` P1, ML-1a/1b/1c, trang Power BI 2–3 |
| **Minh Hiếu** | P2: quy mô thị trường theo zip → nên phát triển khu vực nào | Expansion / Commerce Manager | `fact_geo_month`, KPI P2, view `bi` P2, ML-2a/2b/2c, trang 4–5 |
| **Xuân Vinh** | P3: hạng mục bán chạy → nên phát triển hạng mục nào | Category Manager | `fact_category_month`, KPI P3, view `bi` P3, ML-3a/3b, trang 6–7 |

Phần hạ tầng (Docker, ingest, `raw`, `meta`, Airflow, khung dbt) **đã có sẵn**, không ai phải làm lại.

Ba bài toán dùng chung rất nhiều dữ liệu (đơn hàng, item, seller, khách, geography…). Mỗi phần dữ liệu dùng chung
chỉ được **làm một lần, bởi một người**. Mục 2 là quy tắc, mục 3 là danh sách phần dùng chung, mục 4 là lịch.

---

## 2. Quy tắc làm việc song song

### 2.1 Ai đến trước thì làm, người đến sau dùng lại

1. Mỗi phần dùng chung có một mã (`C-S*`, `C-W*`, `C-M*`, `C-B*` ở mục 3). Người đầu tiên **cần** phần đó thì **nhận** nó
   (claim) và trở thành **owner**.
2. Người đến sau **không làm lại**: dùng model của owner. Nếu owner chưa xong thì code theo **contract** (2.2) và chờ merge.
3. Một phần chỉ có **một owner**. Owner chịu trách nhiệm chốt nghiệp vụ, code, test, view `bi`, mô tả YAML của phần đó.

### 2.2 Nhận việc (claim) và contract

- **Claim bằng GitHub Issue**: mỗi phần dùng chung là 1 issue, tiêu đề `[C-S1] stg_orders`, label `shared`.
  Ai **assign mình vào issue trước** thì là owner. Trước khi bắt đầu một phần, mở issue ra kiểm tra; chưa có issue thì tạo
  rồi assign mình. Hai người cùng claim thì ai assign trước (theo timeline của issue) được nhận.
- **Contract trước, code sau**: trong vòng **vài giờ** sau khi claim, owner comment vào issue:
  - grain (1 dòng là gì) và natural key;
  - danh sách cột: tên, kiểu, ý nghĩa;
  - các rule BR-* sẽ áp dụng (đề xuất).
  Người dùng phần đó (consumer) đọc contract và góp ý trong issue. Sau khi chốt contract, consumer có thể viết SQL / notebook
  dựa vào tên cột ngay, không phải chờ owner merge.
- **Draft PR sớm**: owner mở draft PR `feat/<mã>-<mô-tả>` ngay khi bắt đầu, để mọi người thấy tiến độ.

### 2.3 Nghiệp vụ dùng chung phải được consumer đồng ý

- Rule BR-* của phần dùng chung ảnh hưởng tới mọi consumer (ví dụ định nghĩa "đơn trễ" dùng cho cả P1 và P2). Owner
  **đề xuất**, consumer **review** trong issue / PR. Owner ghi rule đã chốt vào `docs/business_rules.md` trong cùng PR.
- Một số rule chung cho **mọi** model (mục 3.1) chốt **cùng nhau trong buổi kickoff**, không ai tự quyết riêng.

### 2.4 Cần thay đổi model của người khác

| Loại thay đổi | Ví dụ | Cách làm |
| --- | --- | --- |
| Thêm cột, không đổi grain và định nghĩa cũ | P1 cần thêm `geo_cell_id` vào `dim_geography` của owner P2 | Comment vào issue của owner; owner thêm, **hoặc** consumer tự mở PR nhỏ và owner review |
| Đổi grain / định nghĩa / tên cột đang dùng | Đổi cách tính `is_late` | Đề xuất trong issue, **mọi consumer đồng ý**, cập nhật `business_rules.md`, owner sửa |
| Rule riêng của một bài toán | P1 muốn late rate chỉ trên đơn có toạ độ | **Không** sửa model chung; lọc / tính trong model hoặc view của bài toán mình |

**Không** copy model của người khác ra một model mới chỉ để sửa nhẹ (sinh ra hai định nghĩa cho cùng một dữ liệu, đúng
vấn đề "hai quản lý hai con số" mà DW phải giải quyết).

### 2.5 File dễ đụng nhau và cách tránh

| File | Nguy cơ | Quy ước |
| --- | --- | --- |
| YAML của model | Nhiều người sửa chung 1 file `_models.yml` | **1 file YAML / model**, đặt cạnh file SQL: `stg_orders.sql` + `stg_orders.yml` |
| `docs/business_rules.md` | Ba người cùng thêm dòng | Đã chia sẵn **mục theo phần** (orders, items, …). Chỉ owner của phần đó sửa mục đó |
| `docs/kpi_dictionary.md` | Ba người cùng thêm KPI | Đã chia sẵn mục **Chung / P1 / P2 / P3**. Mỗi người sửa mục của mình; KPI chung do owner fact tương ứng viết |
| `models/staging/_sources.yml` | — | Đã khai báo đủ 9 bảng raw, không cần sửa |
| Source `ml` trong dbt | Ba người cùng khai báo source `ml` | Mỗi bài toán khai báo **source riêng** cùng schema `ml`: `ml_p1`, `ml_p2`, `ml_p3` (file `models/bi/_sources_ml_p1.yml`…) |
| DDL bảng `ml.*` | Ba người cùng sửa `03_ml.sql` | Mỗi bài toán **1 file**: `docker/postgres/init/03_ml_p1.sql`, `03_ml_p2.sql`, `03_ml_p3.sql`; bảng dùng chung (`recommendations`) ở `03_ml_shared.sql`. Nhớ thêm file vào vòng lặp `reset-db` trong Makefile |
| Code ML | — | Mỗi bài toán 1 thư mục: `ml/p1_logistics/`, `ml/p2_regional/`, `ml/p3_category/` (refactor plan 6.6); phần dùng chung ở `ml/common/` |
| `Makefile`, DAG Airflow | Ba người cùng thêm lệnh ML | Mỗi bài toán 1 target `ml-p1`, `ml-p2`, `ml-p3`; `ml` gọi cả ba. Trong DAG mỗi người thêm đúng 1 task `ml_p1` / `ml_p2` / `ml_p3` |
| `dbt_project.yml` | Thêm var | Hiếm; báo trong nhóm trước khi sửa |
| Power BI `.pbip` | File nhị phân / text lớn, merge khó | Xem mục 2.6 |

### 2.6 Power BI

- Model chung (bảng Date, dim chung, relationship) làm **một lần** (C-B2), lưu `powerbi/olist_dw.pbip`.
- Mỗi người làm trang của mình trên **bản copy** (`powerbi/work/p1.pbip`, `p2.pbip`, `p3.pbip`, không merge), xong thì
  người giữ file chính (owner C-B2) ghép trang vào file chính. Measure đặt tên có tiền tố bài toán khi chỉ dùng riêng
  (`P1 Late Density`), measure chung không tiền tố.

### 2.7 Nhịp làm việc

- **Kickoff (30–45 phút, ngày 07/11)**: chốt rule chung (mục 3.1), tạo issue cho mục 3.2–3.5, nhận việc theo gợi ý ở mục 3.
- **Sync 15 phút mỗi ngày**: mỗi người nói đang làm gì, contract nào cần review, đang chờ ai.
- PR vào `main` cần **1 review**; với phần dùng chung, reviewer là một consumer của phần đó.
- `dbt build` phải xanh trên máy reviewer trước khi merge.

---

## 3. Danh sách phần dùng chung

Cột **Gợi ý owner** chia đều tải và đi theo đường găng của từng bài toán, để ngày đầu không phải giành nhau. Quy tắc
"ai đến trước làm trước" vẫn áp dụng: owner gợi ý chưa bắt đầu thì người khác có thể nhận (báo trong sync).

Cột **Dùng bởi**: P1 = Cẩn, P2 = Hiếu, P3 = Vinh.

### 3.1 Rule chung — chốt cùng nhau ở kickoff

| Mã | Nội dung (câu hỏi trong `rebuild_guide.md`) | Kết quả |
| --- | --- | --- |
| C-R1 | Rule staging chung: dedup theo batch, chuỗi rỗng, zip 5 số, chuẩn hoá city, mã bang, xử lý dữ liệu lỗi (BR-S1…BR-S6) | Mục *Chung* trong `business_rules.md` + macro `clean_*` (owner: người làm C-S1) |
| C-R2 | Cờ dẫn xuất tính ở staging hay fact (BR-S7) | Mục *Chung* |
| C-R3 | Quy ước warehouse: surrogate key, unknown member -1, date key, cờ 0/1 (BR-W1, BR-W2, BR-W11) | Mục *Chung* + macro `unknown_key` / `date_key` (owner: người làm C-W1) |
| C-R4 | Đơn nào được tính là bán, cửa sổ phân tích (BR-K1, BR-W4) | Mục *Chung* + seed `order_status_map` (C-W6) |
| C-R5 | Dữ liệu tham chiếu ngoài dataset: vùng, ngày lễ, dân số — có dùng không (BR-W12) | Mục *Chung*; nếu dùng thì tạo seed (owner: người làm C-W2) |

### 3.2 Staging (`stg`) — mỗi mã gồm model, YAML, test, rule BR-S* của nguồn đó

| Mã | Model | Dùng bởi | Gợi ý owner | Ghi chú |
| --- | --- | --- | --- | --- |
| C-S1 | `stg_orders` | P1, P2, P3 | Cẩn | Rule "delivered", "late", mốc thời gian lỗi: quan trọng nhất cho P1 |
| C-S2 | `stg_order_items` | P1, P2, P3 | Vinh | |
| C-S3 | `stg_customers` + `int_customer_map` | P1, P2, P3 | Hiếu | Định nghĩa "một khách" (`customer_unique_id`) |
| C-S4 | `stg_sellers` | P1, P2, P3 | Hiếu | |
| C-S5 | `stg_geolocation` | P1, P2 | Cẩn | Gộp điểm / zip, bbox Brazil |
| C-S6 | `stg_products` + `stg_product_category_name_translation` (+ seed `category_group` nếu chốt) | P1, P3 | Vinh | |
| C-S7 | `stg_order_reviews` | P1, P3 | Vinh | Review nào được tính cho một đơn |
| C-S8 | `stg_order_payments` | P2 (tuỳ chọn) | Hiếu | Chỉ làm nếu P2 dùng (refactor plan Q1) |

### 3.3 Warehouse (`dw`) dùng chung

| Mã | Model | Cần trước | Dùng bởi | Gợi ý owner |
| --- | --- | --- | --- | --- |
| C-W1 | `dim_date` | C-R3, C-R5 | P1, P2, P3 | Cẩn |
| C-W2 | `dim_geography` (zip → zip_prefix_3 → zip_prefix_2 → state (→ region); lat/lng; `geo_cell_id`) | C-S3, C-S4, C-S5 | P1, P2, P3 | Hiếu |
| C-W3 | `dim_customer` | C-S3, C-W2 | P2 (P1, P3 qua fact) | Hiếu |
| C-W4 | `dim_seller` (+ quyết định SCD2 tier, BR-W10) | C-S4, C-W2 | P1, P2, P3 | Hiếu |
| C-W5 | `dim_product` + `dim_category` | C-S6 | P1, P3 | Vinh |
| C-W6 | `dim_order_status` + seed `order_status_map` | C-R4 | P1, P2, P3 | Cẩn |
| C-W7 | `int_order_primary_seller`, `int_order_agg` (BR-W5, BR-W6) | C-S1, C-S2 | P1, P2 | Cẩn |
| C-W8 | `fact_order_item` | C-S2, C-W1…C-W6 | P2, P3 | Vinh |
| C-W9 | `fact_order_fulfillment` (lag, khoảng cách, cờ trễ) | C-S1, C-W7, C-W1…C-W4, C-W6 | P1, P2 | Cẩn |
| C-W10 | `fact_review` | C-S7, C-W7 | P1, P3 | Vinh |

Chia theo gợi ý: Cẩn 6 phần (C-S1, C-S5, C-W1, C-W6, C-W7, C-W9), Hiếu 6 phần (C-S3, C-S4, C-S8, C-W2, C-W3, C-W4),
Vinh 6 phần (C-S2, C-S6, C-S7, C-W5, C-W8, C-W10). Mỗi người làm phần chung gần với bài toán của mình nhất.

### 3.4 Serving và ML dùng chung

| Mã | Phần | Dùng bởi | Gợi ý owner |
| --- | --- | --- | --- |
| C-B1 | View `bi` của model dùng chung (`v_dim_*`, `v_fact_sales`, `v_fact_fulfillment`, `v_fact_review`) | P1, P2, P3 | **Owner của model dw tương ứng** viết luôn view của nó |
| C-B2 | Power BI model chung: bảng Date, dim chung, relationship, measure chung; giữ file `olist_dw.pbip` và ghép trang | P1, P2, P3 | Người đầu tiên mở Power BI (máy Windows) |
| C-B3 | Trang 1 Executive Overview, trang 8 Data Quality | P1, P2, P3 | Owner C-B2 |
| C-M1 | `ml/common/forecasting.py` (baseline seasonal-naive, moving average, ETS; MAPE) | P1 (ML-1c), P2 (ML-2a), P3 (ML-3a) | Người làm forecast đầu tiên (thường P2) |
| C-M2 | `03_ml_shared.sql` (`ml.recommendations`) + `ml/recommendations.py` + view `v_recommendations` | P1, P2, P3 | Người xong ML trước; mỗi bài toán tự thêm rule đề xuất của mình |
| C-K1 | KPI chung trong `kpi_dictionary.md` (GMV, Orders, AOV, Late rate, Avg review score, Cancel rate) | P1, P2, P3 | Owner của fact chứa KPI đó (C-W8, C-W9, C-W10) |

### 3.5 Phần riêng của từng bài toán (không cần claim)

| Bài toán | Phần riêng | Dựa trên |
| --- | --- | --- |
| P1 (Cẩn) | KPI P1 (late rate theo khu vực, late density, lag, distance); view `bi` P1; ML-1a late risk, ML-1b hub placement, ML-1c courier plan; `03_ml_p1.sql`; trang 2–3 | C-W2 (`geo_cell_id`), C-W9, C-W10, C-W4, C-M1 |
| P2 (Hiếu) | `fact_geo_month`; KPI P2 (market size, customers / sellers, local fulfilment, supply gap, growth); view `bi` P2; ML-2a forecast, ML-2b segment, ML-2c opportunity; `03_ml_p2.sql`; trang 4–5 | C-W2, C-W3, C-W4, C-W8, C-W9, C-M1 |
| P3 (Vinh) | `fact_category_month`; KPI P3 (category share, growth, satisfaction, HHI); view `bi` P3; ML-3a category forecast, ML-3b portfolio; `03_ml_p3.sql`; trang 6–7 | C-W5, C-W8, C-W10, C-M1 |

`fact_geo_month` cần `late_orders` từ C-W9 (Cẩn) và GMV từ C-W8 (Vinh): Hiếu dùng hai fact đó (hoặc cùng nguồn `stg`
và cùng rule), **không** tự định nghĩa lại "đơn trễ" hay "GMV".

---

## 4. Lịch (07/11 → 13/11)

| Ngày | Mốc chung | Cẩn (P1) | Hiếu (P2) | Vinh (P3) |
| --- | --- | --- | --- | --- |
| 07/11 | Kickoff: chốt C-R1…C-R5, tạo issue, claim | C-S1, C-S5 (contract trong ngày) | C-S3, C-S4 (contract trong ngày) | C-S2, C-S6, C-S7 (contract trong ngày) |
| 08/11 | Staging merge; contract warehouse | C-W1, C-W6, C-W7 | C-S8 (nếu dùng), C-W2, C-W3 | C-W5; bắt đầu C-W8 theo contract |
| 09/11 | Dims merge; fact chung | C-W9 + view C-B1; KPI P1 | C-W4 + view C-B1; bắt đầu `fact_geo_month` | C-W8, C-W10 + view C-B1; bắt đầu `fact_category_month` |
| 10/11 | Fact chung merge; KPI dictionary đủ | View `bi` P1; EDA + ML-1a | `fact_geo_month`, view `bi` P2; C-M1 | `fact_category_month`, view `bi` P3 |
| 11/11 | ML | ML-1b, ML-1c | ML-2a, ML-2b, ML-2c | ML-3a, ML-3b |
| 12/11 | Power BI + C-M2 recommendations | Trang 2–3 | Trang 4–5 | Trang 6–7; C-B2 ghép (nếu Vinh giữ file) |
| 13/11 | `make all` trên máy sạch, báo cáo, demo | Phần P1 báo cáo | Phần P2 báo cáo | Phần P3 báo cáo |

Thứ tự phụ thuộc: rule chung → staging → dims → fact chung → fact / KPI riêng → ML → Power BI. Nhờ contract (2.2), mỗi
người có thể viết bước sau trước khi bước trước của người khác được merge.

---

## 5. Checklist cho mỗi phần (Definition of Done)

- [ ] Issue có owner và contract đã được consumer đồng ý
- [ ] Rule BR-* ghi trong mục tương ứng của `docs/business_rules.md`
- [ ] SQL + YAML riêng của model (mô tả model, từng cột, mã rule `BR-*`)
- [ ] Test: unique / not_null key, relationships cho FK, test rule nghiệp vụ hoặc đối soát
- [ ] View `bi` (nếu là model dw dùng chung) và KPI trong `kpi_dictionary.md` (nếu có)
- [ ] `dbt build` xanh, PR được 1 consumer review rồi merge vào `main`
