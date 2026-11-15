# Business rules — sổ quyết định nghiệp vụ

> Mỗi rule nghiệp vụ được chốt ở đây **trước** khi code. Câu hỏi và số liệu tham khảo: `docs/rebuild_guide.md`
> (mã BR-S*, BR-W*, BR-K*). Cách chia owner: `docs/PROJECT_PLAN.md`.
> Mỗi mục chỉ do **owner của phần đó** sửa (tránh conflict khi merge). Rule chung (mục *Chung*) chốt cùng nhau ở kickoff.
> Khi đổi một rule đã chốt: sửa dòng, ghi ngày vào cột cuối, báo mọi consumer (PROJECT_PLAN 2.4).

Cột: **ID** (mã BR) · **Câu hỏi** · **Bằng chứng** (profiling / query) · **Lựa chọn** · **Quyết định** ·
**Code ở đâu** (model / seed / macro) · **Test** · **Ai chốt / ngày**.

Ví dụ:

```markdown
| BR-K1 | Đơn nào tính là bán? | profiling A1: 8 status | (a) chỉ delivered (b) mọi status trừ canceled, unavailable | (b) | seed order_status_map | accepted_values + đối soát GMV | cả nhóm, 07/11 |
```

---

## Chung (kickoff: C-R1 … C-R5)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-S1 | `raw` là append-only, dedup theo batch thế nào? | `load_raw.py` ghi `_batch_id`, `_loaded_at` | (a) `row_number()` theo `_loaded_at desc` trên natural key (b) lấy batch mới nhất | (a) cho các bảng có natural key; riêng `geolocation` không có NK đơn lẻ nên lọc batch có `max(_loaded_at)` | `stg_*.sql` | `unique` + `not_null` trên NK ở mọi `stg_*` | cả nhóm, 07/11 |
| BR-S2 | Xử lý chuỗi rỗng và khoảng trắng thừa ở cột text? | profiling: ô trống CSV nạp là `NULL`, nhưng cần phòng chuỗi toàn dấu cách | `nullif(trim(col), '')` | Dùng macro `clean_text(col)` cho mọi cột text | `macros/cleaning.sql` | `not_null` trên các cột bắt buộc | cả nhóm, 07/11 |
| BR-S3 | Định dạng `zip_prefix` 5 chữ số? | profiling A9: 23 995 khách có zip bắt đầu bằng `0` | `lpad(nullif(trim(col), ''), 5, '0')` | Dùng macro `zip5(col)` | `macros/cleaning.sql` | `not_null` trên zip ở staging | cả nhóm, 07/11 |
| BR-S4 | Tên thành phố (`city`) có dấu và viết hoa/thường lẫn lộn? | profiling A3: 8 011 giá trị thô → 5 969 sau `lower(unaccent())` | Bỏ dấu bằng `public.unaccent`, `lower`, gộp khoảng trắng | Dùng macro `clean_city(col)` | `macros/cleaning.sql` | kiểm tra số distinct city giảm ở `stg_geolocation` | cả nhóm, 07/11 |
| BR-S5 | Định dạng mã bang (`state_code`)? | profiling: 27 bang khách, 23 bang seller, đều 2 ký tự | `upper(nullif(trim(col), ''))` | Dùng macro `state_code(col)` | `macros/cleaning.sql` | `not_null` | cả nhóm, 07/11 |
| BR-S6 | Dữ liệu bẩn / ngược thứ tự thời gian: xoá, sửa hay gắn cờ? | profiling phát hiện 2, 7 | (a) Xoá dòng lỗi (b) Giữ dòng, gắn cờ `_dq_issue`, chỉ đặt `NULL` cho giá trị bất khả thi | (b) Không bao giờ xoá dòng ở staging; ghi mã lỗi vào `_dq_issue` | `stg_orders.sql`, `stg_order_items.sql` | singular test + thống kê `_dq_issue` | cả nhóm, 07/11 |
| BR-S7 | Cờ dẫn xuất (`is_delivered`, `is_late`, `delay_days`) tính ở `stg` hay `fact`? | Dùng chung cho `fact_order_fulfillment` (P1) và `fact_geo_month` (P2) | (a) Tính ở `stg_orders` (b) Tính riêng ở từng fact | (a) Tính một lần ở `stg_orders` (kiểu boolean), sang `dw` fact ép thành `0/1` để mọi bài toán dùng chung một định nghĩa | `stg_orders.sql` | đối soát late orders giữa các fact | cả nhóm, 07/11 |
| BR-W1 | Surrogate key sinh bằng sequence hay hàm băm? | Cần ổn định khi rebuild và incremental load | `('x' \|\| left(md5(concat_ws('\|', ...)), 15))::bit(60)::bigint` | Dùng macro `int_sk(cols)` | `macros/int_sk.sql` | `unique`, `not_null` trên mọi `*_key` | cả nhóm, 07/11 |
| BR-W2 | Xử lý FK khi thiếu bản ghi dimension hoặc sự kiện chưa xảy ra? | Tránh mất dòng fact khi join | Dòng unknown member có key = `-1`; date key = `YYYYMMDD` (`-1` khi null) | Dùng macro `unknown_key`, `coalesce_key`, `date_key` | `macros/unknown_member.sql` | `relationships` FK fact → dim; test tỷ lệ `-1` < 1% | cả nhóm, 07/11 |
| BR-W4 | Cửa sổ thời gian phân tích chuỗi thời gian & ML? | profiling A8: 2016 (329 đơn) và 09–10/2018 (20 đơn) rất thưa; 2017-01 → 2018-08 chứa 99,6% đơn | Giữ toàn bộ trong `dw`, lọc `2017-01-01 → 2018-08-31` cho KPI xu hướng và ML | `ANALYSIS_START = 2017-01-01`, `ANALYSIS_END = 2018-08-31` | `.env.example`, `dbt_project.yml` | kiểm tra phạm vi tháng trong ML | cả nhóm, 07/11 |
| BR-W11 | Cờ trong bảng `fact_*` lưu boolean hay integer `0/1`? | Power BI và SQL cộng trực tiếp tử số | Integer `0/1` | Mọi cờ `is_*`, `has_*` ở fact lưu dạng `0/1` | `fact_*.sql` | `accepted_values: [0, 1]` | cả nhóm, 07/11 |
| BR-W12 | Ánh xạ 27 bang → 5 vùng địa lý Brazil và tuần Black Friday khi chỉ dùng 1 dataset? | P1, P2, P3 đều cần `region_name` và cờ `is_black_friday_week` | Mã hoá trực tiếp bảng 27 bang → 5 vùng (IBGE chuẩn) và thứ Sáu tuần thứ 4 tháng 11 trong dbt (seed/SQL) | Dùng CASE / seed nội bộ trong dbt, không phụ thuộc API hay file ngoài | `dim_geography.sql`, `dim_date.sql` | `not_null` trên `region_name` | cả nhóm, 07/11 |
| BR-K1 | Đơn nào được tính là bán (`counts_as_sale`) và cơ sở tính GMV? | profiling A1: 8 `order_status` | (a) Chỉ `delivered` (b) Mọi trạng thái trừ `canceled`, `unavailable`; GMV = $\sum \text{price}$ (không gồm ship) | (b) `counts_as_sale = true` cho `delivered, shipped, invoiced, processing, approved, created`; GMV không gồm phí ship | seed `order_status_map`, `dim_order_status.sql` | `accepted_values` + đối soát GMV `stg` vs `fact` | cả nhóm, 07/11 |

## Orders — `stg_orders` (C-S1)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-O1 | Danh sách giá trị hợp lệ của `order_status`? | profiling A1: 8 giá trị (`delivered` 96 478, `shipped` 1 107, `canceled` 625, `unavailable` 609, `invoiced` 314, `processing` 301, `created` 5, `approved` 2) | Chuẩn hoá `lower(clean_text(order_status))` và kiểm tra thuộc 8 giá trị | Giữ nguyên 8 trạng thái viết thường | `stg_orders.sql` | `accepted_values` (8 trạng thái) trong `stg_orders.yml` | Cẩn, 07/11 |
| BR-O2 | Khi nào một đơn được coi là đã giao (`is_delivered`)? | profiling phát hiện 3: 8 đơn `delivered` thiếu `order_delivered_customer_date`; 6 đơn `canceled` lại có ngày giao | (a) Chỉ xét `order_status = 'delivered'` (b) Chỉ xét `order_delivered_customer_date is not null` (c) Kết hợp cả hai | (c) `order_status = 'delivered' and order_delivered_customer_date is not null` (96 470 đơn) | `stg_orders.sql` | `not_null` trên `is_delivered` | Cẩn, 07/11 |
| BR-O3 | Định nghĩa đơn giao trễ (`is_late`) và số ngày trễ (`delay_days`): so sánh theo ngày (`::date`) hay timestamp? | profiling phát hiện 1: `order_estimated_delivery_date` luôn có giờ `00:00:00`; so timestamp ra 8,11% (coi giao trong ngày hứa là trễ), so theo `::date` ra **6,77%** | (a) So theo `::date` (b) So theo timestamp | (a) `is_delivered and order_delivered_customer_date::date > order_estimated_delivery_date::date`; `delay_days = delivered::date - estimated::date` (âm = giao sớm, null nếu chưa giao) | `stg_orders.sql` | kiểm tra late rate = 6,77% (6 534 / 96 470 đơn) | Cẩn, 07/11 |
| BR-O4 | Xử lý các mốc thời gian ngược thứ tự (`carrier < approved`, `carrier < purchase`, `delivered < carrier`, `delivered < purchase`)? | profiling phát hiện 2: 0 đơn `delivered < purchase`; 1 359 đơn `carrier < approved`; 166 đơn `carrier < purchase`; 23 đơn `delivered < carrier` | Gắn cờ `_dq_issue` (nối bằng dấu phẩy); nếu `delivered < purchase` thì null ngày giao, các trường hợp còn lại giữ nguyên timestamp ở `stg_orders` và đặt lag âm = null ở fact | Áp dụng đúng quy tắc trên (`delivered_before_purchase`, `carrier_before_purchase`, `carrier_before_approved`, `delivered_before_carrier`) | `stg_orders.sql` | singular test `assert_fulfillment_dates_in_order.sql` | Cẩn, 07/11 |

## Order items — `stg_order_items` (C-S2)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-CS2-1 | Khoá tự nhiên và dedup | BR-S1 (rule chung C-R1, chốt ở kickoff); 112 650 dòng raw | — | Áp dụng C-R1 với key (`order_id`, `order_item_id`); trong lúc C-R1 chưa chốt dùng mặc định của `rebuild_guide` (giữ `_loaded_at` mới nhất) | `stg_order_items` | unique combination key sau dedup | Vinh đề xuất 08/11, chờ consumer |
| BR-CS2-2 | `shipping_limit_date` ngoài khoảng hợp lệ | Finding 7: 4 item (3 đơn, 2017) có hạn năm 2020 | (a) giữ (b) null + cờ (c) bỏ dòng | Đề xuất (b): ngoài phạm vi `dim_date` (BR-W3, hiện 2016-01-01 … 2019-12-31) → null, `_dq_issue = shipping_limit_out_of_range` (BR-S6, không bỏ dòng) | `stg_order_items` | đếm `_dq_issue` = 4 | Vinh đề xuất 08/11, chờ consumer |
| BR-CS2-3 | Kiểu dữ liệu tiền | price, freight là text trong raw | numeric(12,2) / float | Đề xuất numeric(12,2) cho `price`, `freight_value`; `shipping_limit_at` timestamp | `stg_order_items` | `not_null` price; price ≥ 0; freight_value ≥ 0 | Vinh đề xuất 08/11, chờ consumer |

## Customers — `stg_customers`, `int_customer_map` (C-S3)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-CS3-1 | Một "khách" là gì? | A7: 99 441 `customer_id`, 96 096 `customer_unique_id`; 3,12% mua lặp | (a) `customer_id` (b) `customer_unique_id` | Đề xuất (b): khách = `customer_unique_id`; `customer_id` chỉ là khoá theo đơn, map qua `int_customer_map` | `stg_customers`, `int_customer_map` | unique/not_null `customer_id`; not_null `customer_unique_id` | Hiếu đề xuất 09/11, chờ consumer (#17) |
| BR-CS3-2 | Khách đổi địa chỉ giữa các đơn | Đếm trên raw: 250 `customer_unique_id` có > 1 zip, 39 có > 1 bang | (a) 1 địa chỉ / khách (b) địa chỉ theo đơn | Đề xuất (b): map giữ địa chỉ của từng đơn; fact cấp đơn dùng zip của đơn; `dim_customer` dùng zip đơn đầu tiên (BR-W8, C-W3) | `int_customer_map` | not_null `customer_zip_prefix` | Hiếu đề xuất 09/11, chờ consumer (#17) |
| BR-CS3-3 | Dedup, làm sạch | BR-S1…BR-S5 (C-R1, #15) | — | Áp rule chung; trong lúc C-R1 chưa chốt dùng mặc định của `rebuild_guide` (giữ `_loaded_at` mới nhất / `customer_id`; `lpad(zip,5,'0')`; lower + unaccent + gộp khoảng trắng; `upper(trim(state))`), viết inline, thay bằng macro khi C-R1 merge | `stg_customers` | zip dài 5; state ∈ 27 mã; số dòng = số `customer_id` phân biệt trong raw | Hiếu đề xuất 09/11, chờ consumer (#17) |

## Sellers — `stg_sellers` (C-S4)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-CS4-1 | Dedup, làm sạch | BR-S1…BR-S5 (C-R1, #15) | — | Như BR-CS3-3, key `seller_id` | `stg_sellers` | unique/not_null `seller_id`; zip dài 5; state ∈ 27 mã; số dòng = raw | Hiếu đề xuất 09/11, chờ consumer (#18) |
| BR-CS4-2 | `seller_city` nhập tay rất bẩn | 611 giá trị thô → 607 sau BR-S4; còn `sbc/sp`, `sao paulo / sao paulo`, `04482255`, `novo hamburgo, rio grande do sul, brasil` | (a) sửa tay từng giá trị (b) chỉ BR-S4, city phân tích lấy từ geolocation | Đề xuất (b): `seller_city` chỉ để tham khảo; city dùng phân tích lấy từ `dim_geography` (mode geolocation theo zip, C-W2) | `stg_sellers` | — | Hiếu đề xuất 09/11, chờ consumer (#18) |
| BR-CS4-3 | Zip seller không có trong geolocation | A3: 7 seller | (a) bỏ (b) giữ | Đề xuất (b): giữ; `dim_geography` lấy hợp tập zip nên vẫn có `seller_geo_key` (toạ độ null) | `stg_sellers`, `dim_geography` | not_null `seller_zip_prefix` | Hiếu đề xuất 09/11, chờ consumer (#18) |

## Geolocation — `stg_geolocation` (C-S5)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-G1 | Bảng `raw.geolocation` (~1M dòng) không có khoá đơn lẻ, xử lý khi nạp nhiều batch thế nào? | `load_raw.py` append theo `_loaded_at` | Lọc `_loaded_at = (select max(_loaded_at) from raw.geolocation)` trước khi gộp | Chỉ lấy batch mới nhất để không nhân bản điểm toạ độ | `stg_geolocation.sql` | `unique`, `not_null` trên `zip_prefix` (19 015 dòng) | Cẩn, 07/11 |
| BR-G2 | Gộp ~52,6 điểm / zip prefix và loại điểm ngoài lãnh thổ Brazil thế nào? | profiling A3: 42 điểm (21 zip) ngoài bbox Brazil (`lat` −34…5,5; `lng` −74…−34); 5 zip toàn bộ điểm ngoài bbox | Tính `avg(lat)` và `avg(lng)` chỉ trên các điểm trong bbox (`in_brazil`); zip không có điểm hợp lệ thì `latitude = null, longitude = null`; giữ cột `n_points` và `n_points_outside_brazil` | Áp dụng bbox `lat between -34 and 5.5 and lng between -74 and -34` | `stg_geolocation.sql` | `dbt_utils.accepted_range` cho `latitude` (−34…5,5) và `longitude` (−74…−34) | Cẩn, 07/11 |
| BR-G3 | Chọn `city` và `state_code` đại diện cho mỗi `zip_prefix` khi có nhiều cách viết hoặc nhiều bang? | profiling A3: 8 zip có > 1 bang; nhiều biến thể tên city | Sau khi chuẩn hoá `clean_city` (BR-S4) và `state_code` (BR-S5), lấy giá trị xuất hiện nhiều nhất (mode) theo `count(*) desc`, nếu hoà lấy theo thứ tự chữ cái | Dùng `distinct on (zip_prefix) ... order by zip_prefix, count(*) desc, city/state_code` | `stg_geolocation.sql` | `not_null` trên `city`, `state_code` | Cẩn, 07/11 |

## Products & categories — `stg_products`, translation, `category_group` (C-S6)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-CS6-1 | Product không có category | A4: 610 product (1 603 item, 1,4%) | (a) null (b) `unknown` | Đề xuất (b): `category_pt = coalesce(clean, 'unknown')` | `stg_products` | `not_null` category_pt | Vinh đề xuất 08/11, chờ consumer |
| BR-CS6-2 | Category không có bản dịch | A4: 13 product thuộc 2 category; translation 71 dòng | (a) null (b) giữ tên PT | Đề xuất (b): `category_en = coalesce(en, category_pt)` | `stg_products` | `not_null` category_en | Vinh đề xuất 08/11, chờ consumer |
| BR-CS6-3 | Cân nặng 0, thiếu kích thước, cột sai chính tả | A4: 4 product weight 0; 2 thiếu kích thước; cột `product_name_lenght`, `product_description_lenght` | — | Đề xuất: weight 0 → null + `_dq_issue = weight_zero`; đổi tên cột thành `name_length`, `description_length`, `photos_qty` (bỏ tiền tố `product_`); `volume_cm3` = L × H × W (null nếu thiếu 1 chiều) | `stg_products` | weight > 0 khi not null; đếm `weight_zero` = 4 | Vinh đề xuất 08/11, chờ consumer |
| BR-CS6-4 | Nhóm category (cho P3, P2 tuỳ chọn) | 73 category + `unknown`; thiết kế cũ có seed 11 nhóm + `Unknown` | (a) không nhóm (b) seed `category_group` | Đề xuất (b): khôi phục seed từ `83891b5` (74 dòng, header `product_category_name,category_group`) | seed `category_group` | unique/not_null; mọi `category_pt` của `stg_products` có trong seed | Vinh đề xuất 08/11, chờ consumer |

## Reviews — `stg_order_reviews` (C-S7)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-CS7-1 | Khoá của review | A2: 789 review_id gắn > 1 đơn | (a) `review_id` (b) (`review_id`, `order_id`) | Đề xuất (b) + dedup BR-S1 | `stg_order_reviews` | unique combination key | Vinh đề xuất 08/11, chờ consumer |
| BR-CS7-2 | Đơn có nhiều review: review nào được tính | A2: 547 đơn > 1 review (202 khác điểm); 768 đơn không có review | (a) trung bình (b) mới nhất | Đề xuất (b): `is_latest_for_order` theo `review_answer_timestamp desc`, `review_creation_date desc`, `review_id desc`; KPI chỉ dùng review mới nhất (BR-K3) | `stg_order_reviews` | đúng 1 latest / đơn có review (98 673 đơn) | Vinh đề xuất 08/11, chờ consumer |
| BR-CS7-3 | Cờ dẫn xuất từ comment | 27 message chỉ có khoảng trắng | — | Đề xuất: `has_comment` = `nullif(trim(message), '') is not null` (0/1), `comment_length` = độ dài sau trim | `stg_order_reviews` | `accepted_values` 0/1 | Vinh đề xuất 08/11, chờ consumer |

## Payments — `stg_order_payments` (C-S8, tuỳ chọn)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Warehouse dùng chung — dims, intermediate, facts (C-W1 … C-W10)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-W3 | Phạm vi `dim_date` và cờ lịch/sự kiện? | Đơn hàng 2016-09 → 2018-10 | Sinh bằng `dbt_utils.date_spine` từ `2016-01-01` đến `2019-12-31` + dòng unknown `-1`; đánh dấu `is_weekend` và `is_black_friday_week` (tuần ISO chứa thứ Sáu thứ 4 của tháng 11) | `dim_date` (1 461 ngày + dòng `-1`) | `dim_date.sql` | `unique`, `not_null` trên `date_key` | Cẩn, 07/11 |
| BR-W5 | Đơn có nhiều seller (1 278 đơn = 1,3%): ai là `primary_seller` ở các fact cấp đơn (`fact_order_fulfillment`, `fact_review`)? | profiling phát hiện 5 | Seller của item có `price` cao nhất trong đơn; nếu hoà lấy `seller_id` nhỏ nhất theo thứ tự chữ cái | Tạo `int_order_primary_seller` (1 dòng / `order_id` có item) | `int_order_primary_seller.sql` | `unique`, `not_null` trên `order_id` | Cẩn, 07/11 |
| BR-W6 | Giá trị đơn hàng (`order_value`) ở cấp đơn tính thế nào và xử lý hạn giao hãng vận chuyển (`max_shipping_limit_date`)? | profiling A5: 775 đơn không có item | Tổng hợp ở `int_order_agg`: `item_count = count(*)`, `order_value = sum(price)` (cùng cơ sở GMV, không gồm ship), `freight_total = sum(freight_value)`, `item_total = sum(item_total)`, `max_shipping_limit_date = max(shipping_limit_date)`; đơn không có item → `0` ở `fact_order_fulfillment` | Tạo `int_order_agg` (1 dòng / `order_id` có item) | `int_order_agg.sql`, `fact_order_fulfillment.sql` | đối soát `sum(order_value)` = GMV `fact_order_item` | Cẩn, 07/11 |
| BR-CW5-1 | Category: thuộc tính của `dim_product` hay dim riêng | P3 cần category làm trục phân tích; P1 dùng qua product | (a) cột trong `dim_product` (b) `dim_category` snowflake | Đề xuất (b): `dim_category` 1 dòng / `category_pt` (+ `-1`), `dim_product.category_key` FK; `is_rankable = 0` cho `unknown` | `dim_category`, `dim_product` | relationships product → category | Vinh đề xuất 08/11, chờ consumer |
| BR-CW5-2 | Band cân nặng / kích thước | Thiết kế cũ `83891b5` | — | Đề xuất giữ band cũ: weight < 0,5 / 0,5–2 / 2–5 / 5–10 / ≥ 10 kg; volume < 1 / 1–10 / 10–50 / ≥ 50 L; thiếu → `Unknown` | `dim_product` | `accepted_values` band | Vinh đề xuất 08/11, chờ consumer |
| BR-CW8-1 | Grain và seller version trong `fact_order_item` | 112 650 item; giữ SCD2 hay không là BR-W10 (C-W4, Hiếu, chưa chốt) | — | Đề xuất: 1 dòng / item; `seller_key` theo contract C-W4: nếu giữ SCD2 thì lookup theo ngày mua với quy ước Hiếu chốt (đề xuất closed `purchase::date between valid_from and valid_to`), nếu không thì 1 key / seller; luôn giữ degenerate `seller_id` để đếm seller và tính HHI | `fact_order_item` | unique (`order_id`, `order_item_id`); unknown seller share ≤ 1% | Vinh đề xuất 08/11, chờ consumer |
| BR-CW8-2 | Đối soát GMV | BR-K1: GMV = Σ price, chỉ `counts_as_sale`; rebuild §4.3 | — | Đề xuất 2 test: Σ `item_price` của fact = Σ `price` của `stg_order_items` (mọi status); GMV sale (join `dim_order_status.counts_as_sale`) = GMV tính thẳng từ `stg_order_items` + `stg_orders` + seed `order_status_map` | `fact_order_item` | `assert_reconcile_gmv_stg_vs_fact` | Vinh đề xuất 08/11, chờ consumer |
| BR-CW10-1 | Grain và seller của `fact_review` | Key (`review_id`, `order_id`); đơn nhiều seller 1,3% (BR-W5) | — | Đề xuất: 1 dòng / (`review_id`, `order_id`); `primary_seller_key` từ `int_order_primary_seller` (C-W7), lookup SCD2 theo ngày mua của đơn (cùng quy ước BR-CW8-1); measures `review_count = 1`, `score_sum`, `is_low_score` (ngưỡng BR-P3-6), `response_hours` | `fact_review` | score_sum ∈ [1, 5]·review_count; 1 latest / đơn | Vinh đề xuất 08/11, chờ consumer |

## P1 — Logistics (Cẩn)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-K2 | Mẫu số của `Late rate` là tổng số đơn hay số đơn đã giao (`is_delivered`)? | Đơn chưa giao / huỷ chưa có kết quả giao trễ hay đúng hẹn | $\sum \text{is\_late} / \sum \text{is\_delivered}$ | Mẫu số là tổng đơn đã giao (`is_delivered = 1`) | `fact_order_fulfillment.sql`, `kpi_dictionary.md` | kiểm tra tổng `is_late <= is_delivered` | Cẩn, 07/11 |
| BR-K4 | Đơn vị không gian để đo *Mật độ giao trễ (Late density)* và làm ứng viên đặt Hub (ML-1b)? | Zip prefix (~19k) quá nhỏ và diện tích không đều; bang (27) quá thô | Lưới toạ độ $0.5^\circ \times 0.5^\circ$: `geo_cell_id = floor(lat / 0.5)::int \|\| '_' \|\| floor(lng / 0.5)::int` (tâm ô: `(floor + 0.5) * 0.5`). *Late density* = $\sum \text{late\_orders} / \text{số tháng}$ trong mỗi `geo_cell_id` | Thêm `geo_cell_id`, `geo_cell_lat`, `geo_cell_lng` vào `dim_geography`; tính mật độ theo ô lưới | `dim_geography.sql`, `kpi_dictionary.md`, `ml/p1_logistics/` | kiểm tra `geo_cell_id` null khi và chỉ khi `latitude` null | Cẩn, 07/11 |
| BR-K6 | Ngưỡng số đơn tối thiểu khi xếp hạng khu vực / tuyến theo `Late rate`? | Nhiều zip / tuyến chỉ có 1–5 đơn, late rate 100% gây nhiễu | Lọc khu vực / tuyến có $\ge 20$ đơn đã giao (`delivered_orders >= 20`) khi xếp hạng theo tỷ lệ; không lọc khi xem tổng lượng trễ tuyệt đối (`Late volume`, `Late density`) | Ngưỡng mặc định = 20 đơn đã giao | `kpi_dictionary.md`, `ml/p1_logistics/` | — | Cẩn, 07/11 |
| BR-P1-1 | Cách tính các khoảng trễ từng chặng (lags) và phân biệt lỗi do Seller (`is_dispatch_late`) vs lỗi do Vận chuyển (`transit_share`)? | profiling phát hiện 2: có mốc thời gian ngược làm lag âm | Tính số ngày (có phần thập phân) bằng macro `lag_days(from_ts, to_ts)`: âm → `null`. `is_dispatch_late = 1` khi `carrier_date > max_shipping_limit_date` (mẫu số: `has_carrier_date = 1`). `transit_share = sum(transit_lag) / sum(delivery_lag)` | Hiện thực trong `macros/haversine.sql` và `fact_order_fulfillment.sql` | `macros/haversine.sql`, `fact_order_fulfillment.sql` | kiểm tra mọi lag $\ge 0$ | Cẩn, 07/11 |

## P2 — Regional market (Hiếu)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |

## P3 — Category (Vinh)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BR-P3-1 | Category key cho phân tích | 74 giá trị `category_pt` | — | Dùng `dim_category` của BR-CW5-1 qua `dim_product.category_key`; không lưu chuỗi category trong fact P3 | `fact_category_month` | relationships | Vinh đề xuất 08/11, chờ consumer |
| BR-P3-2 | Grain `fact_category_month` | ~11 657 ô có dữ liệu / 39 960 ô có thể | category × tháng / × bang × tháng | Đề xuất: category × bang khách × tháng mua (sparse), chỉ đơn `counts_as_sale` | `fact_category_month` | unique (category, state, month) | Vinh đề xuất 08/11, chờ consumer |
| BR-P3-3 | Nguồn và cách gộp | Join review ở grain item làm `review_count` +13% (office_furniture 3,63 → 3,50) | (a) join ở grain item (b) gộp order × category trước | Đề xuất (b): gộp `fact_order_item` về order × category, rồi join 1–1 theo `order_id` với `fact_review` (latest) và `fact_order_fulfillment` | `fact_category_month` | đối soát items, GMV, review | Vinh đề xuất 08/11, chờ consumer |
| BR-P3-4 | Growth dùng để phân loại | Sàn tăng 73,8% YoY; tăng trưởng tương đối không chặn (1 category ×543) | (a) YoY tuyệt đối (KPI *Category growth*, refactor §5) (b) forecast growth (refactor §6.3) (c) relative growth = (1+g_cat)/(1+g_platform) − 1 | Đề xuất (c) làm trục y của phân loại, 3 tháng gần nhất vs cùng kỳ (BR-K5); chỉ tính khi ≥ 30 đơn ở cả hai cửa sổ, còn lại null + cờ low volume. **Lệch refactor §6.3, cần nhóm đồng ý**; nếu không, trục y = `forecast_growth` (cột vẫn có trong `ml.category_opportunity`). KPI *Category growth* (a) vẫn giữ để hiển thị | `ml/p3_category/features.py` | không có growth ±inf | Vinh đề xuất 08/11, chờ consumer |
| BR-P3-5 | Min volume (BR-K6 phần P3) | Rate của category vài chục đơn dao động mạnh | ngưỡng 50 / 100 / 200 | Đề xuất ≥ 100 đơn delivered trong 12 tháng; dưới → `Low volume`, không xếp loại | `ml/p3_category/features.py` | — | Vinh đề xuất 08/11, chờ consumer |
| BR-P3-6 | Low score | Thang 1–5 | ≤ 1 / ≤ 2 / ≤ 3 | Đề xuất `review_score ≤ 2`, review mới nhất / đơn | `fact_review.is_low_score` | — | Vinh đề xuất 08/11, chờ consumer |
| BR-P3-7 | Mức dự báo | 19 category có ≥ 10 đơn mọi tháng trong cửa sổ 20 tháng (đếm lại trên 17 tháng train khi build); nhóm Food & Drinks có tháng chỉ 2 đơn | category / nhóm | Đề xuất: category nếu ≥ 10 đơn mọi tháng train; còn lại theo 11 nhóm (không dự báo `Unknown`); nhóm thưa chỉ baseline + cờ | `ml/p3_category/category_forecast.py` | — | Vinh đề xuất 08/11, chờ consumer |
| BR-P3-8 | Ngưỡng cờ | Late rate sàn 6,77% (profiling, theo ngày); category đủ volume 2,5–13%; HHI computers 0,555, office_furniture 0,426 (12 tháng) | — | Đề xuất: *Fix quality first* khi avg score < TB sàn − 0,2 hoặc low-score rate > TB sàn + 5 điểm % hoặc late rate > TB sàn + 2 điểm % (TB sàn tính cùng cửa sổ 12 tháng); *Recruit sellers* khi HHI (theo `seller_id`) ≥ 0,25 | `ml/p3_category/category_portfolio.py` | — | Vinh đề xuất 08/11, chờ consumer |
| BR-P3-9 | Lợi nhuận | Dataset không có giá vốn | — | Đề xuất proxy: freight ratio (Σ freight / Σ price) và AOV | `fact_category_month` | — | Vinh đề xuất 08/11, chờ consumer |
| BR-P3-10 | Phân loại danh mục | Profiling P3 chạy lại 08/11 (chưa có trong `profiling.md`): chia theo trung vị xếp 72% category vào high share | (a) trung vị (b) Pareto 80% + dead band | Đề xuất (b). Tập xếp loại: `is_rankable = 1` và qua BR-P3-5. High share: nhóm chiếm 80% GMV tích luỹ của tập đó. Growth (BR-P3-4) > +5% là tăng, < −5% là giảm, giữa là ổn định. High & tăng → *Grow*; low & tăng → *Invest selectively*; high & ổn định/giảm → *Maintain*; low & ổn định/giảm → *Review*. Ngưỡng 80% và ±5% là tham số (`params_json`) | `ml/p3_category/category_portfolio.py` | báo số category đổi class khi Pareto 75/85% và dead band ±3/±7% | Vinh đề xuất 08/11, chờ consumer |
| BR-P3-11 | Category `unknown` | 1,4% item | (a) bỏ (b) giữ, không xếp loại | Đề xuất (b): hiện trên dashboard, `is_rankable = 0`, không vào Pareto / xếp loại / ML-3b | `dim_category` | unknown share (cả `-1` và `unknown`) warn > 2% | Vinh đề xuất 08/11, chờ consumer |
| BR-P3-12 | Backtest phân loại | A8: 2016 có 329 đơn (11/2016: 0, 12/2016: 1), nên as-of 2017-12 không có cửa sổ cùng kỳ | as-of 2017-12 / 2018-05 | Đề xuất as-of 2018-05-31: feature 2018-03..05 vs 2017-03..05; kết quả = thay đổi GMV share 2018-06..08 vs 2018-03..05 theo class; không dùng forecast trong backtest | `ml/p3_category/category_portfolio.py` | báo kết quả, không chỉnh ngưỡng | Vinh đề xuất 08/11, chờ consumer |
