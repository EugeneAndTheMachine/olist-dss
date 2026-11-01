with source as (
    select * from {{ source('raw', 'product_category_name_translation') }}
),

deduped as (
    select
        *,
        row_number() over (partition by product_category_name order by _loaded_at desc) as _rn
    from source
)

select
    lower({{ clean_text('product_category_name') }}) as product_category_name,
    lower({{ clean_text('product_category_name_english') }}) as product_category_name_english
from deduped
where _rn = 1
