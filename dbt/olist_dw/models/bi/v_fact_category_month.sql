select
    category_key,
    customer_state_code,
    month_date_key,
    to_date(month_date_key::text, 'YYYYMMDD') as month_date,
    orders,
    items,
    gmv,
    freight,
    customers,
    sellers_active,
    review_count,
    score_sum,
    low_score_count,
    delivered_orders,
    late_orders,
    weight_g_sum,
    weight_g_items
from {{ ref('fact_category_month') }}
where month_date_key <> -1
