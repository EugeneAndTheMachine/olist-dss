{#- C-B1: role seller geo của dim_geography (role-playing), nối v_fact_*[seller_geo_key]. -#}
select
    geo_key,
    zip_prefix,
    zip_prefix_3,
    zip_prefix_2,
    city,
    state_code,
    state_name,
    region_name,
    latitude,
    longitude,
    geo_cell_id,
    geo_cell_lat,
    geo_cell_lng,
    in_geolocation
from {{ ref('dim_geography') }}
