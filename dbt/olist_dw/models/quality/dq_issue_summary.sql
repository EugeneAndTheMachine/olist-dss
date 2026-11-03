{#-
    Tổng hợp lỗi chất lượng dữ liệu đã được GIỮ LẠI và gắn cờ (không xoá dòng) — nguồn cho trang Data Quality (8)
    cùng với meta.dq_results (kết quả test dbt). Mỗi dòng: 1 loại lỗi trong 1 model, số dòng bị ảnh hưởng / tổng.
    Danh sách lỗi đến từ profiling S1 (docs/profiling.md) và rule staging (implementation.md mục 9).
-#}
with payment_check as (
    select i.order_id, i.item_total, p.payment_total
    from (
        select order_id, sum(item_total) as item_total
        from {{ ref('fact_order_item') }}
        group by order_id
    ) as i
    inner join (
        select order_id, sum(payment_value) as payment_total
        from {{ ref('fact_payment') }}
        group by order_id
    ) as p on i.order_id = p.order_id
),

orders_issues as (
    select 'stg' as layer, 'stg_orders' as model_name, issue, count(*) as issue_rows
    from {{ ref('stg_orders') }}
    cross join lateral unnest(string_to_array(_dq_issue, ',')) as issue
    where _dq_issue is not null
    group by issue
),

items_issues as (
    select 'stg', 'stg_order_items', _dq_issue, count(*)
    from {{ ref('stg_order_items') }}
    where _dq_issue is not null
    group by _dq_issue
),

payments_issues as (
    select 'stg', 'stg_order_payments', _dq_issue, count(*)
    from {{ ref('stg_order_payments') }}
    where _dq_issue is not null
    group by _dq_issue
),

products_issues as (
    select 'stg', 'stg_products', issue, count(*)
    from {{ ref('stg_products') }}
    cross join lateral unnest(string_to_array(_dq_issue, ',')) as issue
    where _dq_issue is not null
    group by issue
),

funnel_issues as (
    select 'dw', 'fact_lead_funnel', _dq_issue, count(*)
    from {{ ref('fact_lead_funnel') }}
    where _dq_issue is not null
    group by _dq_issue
),

-- Bất thường đã biết nhưng không gắn cờ trên dòng
known_anomalies as (
    select 'stg', 'stg_geolocation', 'points_outside_brazil', sum(n_points_outside_brazil)
    from {{ ref('stg_geolocation') }}
    union all
    select 'dw', 'dim_geography', 'zip_without_coordinates', count(*)
    from {{ ref('dim_geography') }}
    where latitude is null and geo_key <> -1
    union all
    select 'dw', 'fact_order_fulfillment', 'order_without_items', count(*)
    from {{ ref('fact_order_fulfillment') }}
    where item_count = 0
    union all
    select 'dw', 'dim_seller', 'funnel_seller_not_in_sellers', count(*)
    from {{ ref('dim_seller') }}
    where is_from_funnel and not has_sales and is_current
    union all
    select 'stg', 'stg_order_reviews', 'order_with_multiple_reviews', count(distinct order_id)
    from {{ ref('stg_order_reviews') }}
    where not is_latest_for_order
    union all
    -- Test assert_reconcile_item_vs_payment chỉ cảnh báo khi > 1000 đơn; dbt ghi failures = 0 khi dưới ngưỡng
    -- → đếm lại ở đây để trang DQ vẫn thấy số đơn lệch thật
    select 'dw', 'reconcile_item_vs_payment', 'payment_mismatch_over_tolerance', count(*)
    from payment_check
    where abs(payment_total - item_total) > greatest(1, 0.01 * item_total)
),

totals as (
    select 'stg_orders' as model_name, count(*) as total_rows from {{ ref('stg_orders') }}
    union all select 'stg_order_items', count(*) from {{ ref('stg_order_items') }}
    union all select 'stg_order_payments', count(*) from {{ ref('stg_order_payments') }}
    union all select 'stg_products', count(*) from {{ ref('stg_products') }}
    union all select 'fact_lead_funnel', count(*) from {{ ref('fact_lead_funnel') }}
    union all select 'stg_geolocation', sum(n_points) from {{ ref('stg_geolocation') }}
    union all select 'dim_geography', count(*) - 1 from {{ ref('dim_geography') }}
    union all select 'fact_order_fulfillment', count(*) from {{ ref('fact_order_fulfillment') }}
    union all select 'dim_seller', count(*) filter (where is_current) - 1 from {{ ref('dim_seller') }}
    union all select 'stg_order_reviews', count(distinct order_id) from {{ ref('stg_order_reviews') }}
    union all select 'reconcile_item_vs_payment', count(*) from payment_check
),

all_issues as (
    select * from orders_issues
    union all select * from items_issues
    union all select * from payments_issues
    union all select * from products_issues
    union all select * from funnel_issues
    union all select * from known_anomalies
)

select
    i.layer,
    i.model_name,
    i.issue,
    i.issue_rows::bigint as issue_rows,
    t.total_rows::bigint as total_rows,
    round(100.0 * i.issue_rows / nullif(t.total_rows, 0), 3) as issue_pct,
    current_timestamp as checked_at
from all_issues as i
left join totals as t on i.model_name = t.model_name
