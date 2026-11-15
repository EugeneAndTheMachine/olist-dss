{#-
    C-B1: v_dim_date — Bảng Date cho Power BI (role-playing bằng 1 bảng + inactive relationship).
    Bỏ dòng -1: Power BI chỉ cho "Mark as date table" khi cột Date không null và không trùng.
-#}
select
    date_key,
    full_date as "Date",
    day_name as "Day Name",
    day_of_week_no as "Day Of Week No",
    is_weekend as "Is Weekend",
    iso_week as "ISO Week",
    month_no as "Month No",
    month_name as "Month Name",
    left(month_name, 3) as "Month Short",
    quarter as "Quarter No",
    'Q' || quarter as "Quarter",
    year as "Year",
    year_month as "Year Month",
    year * 100 + month_no as "Year Month Sort",
    date_trunc('month', full_date)::date as "Month Start",
    is_black_friday_week as "Is Black Friday Week",
    full_date between '{{ var("analysis_start") }}'::date and '{{ var("analysis_end") }}'::date
        as "In Analysis Window"
from {{ ref('dim_date') }}
where date_key <> {{ unknown_key() }}

