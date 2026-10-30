# dbt models — việc còn lại theo task

Model mẫu đã có (copy cấu trúc CTE + YAML khi viết model mới):

| Layer | Mẫu | Ghi chú |
| --- | --- | --- |
| staging | `stg_orders`, `stg_br_holidays` | dedup theo `_loaded_at` → ép kiểu → rule DQ → cờ dẫn xuất |
| warehouse/dims | `dim_date`, `dim_order_status` | `int_sk()`, `unknown_key()`, `date_key()` trong `macros/` |
| bi | `v_dim_order_status` | view mỏng, tên cột thân thiện |

Cần viết (CLAUDE.md mục 7, 9, 10, 14):

| Thư mục | Model | Task | Người |
| --- | --- | --- | --- |
| staging | `stg_order_items`, `stg_order_payments`, `stg_order_reviews`, `stg_customers`, `stg_sellers`, `stg_products`, `stg_geolocation`, `stg_product_category_name_translation`, `stg_mql`, `stg_closed_deals`, `stg_ibge_states`, `stg_ibge_municipalities`, `stg_br_states`, `stg_calendar_events` | S3 | Minh Hiếu (TV2) |
| intermediate | `int_customer_map` | S3 | Minh Hiếu (TV2) |
| intermediate | `int_seller_month_metrics`, `int_seller_tier_monthly`, `int_seller_tier_versions` | S6 | Minh Hiếu (TV2) |
| intermediate | `int_order_primary_seller`, `int_order_agg` | F1 | Xuân Vinh (TV3) |
| warehouse/dims | `dim_geography`, `dim_product`, `dim_customer`, `dim_payment_type`, `dim_seller` | S4, S6 | Minh Hiếu (TV2) |
| warehouse/dims | `dim_lead_origin`, `dim_lead_profile`, `dim_sales_rep` | S5 | Minh Hiếu (TV2) |
| warehouse/facts | `fact_lead_funnel` | S5 | Minh Hiếu (TV2) |
| warehouse/facts | `fact_order_item`, `fact_payment`, `fact_order_fulfillment`, `fact_review`, `fact_seller_month`, `fact_seller_product_activity` | F2–F4 | Xuân Vinh (TV3) |
| bi | `v_*` còn lại | F6 | Xuân Vinh (TV3) |
| tests | singular tests (business rule, reconciliation) | S7, F5 | TV2, TV3 |
