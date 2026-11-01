{#-
    BẢN TẠM (Type 1) — để fact có seller_key ngay (S6 sẽ thay bằng SCD2 trên seller_tier).
    Đã dùng sẵn cấu trúc SCD2 để fact không phải sửa khi chuyển:
      - 1 version / seller: valid_from = scd_first_valid_from (1900-01-01), valid_to = 9999-12-31, is_current = true
      - seller_key = int_sk(seller_id, valid_from) → version đầu tiên của SCD2 sẽ giữ đúng key này
      - seller_tier = 'Unscored' cho tới khi S6 chấm tier
    Tập seller = sellers ∪ closed_deals.seller_id (S1: 462 seller chốt deal không có trong sellers).
-#}
with sellers as (
    select seller_id, seller_zip_prefix
    from {{ ref('stg_sellers') }}
),

funnel_sellers as (
    select distinct seller_id
    from {{ ref('stg_closed_deals') }}
    where seller_id is not null
),

selling as (
    select distinct seller_id
    from {{ ref('stg_order_items') }}
),

all_sellers as (
    select seller_id from sellers
    union
    select seller_id from funnel_sellers
),

final as (
    select
        {{ int_sk(['a.seller_id', "'" ~ var('scd_first_valid_from') ~ "'::date"]) }} as seller_key,
        a.seller_id,
        {{ coalesce_key('g.geo_key') }} as seller_geo_key,
        'Unscored'::text as seller_tier,
        null::text as tier_rule_version,
        '{{ var("scd_first_valid_from") }}'::date as valid_from,
        '{{ var("scd_open_end_date") }}'::date as valid_to,
        true as is_current,
        sl.seller_id is not null as has_sales,
        f.seller_id is not null as is_from_funnel
    from all_sellers as a
    left join sellers as s on a.seller_id = s.seller_id
    left join {{ ref('dim_geography') }} as g on s.seller_zip_prefix = g.zip_prefix
    left join selling as sl on a.seller_id = sl.seller_id
    left join funnel_sellers as f on a.seller_id = f.seller_id

    union all

    select
        {{ unknown_key() }},
        'unknown',
        {{ unknown_key() }},
        'Unscored',
        null,
        '{{ var("scd_first_valid_from") }}'::date,
        '{{ var("scd_open_end_date") }}'::date,
        true,
        false,
        false
)

select * from final
