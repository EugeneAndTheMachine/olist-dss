{#- C-B1: v_dim_order_status — View trạng thái đơn hàng cho Power BI -#}
select
    order_status_key,
    order_status as "Order Status",
    status_group as "Status Group",
    counts_as_sale as "Counts As Sale"
from {{ ref('dim_order_status') }}

