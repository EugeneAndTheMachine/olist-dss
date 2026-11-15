{#-
    C-S1: stg_orders — Đơn hàng đã dedup, ép kiểu, gắn cờ DQ và dẫn xuất cờ giao hàng.
    Rules: BR-S1, BR-S2, BR-S6, BR-S7, BR-O1, BR-O2, BR-O3, BR-O4 (docs/business_rules.md).
-#}
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
        {{ clean_text('order_id') }} as order_id,
        {{ clean_text('customer_id') }} as customer_id,
        lower({{ clean_text('order_status') }}) as order_status,
        {{ clean_text('order_purchase_timestamp') }}::timestamp as order_purchase_timestamp,
        {{ clean_text('order_approved_at') }}::timestamp as order_approved_at,
        {{ clean_text('order_delivered_carrier_date') }}::timestamp as order_delivered_carrier_date,
        {{ clean_text('order_delivered_customer_date') }}::timestamp as order_delivered_customer_date,
        {{ clean_text('order_estimated_delivery_date') }}::timestamp as order_estimated_delivery_date,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
),

-- BR-O4 (profiling phát hiện 2): 0 dòng delivered < purchase; 1 359 carrier < approved; 166 carrier < purchase; 23 delivered < carrier.
-- Chỉ delivered < purchase làm null ngày giao; các lỗi còn lại giữ timestamp, gắn cờ _dq_issue, lag âm được null ở fact.
checked as (
    select
        *,
        nullif(concat_ws(',',
            case when order_delivered_customer_date < order_purchase_timestamp then 'delivered_before_purchase' end,
            case when order_delivered_carrier_date < order_purchase_timestamp then 'carrier_before_purchase' end,
            case when order_delivered_carrier_date < order_approved_at then 'carrier_before_approved' end,
            case when order_delivered_customer_date < order_delivered_carrier_date then 'delivered_before_carrier' end
        ), '') as _dq_issue
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
        case
            when order_delivered_customer_date < order_purchase_timestamp then null
            else order_delivered_customer_date
        end as order_delivered_customer_date,
        order_estimated_delivery_date,
        _dq_issue,
        _batch_id,
        _loaded_at
    from checked
),

final as (
    select
        *,
        order_purchase_timestamp as purchased_at,
        order_approved_at as approved_at,
        order_delivered_carrier_date as delivered_carrier_at,
        order_delivered_customer_date as delivered_customer_at,
        order_estimated_delivery_date as estimated_delivery_at,
        -- BR-O2: đã giao khi status = delivered VÀ có ngày khách nhận
        (order_status = 'delivered' and order_delivered_customer_date is not null) as is_delivered,
        -- BR-O3: so sánh theo ngày (::date) vì estimated_delivery_date luôn có giờ 00:00:00
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

