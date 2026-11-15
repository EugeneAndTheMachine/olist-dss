{#-
    C-W7: int_order_agg — Tổng hợp item theo đơn cho fact_order_fulfillment.
    Rule BR-W6: order_value = Σ price (cùng cơ sở GMV, không gồm ship); đơn không có item (775 đơn) không có dòng ở đây.
-#}
select
    order_id,
    count(*) as item_count,
    sum(price) as order_value,
    sum(freight_value) as freight_total,
    sum(price + freight_value) as order_total,
    count(distinct seller_id) as seller_count,
    max(shipping_limit_at) as max_shipping_limit_date,
    max(shipping_limit_at) as max_shipping_limit_at
from {{ ref('stg_order_items') }}
group by order_id

