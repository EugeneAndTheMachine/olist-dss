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

## Orders — `stg_orders` (C-S1)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Order items — `stg_order_items` (C-S2)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |

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

## Products & categories — `stg_products`, translation, `category_group` (C-S6)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Reviews — `stg_order_reviews` (C-S7)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Payments — `stg_order_payments` (C-S8, tuỳ chọn)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Warehouse dùng chung — dims, intermediate, facts (C-W1 … C-W10)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |

## P1 — Logistics (Cẩn)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |

## P2 — Regional market (Hiếu)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |

## P3 — Category (Vinh)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |
