# Profiling dữ liệu nguồn (S1)

> Người làm: **Minh Hiếu (TV2)**. Hạn: ngày 2 (CN 1/11/2026).
> Mỗi giả định: ghi query/notebook đã dùng, con số, kết luận, rồi cập nhật bảng mục 18 trong `CLAUDE.md`.

## Tổng quan nguồn

| Bảng raw | Số dòng | Khoảng thời gian | Ghi chú |
| --- | --- | --- | --- |
| raw.orders | | | |
| raw.order_items | | | |
| raw.order_payments | | | |
| raw.order_reviews | | | |
| raw.customers | | | |
| raw.sellers | | | |
| raw.products | | | |
| raw.geolocation | | | |
| raw.product_category_name_translation | | | |
| raw.mql | | | |
| raw.closed_deals | | | |

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
