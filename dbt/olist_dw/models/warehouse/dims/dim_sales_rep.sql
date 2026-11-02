{#-
    1 dòng / cặp sdr_id (sales development rep, người khai thác lead) + sr_id (sales rep, người chốt). Type 1.
    Chỉ lead đã chốt có cặp này → lead chưa chốt dùng key -1.
-#}
with reps as (
    select distinct
        sdr_id,
        sr_id
    from {{ ref('stg_closed_deals') }}
),

final as (
    select
        {{ int_sk(['sdr_id', 'sr_id']) }} as sales_rep_key,
        sdr_id,
        sr_id
    from reps

    union all

    select
        {{ unknown_key() }},
        'unknown',
        'unknown'
)

select * from final
