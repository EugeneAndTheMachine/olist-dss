{#- C-B1: v_dim_customer — 1 dòng / người mua thật + -1. -#}
select
    customer_key,
    customer_unique_id,
    customer_geo_key,
    first_order_date_key,
    order_count,
    is_repeat_customer
from {{ ref('dim_customer') }}
