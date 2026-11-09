{#-
    C-W7: int_order_primary_seller — Seller đại diện cho đơn hàng ở các fact cấp đơn (fact_order_fulfillment, fact_review).
    Rule BR-W5: seller của item có price cao nhất trong đơn; hoà → seller_id nhỏ nhất theo thứ tự chữ.
-#}
select distinct on (order_id)
    order_id,
    seller_id,
    seller_id as primary_seller_id
from {{ ref('stg_order_items') }}
order by order_id, price desc, seller_id

