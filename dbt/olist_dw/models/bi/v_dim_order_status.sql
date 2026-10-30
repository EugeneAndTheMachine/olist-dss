{#- Model mẫu cho schema bi: view mỏng, tên cột thân thiện, không đổi grain -#}
select
    order_status_key,
    order_status as "Order Status",
    status_group as "Status Group",
    counts_as_sale as "Counts As Sale"
from {{ ref('dim_order_status') }}
