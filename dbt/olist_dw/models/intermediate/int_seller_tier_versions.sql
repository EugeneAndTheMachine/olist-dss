{#-
    S6 bước 3: tier tháng → các version SCD2.
    - Tier chấm cho tháng M chỉ "biết" khi tháng M kết thúc → hiệu lực từ ngày đầu tháng M+1.
    - Version đầu: valid_from = 1900-01-01, tier New → mọi sự kiện trước lần chấm đầu đều tra được.
    - Chỉ tạo version mới khi tier đổi; valid_to = valid_from version kế − 1 ngày; version cuối 9999-12-31.
    Seller không có trong bảng này (chưa bán, hoặc chỉ bán sau ANALYSIS_END) được dim_seller cấp 1 version mặc định.
-#}
with monthly as (
    select * from {{ ref('int_seller_tier_monthly') }}
),

events as (
    select distinct
        seller_id,
        '{{ var("scd_first_valid_from") }}'::date as valid_from,
        'New'::text as seller_tier,
        null::text as rule_version,
        null::date as scored_month
    from monthly

    union all

    select
        seller_id,
        (month_start + interval '1 month')::date as valid_from,
        seller_tier,
        rule_version,
        month_start as scored_month
    from monthly
),

changes as (
    select
        *,
        lag(seller_tier) over (partition by seller_id order by valid_from) as prev_tier
    from events
),

versions as (
    select
        seller_id,
        valid_from,
        seller_tier,
        prev_tier,
        rule_version,
        scored_month
    from changes
    where prev_tier is null or seller_tier <> prev_tier
)

select
    seller_id,
    row_number() over (partition by seller_id order by valid_from) as version_no,
    valid_from,
    coalesce(
        (lead(valid_from) over (partition by seller_id order by valid_from) - 1),
        '{{ var("scd_open_end_date") }}'::date
    ) as valid_to,
    lead(valid_from) over (partition by seller_id order by valid_from) is null as is_current,
    seller_tier,
    prev_tier,
    rule_version,
    scored_month
from versions
