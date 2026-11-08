{#- Làm sạch text inline cho tới khi macro clean_text dùng chung (C-R1, owner C-S1) có trên main. -#}
with source as (
    select * from {{ source('raw', 'products') }}
),

deduped as (
    select
        *,
        row_number() over (partition by product_id order by _loaded_at desc) as _rn
    from source
),

typed as (
    select
        nullif(trim(product_id), '') as product_id,
        lower(nullif(trim(product_category_name), '')) as category_pt_raw,
        nullif(trim(product_name_lenght), '')::numeric::int as name_length,
        nullif(trim(product_description_lenght), '')::numeric::int as description_length,
        nullif(trim(product_photos_qty), '')::numeric::int as photos_qty,
        nullif(trim(product_weight_g), '')::numeric as weight_g_raw,
        nullif(trim(product_length_cm), '')::numeric as length_cm,
        nullif(trim(product_height_cm), '')::numeric as height_cm,
        nullif(trim(product_width_cm), '')::numeric as width_cm,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
),

translation as (
    select category_pt, category_en from {{ ref('stg_product_category_name_translation') }}
)

select
    p.product_id,
    coalesce(p.category_pt_raw, 'unknown') as category_pt,
    coalesce(t.category_en, p.category_pt_raw, 'unknown') as category_en,
    p.name_length,
    p.description_length,
    p.photos_qty,
    nullif(p.weight_g_raw, 0) as weight_g,
    p.length_cm,
    p.height_cm,
    p.width_cm,
    p.length_cm * p.height_cm * p.width_cm as volume_cm3,
    nullif(concat_ws(',',
        case when p.category_pt_raw is null then 'missing_category' end,
        case when p.weight_g_raw = 0 then 'weight_zero' end
    ), '') as _dq_issue,
    p._batch_id,
    p._loaded_at
from typed as p
left join translation as t on t.category_pt = p.category_pt_raw
