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

> Đo ngày 1/11/2026 trên cùng batch với phần tổng quan. Query: [`docs/profiling/02_assumptions.sql`](profiling/02_assumptions.sql) (mỗi khối có nhãn `== A<n>`).
> Lưu ý khi viết staging: `load_raw` nạp bằng `COPY ... csv` nên **ô rỗng trong CSV thành NULL**, không phải chuỗi rỗng.

| # | Giả định | Cách kiểm | Kết quả | Kết luận / rule staging |
| --- | --- | --- | --- | --- |
| A1 | Danh sách order_status, payment_type | `group by` status / type / installments | **Đúng.** 8 status, khớp đủ seed `order_status_map`. 5 payment_type, gồm `not_defined` (3 dòng). 2 dòng installments = 0 | Giữ seed. installments 0 → 1. `not_defined` giữ lại (value = 0, cả 3 đơn đều canceled) |
| A2 | review_id trùng trên nhiều order; order có nhiều review | Đếm review_id / order, order / review | **Đúng cả hai.** 789 review_id gắn 2–3 đơn; 547 đơn có 2–3 review. (review_id, order_id) duy nhất | Khoá fact = (review_id, order_id). `is_latest_for_order` theo answer_timestamp: không có hoà |
| A3 | Geolocation nhiều điểm / zip, điểm ngoài Brazil, city có dấu | Phân phối điểm / zip, bounding box, unaccent | **Đúng.** Trung vị 29 điểm / zip, 26% dòng trùng hẳn. 42 dòng (21 zip) ngoài bbox. 7.3% dòng city có dấu, 8,011 → 5,968 city sau chuẩn hoá | Gộp theo zip như mục 9, **nhưng nới lng tới −28** để không loại Fernando de Noronha. Chuẩn hoá city = lower + unaccent + trim |
| A4 | Product thiếu category / thiếu bản dịch | Đếm product rỗng category, join translation, seed | **Đúng.** 610 product rỗng category (1.42% item, 1.32% GMV). 2 category thiếu bản dịch (13 product, 24 item). Seed `category_group` phủ đủ 73 category | category null → `unknown`; thiếu bản dịch → giữ tên PT |
| A5 | Chênh Σ item_total vs Σ payment_value theo đơn → tolerance | So từng đơn có cả item lẫn payment (98,665 đơn) | 99.69% đơn khớp trong 0.01 BRL. 303 đơn lệch (0.31%), 88% là đơn trả góp: trả nhiều hơn khoảng 10% (lãi). Tổng toàn bộ chỉ lệch 0.018% | **Tolerance 0.01 BRL / đơn**; test reconciliation `warn` khi > 0.5% đơn lệch |
| A6 | Tỷ lệ closed_deals.seller_id khớp sellers | Join closed_deals ↔ sellers ↔ đơn hàng | **45.1%** (380 / 842). Cả 380 đều bán sau won_date. 324 deal có GMV trong 90 ngày đầu (trung vị 320 BRL) | `gmv_first_90_days` thưa: chỉ ~38% deal có giá trị. 462 seller chỉ có trong funnel → `has_sales = false` |
| A7 | Tỷ lệ khách mua lặp (customer_unique_id ≥ 2 đơn) | Đếm đơn / customer_unique_id | **3.04%** khách có ≥ 2 đơn counts_as_sale (2,888 / 94,990). Tính theo ngày mua khác nhau chỉ còn 2.17% | Xác nhận mục 1.3: CRM không dự đoán giữ chân thuần tuý |
| A8 | Cửa sổ phân tích 2017-01-01 → 2018-08-31 | Số đơn theo tháng | **Đúng.** 99.65% đơn nằm trong cửa sổ. Ngoài cửa sổ: 2016 có 329 đơn (thiếu hẳn 11/2016), 9–10/2018 chỉ 20 đơn | Giữ `ANALYSIS_START` / `ANALYSIS_END`. Forecast có 20 điểm tháng |
| A9 | Zip prefix mất số 0 đầu | Độ dài zip, zip bắt đầu bằng 0 | **Không mất.** Mọi zip đủ 5 ký tự ở cả 3 bảng; CSV để zip trong ngoặc kép, `load_raw` đọc dạng text nên giữ số 0 (24k zip khách bắt đầu bằng 0) | Vẫn giữ `lpad(zip, 5, '0')` để phòng file sửa qua Excel |

### Chi tiết

**A1 — Trạng thái đơn & thanh toán**
- order_status: delivered 96,478 · shipped 1,107 · canceled 625 · unavailable 609 · invoiced 314 · processing 301 · created 5 · approved 2.
- 8 đơn `delivered` không có `delivered_customer_date` → theo định nghĩa KPI, `is_delivered = false`. 6 đơn `canceled` lại có ngày giao.
- Đơn không có item tập trung ở `unavailable` (603 / 609) và `canceled` (164 / 625).
- payment_type: credit_card 76,795 · boleto 19,784 · voucher 5,775 · debit_card 1,529 · not_defined 3. Có 6 dòng voucher với value = 0; 1,621 đơn trả hoàn toàn bằng voucher.
- Chỉ credit_card có installments > 1 (tối đa 24). Seed `instalment_band` (1, 2–3, 4–6, 7–10, 11+) phủ đủ; band 11+ chỉ có 341 dòng.

**A2 — Review trùng**
- review_id: 97,621 gắn 1 đơn, 764 gắn 2 đơn, 25 gắn 3 đơn. Cả 789 review_id trùng đều có **nội dung giống hệt** (điểm, comment, ngày tạo, ngày trả lời) và thuộc **cùng 1 khách** → một lần đánh giá được chép cho nhiều đơn mua cùng lúc.
- Đơn: 98,126 có 1 review, 543 có 2, 4 có 3. Trong 547 đơn nhiều review, 202 đơn có điểm khác nhau → cần `is_latest_for_order` để KPI không đếm trùng.
- review_score chỉ gồm 1–5; không có answer trước creation. 64 review có ngày tạo trước ngày mua (ghi nhận, không loại).

**A3 — Geolocation**
- Điểm / zip: trung vị 29, p90 124, p99 353, tối đa 1,146. 261,831 dòng trùng hoàn toàn.
- 5 zip có toàn bộ điểm ngoài bbox: 4 zip toạ độ ở Bồ Đào Nha, Tây Ban Nha, Canary, Philippines (lỗi thật), còn zip 53990 (PE) là **Fernando de Noronha** (lng −32.4), vẫn thuộc Brazil. Bbox mục 9 (lng −74 → −34) sẽ loại nhầm zip này → đề xuất lng −74 → −28 (bao cả đảo Trindade, −29.3). Các điểm nước ngoài vẫn bị loại nhờ cận lat 5.5.
- 8 zip có điểm thuộc ≥ 2 bang → state lấy giá trị xuất hiện nhiều nhất.
- City trong geolocation: không có chữ hoa; 73,437 dòng có dấu (`são paulo` 24,918 dòng so với `sao paulo` 135,800). 550 zip vẫn có > 1 city sau chuẩn hoá → lấy city xuất hiện nhiều nhất. 26 dòng chứa ký tự lạ (`florian&oacute;polis`, `lambari d%26apos%3boeste`, `maceia³`, `* cidade`).
- customers: city không dấu, 157 zip (278 khách) không có trong geolocation → lat/lng null như thiết kế. sellers: 7 zip (7 seller) không có trong geolocation; `seller_city` có giá trị gõ tự do (`auriflama/sp`, `rio de janeiro, rio de janeiro, brasil`), không dùng làm tên city.
- Bang của khách luôn khớp bang phổ biến nhất của zip đó trong geolocation; **35 seller lệch**. Nhóm cần chốt state của seller lấy theo zip (dim_geography) hay theo `seller_state`.

**A4 — Category**
- 610 product rỗng category, cũng rỗng name/description length và photos_qty: 1,603 item, 179,535 BRL.
- `pc_gamer` 3 product / 9 item; `portateis_cozinha_e_preparadores_de_alimentos` 10 product / 15 item.
- Seed `category_group`: 73 category + `unknown` → 11 nhóm + `Unknown` (mục 7.4 ghi "~10 nhóm").

**A5 — Tiền hàng vs thanh toán**
- Trong 303 đơn lệch: 264 trả nhiều hơn, 39 trả ít hơn (không đơn nào dùng voucher). |lệch|: trung vị 5.9, p90 25.8, p99 76.2, tối đa 182.81 BRL.
- Theo nhóm: không trả góp & không voucher 30 / 44,773 lệch; trả góp 266 / 50,126 (paid / item_total trung vị 1.10).
- So sánh dùng 98,665 đơn có cả item và payment (bỏ 775 đơn không item, 1 đơn không payment).

**A6 — Funnel**
- 667 deal có đủ cửa sổ 90 ngày trước 2018-08-31; 346 trong số đó có seller bán hàng.
- Từ won_date đến đơn đầu tiên: p10 12 ngày, trung vị 44, p90 103.
- Won theo tháng: 3 deal 12/2017, đỉnh 207 ở 4/2018, còn 50 deal sau 8/2018.
- Conversion theo origin: unknown 16.3%, paid_search 12.3%, organic_search 11.8%, direct_traffic 11.2% … email 3.0%, other 2.7%. **60 MQL origin NULL** (14 đã chốt) → gộp vào `unknown`.
- days_to_close: p10 2, trung vị 14, p90 162 ngày; 1 deal có won_date trước first_contact_date.
- `declared_monthly_revenue` = 0 ở 797 / 842 deal → gần như vô dụng cho phân tích.

**A7 — Khách mua lặp**
- Đơn / khách (counts_as_sale): 1 đơn 92,102 · 2 đơn 2,652 · 3 đơn 188 · 4 đơn 29 · ≥5 đơn 19. Tối đa 16 đơn.
- Tính mọi status: 3.12%; trong cửa sổ phân tích: 3.04%.

**A8 — Cửa sổ thời gian**
- 1/2017 = 800 đơn, tăng dần tới đỉnh 11/2017 = 7,544 (Black Friday), sau đó ổn định 6–7k / tháng tới 8/2018 (6,512).
- 3 tháng cuối cửa sổ vẫn còn 46–74 đơn ở trạng thái mở mỗi tháng → late rate các tháng này hơi thấp hơn thực tế.

**A9 — Zip prefix**
- Zip bắt đầu bằng 0: customers 23,995, sellers 1,027, geolocation 245,733; nhỏ nhất `01001`.

## Phát hiện khác
