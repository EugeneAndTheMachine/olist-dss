{#-
    Primary seller của đơn (implementation.md mục 7.3): seller của item có price cao nhất;
    hoà → seller_id nhỏ nhất theo thứ tự chữ. Dùng cho fact cấp đơn (fulfillment, review).
    S1: chỉ 1 278 đơn (1,3%) có > 1 seller nên rule này ảnh hưởng nhỏ.
-#}
select distinct on (order_id)
    order_id,
    seller_id as primary_seller_id
from {{ ref('stg_order_items') }}
order by order_id, price desc, seller_id
