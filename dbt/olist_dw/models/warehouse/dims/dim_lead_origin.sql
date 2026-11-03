{#- 1 dòng / cặp kênh marketing (origin) + landing page. Type 1. -#}
with origins as (
    select distinct origin, landing_page_id
    from {{ ref('stg_mql') }}
)

select
    {{ int_sk(['origin', 'landing_page_id']) }} as lead_origin_key,
    origin,
    landing_page_id
from origins

union all

select {{ unknown_key() }}, 'unknown', 'unknown'
