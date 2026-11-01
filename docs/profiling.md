# Profiling dữ liệu nguồn (S1)

> Người làm: **Minh Hiếu (TV2)**. Hạn: ngày 2 (CN 1/11/2026).
> Mỗi giả định: ghi query/notebook đã dùng, con số, kết luận, rồi cập nhật bảng mục 18 trong `CLAUDE.md`.

## Tổng quan nguồn

> Đo ngày 1/11/2026 trên schema `raw` (batch `20261101T091107_05e44c68`, mọi cột kiểu text). Query: [`docs/profiling/01_overview.sql`](profiling/01_overview.sql).
> Số dòng `raw` khớp số dòng CSV của từng file (log `load_raw`). "Rỗng" = null hoặc chuỗi rỗng sau trim.

| Bảng raw | Số dòng | Khoảng thời gian | Ghi chú |
| --- | --- | --- | --- |
| raw.orders | 99,441 | purchase 2016-09-04 → 2018-10-17 | `order_id` duy nhất, 1 `customer_id` / đơn. Theo năm: 2016 = 329, 2017 = 45,101, 2018 = 54,011. Đầu/cuối rất thưa: 2016-09 = 4, 2016-11 = 0, 2016-12 = 1, 2018-09 = 16, 2018-10 = 4 (2018-08 còn 6,512). Rỗng: approved_at 160, delivered_carrier 1,783, delivered_customer 2,965. `estimated_delivery_date` chỉ có ngày (giờ luôn 00:00:00), tới 2018-11-12. 775 đơn không có item, 1 đơn không có payment, 768 đơn không có review |
| raw.order_items | 112,650 | shipping_limit 2016-09-19 → 2020-04-09 | Khoá (order_id, order_item_id) duy nhất; 98,666 đơn có item. **4 dòng shipping_limit ≥ 2020-02** (ngoại lệ, kiểm ở S3). Mọi order_id đều có trong orders. Không cột nào rỗng |
| raw.order_payments | 103,886 | — (không có cột ngày) | Khoá (order_id, payment_sequential) duy nhất; 99,440 đơn (thiếu 1 đơn so với orders). Không cột nào rỗng. Giá trị payment_type / installments: xem A1 |
| raw.order_reviews | 99,224 | creation 2016-10-02 → 2018-08-31; answer 2016-10-07 → 2018-10-29 | Chỉ 98,410 review_id phân biệt: **789 review_id gắn nhiều đơn**, **547 đơn có nhiều review** (A2). `review_creation_date` gần như chỉ có ngày (99,139 / 99,224 dòng là 00:00:00). Rỗng: comment_title 87,658 (88%), comment_message 58,256 (59%); 3,852 message chứa xuống dòng |
| raw.customers | 99,441 | — | `customer_id` duy nhất, khớp 1–1 với orders; chỉ **96,096 `customer_unique_id`** (cơ sở cho A7). Zip 5 ký tự, 27 bang. Không cột nào rỗng |
| raw.sellers | 3,095 | — | `seller_id` duy nhất, mọi seller đều có ít nhất 1 item. 2,246 zip phân biệt, chỉ 23 / 27 bang có seller. Không cột nào rỗng |
| raw.products | 32,951 | — | `product_id` duy nhất, mọi product đều đã bán. 73 category; **610 product rỗng category** (đồng thời rỗng name/description length, photos_qty); 2 product rỗng kích thước/cân nặng. Cột tên sai chính tả `product_name_lenght`, `product_description_lenght` |
| raw.geolocation | 1,000,163 | — | Chỉ 19,015 zip prefix phân biệt (~53 dòng / zip) và 738,332 bộ (zip, lat, lng, city, state) phân biệt → nhiều điểm trùng hẳn. Zip 5 ký tự, 27 bang. Không cột nào rỗng. Ngoài khung Brazil / city có dấu: xem A3 |
| raw.product_category_name_translation | 71 | — | 71 category có bản dịch, tất cả đều được dùng trong products. Thiếu bản dịch: `pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos` (A4). File CSV có BOM UTF-8, `load_raw` đọc bằng `utf-8-sig` nên tên cột đúng |
| raw.mql | 8,000 | first_contact 2017-06-14 → 2018-05-31 | `mql_id` duy nhất. 10 giá trị origin (tính cả rỗng); **60 dòng rỗng origin** |
| raw.closed_deals | 842 | won 2017-12-05 → 2018-11-14 | `mql_id` và `seller_id` đều duy nhất; mọi mql_id có trong mql. **Chỉ 380 / 842 seller_id có trong sellers** (A6). 50 deal chốt sau 2018-08-31, 17 deal chốt sau đơn cuối cùng (2018-10-17) → không thể có `gmv_first_90_days`. Profile lead rất thưa: rỗng has_company 779, has_gtin 778, average_stock 776, declared_product_catalog_size 773, lead_behaviour_profile 177, business_type 10, lead_type 6, business_segment 1 |
| raw.br_holidays | 36 | 2016-01-01 → 2019-12-25 | Sinh bằng package `holidays` (9 ngày lễ quốc gia / năm × 4 năm), ngày duy nhất |
| raw.br_states | 27 | — | 27 bang (26 bang + DF), 5 vùng. Mọi mã bang trong customers, sellers, geolocation đều có trong br_states |
| raw.calendar_events | 52 | 2016-01-01 → 2019-12-25 | 36 `national_holiday` (trùng br_holidays) + 16 `retail_event` |

**Tóm tắt cho thiết kế**
- Cửa sổ 2017-01-01 → 2018-08-31 hợp lý: ngoài cửa sổ chỉ có 329 đơn năm 2016 và 20 đơn tháng 9–10/2018 (xác nhận chính thức ở A8).
- Không bảng raw nào trùng natural key → dedup ở staging chỉ cần cho replay/append (mục 9).
- Ngoại lệ cần rule ở S3: 4 item có shipping_limit năm 2020; 775 đơn không có item (fact cấp đơn sẽ có `item_count = 0`); 610 product không có category → `unknown`.
- Funnel thưa hơn dự kiến: 55% deal chốt có seller không xuất hiện trong dữ liệu đơn hàng; profile lead phần lớn rỗng (~92% với has_company / has_gtin / average_stock).

## Giả định cần xác nhận

| # | Giả định | Cách kiểm | Kết quả | Kết luận / rule staging |
| --- | --- | --- | --- | --- |
| A1 | Danh sách order_status, payment_type | `select x, count(*) group by 1` | | |
| A2 | review_id trùng trên nhiều order; order có nhiều review | | | |
| A3 | Geolocation nhiều điểm / zip, điểm ngoài Brazil, city có dấu | | | |
| A4 | Product thiếu category / thiếu bản dịch | Đã thấy: `pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos` không có bản dịch | | |
| A5 | Chênh Σ item_total vs Σ payment_value theo đơn → tolerance | | | |
| A6 | Tỷ lệ closed_deals.seller_id khớp sellers | | | |
| A7 | Tỷ lệ khách mua lặp (customer_unique_id ≥ 2 đơn) | | | |
| A8 | Cửa sổ phân tích 2017-01-01 → 2018-08-31 | số đơn theo tháng | | |
| A9 | Zip prefix mất số 0 đầu | độ dài zip | | |

## Phát hiện khác
