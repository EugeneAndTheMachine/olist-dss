{#-
    1 dòng / người mua thật (customer_unique_id). Type 1.
    Không chứa segment: segment từ ML được nối ở bi.v_dim_customer (tránh vòng phụ thuộc dw ↔ ml).
-#}
with orders as (
    select
        o.order_id,
        o.order_purchase_timestamp,
        m.customer_unique_id,
        m.customer_zip_prefix,
        m.customer_state
    from {{ ref('stg_orders') }} as o
    inner join {{ ref('int_customer_map') }} as m
        on o.customer_id = m.customer_id
),

first_order as (
    select distinct on (customer_unique_id)
        customer_unique_id,
        order_purchase_timestamp as first_order_at,
        customer_zip_prefix as first_order_zip_prefix,
        customer_state as first_order_state
    from orders
    order by customer_unique_id, order_purchase_timestamp, order_id
),

order_counts as (
    select
        customer_unique_id,
        count(distinct order_id) as order_count_lifetime
    from orders
    group by customer_unique_id
),

final as (
    select
        {{ int_sk(['f.customer_unique_id']) }} as customer_key,
        f.customer_unique_id,
        {{ date_key('f.first_order_at') }} as first_order_date_key,
        f.first_order_state,
        {{ coalesce_key('g.geo_key') }} as customer_geo_key,
        c.order_count_lifetime
    from first_order as f
    inner join order_counts as c on f.customer_unique_id = c.customer_unique_id
    left join {{ ref('dim_geography') }} as g on f.first_order_zip_prefix = g.zip_prefix

    union all

    select
        {{ unknown_key() }},
        'unknown',
        {{ unknown_key() }},
        'NA',
        {{ unknown_key() }},
        0
)

select * from final
