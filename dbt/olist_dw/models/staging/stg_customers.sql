{#- Làm sạch inline (BR-S1…BR-S5) cho tới khi macro clean_* dùng chung (C-R1, owner C-S1) có trên main. -#}
with source as (
    select * from {{ source('raw', 'customers') }}
),

deduped as (
    select
        *,
        row_number() over (partition by trim(customer_id) order by _loaded_at desc) as _rn
    from source
),

final as (
    select
        nullif(trim(customer_id), '') as customer_id,
        nullif(trim(customer_unique_id), '') as customer_unique_id,
        lpad(nullif(trim(customer_zip_code_prefix), ''), 5, '0') as customer_zip_prefix,
        nullif(regexp_replace(lower(public.unaccent(trim(customer_city))), '\s+', ' ', 'g'), '') as customer_city,
        nullif(upper(trim(customer_state)), '') as customer_state,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
)

select * from final
