# dbt models — tiến độ theo task

Đã có (02/11/2026, `dbt build` 334/334 xanh: 60 model, 269 test, 5 seed):

| Layer | Model | Task |
| --- | --- | --- |
| staging | `stg_orders`, `stg_order_items`, `stg_order_payments`, `stg_order_reviews`, `stg_customers`, `stg_sellers`, `stg_products`, `stg_geolocation`, `stg_product_category_name_translation`, `stg_mql`, `stg_closed_deals`, `stg_br_states`, `stg_calendar_events`, `stg_br_holidays` | S3 |
| intermediate | `int_customer_map` | S3 |
| intermediate | `int_order_primary_seller`, `int_order_agg` | F1 |
| intermediate | `int_seller_month_metrics`, `int_seller_tier_monthly`, `int_seller_tier_versions` | S6 |
| warehouse/dims | `dim_date`, `dim_order_status`, `dim_geography`, `dim_product`, `dim_customer`, `dim_payment_type` | S4 |
| warehouse/dims | `dim_seller` (SCD2 trên seller_tier) | S6 |
| warehouse/dims | `dim_lead_origin`, `dim_lead_profile`, `dim_sales_rep` | S5 |
| warehouse/facts | `fact_order_item`, `fact_payment`, `fact_order_fulfillment`, `fact_review` | F2, F3 |
| warehouse/facts | `fact_seller_month`, `fact_seller_product_activity` | F4 |
| warehouse/facts | `fact_lead_funnel` | S5 |
| quality | `dq_issue_summary` → schema `meta` | S7, F5, P8 |
| bi | 11 `v_dim_*`, 7 `v_fact_*`, `v_dq_latest`, `v_etl_runs`, `v_dq_issue_summary` (docs/bi_layer.md) | F6 |
| tests | `assert_dim_seller_*` (SCD2), `assert_fact_seller_point_in_time`, `assert_reconcile_*`, `assert_fact_unknown_key_share`, `assert_fulfillment_dates_in_order` | S7, F5 |

Macro dùng chung (`macros/`): `int_sk`, `unknown_key`, `coalesce_key`, `date_key`, `clean_text`, `zip5`, `clean_city`, `state_code`, `to_bool`, `haversine_km`, `lag_days`, `tier_sort`, `grant_bi_reader` (on-run-end: user chỉ đọc schema bi).

Cần viết tiếp (implementation.md mục 14):

| Thư mục | Model | Task |
| --- | --- | --- |
| bi | view ML (model_run_id mới nhất), nối segment vào `v_dim_customer` | M3–M7 |
| snapshots | dbt snapshot cho seller tier khi load live (sau backfill) | S6 (COULD) |
| facts | incremental cho stg/fact chính (replay) | F8 |
