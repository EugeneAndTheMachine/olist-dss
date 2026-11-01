{#-
    Gộp ~1M điểm về 1 dòng / zip prefix (S1 A3: ~52,6 điểm / zip).
    - lat/lng = trung bình các điểm trong bounding box Brazil (lat −34…5,5; lng −74…−34); zip không còn điểm hợp lệ → null.
    - city / state = giá trị xuất hiện nhiều nhất (city đã bỏ dấu; 8 zip có > 1 bang).
-#}
with source as (
    select * from {{ source('raw', 'geolocation') }}
),

-- Raw append theo batch: chỉ lấy batch mới nhất để không nhân điểm khi nạp lại
latest_batch as (
    select *
    from source
    where _loaded_at = (select max(_loaded_at) from source)
),

points as (
    select
        {{ zip5('geolocation_zip_code_prefix') }} as zip_prefix,
        {{ clean_text('geolocation_lat') }}::double precision as lat,
        {{ clean_text('geolocation_lng') }}::double precision as lng,
        {{ clean_city('geolocation_city') }} as city,
        {{ state_code('geolocation_state') }} as state_code
    from latest_batch
),

flagged as (
    select
        *,
        (lat between -34 and 5.5 and lng between -74 and -34) as in_brazil
    from points
    where zip_prefix is not null
),

coords as (
    select
        zip_prefix,
        avg(lat) filter (where in_brazil) as latitude,
        avg(lng) filter (where in_brazil) as longitude,
        count(*) as n_points,
        count(*) filter (where not in_brazil) as n_points_outside_brazil
    from flagged
    group by zip_prefix
),

city_mode as (
    select distinct on (zip_prefix) zip_prefix, city
    from flagged
    where city is not null
    group by zip_prefix, city
    order by zip_prefix, count(*) desc, city
),

state_mode as (
    select distinct on (zip_prefix) zip_prefix, state_code
    from flagged
    where state_code is not null
    group by zip_prefix, state_code
    order by zip_prefix, count(*) desc, state_code
)

select
    c.zip_prefix,
    cm.city,
    sm.state_code,
    c.latitude,
    c.longitude,
    c.n_points,
    c.n_points_outside_brazil
from coords as c
left join city_mode as cm on c.zip_prefix = cm.zip_prefix
left join state_mode as sm on c.zip_prefix = sm.zip_prefix
