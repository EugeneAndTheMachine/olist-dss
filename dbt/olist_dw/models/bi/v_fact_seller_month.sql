{#-
    Hiệu suất seller — 1 seller × 1 tháng. seller_key = version hiệu lực cuối tháng.
    "Is Active" semi-additive: nhiều tháng → trung bình theo tháng, không cộng dồn.
    "Distinct Customers" non-additive: không SUM qua seller / tháng.
-#}
select
    month_date_key,
    seller_key,
    seller_geo_key,
    orders as "Orders",
    items as "Items",
    gmv as "GMV",
    delivered_orders as "Delivered Orders",
    late_orders as "Late Orders",
    cancelled_orders as "Cancelled Orders",
    review_count as "Review Count",
    score_sum as "Score Sum",
    is_active as "Is Active",
    distinct_customers as "Distinct Customers"
from {{ ref('fact_seller_month') }}
