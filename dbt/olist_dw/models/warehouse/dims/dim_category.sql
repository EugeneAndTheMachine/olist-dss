{#- Member -1 viết inline cho tới khi macro unknown member dùng chung (C-R3, owner C-W1) có trên main. -#}
with seed as (
    select product_category_name as category_pt, category_group
    from {{ ref('category_group') }}
),

names as (
    select distinct category_pt, category_en from {{ ref('stg_products') }}
),

categories as (
    select
        {{ int_sk(['s.category_pt']) }} as category_key,
        s.category_pt,
        coalesce(n.category_en, s.category_pt) as category_en,
        case
            when s.category_pt = 'unknown' then 'Unknown'
            else initcap(replace(coalesce(n.category_en, s.category_pt), '_', ' '))
        end as category_name,
        s.category_group,
        (s.category_pt <> 'unknown')::int::smallint as is_rankable
    from seed as s
    left join names as n on n.category_pt = s.category_pt
)

select * from categories
union all
select -1, 'not_found', 'not_found', 'Not found', 'Unknown', 0::smallint
