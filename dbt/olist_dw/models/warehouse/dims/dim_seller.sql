{#-
    SCD Type 2 trên seller_tier (S6, implementation.md mục 10); Type 1 trên các cột còn lại.
    - Version lấy từ int_seller_tier_versions; seller_key = int_sk(seller_id, valid_from)
      → version đầu (1900-01-01) giữ đúng key của bản tạm trước đây.
    - Seller không có version (chỉ có trong funnel, hoặc chỉ bán sau ANALYSIS_END) → 1 version:
      Unscored nếu chưa từng bán, New nếu có bán.
    - Tra cứu trong fact: event_date between valid_from and valid_to.
    Tập seller = sellers ∪ closed_deals.seller_id (S1: 462 seller chốt deal không có trong sellers).
    Load live sau này: dbt snapshot (strategy check trên seller_tier) — snapshot chỉ ghi trạng thái
    quan sát lúc chạy, không dựng lại lịch sử, nên backfill dùng SQL như ở đây.
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

scored_versions as (
    select * from {{ ref('int_seller_tier_versions') }}
),

default_versions as (
    select
        a.seller_id,
        1 as version_no,
        '{{ var("scd_first_valid_from") }}'::date as valid_from,
        '{{ var("scd_open_end_date") }}'::date as valid_to,
        true as is_current,
        case when sl.seller_id is not null then 'New' else 'Unscored' end as seller_tier,
        null::text as rule_version
    from all_sellers as a
    left join selling as sl on a.seller_id = sl.seller_id
    where not exists (select 1 from scored_versions as v where v.seller_id = a.seller_id)
),

versions as (
    select seller_id, version_no, valid_from, valid_to, is_current, seller_tier, rule_version
    from scored_versions
    union all
    select seller_id, version_no, valid_from, valid_to, is_current, seller_tier, rule_version
    from default_versions
),

final as (
    select
        {{ int_sk(['v.seller_id', 'v.valid_from']) }} as seller_key,
        v.seller_id,
        v.version_no,
        {{ coalesce_key('g.geo_key') }} as seller_geo_key,
        v.seller_tier,
        v.rule_version as tier_rule_version,
        v.valid_from,
        v.valid_to,
        v.is_current,
        sl.seller_id is not null as has_sales,
        f.seller_id is not null as is_from_funnel
    from versions as v
    left join sellers as s on v.seller_id = s.seller_id
    left join {{ ref('dim_geography') }} as g on s.seller_zip_prefix = g.zip_prefix
    left join selling as sl on v.seller_id = sl.seller_id
    left join funnel_sellers as f on v.seller_id = f.seller_id

    union all

    select
        {{ unknown_key() }},
        'unknown',
        1,
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
