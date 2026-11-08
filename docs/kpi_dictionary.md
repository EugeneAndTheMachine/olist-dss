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
