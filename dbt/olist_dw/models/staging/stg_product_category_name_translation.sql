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
    lower(nullif(trim(product_category_name), '')) as category_pt,
    lower(nullif(trim(product_category_name_english), '')) as category_en,
    _batch_id,
    _loaded_at::timestamptz as _loaded_at
from deduped
where _rn = 1
