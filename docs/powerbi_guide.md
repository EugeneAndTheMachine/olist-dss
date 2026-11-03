# Hướng dẫn Power BI — kết nối, dựng model và nội dung từng trang

> Cập nhật: 02/11/2026. Viết cho người dựng file `powerbi/olist_dw.pbip` (TV3, trang 1, 3, 5, 6, 8; TV4, trang 2, 4, 7).
> Tài liệu liên quan:
> - `docs/kpi_dictionary.md`: định nghĩa KPI, nguồn sự thật. Measure trong file này phải khớp.
> - `docs/bi_layer.md`: thiết kế lớp `bi` (vì sao view như vậy).
> - `powerbi/README.md`: cài Power BI Desktop, lưu `.pbip`, làm việc chung.
>
> Mọi con số "giá trị tham chiếu" / "bạn sẽ thấy" bên dưới là kết quả SQL trên `bi.*` ngày 02/11/2026.
> Dùng để kiểm tra visual vừa dựng có đúng không.

**Mục lục**

- Phần A — Kết nối và dựng semantic model (làm 1 lần)
  - A1. Chuẩn bị · A2. Kết nối · A3. Power Query · A4. Relationships · A5. Thiết lập cột
  - A6. Tạo measures · A7. Quy ước trình bày · A8. Kiểm tra số
- Phần B — Nội dung từng trang
  - B1. Executive Overview · B3. Fulfillment & Late Delivery · B5. Seller Quality & Tier Migration
  - B6. Lead Funnel & Channel Value · B8. Data Quality & Pipeline Health
  - B2, B4, B7. Các trang cần ML (làm được một phần ngay)
- Phần C — Lỗi thường gặp
- Phụ lục — Khối DAX tạo toàn bộ measure một lần

---

# Phần A — Kết nối và dựng semantic model

## A1. Chuẩn bị

1. **Power BI Desktop** (Windows) cài từ Microsoft Store. Bật lưu dạng project nếu bản của bạn còn để ở Preview:
   *File → Options and settings → Options → Preview features* → tick **Power BI Project (.pbip) save option** và
   **Store semantic model using TMDL format** → khởi động lại Power BI.
2. **Bật Docker Desktop**, mở terminal ở thư mục repo:

   ```bash
   make up      # postgres + azurite
   make build   # dbt build → tạo stg, dw, bi; tạo user powerbi_reader
   make meta    # ghi kết quả test vào meta.* → trang 8 có dữ liệu
   ```

   Nếu đã build trước đó và chỉ cần bật lại DB: `docker compose up -d postgres` là đủ.
3. Kiểm tra nhanh DB đang chạy: `docker ps` phải thấy `olist-dss-postgres-1 … (healthy)`.

## A2. Kết nối

1. Mở Power BI Desktop → **Blank report**.
2. *Home → Get data → More… → Database → **PostgreSQL database*** → *Connect*.
3. Điền:

   | Ô | Giá trị |
   | --- | --- |
   | Server | `localhost:5432` |
   | Database | `olist_dw` |
   | Data Connectivity mode | **Import** |
   | Advanced options | để trống |

4. Hộp đăng nhập: chọn tab **Database** (không phải Windows) → User name `powerbi_reader`, Password `powerbi_reader`
   (hoặc giá trị `BI_READER_USER` / `BI_READER_PASSWORD` trong `.env`). *Select which level to apply these settings to*: `localhost:5432`.
5. **Nếu báo lỗi SSL / "The remote certificate is invalid"**: Postgres trong Docker không bật SSL.
   *File → Options and settings → Data source settings* → chọn `localhost:5432;olist_dw` → *Edit Permissions* →
   **bỏ tick "Encrypt connections"** → OK → thử lại.
6. Navigator chỉ hiện schema `bi` (21 view), vì user này không có quyền ở `dw`, `stg` hay `raw`. **Tick cả 21** → bấm
   **Transform Data** (không bấm Load).

> Không dùng user `olist`: user đó thấy mọi schema, dễ kéo nhầm bảng `dw`/`stg` vào báo cáo.

## A3. Power Query — đổi tên bảng

Trong Power Query Editor, cột *Queries* bên trái: double-click từng query để đổi tên (tên này dùng trong mọi DAX).

| Query gốc | Đổi thành | | Query gốc | Đổi thành |
| --- | --- | --- | --- | --- |
| bi v_dim_date | `Date` | | bi v_fact_sales | `Sales` |
| bi v_dim_customer | `Customer` | | bi v_fact_fulfillment | `Fulfillment` |
| bi v_dim_product | `Product` | | bi v_fact_review | `Review` |
| bi v_dim_seller | `Seller` | | bi v_fact_payment | `Payment` |
| bi v_dim_customer_geo | `Customer Geo` | | bi v_fact_seller_month | `Seller Month` |
| bi v_dim_seller_geo | `Seller Geo` | | bi v_fact_lead_funnel | `Lead Funnel` |
| bi v_dim_payment_type | `Payment Type` | | bi v_fact_seller_product_activity | `Seller Product Activity` |
| bi v_dim_order_status | `Order Status` | | bi v_dq_latest | `DQ Latest` |
| bi v_dim_lead_origin | `Lead Origin` | | bi v_etl_runs | `ETL Runs` |
| bi v_dim_lead_profile | `Lead Profile` | | bi v_dq_issue_summary | `DQ Issues` |
| bi v_dim_sales_rep | `Sales Rep` | | | |

Kiểm tra kiểu dữ liệu, thường Power BI tự nhận đúng từ Postgres:
- `Date[Date]`, `Date[Month Start]`, `Seller[Valid From]`, `Seller[Valid To]` phải là **Date**.
- Các cột tiền, lag, `Distance (km)` là **Decimal number**.
- Cờ `Is …` trong fact là **Whole number** (0/1). Cờ trong dim (`Is Current`, `Counts As Sale`) là **True/False**.

**Không** thêm bước biến đổi nào khác trong Power Query. Mọi làm sạch đã nằm ở dbt.

*Home → Close & Apply*. Lần nạp đầu mất khoảng 30–60 giây (khoảng 1 triệu dòng tổng).

## A4. Relationships

1. **Tắt tự đoán relationship trước khi nạp**, hoặc xoá hết relationship Power BI tự tạo sau khi nạp:
   *File → Options → Current file → Data Load* → bỏ tick **Autodetect new relationships after data is loaded**.
2. Mở **Model view** (icon thứ 3 bên trái). Kéo cột khoá của fact thả lên cột khoá của dim, hoặc dùng *Manage relationships → New*.
   Mọi relationship: **Cardinality = Many to one (\*:1)**, **Cross filter direction = Single**.
3. Relationship **inactive**: khi tạo, bỏ tick **Make this relationship active**. Power BI vẽ chúng bằng nét đứt.

| Fact | Cột ở fact → Dim[cột] | Ghi chú |
| --- | --- | --- |
| **Sales** | `purchase_date_key` → `Date[date_key]` | active |
| | `shipping_limit_date_key` → `Date[date_key]` | **inactive** |
| | `customer_key` → `Customer`, `product_key` → `Product`, `seller_key` → `Seller` | |
| | `customer_geo_key` → `Customer Geo`, `seller_geo_key` → `Seller Geo`, `order_status_key` → `Order Status` | |
| **Fulfillment** | `purchase_date_key` → `Date[date_key]` | active |
| | `approved_date_key`, `carrier_date_key`, `delivered_date_key`, `estimated_date_key` → `Date[date_key]` | **inactive** (4 cái) |
| | `customer_key`, `seller_key`, `customer_geo_key`, `seller_geo_key`, `order_status_key` → dim tương ứng | |
| **Review** | `review_creation_date_key` → `Date[date_key]` | active |
| | `review_answer_date_key` → `Date[date_key]` | **inactive** |
| | `customer_key`, `seller_key`, `customer_geo_key`, `order_status_key` → dim tương ứng | |
| **Payment** | `purchase_date_key` → `Date`, `customer_key` → `Customer`, `payment_type_key` → `Payment Type`, `order_status_key` → `Order Status` | |
| **Seller Month** | `month_date_key` → `Date[date_key]`, `seller_key` → `Seller`, `seller_geo_key` → `Seller Geo` | |
| **Lead Funnel** | `first_contact_date_key` → `Date[date_key]` | active |
| | `won_date_key`, `first_sale_date_key` → `Date[date_key]` | **inactive** |
| | `lead_origin_key` → `Lead Origin`, `lead_profile_key` → `Lead Profile`, `sales_rep_key` → `Sales Rep`, `seller_key` → `Seller` | |
| **Seller Product Activity** | `month_date_key` → `Date`, `seller_key` → `Seller`, `product_key` → `Product` | |

Không tạo relationship cho:
- `Customer[first_order_date_key]`: sẽ tạo đường lọc thứ hai từ Date tới fact.
- Ba bảng `DQ Latest`, `ETL Runs`, `DQ Issues`: đứng riêng.

Kiểm tra: Model view phải giống hình sao nhiều tâm (galaxy). Mỗi dim nối tới nhiều fact, không có mũi tên hai chiều,
không có đường nối giữa hai fact hoặc giữa hai dim.

## A5. Thiết lập cột

1. **Mark as date table**: chọn bảng `Date` → *Table tools → Mark as date table* → cột `Date`.
   Nếu báo lỗi "contains blanks / duplicates" nghĩa là bạn đang dùng view cũ. Chạy lại `make build`.
2. **Ẩn cột khoá**: Model view → chọn mọi cột `*_key` và `log_id` (giữ Ctrl để chọn nhiều) → *Properties → Is hidden = Yes*.
   Ẩn luôn `Seller Tier Sort`, `Previous Tier Sort`, `Current Tier Sort`, các cột `… Sort` khác và `Year Month Sort`.
3. **Sort by column** (*Column tools → Sort by column*):

   | Cột | Sort theo |
   | --- | --- |
   | `Date[Day Name]` | `Date[Day Of Week No]` |
   | `Date[Month Name]`, `Date[Month Short]` | `Date[Month No]` |
   | `Date[Year Month]` | `Date[Year Month Sort]` |
   | `Seller[Seller Tier]` / `[Previous Tier]` / `[Current Tier]` | `[Seller Tier Sort]` / `[Previous Tier Sort]` / `[Current Tier Sort]` |
   | `Product[Weight Band]`, `Product[Size Band]` | `[Weight Band Sort]`, `[Size Band Sort]` |
   | `Payment Type[Instalment Band]` | `[Instalment Band Sort]` |

4. **Data category** (*Column tools → Data category*):
   - `Customer Latitude`, `Seller Latitude` → **Latitude**.
   - `Customer Longitude`, `Seller Longitude` → **Longitude**.
   - `Customer State Name`, `Seller State Name` → **State or Province**.
   - `Customer City`, `Seller City` → **City**.
5. **Summarize by = Don't summarize** cho cột số không được cộng:
   - `Review[Review Score]`, `Payment[Installments]`, `Fulfillment[Distance (km)]`, mọi cột `… Lag (days)`, `Delay Days`.
   - `Seller Month[Distinct Customers]`, `Customer[Lifetime Orders]`, `… State Population`, mọi `… Latitude/Longitude`.
   - `Date[Year]`, `Date[Month No]`, `Date[Quarter No]`, `Date[ISO Week]`.

   Mục đích: người dùng không kéo nhầm cột thô và ra một "tổng điểm review" vô nghĩa.
6. **Hierarchy**: chuột phải cột → *Create hierarchy*, rồi kéo các cột còn lại vào:
   - `Date`: Year → Quarter → Month Name → Date.
   - `Product`: Category Group → Category → Product ID.
   - `Customer Geo`: Customer Region → Customer State → Customer City. Tương tự cho `Seller Geo`.

## A6. Tạo measures

1. *Home → Enter data* → đặt tên bảng `_Measures` → *Load*. Power BI tạo cột `Column1`.
2. Cách nhanh nhất: mở **DAX query view** (icon thứ 4 bên trái), dán **khối DAX ở Phụ lục** → *Run*.
   - Kết quả là một dòng số. So từng cột với bảng ở A8.
   - Bấm **Update model with changes** (hoặc CodeLens *Update model: Add new measure* trên từng measure) để lưu toàn bộ measure vào model.
3. Chuyển các measure mới vào bảng `_Measures` nếu chúng nằm chỗ khác (*Model view → measure → Properties → Home table*).
   Xoá cột `Column1`. Bảng `_Measures` sẽ có icon máy tính và nổi lên đầu danh sách *Data*.
4. **Định dạng** (*Measure tools → Format*):
   - Tiền (GMV, AOV, …): `#,0` trên card, `#,0.00` trong bảng.
   - Tỷ lệ (… Rate, Conversion, YoY %): **Percentage**, 1–2 chữ số thập phân.
   - Ngày, điểm: Decimal, 1–2 chữ số.
5. Đặt measure vào **Display folder** (*Properties → Display folder*): `Sales`, `Logistics`, `Review`, `Seller`, `Funnel`, `DQ`, `What-if`.
   Danh sách measure dài, chia folder sẽ dễ tìm hơn.

## A7. Quy ước trình bày (áp dụng cho mọi trang)

**Canvas & bố cục**
- Kích thước trang 16:9 (1280 × 720). *Format page → Canvas settings*.
- Mỗi trang đi từ trên xuống: **(1) dải tiêu đề + slicer → (2) hàng KPI card → (3) biểu đồ xu hướng → (4) biểu đồ phân tích / bảng chi tiết**.
  Đọc theo hình chữ Z: trái → phải, trên → dưới, từ tổng quát tới chi tiết.
- Tiêu đề trang ghi câu hỏi mà trang trả lời, ví dụ "Giao hàng trễ ở đâu và vì sao?", không chỉ ghi "Fulfillment".

**Bộ lọc cửa sổ phân tích (bắt buộc)**
- Dữ liệu ngoài 01/2017 → 08/2018 rất thưa: 09/2016 có 2 đơn với late rate 100%, 09/2018 có 1 đơn. Nếu không lọc,
  đường xu hướng sẽ có đầu và đuôi nhảy vọt vô nghĩa.
- Thêm `Date[In Analysis Window] = True` vào **Filters on all pages** (khung Filters → kéo cột vào mục "Filters on all pages").
- Trang 6 (funnel): `first_contact` có từ 06/2017 → 05/2018, nằm trọn trong cửa sổ, nên không bị ảnh hưởng.

**Màu**
- Một màu chủ đạo cho số liệu bình thường. Màu đỏ/cam **chỉ** dùng cho cái xấu (trễ, điểm thấp, At-risk, test fail).
  Xanh lá cho cái tốt. Đừng dùng đỏ cho series bình thường.
- Tier luôn cùng một bộ màu ở mọi trang: Gold (vàng đậm), Silver (xám), Bronze (nâu cam), New (xanh dương nhạt),
  At-risk (đỏ), Unscored (xám nhạt). Đặt 1 lần bằng theme JSON hoặc *Format → Colors* trên từng visual.

**Tương tác**
- Click một cột hoặc một vùng sẽ lọc các visual khác trên trang (cross-filter). Visual nào không nên bị lọc (ví dụ card tổng)
  thì tắt bằng *Format → Edit interactions → None*.
- Tooltip: thêm `Orders` / `Delivered Orders` vào tooltip của mọi biểu đồ tỷ lệ. Người đọc cần biết tỷ lệ dựa trên bao nhiêu đơn.
- Đặt slicer chung (Year Month, Region) ở cùng vị trí trên mọi trang, và **Sync slicers** (*View → Sync slicers*) để lọc giữ nguyên khi chuyển trang.

## A8. Kiểm tra số trước khi dựng trang

Tạo một trang nháp, đặt một **Table visual** chỉ chứa measure, **không slicer**. Làm 2 lần: có và không có filter `In Analysis Window`.

| Measure | Toàn bộ dữ liệu | Trong cửa sổ 01/2017–08/2018 |
| --- | --- | --- |
| GMV | 13 494 400,74 | 13 449 530 |
| Orders | 98 207 | 97 910 |
| AOV | 137,41 | 137,37 |
| Late Rate | 6,77 % | 6,79 % |
| Cancel Rate | 1,24 % | 1,19 % |
| Avg Review Score | 4,086 | 4,088 (theo ngày tạo review) |
| Avg Delivery Days | 12,56 | |
| Dispatch Late Rate | 9,06 % | |
| Repeat Customer Rate | 3,04 % | |
| Leads / Won Deals / Lead Conversion | 8 000 / 842 / 10,53 % | (như cũ) |
| Avg Days To Close | 48,5 | |
| GMV 90d per Won Lead | 514,97 | |
| Seller Late Rate | 6,69 % | |

Lệch thì xem Phần C trước khi đi tiếp.

---

# Phần B — Nội dung từng trang

Mỗi trang có các phần:
- **Người dùng và câu hỏi**: trang giúp ai quyết định gì.
- **Bố cục**: phác thảo vị trí visual.
- **Bảng visual**: loại biểu đồ, kéo field nào vào ô nào, vì sao chọn loại đó.
- **Cách đọc**: kèm con số bạn sẽ thấy với dữ liệu hiện tại.
- **Lỗi hay gặp** riêng của trang.

Tên field ghi dạng `Bảng[Cột]`. Tên trong ngoặc vuông không có bảng, ví dụ `[GMV]`, là measure.

## B1. Executive Overview — Commerce Manager

**Câu hỏi**: Doanh số đang tăng hay giảm, đến từ đâu, và có dấu hiệu gì về chất lượng phục vụ cần lo?
Đây là trang "Intelligence" (pha 1 của Simon): phát hiện vấn đề, chưa đề xuất hành động.

**Bố cục**

```
┌───────────────────────────────────────────────────────────────────────────┐
│ Executive Overview — Doanh số và chất lượng   [Year Month ▾][Region ▾][Group ▾] │
├──────────┬──────────┬──────────┬──────────┬──────────┬──────────────────────┤
│ GMV      │ Orders   │ AOV      │ Late Rate│ Review   │ Cancel Rate          │
│ +YoY %   │ +YoY %   │          │          │ Score    │                      │
├──────────┴──────────┴──────────┴──────────┴──────────┴──────────────────────┤
│ (3) GMV & Orders theo tháng (line + column)                                  │
├────────────────────────────┬────────────────────────┬────────────────────────┤
│ (4) GMV theo Category Group│ (5) GMV theo bang khách│ (6) Late Rate vs Review │
│     (bar ngang)            │     (map / bar)        │     theo tháng (combo)  │
└────────────────────────────┴────────────────────────┴────────────────────────┘
```

**Slicer**
- `Date[Year Month]`: kiểu *Between*. Nếu muốn chọn bằng thanh trượt ngày thì dùng `Date[Date]`.
- `Customer Geo[Customer Region]`: dropdown.
- `Product[Category Group]`: dropdown.

| # | Visual | Field | Vì sao chọn |
| --- | --- | --- | --- |
| 1 | **Card (new)** × 6 | `[GMV]`, `[Orders]`, `[AOV]`, `[Late Rate]`, `[Avg Review Score]`, `[Cancel Rate]`. Reference label: `[GMV YoY %]` dưới card GMV, `[Orders YoY %]` dưới card Orders | Lãnh đạo đọc 6 con số trong 5 giây |
| 2 | (cùng hàng) | Conditional formatting màu chữ: YoY % < 0 đỏ, > 0 xanh | Hướng tăng/giảm thấy ngay |
| 3 | **Line and clustered column chart** | X: `Date[Month Start]` (tắt hierarchy, chọn *Continuous* hoặc dùng `Year Month`); Column y: `[Orders]`; Line y: `[GMV]`; Tooltip: `[GMV MoM %]`, `[AOV]` | Hai đại lượng khác đơn vị trên cùng trục thời gian; cột = khối lượng, đường = giá trị |
| 4 | **Clustered bar chart** (ngang) | Y: `Product[Category Group]`; X: `[GMV]`; Tooltip: `[Orders]`, `[AOV]`, `[GMV YoY %]`. Sort giảm dần | Bar ngang đọc được tên nhóm dài; sort để thấy Pareto |
| 5 | **Map** (bubble) hoặc **Filled map** | Location: `Customer Geo[Customer State Name]`; Bubble size: `[GMV]`; Tooltip: `[Orders]`, `[Late Rate]`. Nếu Map không hiện, thay bằng Clustered bar theo `Customer State` | Doanh số tập trung theo địa lý |
| 6 | **Line and clustered column chart** | X: `Date[Month Start]`; Column: `[Late Rate]`; Line: `[Avg Review Score]` (trục phụ) | Cho thấy quan hệ giao trễ → điểm review giảm cùng lúc |

**Cách đọc**
- **Card**: GMV khoảng 13,4 triệu BRL, khoảng 98 nghìn đơn, AOV khoảng 137 BRL.
  Chọn Year Month 2018-01 → 2018-08 thì `GMV YoY %` khoảng **+138 %** so với 01–08/2017 (7,34 triệu so với 3,08 triệu). Olist tăng trưởng rất nhanh.
- **Xu hướng (3)**:
  - GMV tăng đều trong 2017, **đỉnh 11/2017** (khoảng 1,0 triệu, Black Friday), sau đó đi ngang khoảng 0,85–1,0 triệu/tháng trong 2018.
  - Nếu cột Orders tăng mà đường GMV đi ngang, AOV đang giảm: khách mua đơn nhỏ hơn.
- **Category Group (4)**:
  - Home & Furniture dẫn đầu (khoảng 2,9 triệu), tiếp theo Electronics & Tech, Sports & Leisure, Health & Beauty (mỗi nhóm khoảng 1,6–1,9 triệu).
  - Đọc cùng tooltip YoY: nhóm GMV lớn nhưng YoY thấp là nhóm đang chững lại.
- **Địa lý (5)**: Sudeste (SP, RJ, MG) chiếm khoảng 70 % đơn (68 nghìn / 98 nghìn). Bubble SP lấn át, nên khi đọc các bang nhỏ hãy lọc bỏ SP hoặc xem bar chart.
- **Late vs Review (6)**:
  - Late rate vọt ở **11/2017 (12,4 %)** và **02–03/2018 (14,1 % và 19,0 %)**. Ở chính các tháng đó điểm review chùng xuống.
  - Đây là "vấn đề" mà trang 3 sẽ đào sâu. Đơn trễ có điểm review trung bình **2,27** so với **4,29** của đơn đúng hẹn.

**Lỗi hay gặp**
- Card YoY trống: khoảng đang chọn không có dữ liệu năm trước (ví dụ chọn 2017). Đây là đúng.
- GMV ở visual 4 cộng lại lớn hơn card: kiểm tra xem visual có bị *Edit interactions* bỏ qua slicer không.

## B3. Fulfillment & Late Delivery — Logistics Manager

**Câu hỏi**: Đơn trễ tập trung ở tuyến nào, tháng nào, và chậm ở chặng nào (duyệt đơn, seller gửi hàng, vận chuyển)?

**Bố cục**

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Giao hàng trễ ở đâu và vì sao?      [Year Month ▾][Seller State ▾][Cust Region ▾] │
├────────────┬────────────┬────────────┬────────────┬───────────────────────┤
│ Late Rate  │ Avg Deliv. │ Avg Promise│ Dispatch   │ Avg Distance          │
│            │ Days       │ Days       │ Late Rate  │                       │
├────────────┴────────────┴────────────┴────────────┴───────────────────────┤
│ (2) Late Rate & Delivered Orders theo tháng   │ (3) Phân rã thời gian giao │
│     (combo)                                   │     theo vùng (stacked bar)│
├───────────────────────────────────────────────┼────────────────────────────┤
│ (4) Ma trận tuyến Seller State × Customer State│ (5) Phân bố Delay Days     │
│     (matrix, tô màu Late Rate)                │     (histogram)            │
│                                               ├────────────────────────────┤
│                                               │ (6) Review: trễ vs đúng hẹn │
└───────────────────────────────────────────────┴────────────────────────────┘
```

| # | Visual | Field | Vì sao chọn |
| --- | --- | --- | --- |
| 1 | **Card** × 5 | `[Late Rate]`, `[Avg Delivery Days]`, `[Avg Promised Days]`, `[Dispatch Late Rate]`, `[Avg Distance km]` | Đặt Avg Delivery cạnh Avg Promised để thấy khoảng đệm Olist đang hứa |
| 2 | **Line and clustered column** | X: `Date[Month Start]`; Column: `[Delivered Orders]`; Line: `[Late Rate]` | Xem late rate tăng có trùng lúc khối lượng tăng không, tức quá tải |
| 3 | **Stacked bar** (ngang) | Y: `Customer Geo[Customer Region]`; X: `[Avg Approval Lag]`, `[Avg Dispatch Lag]`, `[Avg Transit Lag]` | Mỗi thanh là tổng thời gian; từng khúc màu là một chặng |
| 4 | **Matrix** | Rows: `Seller Geo[Seller State]`; Columns: `Customer Geo[Customer State]`; Values: `[Late Rate]`. Conditional formatting → *Background color* → Gradient trắng → đỏ. Visual filter: `[Delivered Orders]` ≥ 100 | Tuyến = cặp bang gửi → nhận. Heatmap cho mắt bắt ô đỏ ngay |
| 4b | (thay thế 4, dễ đọc hơn) **Table** | `Seller State`, `Customer State`, `[Delivered Orders]`, `[Late Orders]`, `[Late Rate]`, `[Late Share]`, `[Avg Delivery Days]`. Filter `[Delivered Orders]` ≥ 300, sort `[Late Orders]` giảm dần | Danh sách tuyến ưu tiên: vừa trễ nhiều vừa đông đơn |
| 5 | **Clustered column** | X: nhóm `Delay Days` theo bin (chuột phải `Fulfillment[Delay Days]` → *New group* → Bin, size 5 ngày); Y: `[Delivered Orders]` | Thấy hình dạng phân bố: phần lớn giao sớm, phần đuôi phải là trễ |
| 6 | **Clustered bar** hoặc 2 card | `[Avg Score On-time]`, `[Avg Score Late]`, `[Low Score Rate Late]` | Lượng hoá cái giá của giao trễ lên trải nghiệm khách |

**Cách đọc**
- **Card**: giao thực tế khoảng **12,6 ngày**, hứa khoảng **23,8 ngày**. Trung bình đơn về **sớm 11,9 ngày** so với hứa (delay_days trung bình −11,9).
  Olist hứa rất "an toàn". Đơn vẫn trễ 6,8 % vì phân bố thời gian giao có đuôi dài, không phải vì hứa quá sát.
  Trang 4 (what-if) dùng chính điều này: rút ngắn ngày hứa thì late rate tăng bao nhiêu.
- **Xu hướng (2)**: hai đỉnh 11/2017 (Black Friday) và 02–03/2018 (late rate 14–19 %, khối lượng không tăng tương ứng),
  nên vấn đề có thể nằm ở vận chuyển (mùa mưa, đình công…) chứ không chỉ do quá tải.
  Click cột 03/2018 để mọi visual khác lọc theo tháng đó, rồi xem tuyến nào đỏ lên.
- **Phân rã (3)**:
  - Toàn quốc: duyệt khoảng 0,4 ngày, seller gửi hãng khoảng 2,9 ngày, **vận chuyển khoảng 9,3 ngày**. Chặng vận chuyển chiếm phần lớn.
  - **Nordeste** và **Norte** có thanh dài nhất (20 và 22,6 ngày giao). Late rate Nordeste **12,7 %**, gấp đôi Sudeste (6,1 %).
  - Ba khúc là trung bình riêng trên các đơn có dữ liệu chặng đó, nên tổng xấp xỉ chứ không bằng đúng `Avg Delivery Days`.
- **Tuyến (4/4b)**: hầu hết seller ở SP, nên hàng SP là hàng quan trọng nhất. Tuyến nặng nhất khi lọc ≥ 300 đơn:
  - SP → MA **19,0 %**, SP → PI 16,5 %, SP → CE 13,8 %, SP → BA 12,9 %.
  - **SP → RJ 14,3 % trên 8 077 đơn**: tỷ lệ không cao nhất nhưng **số đơn trễ tuyệt đối lớn nhất**. Đó là lý do có cột `Late Share`.
    Sửa SP → RJ giảm được nhiều đơn trễ hơn sửa SP → MA.
- **Delay Days (5)**: đỉnh phân bố ở khoảng −10 đến −15 ngày (về sớm). Các cột bên phải 0 là đơn trễ. Đuôi phải kéo dài tới vài chục ngày.
- **Review (6)**: đúng hẹn 4,29 điểm, 9,3 % review thấp; **trễ 2,27 điểm, 62,4 % review ≤ 2 sao**.
  Đây là bằng chứng chính để Logistics Manager xin ngân sách sửa tuyến.

**Lỗi hay gặp**
- Matrix toàn ô đỏ hoặc xanh 100 %: tuyến chỉ có 1–2 đơn. Luôn đặt filter `[Delivered Orders]` ≥ ngưỡng.
- Card `Avg Delivery Days` khác `Avg Delay Days + Avg Promised Days`: đúng, vì mẫu số khác nhau (promised tính mọi đơn, delay chỉ tính đơn đã giao).

## B5. Seller Quality & Tier Migration — Seller Quality Manager

**Câu hỏi**: Chất lượng tập seller đang tốt lên hay xấu đi? Seller nào cần cảnh báo, seller nào nên khen thưởng?
Bộ quy tắc tier (seed `seller_tier_rules`) có phân loại đúng không?

**Khái niệm cần nắm trước** (dim seller là SCD2):
- `Seller[Seller Tier]` = tier **tại thời điểm** của dòng fact. Trong `Seller Month`, đó là tier cuối tháng đó.
  Lọc Gold sẽ ra "các tháng mà seller đang là Gold".
- `Seller[Current Tier]` = tier **hiện tại**. Lọc Gold sẽ ra "các seller hôm nay là Gold", kèm toàn bộ lịch sử của họ.
- Đếm seller: `DISTINCTCOUNT(Seller[Seller ID])`, không đếm dòng của `Seller`, vì một seller có nhiều version.

**Bố cục**

```
┌───────────────────────────────────────────────────────────────────────────┐
│ Chất lượng seller & chuyển tier       [Year Month ▾][Seller State ▾][Current Tier ▾] │
├────────────┬────────────┬────────────┬────────────┬────────────────────────┤
│ Active     │ Seller     │ Seller Avg │ Seller GMV │ At-risk sellers (now)  │
│ Sellers    │ Late Rate  │ Score      │            │                        │
├────────────┴────────────┴────────────┴────────────┴────────────────────────┤
│ (2) Active Sellers theo tháng, chia theo tier   │ (3) Late Rate & Score theo │
│     (stacked column)                            │     tier (clustered bar)   │
├─────────────────────────────────────────────────┼────────────────────────────┤
│ (4) Ma trận chuyển tier Previous → Seller Tier  │ (5) Scatter seller:        │
│     (matrix heatmap)                            │     late rate × điểm        │
├─────────────────────────────────────────────────┴────────────────────────────┤
│ (6) Watchlist: seller hiện At-risk, sort theo GMV (table)                    │
└──────────────────────────────────────────────────────────────────────────────┘
```

| # | Visual | Field | Vì sao chọn |
| --- | --- | --- | --- |
| 1 | **Card** × 5 | `[Active Sellers]`, `[Seller Late Rate]`, `[Seller Avg Score]`, `[Seller GMV]`, `[At-risk Sellers Now]` | |
| 2 | **Stacked column** (hoặc 100 % stacked) | X: `Date[Month Start]`; Y: `[Active Sellers]`; Legend: `Seller[Seller Tier]` | Cơ cấu tier theo thời gian; 100 % stacked để so tỷ trọng |
| 3 | **Clustered bar** | Y: `Seller[Seller Tier]`; X: `[Seller Late Rate]`; tooltip `[Seller Avg Score]`, `[Seller GMV]`. Có thể làm thêm một bar thứ hai cho `[Seller Avg Score]` | Kiểm tra rule tier có phân biệt chất lượng thật không |
| 4 | **Matrix** | Rows: `Seller[Previous Tier]`; Columns: `Seller[Seller Tier]`; Values: `[Tier Changes]`; background gradient. Slicer riêng: `Seller[Valid From]` (Between) | Ma trận chuyển trạng thái: đọc được luồng lên hạng / xuống hạng |
| 5 | **Scatter chart** | Values (Details): `Seller[Seller ID]`; X: `[Seller Late Rate]`; Y: `[Seller Avg Score]`; Size: `[Seller GMV]`; Legend: `Seller[Current Tier]`. Visual filter `[Seller Orders]` ≥ 30. *Analytics pane*: X constant line 0,15; Y constant line 3,5 | Mỗi chấm là 1 seller. Hai đường hằng là ngưỡng At-risk của rule |
| 6 | **Table** | `Seller[Seller ID]`, `Seller[Current Tier]`, `[Seller Orders]`, `[Seller GMV]`, `[Seller Late Rate]`, `[Seller Avg Score]`. Filter `Current Tier = At-risk`; sort `[Seller GMV]` giảm dần; data bars cho GMV, màu đỏ cho late rate > 15 % | Danh sách hành động: cảnh báo seller lớn đang xấu trước |

**Cách đọc**
- **Cơ cấu (2)**: số seller có hoạt động tăng theo thời gian (trung bình khoảng 809/tháng trong cửa sổ). Tháng 08/2018, trong
  snapshot có khoảng 2 058 Bronze, 708 New, 168 Silver, 156 At-risk và chỉ **5 Gold**. Gold rất hiếm vì ngưỡng 50 đơn / 3 tháng.
  Đây là gợi ý cho Seller QM: có nên hạ ngưỡng rule v2 không.
- **Tier có ý nghĩa không (3)**: thứ tự phải đơn điệu. Tier tốt thì late rate thấp, điểm cao. Hiện tại:
  - Gold: 4,5 % trễ / 4,38 điểm.
  - Silver: 5,8 % / 4,24.
  - Bronze: 6,9 % / 4,07.
  - At-risk: **9,9 % / 3,89**.

  Rule đang tách được chất lượng. Nếu một ngày At-risk lại tốt hơn Bronze, rule cần chỉnh.
- **Chuyển tier (4)**: đọc theo hàng là "đang ở tier X thì chuyển đi đâu".
  - Đông nhất: Bronze → At-risk (542 lượt), Bronze → Silver (448), Silver → Bronze (434).
  - Silver → Gold chỉ 26 lượt, Gold → Silver 21 lượt.
  - Hàng trống `(Blank)` là version đầu tiên (New / Unscored), không phải một lần chuyển.
  - Đường chéo trống là đúng thiết kế: version mới chỉ sinh khi tier đổi.
- **Scatter (5)**:
  - Góc **dưới phải** (trễ nhiều, điểm thấp) là seller cần can thiệp. Bong bóng to ở góc đó là ưu tiên số 1.
  - Góc **trên trái** là ứng viên khen thưởng / tăng hiển thị.
  - Chấm màu Gold mà nằm góc xấu nghĩa là seller vừa xuống phong độ, rule chưa kịp hạ tier (cửa sổ 3 tháng).
- **Watchlist (6)**: đây là đầu vào cho đề xuất M7 sau này. Bây giờ Seller QM có thể dùng trực tiếp.

**Lỗi hay gặp**
- Card Active Sellers ra con số vài chục nghìn: measure đang cộng `Is Active` qua nhiều tháng. Dùng đúng `[Active Sellers]` (AVERAGEX theo tháng).
- Matrix chuyển tier không đổi khi chọn Year Month: bình thường, vì `Seller` không nối với `Date`. Dùng slicer `Valid From`.

## B6. Lead Funnel & Channel Value — Seller Quality Manager (thu hút seller)

**Câu hỏi**: Kênh marketing nào mang về seller **chốt được** và **bán được hàng**, chứ không chỉ nhiều lead? Chốt deal mất bao lâu?

**Bố cục**

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Funnel thu hút seller & giá trị kênh       [First contact month ▾][Origin ▾] │
├────────────┬────────────┬────────────┬────────────┬───────────────────────┤
│ Leads      │ Won Deals  │ Conversion │ Days to    │ GMV 90d / won lead    │
│            │            │            │ Close      │                       │
├────────────┴────────────┼────────────┴────────────┴───────────────────────┤
│ (2) Funnel MQL → Won →  │ (3) Leads & Conversion theo tháng liên hệ (combo) │
│     First sale          │                                                  │
├─────────────────────────┼──────────────────────────────────────────────────┤
│ (4) Leads & Conversion  │ (5) Scatter kênh: Conversion × GMV 90d (bubble)  │
│     theo Origin (combo) │                                                  │
├─────────────────────────┴───────────────┬──────────────────────────────────┤
│ (6) Won theo Business Segment (bar)      │ (7) Phân bố Days to Close (hist.) │
└──────────────────────────────────────────┴──────────────────────────────────┘
```

| # | Visual | Field | Vì sao chọn |
| --- | --- | --- | --- |
| 1 | **Card** × 5 | `[Leads]`, `[Won Deals]`, `[Lead Conversion]`, `[Avg Days To Close]`, `[GMV 90d per Won Lead]` | |
| 2 | **Funnel** | Category: `Funnel Stage[Stage]`; Values: `[Funnel Value]` (bảng phụ, xem Phụ lục) | Thấy tỷ lệ rơi giữa các bước |
| 3 | **Line and clustered column** | X: `Date[Month Start]` (relationship active = first contact); Column: `[Leads]`; Line: `[Lead Conversion]` | Lượng lead và chất lượng lead theo thời gian |
| 4 | **Line and clustered column** | X: `Lead Origin[Lead Origin]` sort theo Leads; Column: `[Leads]`; Line: `[Lead Conversion]` | So khối lượng và tỷ lệ chốt từng kênh |
| 5 | **Scatter** | Details: `Lead Origin[Lead Origin]`; X: `[Lead Conversion]`; Y: `[GMV 90d per Won Lead]`; Size: `[Leads]`; *Analytics*: average line cho X và Y | Ma trận 4 ô chọn kênh đầu tư |
| 6 | **Clustered bar** | Y: `Lead Profile[Business Segment]`; X: `[Won Deals]`; tooltip `[GMV 90d per Won Lead]`. Filter: Business Segment *is not blank* | Seller chốt được thuộc ngành nào |
| 7 | **Clustered column** | X: bin `Lead Funnel[Days To Close]` (size 15 ngày); Y: `[Won Deals]` | Thời gian chốt điển hình, đuôi dài |

**Cách đọc**
- **Funnel (2)**: 8 000 MQL → **842 chốt (10,5 %)** → **379 có đơn bán đầu tiên** (khoảng 45 % số đã chốt).
  Hơn một nửa seller chốt xong không bán gì trong dữ liệu. Đây là vấn đề onboarding, không phải vấn đề marketing.
- **Theo tháng (3)**: conversion các tháng liên hệ cuối (04–05/2018) thấp hơn **một phần vì chưa đủ thời gian chốt**
  (trung bình 48 ngày), không hẳn là lead kém đi. Ghi chú điều này ngay trên visual (*text box*).
- **Theo kênh (4)**:
  - organic_search nhiều lead nhất (2 296, 11,8 %).
  - paid_search 1 586 lead, conversion **12,3 %**.
  - social 1 350 lead nhưng chỉ 5,6 %. email 3,0 %.
  - `unknown` (origin gốc bị trống) có conversion 16,7 %. Không kết luận được gì từ nhóm này, ghi chú là chất lượng dữ liệu nguồn.
- **Giá trị kênh (5)**: góc **trên phải** (chốt tốt và seller bán tốt) là kênh nên tăng ngân sách.
  - paid_search: 12,3 % và khoảng 521 BRL GMV 90 ngày / seller chốt. Tốt hơn organic_search (11,8 %, khoảng 436).
  - social nằm góc dưới trái (5,6 %, khoảng 249).
  - Bong bóng nhỏ như `other` (4 deal) hay `display` thì **không đáng tin**. Luôn đọc kèm Size = số lead.
  - GMV 90 ngày chỉ tính trên lead chốt đủ 90 ngày trước 31/08/2018 (667 / 842 lead). Measure đã lọc sẵn.
- **Days to close (7)**: trung bình 48,5 ngày. Phần lớn chốt trong 1–2 tháng đầu, đuôi dài vài tháng.

**Lỗi hay gặp**
- Slicer Year Month của trang khác (đồng bộ) lọc theo **ngày liên hệ đầu**. Không đồng bộ slicer này sang trang 6 nếu nó gây nhầm lẫn.
- Muốn xem "deal chốt trong tháng" (theo won date): dùng measure với `USERELATIONSHIP ( 'Lead Funnel'[won_date_key], 'Date'[date_key] )`.

## B8. Data Quality & Pipeline Health — mọi người dùng

**Câu hỏi**: Số liệu trên các trang khác có đáng tin không? Lần nạp gần nhất khi nào, có test nào lỗi, dữ liệu lỗi được xử lý ra sao?
Trang "Trust": người xem báo cáo mở trang này trước khi trích số đi họp.

**Bố cục**

```
┌───────────────────────────────────────────────────────────────────────────┐
│ Dữ liệu có đáng tin không?                                               │
├────────────┬────────────┬────────────┬────────────┬────────────────────────┤
│ Last succ. │ Tests Run  │ Test Pass  │ Failed     │ Flagged Rows           │
│ run        │            │ Rate       │ Tests      │                        │
├────────────┴────────────┴─────┬──────┴────────────┴────────────────────────┤
│ (2) Test theo Layer × Status  │ (3) Lỗi dữ liệu được gắn cờ theo model     │
│     (stacked bar)             │     (bar: Issue %)                         │
├───────────────────────────────┼────────────────────────────────────────────┤
│ (4) Test không pass (table)   │ (5) Lịch sử chạy pipeline (table)          │
└───────────────────────────────┴────────────────────────────────────────────┘
```

| # | Visual | Field | Vì sao chọn |
| --- | --- | --- | --- |
| 1 | **Card** × 5 | `[Last Successful Run]`, `[Tests Run]`, `[Test Pass Rate]`, `[Failed Tests]` (đỏ nếu > 0), `[Flagged Rows]` | |
| 2 | **Stacked bar** | Y: `DQ Latest[Layer]`; X: `[Tests Run]`; Legend: `DQ Latest[Status]` (pass xanh, warn cam, fail/error đỏ) | Test phủ đều các tầng không |
| 3 | **Clustered bar** | Y: `DQ Issues[Issue]` (hoặc hierarchy Model → Issue); X: `DQ Issues[Issue %]`; tooltip `Issue Rows`, `Total Rows`, `Model` | Lỗi nào nhiều nhất, so tương đối với kích thước bảng |
| 4 | **Table** | `Test Name`, `Model`, `Status`, `Failures`, `Message`. Filter `Is Pass = 0` | Trống là tốt. Thêm text "Không có test lỗi" cạnh bảng |
| 5 | **Table** | `ETL Runs[Started At]`, `Step`, `Status`, `Rows Out`, `Duration (s)`, `Message`. Sort Started At giảm dần; màu đỏ khi Status = failed | Lịch sử nạp (history of extracts) |

**Cách đọc**
- Hiện tại **269 test, pass 100 %**, chia theo tầng: stg 88, dw 134, bi 30, khác 17.
  Test "khác" là các test đối soát tự viết (`assert_*`) và test trên `meta`.
- **Lỗi được gắn cờ (3)**: dữ liệu lỗi **không bị xoá** mà được giữ và gắn cờ `_dq_issue`, để số tổng vẫn khớp nguồn. Ví dụ:
  - `carrier_before_approved` 1 359 đơn (1,4 %): ngày giao hãng trước ngày duyệt, nên lag tương ứng để trống.
  - `order_without_items` 775 đơn: đơn không có item (thường là huỷ).
  - `missing_category` 610 sản phẩm: xếp vào nhóm Unknown.
  - `funnel_seller_not_in_sellers` 462 seller (13 %): seller chốt deal nhưng chưa từng bán. Đây là thực tế kinh doanh, không phải lỗi pipeline.
  - `payment_mismatch_over_tolerance` 249 đơn (0,25 %): tổng thanh toán lệch tổng item quá max(1 BRL, 1 %).
- **Lịch sử (5)**: có dòng `failed` cũ của Airflow là các lần thử trước. Chỉ cần dòng mới nhất là `success`.

**Lưu ý refresh**: `DQ Latest` đọc kết quả do `make meta` ghi. Thứ tự đúng: `make build` → `make meta` → *Refresh* trong Power BI.

## B2, B4, B7 — Các trang cần ML (TV4)

Ba trang này thuộc pha Design/Choice và cần bảng `ml.*`, nên **chờ nhóm M**. Hai trang làm được một phần ngay bằng dữ liệu hiện có:

**B2. Growth: Category × Region (+ Forecast sau)**: Commerce Manager. Câu hỏi: đầu tư nhóm hàng nào ở vùng nào?
- Làm ngay:
  - **Matrix**: Rows `Product[Category Group]`, Columns `Customer Geo[Customer Region]`, Values `[GMV]` và `[GMV YoY %]`
    (lọc Year Month 2018-01 → 2018-08). Tô màu YoY: xanh nếu tăng mạnh, đỏ nếu giảm.
  - **Line**: GMV theo tháng, Legend `Category Group` (chọn top 5).
  - Đọc: ô GMV lớn và YoY cao là nơi đầu tư tiếp. Ô GMV nhỏ nhưng YoY rất cao là thị trường mới nổi (cần đọc kèm số đơn).
- Chờ M5: đường dự báo (`bi.v_gmv_forecast`), dải tin cậy, what-if % tăng trưởng.

**B4. Promise-date What-if & Routes to fix**: Logistics Manager. Câu hỏi: nếu cộng hoặc trừ X ngày vào ngày hứa giao thì late rate thành bao nhiêu? Tuyến nào cần sửa trước?
- Làm ngay bằng DAX (bản tạm cho đến khi có `ml.promise_whatif`):
  1. *Modeling → New parameter → Numeric range*: tên `Buffer Days`, min −5, max 7, increment 1, default 0, tick *Add slicer*.
     Power BI tạo bảng `Buffer Days` và measure `[Buffer Days Value]`.
  2. Measure `[Late Rate What-if]`, `[Avg Promised Days What-if]`, `[Late Rate Change]` (Phụ lục).
  3. Visual:
     - Card `Late Rate` so với `Late Rate What-if`.
     - Line chart: X = `Buffer Days[Buffer Days]`, Y = `[Late Rate What-if]`. Đây là đường cong đánh đổi giữa hứa nhanh và trễ nhiều.
     - Table tuyến như B3-4b, thêm cột `[Late Rate What-if]`.
  4. Đọc:
     - Kéo slider về **−5** (hứa nhanh hơn 5 ngày) để thấy late rate tăng bao nhiêu.
     - Vì đơn trung bình về sớm 11,9 ngày, rút 3–5 ngày có thể vẫn chấp nhận được với các tuyến Sudeste, nhưng không chấp nhận được với Nordeste.
     - Lọc theo `Customer Region` để thấy rõ khác biệt này.
- Chờ M3: `bi.v_order_late_risk` (điểm rủi ro trễ từng đơn) để đánh dấu tuyến rủi ro cao.

**B7. CRM Segments & Voucher Allocation**: CRM Manager. Cần toàn bộ M4 (`ml.customer_segment_history`, `ml.voucher_allocation`),
chưa làm được gì có nghĩa. Để trống trang, ghi "Chờ M4".

---

# Phần C — Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
| --- | --- | --- |
| Measure ra cùng một số ở mọi dòng của visual | Thiếu relationship giữa bảng trên trục và fact của measure, hoặc relationship đang inactive | Model view kiểm tra relationship (A4) |
| GMV bằng đúng Revenue incl. freight, hoặc GMV gồm cả đơn huỷ | Measure không lọc `Counts As Sale` | Dùng đúng measure ở Phụ lục |
| Late Rate theo tháng đầu / cuối 100 % hoặc 0 % | Thiếu filter `In Analysis Window` | A7 |
| Có cột `(Blank)` trên trục ngày giao | Đơn chưa giao (`delivered_date_key = -1`, 2 965 đơn) | Đúng thiết kế. Bỏ bằng filter "is not blank" nếu muốn |
| Có thành viên `unknown` / `-1` trong dim | Fact không khớp được thuộc tính (dưới 1 %, có test) | Đúng thiết kế. Giữ để tổng khớp |
| "Relationship ambiguous" khi tạo relationship | Có đường lọc thứ hai, ví dụ nối `Customer[first_order_date_key]` với Date | Xoá relationship thừa |
| Tỷ lệ trên visual khác card | Visual cộng tỷ lệ (kéo cột `Is Late` với Average) thay vì dùng measure | Luôn dùng measure `[Late Rate]`, không dùng implicit measure |
| Số seller quá lớn | `COUNTROWS(Seller)` hoặc Count of `seller_key` = số version | `[Sellers]` = DISTINCTCOUNT(Seller ID) |
| Map trống | Map visual bị tắt | *File → Options → Security → Use Map and Filled Map visuals*. Hoặc thay bằng bar chart |
| Refresh lỗi "password authentication failed" | Đổi `BI_READER_PASSWORD` nhưng chưa chạy lại dbt, hoặc Power BI nhớ mật khẩu cũ | Chạy `make build`. *Data source settings → Edit Permissions → Edit credentials* |
| Refresh lỗi "could not connect" | Docker / Postgres chưa chạy | `docker compose up -d postgres` |
| `DQ Latest` trống | Chưa chạy `make meta` sau build | `make meta` → Refresh |

---

# Phụ lục — Khối DAX tạo toàn bộ measure

Dán vào **DAX query view** → *Run*. Dòng kết quả dùng để so với A8.
Sau đó bấm **Update model with changes** để lưu measure vào bảng `_Measures`.
Định nghĩa gốc vẫn là `docs/kpi_dictionary.md`. Nếu sửa ở đây thì sửa cả bên đó.

Trước khi chạy:
- Phải tạo bảng `_Measures` (A6).
- Các measure What-if chỉ chạy được sau khi tạo parameter `Buffer Days` (B4). Nếu chưa tạo, xoá 3 measure cuối khỏi khối.

```dax
DEFINE
    // ===== Sales
    MEASURE '_Measures'[GMV] =
        CALCULATE ( SUM ( Sales[Item Price] ), KEEPFILTERS ( 'Order Status'[Counts As Sale] = TRUE () ) )
    MEASURE '_Measures'[Revenue incl Freight] =
        CALCULATE ( SUM ( Sales[Item Total] ), KEEPFILTERS ( 'Order Status'[Counts As Sale] = TRUE () ) )
    MEASURE '_Measures'[Items Sold] =
        CALCULATE ( SUM ( Sales[Item Count] ), KEEPFILTERS ( 'Order Status'[Counts As Sale] = TRUE () ) )
    MEASURE '_Measures'[Orders] =
        CALCULATE ( COUNTROWS ( Fulfillment ), KEEPFILTERS ( 'Order Status'[Counts As Sale] = TRUE () ) )
    MEASURE '_Measures'[AOV] =
        DIVIDE (
            CALCULATE ( SUM ( Fulfillment[Order Value] ), KEEPFILTERS ( 'Order Status'[Counts As Sale] = TRUE () ) ),
            [Orders]
        )
    MEASURE '_Measures'[Cancel Rate] =
        DIVIDE (
            CALCULATE ( COUNTROWS ( Fulfillment ), KEEPFILTERS ( 'Order Status'[Status Group] = "Cancelled" ) ),
            COUNTROWS ( Fulfillment )
        )
    MEASURE '_Measures'[Repeat Customer Rate] =
        VAR Buyers = FILTER ( VALUES ( Fulfillment[customer_key] ), [Orders] >= 1 )
        VAR Repeaters = FILTER ( Buyers, [Orders] >= 2 )
        RETURN DIVIDE ( COUNTROWS ( Repeaters ), COUNTROWS ( Buyers ) )
    MEASURE '_Measures'[Payment Value] = SUM ( Payment[Payment Value] )
    MEASURE '_Measures'[Avg Installments] = AVERAGE ( Payment[Installments] )
    // so sánh thời gian (cần Date đã Mark as date table)
    MEASURE '_Measures'[GMV PY] = CALCULATE ( [GMV], SAMEPERIODLASTYEAR ( 'Date'[Date] ) )
    MEASURE '_Measures'[GMV YoY %] = DIVIDE ( [GMV] - [GMV PY], [GMV PY] )
    MEASURE '_Measures'[Orders PY] = CALCULATE ( [Orders], SAMEPERIODLASTYEAR ( 'Date'[Date] ) )
    MEASURE '_Measures'[Orders YoY %] = DIVIDE ( [Orders] - [Orders PY], [Orders PY] )
    MEASURE '_Measures'[GMV PM] = CALCULATE ( [GMV], DATEADD ( 'Date'[Date], -1, MONTH ) )
    MEASURE '_Measures'[GMV MoM %] = DIVIDE ( [GMV] - [GMV PM], [GMV PM] )

    // ===== Logistics
    MEASURE '_Measures'[Delivered Orders] = SUM ( Fulfillment[Is Delivered] )
    MEASURE '_Measures'[Late Orders] = SUM ( Fulfillment[Is Late] )
    MEASURE '_Measures'[Late Rate] = DIVIDE ( [Late Orders], [Delivered Orders] )
    MEASURE '_Measures'[Late Share] =
        DIVIDE ( [Late Orders], CALCULATE ( [Late Orders], ALLSELECTED ( 'Seller Geo' ), ALLSELECTED ( 'Customer Geo' ) ) )
    MEASURE '_Measures'[Avg Delivery Days] = DIVIDE ( SUM ( Fulfillment[Delivery Lag (days)] ), [Delivered Orders] )
    MEASURE '_Measures'[Avg Promised Days] = AVERAGE ( Fulfillment[Promised Lag (days)] )
    MEASURE '_Measures'[Avg Delay Days] = AVERAGE ( Fulfillment[Delay Days] )
    MEASURE '_Measures'[Dispatch Late Rate] =
        DIVIDE ( SUM ( Fulfillment[Is Dispatch Late] ), SUM ( Fulfillment[Has Carrier Date] ) )
    MEASURE '_Measures'[Avg Approval Lag] = AVERAGE ( Fulfillment[Approval Lag (days)] )
    MEASURE '_Measures'[Avg Dispatch Lag] = AVERAGE ( Fulfillment[Dispatch Lag (days)] )
    MEASURE '_Measures'[Avg Transit Lag] = AVERAGE ( Fulfillment[Transit Lag (days)] )
    MEASURE '_Measures'[Avg Distance km] = AVERAGE ( Fulfillment[Distance (km)] )
    MEASURE '_Measures'[Delivered Orders by Delivery Date] =
        CALCULATE ( [Delivered Orders], USERELATIONSHIP ( Fulfillment[delivered_date_key], 'Date'[date_key] ) )

    // ===== Review
    MEASURE '_Measures'[Reviews] =
        CALCULATE ( SUM ( Review[Review Count] ), KEEPFILTERS ( Review[Is Latest For Order] = TRUE () ) )
    MEASURE '_Measures'[Avg Review Score] =
        DIVIDE (
            CALCULATE ( SUM ( Review[Score Sum] ), KEEPFILTERS ( Review[Is Latest For Order] = TRUE () ) ),
            [Reviews]
        )
    MEASURE '_Measures'[Low Score Rate] =
        DIVIDE (
            CALCULATE ( SUM ( Review[Is Low Score] ), KEEPFILTERS ( Review[Is Latest For Order] = TRUE () ) ),
            [Reviews]
        )
    // Review không nối trực tiếp với Fulfillment → chuyển danh sách Order ID bằng TREATAS
    MEASURE '_Measures'[Avg Score Late] =
        VAR LateOrders = CALCULATETABLE ( VALUES ( Fulfillment[Order ID] ), Fulfillment[Is Late] = 1 )
        RETURN CALCULATE ( [Avg Review Score], TREATAS ( LateOrders, Review[Order ID] ) )
    MEASURE '_Measures'[Avg Score On-time] =
        VAR OnTime = CALCULATETABLE ( VALUES ( Fulfillment[Order ID] ), Fulfillment[Is Delivered] = 1, Fulfillment[Is Late] = 0 )
        RETURN CALCULATE ( [Avg Review Score], TREATAS ( OnTime, Review[Order ID] ) )
    MEASURE '_Measures'[Low Score Rate Late] =
        VAR LateOrders = CALCULATETABLE ( VALUES ( Fulfillment[Order ID] ), Fulfillment[Is Late] = 1 )
        RETURN CALCULATE ( [Low Score Rate], TREATAS ( LateOrders, Review[Order ID] ) )

    // ===== Seller
    MEASURE '_Measures'[Seller Orders] = SUM ( 'Seller Month'[Orders] )
    MEASURE '_Measures'[Seller GMV] = SUM ( 'Seller Month'[GMV] )
    MEASURE '_Measures'[Seller Late Rate] =
        DIVIDE ( SUM ( 'Seller Month'[Late Orders] ), SUM ( 'Seller Month'[Delivered Orders] ) )
    MEASURE '_Measures'[Seller Avg Score] =
        DIVIDE ( SUM ( 'Seller Month'[Score Sum] ), SUM ( 'Seller Month'[Review Count] ) )
    MEASURE '_Measures'[Active Sellers] =
        AVERAGEX ( VALUES ( 'Date'[Month Start] ), CALCULATE ( SUM ( 'Seller Month'[Is Active] ) ) )
    MEASURE '_Measures'[Sellers] = DISTINCTCOUNT ( Seller[Seller ID] )
    MEASURE '_Measures'[At-risk Sellers Now] =
        CALCULATE ( DISTINCTCOUNT ( Seller[Seller ID] ), Seller[Is Current] = TRUE (), Seller[Seller Tier] = "At-risk" )
    MEASURE '_Measures'[Tier Changes] = CALCULATE ( COUNTROWS ( Seller ), KEEPFILTERS ( Seller[Version No] > 1 ) )
    MEASURE '_Measures'[Active Listings] = COUNTROWS ( 'Seller Product Activity' )

    // ===== Funnel
    MEASURE '_Measures'[Leads] = SUM ( 'Lead Funnel'[Lead Count] )
    MEASURE '_Measures'[Won Deals] = SUM ( 'Lead Funnel'[Is Won] )
    MEASURE '_Measures'[Leads With First Sale] = SUM ( 'Lead Funnel'[Has First Sale] )
    MEASURE '_Measures'[Lead Conversion] = DIVIDE ( [Won Deals], [Leads] )
    MEASURE '_Measures'[Avg Days To Close] = AVERAGE ( 'Lead Funnel'[Days To Close] )
    MEASURE '_Measures'[GMV 90d per Won Lead] =
        CALCULATE (
            DIVIDE ( SUM ( 'Lead Funnel'[GMV First 90 Days] ), SUM ( 'Lead Funnel'[Is Won] ) ),
            KEEPFILTERS ( 'Lead Funnel'[Has Full 90d Window] = 1 )
        )

    // ===== Data quality
    MEASURE '_Measures'[Tests Run] = COUNTROWS ( 'DQ Latest' )
    MEASURE '_Measures'[Test Pass Rate] = DIVIDE ( SUM ( 'DQ Latest'[Is Pass] ), [Tests Run] )
    MEASURE '_Measures'[Failed Tests] = [Tests Run] - SUM ( 'DQ Latest'[Is Pass] )
    MEASURE '_Measures'[Flagged Rows] = SUM ( 'DQ Issues'[Issue Rows] )
    MEASURE '_Measures'[Last Successful Run] =
        CALCULATE ( MAX ( 'ETL Runs'[Ended At] ), KEEPFILTERS ( 'ETL Runs'[Status] = "success" ) )

    // ===== What-if (chỉ sau khi tạo parameter Buffer Days ở B4)
    MEASURE '_Measures'[Late Rate What-if] =
        VAR b = [Buffer Days Value]
        RETURN DIVIDE (
            CALCULATE ( COUNTROWS ( Fulfillment ), Fulfillment[Is Delivered] = 1, Fulfillment[Delay Days] > b ),
            [Delivered Orders]
        )
    MEASURE '_Measures'[Avg Promised Days What-if] = [Avg Promised Days] + [Buffer Days Value]
    MEASURE '_Measures'[Late Rate Change] = [Late Rate What-if] - [Late Rate]

EVALUATE
ROW (
    "GMV", [GMV], "Orders", [Orders], "AOV", [AOV], "Late Rate", [Late Rate],
    "Cancel Rate", [Cancel Rate], "Avg Review Score", [Avg Review Score],
    "Avg Delivery Days", [Avg Delivery Days], "Dispatch Late Rate", [Dispatch Late Rate],
    "Repeat Customer Rate", [Repeat Customer Rate], "Lead Conversion", [Lead Conversion],
    "Avg Days To Close", [Avg Days To Close], "GMV 90d per Won Lead", [GMV 90d per Won Lead],
    "Seller Late Rate", [Seller Late Rate], "Avg Score Late", [Avg Score Late], "Avg Score On-time", [Avg Score On-time]
)
```

Kết quả mong đợi khi không lọc: GMV 13 494 400,74 · Orders 98 207 · AOV 137,41 · Late Rate 0,0677 · Cancel Rate 0,0124 ·
Avg Review Score 4,086 · Avg Delivery Days 12,56 · Dispatch Late Rate 0,0906 · Repeat Customer Rate 0,0304 ·
Lead Conversion 0,1053 · Avg Days To Close 48,5 · GMV 90d per Won Lead 514,97 · Seller Late Rate 0,0669 ·
Avg Score Late khoảng 2,27 · Avg Score On-time khoảng 4,29.

**Bảng phụ cho funnel (B6)**: *Modeling → New table*, dán:

```dax
Funnel Stage =
DATATABLE ( "Stage", STRING, "Stage Order", INTEGER,
    { { "1. MQL", 1 }, { "2. Won", 2 }, { "3. First sale", 3 } } )
```

Không tạo relationship cho bảng này. Sort `Stage` theo `Stage Order`. Measure:

```dax
Funnel Value =
SWITCH ( SELECTEDVALUE ( 'Funnel Stage'[Stage] ),
    "1. MQL", [Leads],
    "2. Won", [Won Deals],
    "3. First sale", [Leads With First Sale] )
```
