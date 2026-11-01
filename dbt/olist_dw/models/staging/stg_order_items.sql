with source as (
    select * from {{ source('raw', 'order_items') }}
),

deduped as (
    select
        *,
        row_number() over (partition by order_id, order_item_id order by _loaded_at desc) as _rn
    from source
),

typed as (
    select
        {{ clean_text('order_id') }} as order_id,
        {{ clean_text('order_item_id') }}::int as order_item_id,
        {{ clean_text('product_id') }} as product_id,
        {{ clean_text('seller_id') }} as seller_id,
        {{ clean_text('shipping_limit_date') }}::timestamp as shipping_limit_date_raw,
        {{ clean_text('price') }}::numeric(12, 2) as price,
        {{ clean_text('freight_value') }}::numeric(12, 2) as freight_value,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
),

-- Phát hiện khi build fact: 4 item (3 đơn mua 2017) có shipping_limit_date năm 2020 — ngoài phạm vi dim_date
-- và làm is_dispatch_late luôn = 0 → null + _dq_issue.
final as (
    select
        order_id,
        order_item_id,
        product_id,
        seller_id,
        case
            when shipping_limit_date_raw >= '{{ var("date_spine_start") }}'::date
             and shipping_limit_date_raw < '{{ var("date_spine_end") }}'::date
                then shipping_limit_date_raw
        end as shipping_limit_date,
        price,
        freight_value,
        price + freight_value as item_total,
        case
            when shipping_limit_date_raw < '{{ var("date_spine_start") }}'::date
              or shipping_limit_date_raw >= '{{ var("date_spine_end") }}'::date
                then 'shipping_limit_out_of_range'
        end as _dq_issue,
        _batch_id,
        _loaded_at
    from typed
)

select * from final
