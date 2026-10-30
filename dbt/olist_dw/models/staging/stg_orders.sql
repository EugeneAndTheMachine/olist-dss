{#- Model mẫu cho staging: dedup theo natural key → ép kiểu → rule DQ → cờ dẫn xuất (CLAUDE.md mục 9) -#}
with source as (
    select * from {{ source('raw', 'orders') }}
),

deduped as (
    select
        *,
        row_number() over (partition by order_id order by _loaded_at desc) as _rn
    from source
),

typed as (
    select
        nullif(trim(order_id), '') as order_id,
        nullif(trim(customer_id), '') as customer_id,
        lower(nullif(trim(order_status), '')) as order_status,
        nullif(trim(order_purchase_timestamp), '')::timestamp as order_purchase_timestamp,
        nullif(trim(order_approved_at), '')::timestamp as order_approved_at,
        nullif(trim(order_delivered_carrier_date), '')::timestamp as order_delivered_carrier_date,
        nullif(trim(order_delivered_customer_date), '')::timestamp as order_delivered_customer_date,
        nullif(trim(order_estimated_delivery_date), '')::timestamp as order_estimated_delivery_date,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
),

checked as (
    select
        *,
        case
            when order_delivered_customer_date < order_purchase_timestamp then 'delivered_before_purchase'
        end as _dq_issue
    from typed
),

cleaned as (
    select
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        -- Giao trước ngày mua là lỗi dữ liệu → null, giữ cờ _dq_issue
        case when _dq_issue is null then order_delivered_customer_date end as order_delivered_customer_date,
        order_estimated_delivery_date,
        _dq_issue,
        _batch_id,
        _loaded_at
    from checked
),

final as (
    select
        *,
        (order_status = 'delivered' and order_delivered_customer_date is not null) as is_delivered,
        (
            order_status = 'delivered'
            and order_delivered_customer_date is not null
            and order_delivered_customer_date::date > order_estimated_delivery_date::date
        ) as is_late,
        case
            when order_status = 'delivered' and order_delivered_customer_date is not null
                then order_delivered_customer_date::date - order_estimated_delivery_date::date
        end as delay_days
    from cleaned
)

select * from final
