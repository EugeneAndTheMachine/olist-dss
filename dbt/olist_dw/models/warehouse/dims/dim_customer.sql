{#-
    C-W3: dim_customer — 1 dòng / người mua thật (customer_unique_id) + member -1. Type 1.
    Địa chỉ theo từng đơn nằm ở customer_geo_key của fact; ở đây là zip của đơn đầu tiên (BR-W8, BR-CW3-1).
    Rules: BR-CS3-1, BR-CW3-1 … BR-CW3-3 (docs/business_rules.md).
-#}
with orders as (
    select
        o.order_id,
        o.purchased_at,
        m.customer_unique_id,
        m.customer_zip_prefix
    from {{ ref('stg_orders') }} as o
    inner join {{ ref('int_customer_map') }} as m on m.customer_id = o.customer_id
),

-- BR-CW3-1, BR-CW3-2: đơn đầu tiên tính trên mọi đơn; hoà thì order_id nhỏ nhất
first_order as (
    select distinct on (customer_unique_id)
        customer_unique_id,
        purchased_at as first_order_at,
        customer_zip_prefix as first_order_zip_prefix
    from orders
    order by customer_unique_id, purchased_at, order_id
),

order_counts as (
    select customer_unique_id, count(*)::int as order_count
    from orders
    group by customer_unique_id
)

select
    {{ int_sk(['f.customer_unique_id']) }} as customer_key,
    f.customer_unique_id,
    {{ coalesce_key('g.geo_key') }} as customer_geo_key,
    {{ date_key('f.first_order_at') }} as first_order_date_key,
    c.order_count,
    (c.order_count >= 2)::int::smallint as is_repeat_customer
from first_order as f
inner join order_counts as c on c.customer_unique_id = f.customer_unique_id
left join {{ ref('dim_geography') }} as g on g.zip_prefix = f.first_order_zip_prefix

union all

select {{ unknown_key() }}, 'unknown', {{ unknown_key() }}, {{ unknown_key() }}, 0, 0::smallint
