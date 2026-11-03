{#- 1 dòng / cặp SDR (sales development rep) + SR (sales rep) phụ trách deal. Type 1. -#}
with reps as (
    select distinct
        coalesce(sdr_id, 'unknown') as sdr_id,
        coalesce(sr_id, 'unknown') as sr_id
    from {{ ref('stg_closed_deals') }}
)

select
    {{ int_sk(['sdr_id', 'sr_id']) }} as sales_rep_key,
    sdr_id,
    sr_id
from reps

union all

select {{ unknown_key() }}, 'unknown', 'unknown'
