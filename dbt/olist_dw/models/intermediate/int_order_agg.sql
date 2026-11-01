{#- Tổng hợp item theo đơn cho fact_order_fulfillment. Đơn không có item (S1: 775 đơn) không có dòng ở đây. -#}
select
    order_id,
    count(*) as item_count,
    sum(price) as order_value,
    sum(freight_value) as freight_total,
    sum(item_total) as order_total,
    count(distinct seller_id) as seller_count,
    max(shipping_limit_date) as max_shipping_limit_date
from {{ ref('stg_order_items') }}
group by order_id
