with source as (
    select * from {{ source('raw', 'sellers') }}
),

deduped as (
    select
        *,
        row_number() over (partition by seller_id order by _loaded_at desc) as _rn
    from source
),

final as (
    select
        {{ clean_text('seller_id') }} as seller_id,
        {{ zip5('seller_zip_code_prefix') }} as seller_zip_prefix,
        {{ clean_city('seller_city') }} as seller_city,
        {{ state_code('seller_state') }} as seller_state,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
)

select * from final
