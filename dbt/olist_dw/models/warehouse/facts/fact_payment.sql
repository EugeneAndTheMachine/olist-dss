{#- Transaction fact — grain: 1 lần thanh toán (order_id + payment_sequential). -#}
with payments as (
    select * from {{ ref('stg_order_payments') }}
),

orders as (
    select order_id, customer_id, order_status, order_purchase_timestamp
    from {{ ref('stg_orders') }}
),

final as (
    select
        pay.order_id,
        pay.payment_sequential,
        {{ date_key('o.order_purchase_timestamp') }} as purchase_date_key,
        {{ coalesce_key('c.customer_key') }} as customer_key,
        {{ coalesce_key('pt.payment_type_key') }} as payment_type_key,
        {{ coalesce_key('st.order_status_key') }} as order_status_key,
        pay.payment_value,
        1 as payment_count,
        pay.payment_installments,
        current_timestamp as _dw_loaded_at
    from payments as pay
    inner join orders as o on pay.order_id = o.order_id
    left join {{ ref('int_customer_map') }} as m on o.customer_id = m.customer_id
    left join {{ ref('dim_customer') }} as c on m.customer_unique_id = c.customer_unique_id
    left join {{ ref('dim_payment_type') }} as pt
        on pay.payment_type = pt.payment_type
        and pay.payment_installments between pt.min_instalments and pt.max_instalments
    left join {{ ref('dim_order_status') }} as st on o.order_status = st.order_status
)

select * from final
