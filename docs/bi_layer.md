# Lớp BI (schema `bi`) và kết nối Power BI — task F6

> Cập nhật: 02/11/2026. Người làm F6: TV3 (Xuân Vinh); phần này dựng sẵn để nhóm dùng ngay.
> Liên quan: `docs/kpi_dictionary.md` (định nghĩa KPI + DAX), `powerbi/README.md` (cài đặt Power BI),
> `implementation.md` mục 8 (business rules) và 14 (serving).

---

## 1. Lớp `bi` để làm gì

```
raw  →  stg (Silver)  →  dw (Gold: dim_* / fact_*)  →  bi (view v_*)  →  Power BI
                                         meta.* ──────┘
```

`dw` là kho dữ liệu chuẩn Kimball dành cho người làm dữ liệu. Tên cột kỹ thuật, có dòng `-1`, có nhiều vai trò ngày /
địa lý dùng chung một bảng. `bi` là **lớp hợp đồng (contract) với Power BI**:

| Vấn đề nếu Power BI đọc thẳng `dw` | `bi` giải quyết thế nào |
| --- | --- |
| Tên cột `seller_customer_distance_km`, `is_latest_for_order` khó đọc với người dùng nghiệp vụ | Đổi thành `Distance (km)`, `Is Latest For Order` |
| `dim_geography` dùng cho cả khách và seller → một bảng, hai relationship, phải dùng `USERELATIONSHIP` ở mọi measure địa lý | Hai view `v_dim_customer_geo`, `v_dim_seller_geo`, cột có tiền tố `Customer …` / `Seller …` |
| Đổi tên / thêm cột ở `dw` làm hỏng báo cáo | Báo cáo chỉ phụ thuộc tên cột trong `bi`; `dw` đổi thì sửa view, báo cáo giữ nguyên |
| Power BI thấy cả `raw`, `stg`, `ml` → dễ kéo nhầm bảng | User `powerbi_reader` **chỉ có quyền đọc schema `bi`** |
| `dim_date` có dòng `-1` (ngày rỗng) → không "Mark as date table" được | `v_dim_date` bỏ dòng `-1` |

Nguyên tắc (giữ khi thêm view mới):

1. **View mỏng**: chỉ `select … from {{ ref(...) }}`, đổi tên cột, thêm vài cột hiển thị (sort, nhãn). Không `group by`,
   **không đổi grain** → số dòng view = số dòng bảng nguồn (có test `equal_rowcount`).
2. **Không tính KPI trong SQL.** Tỷ lệ, trung bình, GMV có điều kiện đều là DAX measure theo `docs/kpi_dictionary.md`.
   View chỉ cung cấp tử số / mẫu số cộng được.
3. **Cột khoá giữ `snake_case`** (`customer_key`, `purchase_date_key`) để nhận ra ngay và ẩn đi trong Power BI.
   **Cột hiển thị dùng Title Case có dấu cách** (`"Item Price"`), nên trong SQL phải đặt trong ngoặc kép và trong YAML có `quote: true`.
4. Materialization = **view** (cấu hình ở `dbt_project.yml`, `models: bi: +materialized: view`). Power BI chạy ở chế độ
   Import nên view chỉ được đọc khi Refresh; không cần bảng vật lý.

---

## 2. Những gì đã làm

### 2.1 File thêm / sửa

| File | Thay đổi |
| --- | --- |
| `dbt/olist_dw/models/bi/v_dim_*.sql` (11 file) | View dimension (1 file `v_dim_order_status` đã có sẵn làm mẫu) |
| `dbt/olist_dw/models/bi/v_fact_*.sql` (7 file) | View fact, 1 view / fact của `dw` |
| `dbt/olist_dw/models/bi/v_dq_latest.sql`, `v_etl_runs.sql`, `v_dq_issue_summary.sql` | View cho trang 8 Data Quality & Pipeline Health |
| `dbt/olist_dw/models/bi/_bi.yml` | Mô tả mọi view + mọi cột (được `persist_docs` ghi thành comment trong Postgres, `meta_publish` ghi vào `meta.data_dictionary`) và 37 test |
| `dbt/olist_dw/macros/tier_sort.sql` | Thứ tự hiển thị tier (Gold → Unscored) cho 3 cột sort của `v_dim_seller` |
| `dbt/olist_dw/macros/grant_bi_reader.sql` | Macro tạo / cập nhật user `powerbi_reader` và cấp quyền đọc `bi` |
| `dbt/olist_dw/dbt_project.yml` | Thêm `on-run-end: "{{ grant_bi_reader() }}"` |
| `.env.example` | Thêm `BI_READER_USER`, `BI_READER_PASSWORD` |
| `docs/kpi_dictionary.md` | Viết đầy đủ: KPI, công thức, cột nguồn, giá trị tham chiếu, toàn bộ DAX measure |
| `powerbi/README.md` | Đăng nhập bằng `powerbi_reader`, các bước dựng model |
| `implementation.md`, `dbt/olist_dw/models/README.md` | Đánh dấu F6 xong, ghi changelog |

### 2.2 Danh mục view (số dòng ngày 02/11/2026)

**Dimensions**

| View | Nguồn | Grain | Số dòng | Ghi chú |
| --- | --- | --- | --- | --- |
| `v_dim_date` | `dw.dim_date` | 1 ngày 2016–2019 | 1 461 | Bỏ dòng `-1`; thêm `Quarter`, `Month Short`, `Year Month Sort`, `Month Start`, `In Analysis Window` |
| `v_dim_customer` | `dw.dim_customer` | 1 người mua thật | 96 097 | Thêm `Customer Type` (One-time / Repeat). Segment ML thêm ở M4 |
| `v_dim_product` | `dw.dim_product` | 1 sản phẩm | 32 952 | Thêm `Weight Band Sort`, `Size Band Sort` |
| `v_dim_seller` | `dw.dim_seller` | 1 **version** seller (SCD2) | 8 190 | Thêm `Previous Tier`, `Current Tier` và cột sort cho cả 3 cột tier |
| `v_dim_customer_geo` | `dw.dim_geography` | 1 zip prefix | 19 178 | Role: địa chỉ khách, khoá `customer_geo_key` |
| `v_dim_seller_geo` | `dw.dim_geography` | 1 zip prefix | 19 178 | Role: địa chỉ seller, khoá `seller_geo_key` |
| `v_dim_payment_type` | `dw.dim_payment_type` | payment_type × instalment_band | 26 | |
| `v_dim_order_status` | `dw.dim_order_status` | 1 trạng thái | 9 | `Counts As Sale` là điều kiện của GMV / Orders |
| `v_dim_lead_origin` | `dw.dim_lead_origin` | origin × landing page | 1 183 | |
| `v_dim_lead_profile` | `dw.dim_lead_profile` | tổ hợp thuộc tính lead đã chốt | 503 | `-1` = lead chưa chốt |
| `v_dim_sales_rep` | `dw.dim_sales_rep` | SDR × SR | 225 | |

**Facts**

| View | Nguồn | Grain | Số dòng | Dùng cho trang |
| --- | --- | --- | --- | --- |
| `v_fact_sales` | `dw.fact_order_item` | 1 item | 112 650 | 1, 2 (GMV, item) |
| `v_fact_fulfillment` | `dw.fact_order_fulfillment` | 1 đơn | 99 441 | 1, 3, 4 (Orders, AOV, late, lag) |
| `v_fact_review` | `dw.fact_review` | 1 review × đơn | 99 224 | 1, 3, 5 |
| `v_fact_payment` | `dw.fact_payment` | 1 lần thanh toán | 103 886 | 1 |
| `v_fact_seller_month` | `dw.fact_seller_month` | seller × tháng | 33 488 | 5 |
| `v_fact_lead_funnel` | `dw.fact_lead_funnel` | 1 MQL | 8 000 | 6 |
| `v_fact_seller_product_activity` | `dw.fact_seller_product_activity` | seller × product × tháng | 62 067 | 5 (độ rộng danh mục) |

**Data quality (trang 8)**

| View | Nguồn | Nội dung |
| --- | --- | --- |
| `v_dq_latest` | `meta.dq_results` | Kết quả mọi test dbt của **lần chạy gần nhất** (lọc theo `run_id` có `executed_at` mới nhất); thêm `Layer` (suy từ tên model) và `Is Pass` 0/1 |
| `v_etl_runs` | `meta.etl_run_log` | Lịch sử chạy (load_raw từng file, dbt từng lệnh, Airflow); thêm `Step Group`, `Run Date`, `Duration (s)` |
| `v_dq_issue_summary` | `meta.dq_issue_summary` | Lỗi dữ liệu được giữ lại và gắn cờ, theo model: số dòng lỗi, tổng dòng, % |

### 2.3 Quyết định thiết kế chi tiết

**a. Đổi tên `primary_seller_key` → `seller_key` trong `v_fact_fulfillment` và `v_fact_review`.**
Hai fact cấp đơn dùng *primary seller* (seller của item giá cao nhất). Đặt cùng tên `seller_key` với các fact khác để
trong Power BI chỉ cần một relationship `Seller[seller_key]` → fact, không phân biệt. Ý nghĩa "primary seller" ghi trong
mô tả cột. Lưu ý: trên trang seller, số đơn của `Fulfillment` theo seller **chỉ tính cho primary seller**, còn
`Seller Month[Orders]` tính cho mọi seller trong đơn. Hai số không cộng lẫn.

**b. Role-playing date: một bảng `Date` + relationship inactive, không tách view ngày.**
`v_fact_fulfillment` có 5 vai trò ngày. Tách 5 view ngày sẽ làm model có 5 bảng ngày, slicer ngày không dùng chung được
giữa các trang. Chọn: 1 bảng `Date`, relationship **active** theo ngày mua (hoặc ngày chính của fact), các ngày khác
**inactive** và bật bằng `USERELATIONSHIP` trong measure cần (ví dụ trong `docs/kpi_dictionary.md` mục 4).
Ngược lại, geography được tách thành 2 view, vì người dùng hay đặt *cả hai* cạnh nhau (ví dụ ma trận tuyến seller state × customer state ở trang 3, 4)
và điều này không làm được với một bảng.

**c. Bỏ dòng `-1` khỏi `v_dim_date`.**
Power BI yêu cầu cột ngày của date table không trống và không trùng. Fact có `delivered_date_key = -1` (đơn chưa giao,
2 965 đơn) sẽ không khớp dòng nào trong `Date` → Power BI xếp vào nhóm *(Blank)*. Điều này đúng nghĩa: "chưa giao" không có ngày giao.
`purchase_date_key` không bao giờ là `-1` (đã kiểm tra: 0 đơn lệch). Các dim khác **giữ** dòng `-1` (Unknown) vì nó là một thành viên có nghĩa.

**d. `v_dim_seller` thêm `Current Tier` và `Previous Tier`.**
- `Seller Tier` = tier của version mà fact trỏ tới = tier **tại thời điểm** sự kiện (point-in-time). Ví dụ GMV tháng 03/2018 theo tier
  trả lời câu "seller đang Gold *lúc đó* bán bao nhiêu".
- `Current Tier` (`max(...) over (partition by seller_id)` lấy tier của version `is_current`) trả lời câu "các seller *đang là* Gold
  hôm nay đã bán bao nhiêu trong quá khứ" (kiểu SCD Type 6 / hybrid).
- `Previous Tier` (`lag(seller_tier)` theo `valid_from`) để vẽ ma trận chuyển tier Previous → Seller Tier trên trang 5.
- Đếm seller dùng `DISTINCTCOUNT(Seller[Seller ID])`, **không** `COUNTROWS(Seller)` (8 190 dòng là số version, không phải số seller).

**e. Cờ 0/1 giữ dạng số nguyên, cột boolean giữ boolean.**
Cờ trong fact (`Is Late`, `Is Delivered`, …) là 0/1 để `SUM` trực tiếp (quyết định 01/11). Thuộc tính dim (`Is Current`,
`Counts As Sale`) là boolean → dùng làm slicer True/False.

**f. `Customer Type` dựa trên `Lifetime Orders` (mọi trạng thái).**
Chỉ để phân nhóm nhanh trong slicer. KPI *Repeat customer rate* chính thức tính bằng DAX trên đơn counts_as_sale và phụ thuộc
khoảng thời gian đang lọc (3,04 % trên toàn bộ dữ liệu).

**g. Không có view ML.**
Theo quyết định 02/11 (làm nhóm M sau), chưa tạo `v_order_late_risk`, `v_promise_whatif`, `v_gmv_forecast`,
`v_voucher_allocation`, `v_seller_risk`, `v_recommendations`, và `v_dim_customer` chưa nối segment. Bảng `ml.*` hiện rỗng.
Khi làm M3–M7: thêm view vào `models/bi/`, mỗi view chỉ lấy `model_run_id` mới nhất (implementation.md mục 14.1).

### 2.4 User chỉ đọc `powerbi_reader`

- Macro `grant_bi_reader()` chạy ở `on-run-end` của **mọi** lệnh dbt (`build`, `run`, `seed`, `test`). Nó idempotent:
  tạo role nếu chưa có, ngược lại cập nhật mật khẩu; cấp `connect` database, `usage` schema `bi`, `select` mọi view hiện có và
  `alter default privileges` để view tạo lại sau này tự có quyền.
- User / mật khẩu lấy từ biến môi trường `BI_READER_USER`, `BI_READER_PASSWORD` (mặc định `powerbi_reader` / `powerbi_reader`).
- Vì sao chỉ cần quyền trên `bi`: view Postgres mặc định chạy với quyền của **owner** (user dbt `olist`), nên `powerbi_reader`
  đọc được `bi.v_fact_sales` mà không có quyền trên `dw.fact_order_item`. Đã kiểm tra:

```
powerbi_reader> select count(*) from bi.v_fact_sales;      → 112650
powerbi_reader> select count(*) from dw.fact_order_item;   → ERROR: permission denied for schema dw
```

---

## 3. Kiểm thử

| Kiểm tra | Kết quả 02/11/2026 |
| --- | --- |
| `dbt build --select path:models/bi` | 21 view, 37 test, **58/58 PASS** |
| `dbt build` toàn project | **334/334 PASS** (5 seed, 60 model, 269 test), hook `on-run-end` OK |
| Khoá dim duy nhất, không null (Power BI cần cho relationship 1–nhiều) | `unique` + `not_null` trên khoá của 11 view dim, trên `Date`, `Order ID` (fulfillment), `MQL ID` |
| View fact không đổi grain | `dbt_utils.equal_rowcount` view ↔ fact nguồn, 7/7 |
| Fact khớp được bảng Date | 0 đơn có `purchase_date_key` không có trong `v_dim_date` |
| KPI đối chiếu với profiling | Late rate 6,77 % (= profiling S1), conversion 10,53 % (= S5); toàn bộ số ở `docs/kpi_dictionary.md` mục 2 |
| `meta_publish` sau build | `meta.dq_results` 269 test; `meta.data_dictionary` 603 cột; `meta.source_to_target` 59 model |
| Quyền `powerbi_reader` | Đọc được `bi`, bị từ chối ở `dw` |

Các test kiểu `relationships` giữa view fact và view dim **không** viết lại: chúng đã có ở tầng `dw` (fact → dim), và view là
`select` 1–1 từ đó. Riêng `Date`, test bên trên đã kiểm tra.

---

## 4. Chạy lại

```bash
make up          # postgres + azurite
make build       # dbt build: tạo stg, dw, bi, meta.dq_issue_summary; hook cấp quyền powerbi_reader
make meta        # meta_publish: ghi kết quả test vào meta.dq_results → v_dq_latest có dữ liệu
```

Chỉ build lại lớp `bi`: `dbt build --select path:models/bi` (trong `dbt/olist_dw`, cần biến môi trường từ `.env`).
Đổi mật khẩu Power BI: sửa `BI_READER_PASSWORD` trong `.env` rồi chạy lại bất kỳ lệnh dbt nào.

---

## 5. Dựng semantic model trong Power BI

Cài đặt, bật `.pbip`, SSL: xem `powerbi/README.md`. Phần dưới là cấu trúc model.

### 5.1 Lấy dữ liệu và đổi tên bảng

*Get data → PostgreSQL database* → Server `localhost:5432`, Database `olist_dw`, **Import** → đăng nhập kiểu **Database**
bằng `powerbi_reader` / `powerbi_reader`. Navigator chỉ hiện schema `bi`. Tick cả 21 view, chọn **Transform Data**, đổi tên
query (tên bảng dùng trong DAX):

| View | Tên bảng trong Power BI |
| --- | --- |
| `bi.v_dim_date` | `Date` |
| `bi.v_dim_customer` | `Customer` |
| `bi.v_dim_product` | `Product` |
| `bi.v_dim_seller` | `Seller` |
| `bi.v_dim_customer_geo` | `Customer Geo` |
| `bi.v_dim_seller_geo` | `Seller Geo` |
| `bi.v_dim_payment_type` | `Payment Type` |
| `bi.v_dim_order_status` | `Order Status` |
| `bi.v_dim_lead_origin` | `Lead Origin` |
| `bi.v_dim_lead_profile` | `Lead Profile` |
| `bi.v_dim_sales_rep` | `Sales Rep` |
| `bi.v_fact_sales` | `Sales` |
| `bi.v_fact_fulfillment` | `Fulfillment` |
| `bi.v_fact_review` | `Review` |
| `bi.v_fact_payment` | `Payment` |
| `bi.v_fact_seller_month` | `Seller Month` |
| `bi.v_fact_lead_funnel` | `Lead Funnel` |
| `bi.v_fact_seller_product_activity` | `Seller Product Activity` |
| `bi.v_dq_latest` | `DQ Latest` |
| `bi.v_etl_runs` | `ETL Runs` |
| `bi.v_dq_issue_summary` | `DQ Issues` |

Thêm bảng rỗng `_Measures` (*Enter data*) để chứa measure.

### 5.2 Relationships

Tất cả là **1 (dim) → * (fact), lọc một chiều (Single)**. Power BI có thể tự đoán sai hoặc bỏ sót relationship vì tên cột khoá
khác nhau giữa các bảng. Nên tắt *autodetect* (*Options → Data Load → Relationships*), rồi tạo tay theo bảng sau.

| Fact | Cột fact | → Dim[cột] | Active |
| --- | --- | --- | --- |
| Sales | purchase_date_key | Date[date_key] | ✔ |
| Sales | shipping_limit_date_key | Date[date_key] | inactive |
| Sales | customer_key | Customer[customer_key] | ✔ |
| Sales | product_key | Product[product_key] | ✔ |
| Sales | seller_key | Seller[seller_key] | ✔ |
| Sales | customer_geo_key | Customer Geo[customer_geo_key] | ✔ |
| Sales | seller_geo_key | Seller Geo[seller_geo_key] | ✔ |
| Sales | order_status_key | Order Status[order_status_key] | ✔ |
| Fulfillment | purchase_date_key | Date[date_key] | ✔ |
| Fulfillment | approved_date_key, carrier_date_key, delivered_date_key, estimated_date_key | Date[date_key] | inactive (4 dòng) |
| Fulfillment | customer_key | Customer[customer_key] | ✔ |
| Fulfillment | seller_key | Seller[seller_key] | ✔ |
| Fulfillment | customer_geo_key | Customer Geo[customer_geo_key] | ✔ |
| Fulfillment | seller_geo_key | Seller Geo[seller_geo_key] | ✔ |
| Fulfillment | order_status_key | Order Status[order_status_key] | ✔ |
| Review | review_creation_date_key | Date[date_key] | ✔ |
| Review | review_answer_date_key | Date[date_key] | inactive |
| Review | customer_key | Customer[customer_key] | ✔ |
| Review | seller_key | Seller[seller_key] | ✔ |
| Review | customer_geo_key | Customer Geo[customer_geo_key] | ✔ |
| Review | order_status_key | Order Status[order_status_key] | ✔ |
| Payment | purchase_date_key | Date[date_key] | ✔ |
| Payment | customer_key | Customer[customer_key] | ✔ |
| Payment | payment_type_key | Payment Type[payment_type_key] | ✔ |
| Payment | order_status_key | Order Status[order_status_key] | ✔ |
| Seller Month | month_date_key | Date[date_key] | ✔ |
| Seller Month | seller_key | Seller[seller_key] | ✔ |
| Seller Month | seller_geo_key | Seller Geo[seller_geo_key] | ✔ |
| Lead Funnel | first_contact_date_key | Date[date_key] | ✔ |
| Lead Funnel | won_date_key, first_sale_date_key | Date[date_key] | inactive (2 dòng) |
| Lead Funnel | lead_origin_key | Lead Origin[lead_origin_key] | ✔ |
| Lead Funnel | lead_profile_key | Lead Profile[lead_profile_key] | ✔ |
| Lead Funnel | sales_rep_key | Sales Rep[sales_rep_key] | ✔ |
| Lead Funnel | seller_key | Seller[seller_key] | ✔ |
| Seller Product Activity | month_date_key | Date[date_key] | ✔ |
| Seller Product Activity | seller_key | Seller[seller_key] | ✔ |
| Seller Product Activity | product_key | Product[product_key] | ✔ |

Ba bảng DQ (`DQ Latest`, `ETL Runs`, `DQ Issues`) **không có relationship** và đứng riêng cho trang 8.
`Customer[first_order_date_key]` **không** nối với `Date`, vì nối vào sẽ tạo đường lọc thứ hai từ Date sang Customer sang fact (ambiguous path).

### 5.3 Thiết lập cột

1. **Mark as date table**: chọn bảng `Date` → *Table tools → Mark as date table* → cột `Date`.
2. **Ẩn mọi cột `*_key`** và `log_id` (*Hide in report view*), vì người dùng không kéo các cột này vào visual.
3. **Sort by column** (*Column tools → Sort by column*):

   | Cột | Sort theo |
   | --- | --- |
   | Date[Day Name] | Date[Day Of Week No] |
   | Date[Month Name], Date[Month Short] | Date[Month No] |
   | Date[Year Month] | Date[Year Month Sort] |
   | Seller[Seller Tier] / [Previous Tier] / [Current Tier] | Seller[Seller Tier Sort] / [Previous Tier Sort] / [Current Tier Sort] |
   | Product[Weight Band] | Product[Weight Band Sort] |
   | Product[Size Band] | Product[Size Band Sort] |
   | Payment Type[Instalment Band] | Payment Type[Instalment Band Sort] |

4. **Data category** cho bản đồ: `Customer Latitude`/`Seller Latitude` → *Latitude*; `… Longitude` → *Longitude*;
   `Customer State`/`Seller State` → *State or Province*; `… City` → *City*.
5. **Summarize by = Don't summarize** cho các cột không cộng được: `Review Score`, `Installments`, `Distance (km)`,
   `Distinct Customers`, `… State Population`, `Lifetime Orders`, các cột lag. Người dùng chỉ dùng measure, không kéo cột số thô.
6. **Hierarchy**:
   - `Date`: Year → Quarter → Month Name → Date.
   - `Product`: Category Group → Category → Product ID.
   - `Customer Geo` / `Seller Geo`: Region → State → City.

### 5.4 Measures

Copy toàn bộ khối DAX ở `docs/kpi_dictionary.md` mục 3 vào bảng `_Measures`. Sau đó thả từng measure vào card không slicer
và so với cột *Giá trị tham chiếu* (mục 2). Lệch nghĩa là relationship hoặc filter sai.

### 5.5 Trang báo cáo dùng bảng nào

| # | Trang | Bảng / measure chính |
| --- | --- | --- |
| 1 | Executive Overview | GMV, Orders, AOV, Late Rate, Avg Review Score, Cancel Rate theo `Date[Month Start]`, `Customer Geo[Customer Region]`, `Product[Category Group]` |
| 3 | Fulfillment & Late Delivery | Late Rate, Avg Delivery Days, Dispatch Late Rate, các Avg … Lag; ma trận `Seller Geo[Seller State]` × `Customer Geo[Customer State]`; bản đồ theo lat/lng |
| 5 | Seller Quality & Tier Migration | `Seller Month` + `Seller` (Seller Tier / Current Tier / Previous Tier), Seller Late Rate, Seller Avg Score, Active Sellers, Active Listings |
| 6 | Lead Funnel & Channel Value | `Lead Funnel` + `Lead Origin`, `Lead Profile`, `Sales Rep`: Leads, Won Deals, Lead Conversion, Avg Days To Close, GMV 90d per Won Lead |
| 8 | Data Quality & Pipeline Health | `DQ Latest` (Tests Run, Test Pass Rate theo Layer), `DQ Issues`, `ETL Runs` (Last Successful Run, Duration theo Step) |

Trang 2, 4, 7 cần dữ liệu ML (dự báo, what-if, voucher), nên làm cùng nhóm M.

---

## 6. Việc còn lại liên quan

- **F7**: dựng file `powerbi/olist_dw.pbip` theo mục 5 (trang 1, 3, 5, 6, 8).
- **M3–M7**: thêm view ML vào `bi`, nối segment vào `v_dim_customer`.
- **P9**: chụp lineage `dbt docs` (bây giờ đã có đủ nhánh `dw → bi`).
