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

## Sellers — `stg_sellers` (C-S4)

| ID | Câu hỏi | Bằng chứng | Lựa chọn | Quyết định | Code ở đâu | Test | Ai chốt / ngày |
| --- | --- | --- | --- | --- | --- | --- | --- |

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
