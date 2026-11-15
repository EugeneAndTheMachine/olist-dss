{#- Date key và member -1 viết inline cho tới khi macro dùng chung (C-R3, owner C-W1) có trên main. -#}
with items as (
    select * from {{ ref('stg_order_items') }}
),

orders as (
    select order_id, customer_id, order_status, purchased_at from {{ ref('stg_orders') }}
),

customer_map as (
    select customer_id, customer_unique_id, customer_zip_prefix from {{ ref('int_customer_map') }}
)

select
    coalesce(to_char(o.purchased_at, 'YYYYMMDD')::int, -1) as purchase_date_key,
    coalesce(to_char(i.shipping_limit_at, 'YYYYMMDD')::int, -1) as shipping_limit_date_key,
    coalesce(c.customer_key, -1) as customer_key,
    coalesce(p.product_key, -1) as product_key,
    coalesce(s.seller_key, -1) as seller_key,
    coalesce(cg.geo_key, -1) as customer_geo_key,
    coalesce(s.seller_geo_key, -1) as seller_geo_key,
    coalesce(st.order_status_key, -1) as order_status_key,
    i.order_id,
    i.order_item_id,
    i.seller_id,
    i.price as item_price,
    i.freight_value,
    i.price + i.freight_value as item_total,
    1::smallint as item_count
from items as i
left join orders as o on o.order_id = i.order_id
left join customer_map as m on m.customer_id = o.customer_id
left join {{ ref('dim_customer') }} as c on c.customer_unique_id = m.customer_unique_id
left join {{ ref('dim_geography') }} as cg on cg.zip_prefix = m.customer_zip_prefix
left join {{ ref('dim_product') }} as p on p.product_id = i.product_id
-- BR-CW8-1: phiên bản seller hiệu lực tại ngày mua; khoảng đóng theo contract C-W4.
left join {{ ref('dim_seller') }} as s
    on s.seller_id = i.seller_id
    and o.purchased_at::date between s.valid_from and s.valid_to
left join {{ ref('dim_order_status') }} as st on st.order_status = o.order_status
