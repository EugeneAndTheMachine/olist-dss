{#-
    1 dòng / zip prefix 5 số. Role-playing: customer geo, seller geo.
    Tập zip = geolocation ∪ customers ∪ sellers (S1: 157 zip khách + 7 seller không có trong geolocation).
    city/state ưu tiên geolocation; zip không có trong geolocation → lấy từ customers/sellers, lat/lng null.
    Star (không snowflake): state_name, region_name, dân số nằm luôn trong dim.
-#}
with geo as (
    select zip_prefix, city, state_code, latitude, longitude
    from {{ ref('stg_geolocation') }}
),

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
    where zip_prefix is not null
    group by zip_prefix, city, state_code
    order by zip_prefix, count(*) desc, city, state_code
),

zips as (
    select zip_prefix from geo
    union
    select zip_prefix from addr_mode
),

states as (
    select
        s.state_code,
        s.state_name,
        s.region_name,
        p.ibge_state_id,
        p.population_2018 as state_population
    from {{ ref('stg_br_states') }} as s
    left join {{ ref('br_state_population') }} as p
        on s.state_code = p.state_code
),

joined as (
    select
        z.zip_prefix,
        coalesce(g.city, a.city) as city,
        coalesce(g.state_code, a.state_code) as state_code,
        g.latitude,
        g.longitude,
        g.zip_prefix is not null as in_geolocation
    from zips as z
    left join geo as g on z.zip_prefix = g.zip_prefix
    left join addr_mode as a on z.zip_prefix = a.zip_prefix
),

final as (
    select
        {{ int_sk(['j.zip_prefix']) }} as geo_key,
        j.zip_prefix,
        j.city,
        j.state_code,
        st.state_name,
        st.region_name,
        j.latitude,
        j.longitude,
        st.ibge_state_id,
        st.state_population,
        j.in_geolocation
    from joined as j
    left join states as st on j.state_code = st.state_code

    union all

    select
        {{ unknown_key() }},
        'unknown',
        'unknown',
        'NA',
        'Unknown',
        'Unknown',
        null::double precision,
        null::double precision,
        null::int,
        null::bigint,
        false
)

select * from final
