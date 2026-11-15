# KPI dictionary

> Định nghĩa dùng chung cho mọi DAX measure và mọi con số trong báo cáo. Viết KPI ở đây **trước** khi làm view `bi`
> và measure. Danh sách KPI đích: `docs/refactor_plan.md` mục 5. Câu hỏi cần chốt: `docs/rebuild_guide.md` mục 5 (BR-K*).
> Mỗi mục do người được ghi chú sửa (`docs/PROJECT_PLAN.md` 2.5). Tỷ lệ luôn = Σ tử số / Σ mẫu số, không lưu % trong fact.

Cột: **KPI** · **Định nghĩa nghiệp vụ** · **Công thức** (tử / mẫu) · **Fact nguồn** · **Bộ lọc** · **Rule liên quan** · **DAX measure**.

---

## Chung (owner của fact chứa KPI: C-W8, C-W9, C-W10)

| KPI | Định nghĩa nghiệp vụ | Công thức | Fact nguồn | Bộ lọc | Rule liên quan | DAX measure |
| --- | --- | --- | --- | --- | --- | --- |
| GMV | Giá trị hàng bán, không gồm phí ship | Σ `item_price` | `fact_order_item` | `dim_order_status.counts_as_sale = 1` | BR-K1, BR-CW8-2 | `GMV = CALCULATE(SUM(v_fact_sales[item_price]), v_dim_order_status[counts_as_sale] = 1)` |
| Orders | Số đơn có ít nhất 1 item bán | distinct `order_id` | `fact_order_item` | như GMV | BR-K1 | `Orders = CALCULATE(DISTINCTCOUNT(v_fact_sales[order_id]), v_dim_order_status[counts_as_sale] = 1)` |
| Items | Số item bán | Σ `item_count` | `fact_order_item` | như GMV | BR-K1 | `Items = CALCULATE(SUM(v_fact_sales[item_count]), v_dim_order_status[counts_as_sale] = 1)` |
| AOV | Giá trị trung bình mỗi đơn | GMV / Orders | `fact_order_item` | như GMV | BR-W6 | `AOV = DIVIDE([GMV], [Orders])` |
| Avg review score | Điểm review trung bình, review mới nhất mỗi đơn | Σ `score_sum` / Σ `review_count` | `fact_review` | `is_latest_for_order = 1` | BR-K3, BR-CS7-2 | `Avg Review Score = CALCULATE(DIVIDE(SUM(v_fact_review[score_sum]), SUM(v_fact_review[review_count])), v_fact_review[is_latest_for_order] = 1)` |
| Low-score rate | Tỷ lệ review điểm ≤ 2 | Σ `is_low_score` / Σ `review_count` | `fact_review` | `is_latest_for_order = 1` | BR-K3, BR-P3-6 | `Low Score Rate = CALCULATE(DIVIDE(SUM(v_fact_review[is_low_score]), SUM(v_fact_review[review_count])), v_fact_review[is_latest_for_order] = 1)` |
| Delivered orders | Số đơn đã giao thành công cho khách | $\sum \text{is\_delivered}$ | `fact_order_fulfillment` (`v_fact_fulfillment`) | — | BR-O2, BR-W11 | `Delivered Orders = SUM(v_fact_fulfillment[Is Delivered])` |
| Late rate | Tỷ lệ đơn giao trễ trên tổng số đơn đã giao | $\sum \text{is\_late} / \sum \text{is\_delivered}$ | `fact_order_fulfillment` (`v_fact_fulfillment`) | `is_delivered = 1` (tự động qua mẫu số) | BR-O3, BR-K2 | `Late Rate = DIVIDE(SUM(v_fact_fulfillment[Is Late]), [Delivered Orders])` |
| Avg delivery days | Thời gian giao hàng trung bình từ lúc đặt tới lúc khách nhận (ngày) | $\sum \text{delivery\_lag} / \sum \text{is\_delivered}$ | `fact_order_fulfillment` (`v_fact_fulfillment`) | `is_delivered = 1` | BR-O2, BR-P1-1 | `Avg Delivery Days = DIVIDE(SUM(v_fact_fulfillment[Delivery Lag (days)]), [Delivered Orders])` |
| Dispatch late rate | Tỷ lệ đơn seller bàn giao cho carrier trễ hơn hạn `shipping_limit_date` | $\sum \text{is\_dispatch\_late} / \sum \text{has\_carrier\_date}$ | `fact_order_fulfillment` (`v_fact_fulfillment`) | `has_carrier_date = 1` | BR-P1-1 | `Dispatch Late Rate = DIVIDE(SUM(v_fact_fulfillment[Is Dispatch Late]), SUM(v_fact_fulfillment[Has Carrier Date]))` |
| Cancel rate | Tỷ lệ đơn bị huỷ hoặc không có hàng trên tổng số đơn | $\text{COUNT}(\text{status\_group = Cancelled}) / \text{COUNT}(\text{all orders})$ | `fact_order_fulfillment` (`v_fact_fulfillment`) | — | BR-K1, BR-O1 | `Cancel Rate = DIVIDE(CALCULATE(COUNTROWS(v_fact_fulfillment), v_dim_order_status[Status Group] = "Cancelled"), COUNTROWS(v_fact_fulfillment))` |

## P1 — Logistics (Cẩn)

| KPI | Định nghĩa nghiệp vụ | Công thức | Fact nguồn | Bộ lọc | Rule liên quan | DAX measure |
| --- | --- | --- | --- | --- | --- | --- |
| Late rate (area) | Tỷ lệ đơn giao trễ tới khách trong khu vực (bang / zip_prefix_2 / geo_cell) | $\sum \text{is\_late} / \sum \text{is\_delivered}$ (hoặc $\sum \text{late\_orders} / \sum \text{delivered\_orders}$ trên `fact_geo_month`) | `fact_order_fulfillment` / `fact_geo_month` | Khi xếp hạng khu vực/tuyến: $\sum \text{is\_delivered} \ge 20$ | BR-O3, BR-K2, BR-K6 | `P1 Area Late Rate = IF([Delivered Orders] >= 20, [Late Rate], BLANK())` |
| Late volume | Tổng số đơn giao trễ tuyệt đối trong khu vực | $\sum \text{is\_late}$ | `fact_order_fulfillment` (`v_fact_fulfillment`) | — | BR-O3, BR-W11 | `P1 Late Volume = SUM(v_fact_fulfillment[Is Late])` |
| Late density | Mật độ đơn giao trễ trên một ô lưới $0.5^\circ \times 0.5^\circ$ mỗi tháng (đo mức độ tập trung không gian để đặt kho) | $\sum \text{is\_late} / \text{DISTINCTCOUNT}(\text{year\_month})$ theo `geo_cell_id` của khách | `fact_order_fulfillment` join `dim_geography` (`v_dim_customer_geo`) | `In Analysis Window = TRUE`, `geo_cell_id IS NOT NULL` | BR-K4, BR-W4 | `P1 Late Density = DIVIDE(SUM(v_fact_fulfillment[Is Late]), DISTINCTCOUNT(v_dim_date[Year Month]))` |
| Avg delay of late orders | Mức độ trễ trung bình (ngày) của riêng các đơn bị giao trễ | $\sum_{\text{is\_late}=1} \text{delay\_days} / \sum \text{is\_late}$ | `fact_order_fulfillment` (`v_fact_fulfillment`) | `is_late = 1` | BR-O3 | `P1 Avg Delay When Late = DIVIDE(CALCULATE(SUM(v_fact_fulfillment[Delay Days]), v_fact_fulfillment[Is Late] = 1), [P1 Late Volume])` |
| Transit share of delivery time | Tỷ trọng thời gian nằm ở khâu vận chuyển của carrier so với tổng thời gian giao (phân biệt nghẽn do carrier vs seller) | $\sum \text{transit\_lag} / \sum \text{delivery\_lag}$ | `fact_order_fulfillment` (`v_fact_fulfillment`) | `is_delivered = 1`, `transit_lag IS NOT NULL` | BR-P1-1 | `P1 Transit Share = DIVIDE(SUM(v_fact_fulfillment[Transit Lag (days)]), SUM(v_fact_fulfillment[Delivery Lag (days)]))` |
| Avg seller–customer distance | Khoảng cách đường chim bay trung bình (km) giữa zip seller và zip khách | $\sum \text{seller\_customer\_distance\_km} / \text{COUNT}(\text{seller\_customer\_distance\_km})$ | `fact_order_fulfillment` (`v_fact_fulfillment`) | `Distance (km) IS NOT NULL` | BR-P1-1 | `P1 Avg Distance (km) = AVERAGE(v_fact_fulfillment[Distance (km)])` |
| Review gap late vs on-time | Độ sụt giảm điểm đánh giá trung bình giữa đơn giao đúng hẹn và đơn giao trễ (chi phí chất lượng của giao trễ) | $\text{Avg Score}(\text{is\_late}=0) - \text{Avg Score}(\text{is\_late}=1)$ | `fact_review` join `fact_order_fulfillment` | `is_delivered = 1`, `is_latest_for_order = 1` | BR-O3, BR-K3 | `P1 Review Gap Late vs OnTime = CALCULATE([Avg Review Score], v_fact_fulfillment[Is Delivered] = 1, v_fact_fulfillment[Is Late] = 0) - CALCULATE([Avg Review Score], v_fact_fulfillment[Is Delivered] = 1, v_fact_fulfillment[Is Late] = 1)` |

## P2 — Regional market (Hiếu)

Khu vực = thuộc tính của `v_dim_customer_geo` (region → state → zip_prefix_2 → zip_prefix_3 → zip) nối `v_fact_geo_month[geo_key]`.
Tử số và mẫu số của mọi tỷ lệ cùng lấy trong `fact_geo_month`, nên Σ khớp KPI chung (`assert_reconcile_geo_month`).

| KPI | Định nghĩa nghiệp vụ | Công thức | Fact nguồn | Bộ lọc | Rule liên quan | DAX measure |
| --- | --- | --- | --- | --- | --- | --- |
| Market size (GMV) | GMV do khách trong khu vực đặt (không gồm ship) | Σ `gmv_placed` | `fact_geo_month` | — | BR-K1, BR-P2-1, BR-P2-2 | `P2 Market Size = SUM(v_fact_geo_month[gmv_placed])` |
| Orders placed | Số đơn bán của khách trong khu vực | Σ `orders_placed` | `fact_geo_month` | — | BR-K1, BR-P2-1 | `P2 Orders Placed = SUM(v_fact_geo_month[orders_placed])` |
| Active customers | Số khách có đơn trong tháng, trung bình theo tháng của kỳ chọn | trung bình theo tháng của Σ `customers_active` | `fact_geo_month` | — | BR-P2-7 | `P2 Active Customers = AVERAGEX(VALUES(v_fact_geo_month[month_date_key]), CALCULATE(SUM(v_fact_geo_month[customers_active])))` |
| New customers | Số khách mua lần đầu, ở khu vực của đơn đầu tiên | Σ `customers_new` | `fact_geo_month` | — | BR-P2-4 | `P2 New Customers = SUM(v_fact_geo_month[customers_new])` |
| Active sellers | Số seller có bán trong tháng, trung bình theo tháng của kỳ chọn | trung bình theo tháng của Σ `sellers_active` | `fact_geo_month` | — | BR-P2-7 | `P2 Active Sellers = AVERAGEX(VALUES(v_fact_geo_month[month_date_key]), CALCULATE(SUM(v_fact_geo_month[sellers_active])))` |
| Customers per seller | Áp lực cầu lên nguồn cung tại chỗ | Active customers / Active sellers | `fact_geo_month` | khu vực ≥ 20 đơn (BR-P2-6) | BR-P2-6, BR-P2-7 | `P2 Customers per Seller = DIVIDE([P2 Active Customers], [P2 Active Sellers])` |
| Local fulfilment share | Tỷ lệ đơn được seller cùng bang phục vụ | Σ `orders_local` / Σ `orders_placed` | `fact_geo_month` | khu vực ≥ 20 đơn | BR-P2-3, BR-P2-6 | `P2 Local Share = DIVIDE(SUM(v_fact_geo_month[orders_local]), SUM(v_fact_geo_month[orders_placed]))` |
| Supply gap (BRL) | GMV khu vực mua từ seller ngoài bang | Σ `gmv_placed` − Σ `gmv_local` | `fact_geo_month` | — | BR-P2-3 | `P2 Supply Gap = SUM(v_fact_geo_month[gmv_placed]) - SUM(v_fact_geo_month[gmv_local])` |
| Orders per 1,000 inhabitants | Mức độ dùng TMĐT, chỉ ở cấp bang trở lên | Σ `orders_placed` / `state_population` × 1 000 | `fact_geo_month`, `v_dim_state` | cấp bang / vùng; kỳ 12 tháng 2017-09 … 2018-08 | BR-W12, BR-P2-8 | `P2 Orders per 1000 = DIVIDE([P2 Orders Placed], SUM(v_dim_state[state_population])) * 1000` |
| Area growth | GMV 3 tháng gần nhất so với cùng 3 tháng năm trước (YoY) | (GMV_3m − GMV_3m_ly) / GMV_3m_ly | `fact_geo_month` | ≥ 30 đơn ở cả hai cửa sổ, nếu không → trống | BR-K5, BR-P2-5 | `P2 Area Growth = VAR cur = CALCULATE([P2 Market Size], DATESINPERIOD(v_dim_date[Date], MAX(v_dim_date[Date]), -3, MONTH)) VAR ly = CALCULATE([P2 Market Size], DATESINPERIOD(v_dim_date[Date], EDATE(MAX(v_dim_date[Date]), -12), -3, MONTH)) VAR ok = CALCULATE([P2 Orders Placed], DATESINPERIOD(v_dim_date[Date], MAX(v_dim_date[Date]), -3, MONTH)) >= 30 && CALCULATE([P2 Orders Placed], DATESINPERIOD(v_dim_date[Date], EDATE(MAX(v_dim_date[Date]), -12), -3, MONTH)) >= 30 RETURN IF(ok, DIVIDE(cur - ly, ly))` |

Late rate theo khu vực dùng KPI *Late rate (area)* của P1; trên `fact_geo_month` cho cùng số (Σ `late_orders` / Σ `delivered_orders`).

## P3 — Category (Vinh)

| KPI | Định nghĩa nghiệp vụ | Công thức | Fact nguồn | Bộ lọc | Rule liên quan | DAX measure |
| --- | --- | --- | --- | --- | --- | --- |
