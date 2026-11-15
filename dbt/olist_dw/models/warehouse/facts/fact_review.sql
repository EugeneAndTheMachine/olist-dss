{#- Date key và member -1 viết inline cho tới khi macro dùng chung (C-R3, owner C-W1) có trên main. -#}
with reviews as (
    select * from {{ ref('stg_order_reviews') }}
),

orders as (
    select order_id, customer_id, order_status, purchased_at from {{ ref('stg_orders') }}
),

customer_map as (
    select customer_id, customer_unique_id, customer_zip_prefix from {{ ref('int_customer_map') }}
)

select
    coalesce(to_char(r.review_created_at, 'YYYYMMDD')::int, -1) as review_creation_date_key,
    coalesce(to_char(r.review_answered_at, 'YYYYMMDD')::int, -1) as review_answer_date_key,
    coalesce(c.customer_key, -1) as customer_key,
    coalesce(s.seller_key, -1) as primary_seller_key,
    coalesce(cg.geo_key, -1) as customer_geo_key,
    coalesce(st.order_status_key, -1) as order_status_key,
    r.review_id,
    r.order_id,
    1::smallint as review_count,
    r.review_score as score_sum,
    (r.review_score <= 2)::int::smallint as is_low_score,
    r.has_comment,
    r.comment_length,
    extract(epoch from r.review_answered_at - r.review_created_at) / 3600.0 as response_hours,
    r.is_latest_for_order
from reviews as r
left join orders as o on o.order_id = r.order_id
left join customer_map as m on m.customer_id = o.customer_id
left join {{ ref('dim_customer') }} as c on c.customer_unique_id = m.customer_unique_id
left join {{ ref('dim_geography') }} as cg on cg.zip_prefix = m.customer_zip_prefix
left join {{ ref('int_order_primary_seller') }} as ps on ps.order_id = r.order_id
-- BR-CW10-1: cùng quy ước SCD2 với fact_order_item, theo ngày mua của đơn.
left join {{ ref('dim_seller') }} as s
    on s.seller_id = ps.seller_id
    and o.purchased_at::date between s.valid_from and s.valid_to
left join {{ ref('dim_order_status') }} as st on st.order_status = o.order_status
