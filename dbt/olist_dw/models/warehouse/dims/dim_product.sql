{#-
    1 dòng / product_id. Hierarchy product → category → category_group (seed).
    Category thiếu bản dịch (S1: pc_gamer, portateis_cozinha_e_preparadores_de_alimentos) → giữ tên PT.
-#}
with products as (
    select * from {{ ref('stg_products') }}
),

translation as (
    select * from {{ ref('stg_product_category_name_translation') }}
),

category_group as (
    select * from {{ ref('category_group') }}
),

final as (
    select
        {{ int_sk(['p.product_id']) }} as product_key,
        p.product_id,
        p.product_category_name as category_pt,
        case
            when p.product_category_name = 'unknown' then 'unknown'
            else coalesce(t.product_category_name_english, p.product_category_name)
        end as category_en,
        coalesce(cg.category_group, 'Unknown') as category_group,
        p.product_photos_qty as photos_qty,
        p.product_name_length as name_length,
        p.product_description_length as description_length,
        p.product_weight_g as weight_g,
        p.product_length_cm as length_cm,
        p.product_height_cm as height_cm,
        p.product_width_cm as width_cm,
        p.product_volume_cm3 as volume_cm3,
        case
            when p.product_weight_g is null then 'Unknown'
            when p.product_weight_g < 500 then '< 0.5 kg'
            when p.product_weight_g < 2000 then '0.5–2 kg'
            when p.product_weight_g < 5000 then '2–5 kg'
            when p.product_weight_g < 10000 then '5–10 kg'
            else '>= 10 kg'
        end as weight_band,
        case
            when p.product_volume_cm3 is null then 'Unknown'
            when p.product_volume_cm3 < 1000 then '< 1 L'
            when p.product_volume_cm3 < 10000 then '1–10 L'
            when p.product_volume_cm3 < 50000 then '10–50 L'
            else '>= 50 L'
        end as size_band
    from products as p
    left join translation as t on p.product_category_name = t.product_category_name
    left join category_group as cg on p.product_category_name = cg.product_category_name

    union all

    select
        {{ unknown_key() }},
        'unknown',
        'unknown',
        'unknown',
        'Unknown',
        null::int,
        null::int,
        null::int,
        null::numeric,
        null::numeric,
        null::numeric,
        null::numeric,
        null::numeric,
        'Unknown',
        'Unknown'
)

select * from final
