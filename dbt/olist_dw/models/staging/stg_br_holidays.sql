with source as (
    select * from {{ source('raw', 'br_holidays') }}
),

typed as (
    select
        nullif(trim(holiday_date), '')::date as holiday_date,
        nullif(trim(holiday_name), '') as holiday_name
    from source
),

-- Một ngày có thể trùng nhiều lễ / nhiều batch → gộp về 1 dòng / ngày
final as (
    select
        holiday_date,
        string_agg(distinct holiday_name, '; ' order by holiday_name) as holiday_name
    from typed
    where holiday_date is not null
    group by holiday_date
)

select * from final
