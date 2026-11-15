{#-
    C-W2: dim_geography — 1 dòng / zip prefix 5 số + member -1. Type 1, role-playing (customer geo, seller geo).
    Rules: BR-W9, BR-CW2-1 … BR-CW2-3, BR-W12 (docs/business_rules.md).
-#}
with geo as (
    select zip_prefix, city, state_code, latitude, longitude
    from {{ ref('stg_geolocation') }}
),

-- BR-CW2-2: zip không có trong geolocation lấy city / state phổ biến nhất từ customers ∪ sellers
addr as (
    select customer_zip_prefix as zip_prefix, customer_city as city, customer_state as state_code
    from {{ ref('stg_customers') }}
    union all
    select seller_zip_prefix, seller_city, seller_state
    from {{ ref('stg_sellers') }}
),

addr_mode as (
    select distinct on (zip_prefix) zip_prefix, city, state_code
    from addr
    group by zip_prefix, city, state_code
    order by zip_prefix, count(*) desc, city, state_code
),

-- BR-W9, BR-CW2-1: tập zip = geolocation ∪ customers ∪ sellers
zips as (
    select zip_prefix from geo
    union
    select zip_prefix from addr_mode
),

joined as (
    select
        z.zip_prefix,
        coalesce(g.city, a.city) as city,
        coalesce(g.state_code, a.state_code) as state_code,
        g.latitude,
        g.longitude,
        (g.zip_prefix is not null)::int::smallint as in_geolocation,
        -- BR-CW2-3 / BR-K4: ô lưới 0,5° × 0,5°, cùng công thức với ml/p1_logistics/hub_placement.py
        floor(g.latitude / 0.5)::int as cell_lat_idx,
        floor(g.longitude / 0.5)::int as cell_lng_idx
    from zips as z
    left join geo as g on g.zip_prefix = z.zip_prefix
    left join addr_mode as a on a.zip_prefix = z.zip_prefix
)

select
    {{ int_sk(['j.zip_prefix']) }} as geo_key,
    j.zip_prefix,
    left(j.zip_prefix, 3) as zip_prefix_3,
    left(j.zip_prefix, 2) as zip_prefix_2,
    j.city,
    j.state_code,
    s.state_name,
    s.region_name,
    j.latitude,
    j.longitude,
    j.cell_lat_idx || '_' || j.cell_lng_idx as geo_cell_id,
    (j.cell_lat_idx + 0.5) * 0.5 as geo_cell_lat,
    (j.cell_lng_idx + 0.5) * 0.5 as geo_cell_lng,
    j.in_geolocation
from joined as j
left join {{ ref('br_states') }} as s on s.state_code = j.state_code

union all

-- BR-W2: member -1; state_code khác null để join theo bang (vd fact_category_month) không làm mất dòng
select
    {{ unknown_key() }}, '-1', '-1', '-1', 'unknown', 'NA', 'Unknown', 'Unknown',
    null, null, null, null, null, 0::smallint
