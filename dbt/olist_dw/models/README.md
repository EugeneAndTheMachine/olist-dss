# dbt models — tiến độ theo task

Đã có (01/11/2026, `dbt build` xanh):

| Layer | Model | Task |
| --- | --- | --- |
| staging | `stg_orders`, `stg_order_items`, `stg_order_payments`, `stg_order_reviews`, `stg_customers`, `stg_sellers`, `stg_products`, `stg_geolocation`, `stg_product_category_name_translation`, `stg_mql`, `stg_closed_deals`, `stg_br_states`, `stg_calendar_events`, `stg_br_holidays` | S3 |
| intermediate | `int_customer_map` | S3 |
| intermediate | `int_order_primary_seller`, `int_order_agg` | F1 |
| warehouse/dims | `dim_date`, `dim_order_status`, `dim_geography`, `dim_product`, `dim_customer`, `dim_payment_type` | S4 |
| warehouse/dims | `dim_seller` — **bản tạm Type 1** (tier Unscored, cấu trúc SCD2 sẵn) | S6 (tạm) |
| warehouse/facts | `fact_order_item`, `fact_payment`, `fact_order_fulfillment`, `fact_review` | F2, F3 |
| warehouse/dims + facts | `dim_lead_origin`, `dim_lead_profile`, `dim_sales_rep`, `fact_lead_funnel` (02/11) | S5 |
| bi | `v_dim_order_status` (mẫu) | F6 |
| tests | `assert_dim_seller_*` (SCD2), `assert_reconcile_*`, `assert_fact_unknown_key_share`, `assert_fulfillment_dates_in_order`, `assert_lead_funnel_won_consistency` | S7, F5, S5 |

Macro dùng chung (`macros/`): `int_sk`, `unknown_key`, `coalesce_key`, `date_key`, `clean_text`, `zip5`, `clean_city`, `state_code`, `to_bool`, `haversine_km`, `lag_days`.

Cần viết tiếp (implementation.md mục 7, 10, 14):

| Thư mục | Model | Task |
| --- | --- | --- |
| intermediate | `int_seller_month_metrics`, `int_seller_tier_monthly`, `int_seller_tier_versions` → thay `dim_seller` bằng SCD2 | S6 |
| warehouse/facts | `fact_seller_month` (SHOULD), `fact_seller_product_activity` (COULD) | F4 |
| bi | `v_*` còn lại (dims, facts, ML, DQ) | F6 |
| tests | point-in-time lookup SCD2; Σ fact_seller_month = Σ fact_order_item | S7, F5 |
