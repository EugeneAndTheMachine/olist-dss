# Profiling dữ liệu nguồn (S1)

> Task S1 (TV2). Chạy ngày 01/11/2026 trên schema `raw` (1 batch, nạp từ `data/raw/`).
> Mọi con số tái lập được bằng `docs/profiling.sql`:
> `docker compose exec -T postgres psql -U olist -d olist_dw < docs/profiling.sql`
> Kết luận đã cập nhật vào `implementation.md` mục 1.3 và mục 18.

## Tổng quan nguồn

| Bảng raw | Số dòng | Khoá phân biệt | Khoảng thời gian | Ghi chú |
| --- | ---: | ---: | --- | --- |
| raw.orders | 99 441 | 99 441 order_id | purchase 2016-09-04 → 2018-10-17 | 8 trạng thái; 2016 và 09–10/2018 rất thưa (A8) |
| raw.order_items | 112 650 | 112 650 (order_id, order_item_id) | — | TB 1,14 item/đơn, tối đa 21; 1 278 đơn (1,3%) có > 1 seller |
| raw.order_payments | 103 886 | 103 886 (order_id, payment_sequential) | — | 5 payment_type, trả góp 0–24 kỳ |
| raw.order_reviews | 99 224 | 98 410 review_id | — | review_id lặp trên nhiều đơn (A2) |
| raw.customers | 99 441 | 99 441 customer_id / 96 096 customer_unique_id | — | 1 customer_id / đơn; 27 bang |
| raw.sellers | 3 095 | 3 095 | — | 23 bang |
| raw.products | 32 951 | 32 951 | — | 610 thiếu category (A4) |
| raw.geolocation | 1 000 163 | 19 015 zip prefix | — | ~52,6 điểm / zip (A3) |
| raw.product_category_name_translation | 71 | 71 | — | thiếu 2 category so với products |
| raw.mql | 8 000 | 8 000 mql_id | first_contact 2017-06-14 → 2018-05-31 | |
| raw.closed_deals | 842 | 842 mql_id | won_date 2017-12-05 → 2018-11-14 | won_date vượt quá dữ liệu đơn hàng (A6) |
| raw.br_states | 27 | — | — | khớp 100% mã bang của customers và sellers |
| raw.calendar_events | 52 | — | 2016-01-01 → 2019-12-25 | 36 national_holiday + 16 retail_event |
| raw.br_holidays | 36 | — | 2016-01-01 → 2019-12-25 | khớp phạm vi `dim_date` |

Số dòng raw = số dòng CSV gốc của Kaggle (không mất / nhân đôi dòng khi nạp). Ô trống trong CSV được nạp thành `NULL` (không phải chuỗi rỗng).

## Giả định cần xác nhận

| # | Giả định | Kết quả | Kết luận / rule staging |
| --- | --- | --- | --- |
| A1 | Danh sách order_status, payment_type | **order_status**: delivered 96 478, shipped 1 107, canceled 625, unavailable 609, invoiced 314, processing 301, created 5, approved 2 — đúng 8 giá trị trong seed `order_status_map`. **payment_type**: credit_card 76 795, boleto 19 784, voucher 5 775, debit_card 1 529, not_defined 3. 3 dòng `not_defined` đều thuộc đơn canceled, value = 0. `payment_installments = 0` ở 2 dòng (đơn delivered, credit_card); tối đa 24 kỳ | **Xác nhận**. Seed `order_status_map` giữ nguyên. Giữ `not_defined` như 1 payment_type (accepted_values gồm 5 giá trị). `installments 0 → 1`. Band `11+` bao 11–24 |
| A2 | review_id trùng trên nhiều order; order có nhiều review | 789 review_id gắn với > 1 đơn; 547 đơn có > 1 review (202 đơn trong đó có điểm khác nhau); 768 đơn không có review | **Xác nhận**. Khoá `fact_review` = (review_id, order_id). `is_latest_for_order` là bắt buộc để KPI điểm review không bị đếm trùng. Đơn không review → không có dòng trong fact_review (không phải điểm 0) |
| A3 | Geolocation nhiều điểm / zip, điểm ngoài Brazil, city có dấu | ~52,6 điểm / zip. 42 điểm (21 zip) nằm ngoài bbox Brazil (lat −34…5,5; lng −74…−34); 5 zip **toàn bộ** điểm nằm ngoài → lat/lng null. 8 zip có > 1 bang. City không đồng nhất: 8 011 giá trị thô → 5 969 sau `lower(unaccent())` (vd `sao paulo` 135 800 dòng, `são paulo` 24 918 dòng); 73 337 dòng có dấu. Extension `unaccent` đã có sẵn trong DB. 157 zip của customers (278 khách) và 7 seller **không có** trong geolocation | **Xác nhận**. Gộp 1 dòng / zip: mean lat/lng của điểm trong bbox, city/state = mode. Dùng `unaccent` của Postgres (không cần Python). `dim_geography` phải lấy hợp tập zip geolocation ∪ customers ∪ sellers như thiết kế, nếu không 278 khách / 7 seller rơi vào unknown |
| A4 | Product thiếu category / thiếu bản dịch | 610 product không có category (1 603 item = 1,4% item). 13 product thuộc 2 category không có bản dịch: `portateis_cozinha_e_preparadores_de_alimentos` (10), `pc_gamer` (3). 2 product thiếu cân nặng và kích thước; 4 product nặng 0 g. Seed `category_group` phủ đủ 73 category trong products + `unknown` | **Xác nhận**. category null → `unknown`; thiếu bản dịch → giữ tên PT. Cân nặng 0 → null (không tính vào weight_band). Seed `category_group` không cần sửa |
| A5 | Chênh Σ item_total vs Σ payment_value theo đơn → tolerance | Trên 98 665 đơn có cả item và payment: 98 362 lệch ≤ 0,01 BRL; 54 lệch 0,01–1 BRL; 34 lệch 1 BRL–5%; 216 lệch > 5%. Toàn bộ: Σ payment 16 008 872 > Σ item_total 15 843 553 (+1,0%, chủ yếu do lãi trả góp và voucher). 775 đơn không có item (unavailable 603, canceled 164, created 5, invoiced 2, shipped 1); 1 đơn không có payment | **Tolerance: \|Σpayment − Σitem_total\| ≤ max(1 BRL, 1% item_total)** → 99,75% đơn đạt. Test reconciliation để `severity: warn`, chỉ áp cho đơn có cả item và payment. Đơn không có item vẫn có dòng trong `fact_order_fulfillment` (item_count = 0, order_value = 0) |
| A6 | Tỷ lệ closed_deals.seller_id khớp sellers | 842 deal, 100% mql_id khớp `mql`. Chỉ **380 / 842 (45,1%)** seller_id có trong sellers, và cả 380 đều có đơn. 327 seller có đơn trong 90 ngày sau won_date. won_date kéo dài tới 2018-11-14, sau khi dữ liệu đơn hàng kết thúc → chỉ 667 deal có đủ cửa sổ 90 ngày trước 2018-08-31. Conversion tổng 842 / 8 000 = 10,5%. origin: 1 099 `unknown` + 60 null | **Xác nhận**: 462 seller chốt deal không có trong sellers → `dim_seller` phải gồm sellers ∪ closed_deals (has_sales = false, tier Unscored). `gmv_first_90_days` chỉ có nghĩa khi `won_date + 90 ≤ ANALYSIS_END`; cần thêm cờ `has_full_90d_window` để không so sánh kênh trên cửa sổ bị cắt. origin null → `unknown` |
| A7 | Tỷ lệ khách mua lặp (customer_unique_id ≥ 2 đơn) | 96 096 khách, 2 997 có ≥ 2 đơn = **3,12%** (chỉ tính đơn delivered: 3,00%); tối đa 17 đơn / khách | **Xác nhận** mua lặp rất thấp → giữ hướng CRM theo segment trải nghiệm + uplift giả định (mục 1.3). Không đủ positive để học propensity mua lại một cách tin cậy |
| A8 | Cửa sổ phân tích 2017-01-01 → 2018-08-31 | 2016: chỉ 329 đơn (09/2016: 4, 10/2016: 324, **11/2016: 0**, 12/2016: 1). 2017-01 → 2018-08: 800 → 7 544 đơn/tháng, liên tục, đỉnh 11/2017 (Black Friday). 09/2018: 16 đơn, 10/2018: 4 đơn, 0 đơn delivered | **Xác nhận**: `ANALYSIS_START = 2017-01-01`, `ANALYSIS_END = 2018-08-31` → 20 điểm tháng cho forecast, 99 092 đơn (99,6%) trong cửa sổ. Dữ liệu ngoài cửa sổ vẫn nạp vào dw, chỉ lọc ở KPI chuỗi thời gian / ML |
| A9 | Zip prefix mất số 0 đầu | Trong raw (text) mọi zip đều đúng 5 ký tự; 23 995 khách có zip bắt đầu bằng `0` | **Không bị mất** vì load_raw nạp dạng text. Vẫn giữ `lpad(zip, 5, '0')` trong staging để phòng nguồn đọc bằng pandas/Excel |

## Phát hiện khác (ảnh hưởng thiết kế)

1. **Late rate phụ thuộc cách so sánh.** Trên 96 470 đơn delivered có ngày giao: so theo **ngày** (`delivered::date > estimated::date`, định nghĩa KPI) → **6,77%**; so theo timestamp → 8,11%. `order_estimated_delivery_date` không có phần giờ (luôn 00:00), nên so timestamp sẽ coi đơn giao trong ngày hứa là trễ. Đây đúng là ví dụ "hai quản lý hai con số" → giữ định nghĩa so theo ngày ở mục 8.
2. **Mốc thời gian không đơn điệu.** Không đơn nào giao trước ngày mua (rule "delivered < purchase" trong mục 9 không bắt được dòng nào, vẫn giữ làm test). Nhưng: 1 359 đơn có `carrier_date < approved_at` (dispatch_lag âm), 166 đơn có `carrier_date < purchase`, 23 đơn có `delivered < carrier` (transit_lag âm). Rule đề xuất: giữ nguyên timestamp, thêm cờ `_dq_issue`, đặt lag âm tương ứng = null để không kéo lệch trung bình; ghi số dòng vào `meta.dq_results` (warn).
3. **Trạng thái và ngày giao không luôn khớp.** 8 đơn `delivered` thiếu ngày giao; 6 đơn `canceled` lại có ngày giao. Định nghĩa `is_delivered` (status = delivered **và** có ngày giao) xử lý đúng cả hai trường hợp. 160 đơn thiếu `approved_at` (141 canceled, 14 delivered, 5 created) → approved_date_key = −1.
4. **Thời gian giao.** Trung bình 12,6 ngày (trung vị 10,2) nhưng hứa trung bình 23,7 ngày → Olist hứa rất dư. Đây là cơ sở cho what-if "thắt ngày hứa" (M3): có nhiều dư địa rút ngắn ngày hứa trước khi late rate tăng mạnh.
5. **Đơn nhiều seller hiếm** (1 278 đơn, 1,3%) → rule primary seller (seller của item giá cao nhất) ảnh hưởng nhỏ đến KPI cấp đơn.
6. **Hiệu chỉnh tier seller (cho S6).** Đơn / seller / tháng: p50 = 2, p75 = 6, p90 = 13, p99 ≈ 63. Late rate của seller có ≥ 20 đơn đã giao (804 seller): p50 = 5,3%, p75 = 9,1%, p90 = 13,0%; 50 seller (6,2%) ≥ 15%. → Ngưỡng At-risk `late_rate_3m ≥ 0.15` hợp lý (bắt khoảng 6% seller). Gold `orders_3m ≥ 50` sẽ hiếm (chỉ seller top ~5%), chấp nhận được vì Gold là hạng khen thưởng; TV2 có thể hạ xuống 30 nếu muốn tier phân bố đều hơn.
7. **shipping_limit_date bất thường** (phát hiện khi test FK của fact_order_item): 4 item thuộc 3 đơn mua 03–05/2017 có hạn giao cho hãng vận chuyển năm 2020. Rule: ngày ngoài phạm vi `dim_date` (2016–2019) → null + `_dq_issue = shipping_limit_out_of_range`, nếu không `is_dispatch_late` của các đơn này luôn = 0.
8. **Tiền:** không có giá trị âm. 6 dòng voucher value = 0 và 3 dòng not_defined = 0 → giữ, không ảnh hưởng tổng.

## Việc kéo theo

| Việc | Ở đâu | Người làm |
| --- | --- | --- |
| Rule staging mục 9 bổ sung: lag âm → null + `_dq_issue`; cân nặng 0 → null; origin null → `unknown` | `implementation.md` mục 9 → model `stg_*` | S3 |
| Test reconciliation A5 với tolerance max(1 BRL, 1%), severity warn | `tests/` | F5 |
| Cờ `has_full_90d_window` trong `fact_lead_funnel` | `implementation.md` mục 7.5 | S5 |
| Cửa sổ phân tích: đã có sẵn trong `dbt_project.yml` (`analysis_start`, `analysis_end`), khớp kết luận A8 | — | — |
