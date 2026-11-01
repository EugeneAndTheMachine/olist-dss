{#-
    Transaction fact — grain: 1 item của 1 đơn (order_id + order_item_id).
    seller_key = version của dim_seller hiệu lực tại ngày mua (point-in-time, sẵn sàng cho SCD2).
-#}
with items as (
    select * from {{ ref('stg_order_items') }}
),

orders as (
    select order_id, customer_id, order_status, order_purchase_timestamp
    from {{ ref('stg_orders') }}
),

customer_map as (
    select customer_id, customer_unique_id, customer_zip_prefix
    from {{ ref('int_customer_map') }}
),

final as (
    select
        i.order_id,
        i.order_item_id,
        {{ date_key('o.order_purchase_timestamp') }} as purchase_date_key,
        {{ date_key('i.shipping_limit_date') }} as shipping_limit_date_key,
        {{ coalesce_key('c.customer_key') }} as customer_key,
        {{ coalesce_key('p.product_key') }} as product_key,
        {{ coalesce_key('s.seller_key') }} as seller_key,
        {{ coalesce_key('cg.geo_key') }} as customer_geo_key,
        {{ coalesce_key('s.seller_geo_key') }} as seller_geo_key,
        {{ coalesce_key('st.order_status_key') }} as order_status_key,
        i.price as item_price,
        i.freight_value,
        i.item_total,
        1 as item_count,
        current_timestamp as _dw_loaded_at
    from items as i
    inner join orders as o on i.order_id = o.order_id
    left join customer_map as m on o.customer_id = m.customer_id
    left join {{ ref('dim_customer') }} as c on m.customer_unique_id = c.customer_unique_id
    left join {{ ref('dim_geography') }} as cg on m.customer_zip_prefix = cg.zip_prefix
    left join {{ ref('dim_product') }} as p on i.product_id = p.product_id
    left join {{ ref('dim_seller') }} as s
        on i.seller_id = s.seller_id
        and o.order_purchase_timestamp::date between s.valid_from and s.valid_to
    left join {{ ref('dim_order_status') }} as st on o.order_status = st.order_status
)

select * from final
