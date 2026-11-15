{#-
    C-W1: dim_date — Dimension ngày từ 2016-01-01 đến 2019-12-31 + dòng unknown (-1).
    Rules: BR-W2, BR-W3, BR-W12 (docs/business_rules.md).
-#}
with spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('date_spine_start') ~ "' as date)",
        end_date="cast('" ~ var('date_spine_end') ~ "' as date) + 1"
    ) }}
),

days as (
    select cast(date_day as date) as full_date
    from spine
),

-- BR-W3 / BR-W12: Black Friday = thứ Sáu thứ 4 của tháng 11 (isodow: thứ Sáu = 5)
black_friday as (
    select
        make_date(y, 11, 1)
        + ((5 - extract(isodow from make_date(y, 11, 1))::int + 7) % 7)
        + 21 as black_friday_date
    from (select distinct extract(year from full_date)::int as y from days) as years
),

final as (
    select
        {{ date_key('d.full_date') }} as date_key,
        d.full_date,
        trim(to_char(d.full_date, 'Day')) as day_name,
        extract(isodow from d.full_date)::int as day_of_week_no,
        extract(isodow from d.full_date) in (6, 7) as is_weekend,
        extract(week from d.full_date)::int as iso_week,
        extract(month from d.full_date)::int as month_no,
        trim(to_char(d.full_date, 'Month')) as month_name,
        extract(quarter from d.full_date)::int as quarter,
        extract(year from d.full_date)::int as year,
        to_char(d.full_date, 'YYYY-MM') as year_month,
        bf.black_friday_date is not null as is_black_friday_week
    from days as d
    left join black_friday as bf
        on date_trunc('week', d.full_date) = date_trunc('week', bf.black_friday_date)

    union all

    select
        {{ unknown_key() }} as date_key,
        null::date as full_date,
        'Unknown' as day_name,
        null::int as day_of_week_no,
        null::boolean as is_weekend,
        null::int as iso_week,
        null::int as month_no,
        'Unknown' as month_name,
        null::int as quarter,
        null::int as year,
        'Unknown' as year_month,
        false as is_black_friday_week
)

select
    date_key,
    full_date,
    day_name,
    day_of_week_no,
    is_weekend,
    iso_week,
    month_no,
    month_name,
    quarter,
    year,
    year_month,
    is_black_friday_week
from final

