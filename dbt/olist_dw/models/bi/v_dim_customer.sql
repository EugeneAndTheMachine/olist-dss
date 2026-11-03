{#-
    Dim khách (người mua thật). Segment ML (ml.customer_segment_history) sẽ được nối vào view này
    khi làm M4 — hiện chưa có để không phụ thuộc bảng ml đang rỗng.
-#}
select
    customer_key,
    customer_unique_id as "Customer Unique ID",
    first_order_date_key,
    first_order_state as "First Order State",
    order_count_lifetime as "Lifetime Orders",
    case
        when customer_key = {{ unknown_key() }} then 'Unknown'
        when order_count_lifetime >= 2 then 'Repeat'
        else 'One-time'
    end as "Customer Type"
from {{ ref('dim_customer') }}
