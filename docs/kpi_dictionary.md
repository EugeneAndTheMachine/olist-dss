# KPI dictionary

> Người làm: **Xuân Vinh (TV3)**, task F6. Bản đọc được của `implementation.md` mục 8 cho người dùng nghiệp vụ.
> Mọi DAX measure và mọi con số trong báo cáo phải khớp file này. Đổi định nghĩa → sửa cả `implementation.md` mục 8 trong cùng PR.
> Cập nhật: 02/11/2026. Cách dựng lớp `bi` và model Power BI: `docs/bi_layer.md`.

## 1. Nguyên tắc chung

1. **Tỷ lệ = Σ tử số / Σ mẫu số**, không bao giờ lấy trung bình của các tỷ lệ (vd. không AVERAGE late rate của từng tháng).
   Lý do: tháng ít đơn sẽ kéo lệch kết quả. Fact chỉ lưu tử số và mẫu số (cờ 0/1, `Score Sum`, `Review Count`), cộng được ở mọi mức.
2. **Đơn tính là bán** = `Order Status[Counts As Sale] = TRUE` (delivered, shipped, invoiced, processing, approved, created).
   Đơn canceled / unavailable không vào GMV, Orders, AOV.
3. **GMV không gồm phí ship.** Có ship thì dùng *Revenue incl. freight*.
4. **Review**: chỉ review mới nhất của mỗi đơn (`Is Latest For Order = TRUE`).
5. **Ngày mặc định = ngày mua** (relationship active). Xem theo ngày khác (giao, hứa giao, chốt deal…) thì dùng `USERELATIONSHIP` (mục 4).
6. **Seller tier**: lọc `Seller[Seller Tier]` = tier *lúc phát sinh sự kiện* (point-in-time, SCD2); `Seller[Current Tier]` = tier hôm nay.

Tên bảng trong DAX là tên đã đổi trong Power BI (bảng ở `docs/bi_layer.md` mục 5.1): `Sales` = `bi.v_fact_sales`, `Fulfillment` = `bi.v_fact_fulfillment`, …

## 2. Từ điển KPI

Cột **Giá trị tham chiếu** = kết quả SQL trên `bi.*` ngày 02/11/2026, **toàn bộ dữ liệu, không lọc**. Dùng để kiểm tra
measure DAX vừa viết: thả measure vào card không có slicer, số phải khớp (làm tròn).

### 2.1 Bán hàng (Commerce)

| KPI | Ý nghĩa nghiệp vụ | Công thức | Fact / cột | Giá trị tham chiếu |
| --- | --- | --- | --- | --- |
| GMV | Giá trị hàng đã bán (BRL), không gồm ship | Σ item_price, đơn counts_as_sale | `Sales[Item Price]` | 13 494 400,74 |
| Revenue incl. freight | Tiền khách trả cho hàng + ship | Σ item_total, đơn counts_as_sale | `Sales[Item Total]` | 15 735 527,03 |
| Orders | Số đơn tính là bán | COUNT đơn counts_as_sale | `Fulfillment` (đếm dòng) | 98 207 |
| AOV | Giá trị trung bình 1 đơn | Σ order_value / Orders | `Fulfillment[Order Value]` | 137,41 |
| Items sold | Số item bán | Σ item_count, đơn counts_as_sale | `Sales[Item Count]` | 112 101 |
| Cancel rate | Tỷ lệ đơn bị huỷ / không có hàng | đơn Status Group = Cancelled / tổng đơn | `Fulfillment` + `Order Status[Status Group]` | 1,24 % |
| Repeat customer rate | Tỷ lệ khách mua ≥ 2 đơn | khách có ≥ 2 đơn counts_as_sale / khách có ≥ 1 đơn | `Fulfillment[customer_key]` | 3,04 % (94 990 khách) |
| Payment value | Tổng tiền thanh toán (gồm ship, mọi trạng thái) | Σ payment_value | `Payment[Payment Value]` | 16 008 872,12 |
| Avg installments | Số kỳ trả góp trung bình | AVERAGE installments (non-additive) | `Payment[Installments]` | 2,85 |

### 2.2 Giao hàng (Logistics)

| KPI | Ý nghĩa nghiệp vụ | Công thức | Fact / cột | Giá trị tham chiếu |
| --- | --- | --- | --- | --- |
| Late rate | Tỷ lệ đơn giao sau ngày hứa | Σ is_late / Σ is_delivered | `Fulfillment[Is Late]`, `[Is Delivered]` | 6,77 % |
| Avg delivery days | Số ngày từ lúc mua đến lúc khách nhận | Σ delivery_lag / Σ is_delivered | `Fulfillment[Delivery Lag (days)]` | 12,56 |
| Avg promised days | Số ngày Olist hứa giao | AVERAGE promised_lag | `Fulfillment[Promised Lag (days)]` | 23,77 |
| Avg delay days | Giao sớm (âm) / trễ (dương) so với hứa | AVERAGE delay_days (chỉ đơn đã giao) | `Fulfillment[Delay Days]` | — |
| Dispatch late rate | Seller giao cho hãng vận chuyển trễ hạn | Σ is_dispatch_late / Σ has_carrier_date | `Fulfillment[Is Dispatch Late]`, `[Has Carrier Date]` | 9,06 % |
| Avg approval / dispatch / transit lag | Thời gian từng chặng | AVERAGE cột lag (bỏ null) | `Fulfillment[... Lag (days)]` | — |
| Avg distance | Khoảng cách seller ↔ khách | AVERAGE distance (non-additive) | `Fulfillment[Distance (km)]` | 601,2 km |

### 2.3 Trải nghiệm khách

| KPI | Ý nghĩa nghiệp vụ | Công thức | Fact / cột | Giá trị tham chiếu |
| --- | --- | --- | --- | --- |
| Avg review score | Điểm review trung bình (1–5) | Σ score_sum / Σ review_count, chỉ review mới nhất | `Review[Score Sum]`, `[Review Count]` | 4,086 |
| Low-score rate | Tỷ lệ review ≤ 2 sao | Σ is_low_score / Σ review_count, chỉ review mới nhất | `Review[Is Low Score]` | 14,69 % |

### 2.4 Seller (Seller Quality Manager)

| KPI | Ý nghĩa nghiệp vụ | Công thức | Fact / cột | Giá trị tham chiếu |
| --- | --- | --- | --- | --- |
| Seller late rate | Tỷ lệ đơn trễ tính trên seller | Σ late_orders / Σ delivered_orders | `Seller Month[Late Orders]`, `[Delivered Orders]` | 6,69 % |
| Seller avg score | Điểm review trung bình tính trên seller | Σ score_sum / Σ review_count | `Seller Month[Score Sum]`, `[Review Count]` | 4,099 |
| Active sellers | Số seller có ≥ 1 đơn trong tháng | Σ is_active trong 1 tháng; nhiều tháng → **trung bình theo tháng** | `Seller Month[Is Active]` | 808,6 / tháng (01/2017 → 08/2018) |
| Sellers | Số seller (không phải số version) | DISTINCTCOUNT seller_id | `Seller[Seller ID]` | — |
| Active listings | Số cặp seller × sản phẩm có bán trong tháng | COUNT dòng | `Seller Product Activity` | — |

Seller late rate (6,69 %) và Seller avg score (4,099) **khác** số cấp đơn (6,77 %, 4,086) là đúng thiết kế:
`fact_seller_month` tính trên cặp đơn × seller (đơn nhiều seller được tính cho mỗi seller), chỉ đơn counts_as_sale,
và cắt ở ANALYSIS_END. Trang 5 (seller) dùng số seller; trang 1, 3 dùng số cấp đơn. Không trộn hai loại trên một visual.

### 2.5 Funnel thu hút seller

| KPI | Ý nghĩa nghiệp vụ | Công thức | Fact / cột | Giá trị tham chiếu |
| --- | --- | --- | --- | --- |
| Leads | Số MQL | Σ lead_count | `Lead Funnel[Lead Count]` | 8 000 |
| Won deals | Số lead chốt thành seller | Σ is_won | `Lead Funnel[Is Won]` | 842 |
| Lead conversion | Tỷ lệ chốt | Σ is_won / Σ lead_count | | 10,53 % |
| Days to close | Số ngày từ liên hệ đầu tới chốt | AVERAGE days_to_close (bỏ 1 lead lỗi won_before_contact) | `Lead Funnel[Days To Close]` | 48,5 |
| GMV 90d per won lead | GMV seller tạo ra trong 90 ngày đầu | Σ gmv_first_90_days / Σ is_won, **chỉ lead có Has Full 90d Window = 1** | `Lead Funnel[GMV First 90 Days]` | 514,97 (667 lead) |

### 2.6 Chất lượng dữ liệu (trang 8)

| KPI | Ý nghĩa | Công thức | Nguồn | Giá trị tham chiếu |
| --- | --- | --- | --- | --- |
| Tests run | Số test dbt lần chạy gần nhất | COUNT dòng | `DQ Latest` | 269 |
| Test pass rate | | Σ is_pass / COUNT | `DQ Latest[Is Pass]` | 100 % |
| Flagged rows | Dòng có lỗi được giữ lại + gắn cờ | Σ issue_rows theo model | `DQ Issues[Issue Rows]` | 14 loại lỗi |
| Last successful run | Lần chạy gần nhất thành công | MAX ended_at với status = success | `ETL Runs[Ended At]` | — |

## 3. DAX measures

Đặt tất cả trong bảng `_Measures` (*Home → Enter data* → bảng rỗng tên `_Measures`, xoá cột mặc định sau khi có measure).
Format: tiền `#,0.00`; tỷ lệ `0.00%`; ngày `0.0`.

```dax
-- ===== Bán hàng
GMV =
CALCULATE ( SUM ( Sales[Item Price] ), KEEPFILTERS ( 'Order Status'[Counts As Sale] = TRUE () ) )

Revenue incl Freight =
CALCULATE ( SUM ( Sales[Item Total] ), KEEPFILTERS ( 'Order Status'[Counts As Sale] = TRUE () ) )

Items Sold =
CALCULATE ( SUM ( Sales[Item Count] ), KEEPFILTERS ( 'Order Status'[Counts As Sale] = TRUE () ) )

Orders =
CALCULATE ( COUNTROWS ( Fulfillment ), KEEPFILTERS ( 'Order Status'[Counts As Sale] = TRUE () ) )

AOV =
DIVIDE (
    CALCULATE ( SUM ( Fulfillment[Order Value] ), KEEPFILTERS ( 'Order Status'[Counts As Sale] = TRUE () ) ),
    [Orders]
)

Cancel Rate =
DIVIDE (
    CALCULATE ( COUNTROWS ( Fulfillment ), KEEPFILTERS ( 'Order Status'[Status Group] = "Cancelled" ) ),
    COUNTROWS ( Fulfillment )
)

Repeat Customer Rate =
VAR Buyers = FILTER ( VALUES ( Fulfillment[customer_key] ), [Orders] >= 1 )
VAR Repeaters = FILTER ( Buyers, [Orders] >= 2 )
RETURN DIVIDE ( COUNTROWS ( Repeaters ), COUNTROWS ( Buyers ) )

Payment Value = SUM ( Payment[Payment Value] )
Avg Installments = AVERAGE ( Payment[Installments] )

-- ===== Giao hàng
Delivered Orders = SUM ( Fulfillment[Is Delivered] )
Late Orders = SUM ( Fulfillment[Is Late] )
Late Rate = DIVIDE ( [Late Orders], [Delivered Orders] )
Avg Delivery Days = DIVIDE ( SUM ( Fulfillment[Delivery Lag (days)] ), [Delivered Orders] )
Avg Promised Days = AVERAGE ( Fulfillment[Promised Lag (days)] )
Avg Delay Days = AVERAGE ( Fulfillment[Delay Days] )
Dispatch Late Rate = DIVIDE ( SUM ( Fulfillment[Is Dispatch Late] ), SUM ( Fulfillment[Has Carrier Date] ) )
Avg Approval Lag = AVERAGE ( Fulfillment[Approval Lag (days)] )
Avg Dispatch Lag = AVERAGE ( Fulfillment[Dispatch Lag (days)] )
Avg Transit Lag = AVERAGE ( Fulfillment[Transit Lag (days)] )
Avg Distance km = AVERAGE ( Fulfillment[Distance (km)] )

-- Ví dụ role-playing date: đơn theo NGÀY GIAO thay vì ngày mua
Delivered Orders by Delivery Date =
CALCULATE ( [Delivered Orders], USERELATIONSHIP ( Fulfillment[delivered_date_key], 'Date'[date_key] ) )

-- ===== Review
Reviews =
CALCULATE ( SUM ( Review[Review Count] ), KEEPFILTERS ( Review[Is Latest For Order] = TRUE () ) )

Avg Review Score =
DIVIDE (
    CALCULATE ( SUM ( Review[Score Sum] ), KEEPFILTERS ( Review[Is Latest For Order] = TRUE () ) ),
    [Reviews]
)

Low Score Rate =
DIVIDE (
    CALCULATE ( SUM ( Review[Is Low Score] ), KEEPFILTERS ( Review[Is Latest For Order] = TRUE () ) ),
    [Reviews]
)

-- ===== Seller
Seller Late Rate = DIVIDE ( SUM ( 'Seller Month'[Late Orders] ), SUM ( 'Seller Month'[Delivered Orders] ) )
Seller Avg Score = DIVIDE ( SUM ( 'Seller Month'[Score Sum] ), SUM ( 'Seller Month'[Review Count] ) )
Seller GMV = SUM ( 'Seller Month'[GMV] )

-- semi-additive: trung bình các tháng, không cộng dồn
Active Sellers =
AVERAGEX ( VALUES ( 'Date'[Month Start] ), CALCULATE ( SUM ( 'Seller Month'[Is Active] ) ) )

Sellers = DISTINCTCOUNT ( Seller[Seller ID] )
Active Listings = COUNTROWS ( 'Seller Product Activity' )

-- ===== Funnel
Leads = SUM ( 'Lead Funnel'[Lead Count] )
Won Deals = SUM ( 'Lead Funnel'[Is Won] )
Lead Conversion = DIVIDE ( [Won Deals], [Leads] )
Avg Days To Close = AVERAGE ( 'Lead Funnel'[Days To Close] )

GMV 90d per Won Lead =
CALCULATE (
    DIVIDE ( SUM ( 'Lead Funnel'[GMV First 90 Days] ), SUM ( 'Lead Funnel'[Is Won] ) ),
    KEEPFILTERS ( 'Lead Funnel'[Has Full 90d Window] = 1 )
)

-- ===== Data quality
Tests Run = COUNTROWS ( 'DQ Latest' )
Test Pass Rate = DIVIDE ( SUM ( 'DQ Latest'[Is Pass] ), [Tests Run] )
Failed Tests = [Tests Run] - SUM ( 'DQ Latest'[Is Pass] )
Flagged Rows = SUM ( 'DQ Issues'[Issue Rows] )
Last Successful Run =
CALCULATE ( MAX ( 'ETL Runs'[Ended At] ), KEEPFILTERS ( 'ETL Runs'[Status] = "success" ) )
```

**Vì sao dùng `KEEPFILTERS`**: nếu người dùng chọn slicer `Order Status = canceled`, `CALCULATE(..., cột = TRUE)` không có
`KEEPFILTERS` sẽ **ghi đè** slicer và vẫn hiện GMV. Có `KEEPFILTERS` thì điều kiện được AND với slicer → GMV của đơn huỷ = trống, đúng nghĩa.

## 4. KPI theo ngày khác ngày mua

| Muốn xem theo | Relationship cần bật trong measure |
| --- | --- |
| Ngày giao khách | `USERELATIONSHIP ( Fulfillment[delivered_date_key], 'Date'[date_key] )` |
| Ngày hứa giao | `USERELATIONSHIP ( Fulfillment[estimated_date_key], 'Date'[date_key] )` |
| Ngày giao hãng vận chuyển | `USERELATIONSHIP ( Fulfillment[carrier_date_key], 'Date'[date_key] )` |
| Ngày trả lời review | `USERELATIONSHIP ( Review[review_answer_date_key], 'Date'[date_key] )` |
| Ngày chốt deal | `USERELATIONSHIP ( 'Lead Funnel'[won_date_key], 'Date'[date_key] )` |
| Ngày bán đầu tiên của seller mới | `USERELATIONSHIP ( 'Lead Funnel'[first_sale_date_key], 'Date'[date_key] )` |
