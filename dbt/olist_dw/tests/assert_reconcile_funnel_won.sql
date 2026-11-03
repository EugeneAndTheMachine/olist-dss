-- Đối soát funnel: số lead đã chốt trong fact = số dòng closed_deals; mọi deal có seller_key. Trả dòng = lỗi.
with fact as (
    select
        sum(is_won) as won,
        count(*) filter (where is_won = 1 and seller_key = -1) as won_without_seller
    from {{ ref('fact_lead_funnel') }}
),

deals as (
    select count(*) as deals
    from {{ ref('stg_closed_deals') }}
)

select fact.won, deals.deals, fact.won_without_seller
from fact
cross join deals
where fact.won <> deals.deals
   or fact.won_without_seller > 0
