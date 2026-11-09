{#- Làm sạch inline (BR-S1…BR-S5) cho tới khi macro clean_* dùng chung (C-R1, owner C-S1) có trên main. -#}
with source as (
    select * from {{ source('raw', 'sellers') }}
),

deduped as (
    select
        *,
        row_number() over (partition by trim(seller_id) order by _loaded_at desc) as _rn
    from source
),

final as (
    select
        nullif(trim(seller_id), '') as seller_id,
        lpad(nullif(trim(seller_zip_code_prefix), ''), 5, '0') as seller_zip_prefix,
        nullif(regexp_replace(lower(public.unaccent(trim(seller_city))), '\s+', ' ', 'g'), '') as seller_city,
        nullif(upper(trim(seller_state)), '') as seller_state,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
)

select * from final
