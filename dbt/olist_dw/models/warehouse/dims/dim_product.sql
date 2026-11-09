{#- Member -1 viết inline cho tới khi macro unknown member dùng chung (C-R3, owner C-W1) có trên main. -#}
with products as (
    select * from {{ ref('stg_products') }}
),

categories as (
    select category_key, category_pt from {{ ref('dim_category') }}
),

final as (
    select
        {{ int_sk(['p.product_id']) }} as product_key,
        p.product_id,
        coalesce(c.category_key, -1) as category_key,
        p.name_length,
        p.description_length,
        p.photos_qty,
        p.weight_g,
        p.length_cm,
        p.height_cm,
        p.width_cm,
        p.volume_cm3,
        case
            when p.weight_g is null then 'Unknown'
            when p.weight_g < 500 then '< 0.5 kg'
            when p.weight_g < 2000 then '0.5–2 kg'
            when p.weight_g < 5000 then '2–5 kg'
            when p.weight_g < 10000 then '5–10 kg'
            else '>= 10 kg'
        end as weight_band,
        case
            when p.volume_cm3 is null then 'Unknown'
            when p.volume_cm3 < 1000 then '< 1 L'
            when p.volume_cm3 < 10000 then '1–10 L'
            when p.volume_cm3 < 50000 then '10–50 L'
            else '>= 50 L'
        end as size_band
    from products as p
    left join categories as c on c.category_pt = p.category_pt
)

select * from final
union all
select
    -1, 'not_found', -1,
    null::int, null::int, null::int,
    null::numeric, null::numeric, null::numeric, null::numeric, null::numeric,
    'Unknown', 'Unknown'
