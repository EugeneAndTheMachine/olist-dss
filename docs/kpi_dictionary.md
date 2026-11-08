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

## P1 — Logistics (Cẩn)

| KPI | Định nghĩa nghiệp vụ | Công thức | Fact nguồn | Bộ lọc | Rule liên quan | DAX measure |
| --- | --- | --- | --- | --- | --- | --- |

## P2 — Regional market (Hiếu)

| KPI | Định nghĩa nghiệp vụ | Công thức | Fact nguồn | Bộ lọc | Rule liên quan | DAX measure |
| --- | --- | --- | --- | --- | --- | --- |

## P3 — Category (Vinh)

| KPI | Định nghĩa nghiệp vụ | Công thức | Fact nguồn | Bộ lọc | Rule liên quan | DAX measure |
| --- | --- | --- | --- | --- | --- | --- |
| P3 Category GMV / Orders / Items | Doanh số, số đơn, số item của category | Σ `gmv` / Σ `orders` / Σ `items` | `fact_category_month` | đơn bán (đã lọc trong fact) | BR-P3-2 | `P3 GMV = SUM(v_fact_category_month[gmv])` (tương tự orders, items) |
| P3 GMV share | Thị phần GMV của category trong bộ lọc hiện tại | GMV category / GMV mọi category | `fact_category_month` | cùng bộ lọc thời gian / bang | BR-P3-2 | `P3 GMV Share = DIVIDE([P3 GMV], CALCULATE([P3 GMV], ALL(v_dim_category)))` |
| P3 AOV | Giá trị TB mỗi đơn của category | Σ `gmv` / Σ `orders` | `fact_category_month` | — | BR-W6 | `P3 AOV = DIVIDE([P3 GMV], SUM(v_fact_category_month[orders]))` |
| P3 YoY growth (3 tháng) | Tăng trưởng 3 tháng gần nhất so với cùng kỳ năm trước | (GMV_3m − GMV_3m_LY) / GMV_3m_LY | `ml.category_opportunity` | toàn quốc; null khi < 30 đơn ở một trong hai cửa sổ | BR-K5, BR-P3-4 | đọc cột `yoy_growth` |
| P3 Relative growth | Tăng trưởng so với sàn; âm = mất thị phần | (1 + g_cat) / (1 + g_platform) − 1 | `ml.category_opportunity` | như YoY | BR-P3-4 | đọc cột `relative_growth` |
| P3 Share change | Thay đổi thị phần (điểm %) | share 3 tháng gần nhất − share cùng kỳ | `fact_category_month` | cùng bộ lọc | BR-P3-4 | `P3 Share Change` (DAX theo 2 cửa sổ của dim_date) |
| P3 Avg review score | Điểm TB, review mới nhất mỗi đơn | Σ `score_sum` / Σ `review_count` | `fact_category_month` | — | BR-K3, BR-P3-3 | `P3 Avg Score = DIVIDE(SUM(v_fact_category_month[score_sum]), SUM(v_fact_category_month[review_count]))` |
| P3 Low-score rate | Tỷ lệ review ≤ 2 | Σ `low_score_count` / Σ `review_count` | `fact_category_month` | — | BR-P3-6 | `P3 Low Score Rate = DIVIDE(SUM(v_fact_category_month[low_score_count]), SUM(v_fact_category_month[review_count]))` |
| P3 Late rate | Tỷ lệ đơn trễ trên đơn đã giao | Σ `late_orders` / Σ `delivered_orders` | `fact_category_month` | hiện khi ≥ 100 đơn delivered | BR-K2, BR-P3-5 | `P3 Late Rate = DIVIDE(SUM(v_fact_category_month[late_orders]), SUM(v_fact_category_month[delivered_orders]))` |
| P3 Freight ratio | Phí ship so với giá hàng (proxy lợi nhuận) | Σ `freight` / Σ `gmv` | `fact_category_month` | — | BR-P3-9 | `P3 Freight Ratio = DIVIDE(SUM(v_fact_category_month[freight]), [P3 GMV])` |
| P3 Seller HHI | Độ tập trung seller (0–1) | Σ (GMV seller / GMV category)², theo `seller_id`, 12 tháng | `ml.category_opportunity` | toàn quốc, 12 tháng gần nhất | BR-P3-8 | đọc cột `hhi` |
| P3 Active sellers | Số seller có bán | distinct `seller_id` | `fact_order_item` | đơn bán | BR-CW8-1 | `P3 Active Sellers = CALCULATE(DISTINCTCOUNT(v_fact_sales[seller_id]), v_dim_order_status[counts_as_sale] = 1)` |
| P3 Seasonality index | GMV tháng so với GMV TB tháng của năm | GMV tháng / TB GMV tháng trong năm | `fact_category_month` | theo nhóm | — | `P3 Seasonality Index` (DAX) |
