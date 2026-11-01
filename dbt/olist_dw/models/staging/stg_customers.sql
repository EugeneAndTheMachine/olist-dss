with source as (
    select * from {{ source('raw', 'customers') }}
),

deduped as (
    select
        *,
        row_number() over (partition by customer_id order by _loaded_at desc) as _rn
    from source
),

final as (
    select
        {{ clean_text('customer_id') }} as customer_id,
        {{ clean_text('customer_unique_id') }} as customer_unique_id,
        {{ zip5('customer_zip_code_prefix') }} as customer_zip_prefix,
        {{ clean_city('customer_city') }} as customer_city,
        {{ state_code('customer_state') }} as customer_state,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
)

select * from final
