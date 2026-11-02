{#-
    1 dòng / cặp origin + landing_page_id (kênh marketing đưa lead tới). Type 1.
    Mọi MQL đều có origin (null đã gộp vào 'unknown' ở stg_mql) và landing_page_id → fact luôn tra được.
-#}
with origins as (
    select distinct
        origin,
        landing_page_id
    from {{ ref('stg_mql') }}
),

final as (
    select
        {{ int_sk(['origin', 'landing_page_id']) }} as lead_origin_key,
        origin,
        landing_page_id
    from origins

    union all

    select
        {{ unknown_key() }},
        'unknown',
        'unknown'
)

select * from final
