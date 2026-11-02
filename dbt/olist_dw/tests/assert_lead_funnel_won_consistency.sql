-- fact_lead_funnel: lead đã chốt ⇔ có won_date, sales rep, profile, seller; chưa chốt ⇔ mọi key đó = -1.
-- First sale chỉ có khi đã chốt, và không trước ngày chốt. Σ is_won = số deal trong stg_closed_deals.
select mql_id, 'won_keys_mismatch' as issue
from {{ ref('fact_lead_funnel') }}
where (is_won = 1) <> (won_date_key <> -1)
   or (is_won = 1) <> (sales_rep_key <> -1)
   or (is_won = 1) <> (lead_profile_key <> -1)
   or (is_won = 1) <> (seller_key <> -1)
   or (is_won = 0 and (first_sale_date_key <> -1 or has_full_90d_window = 1 or gmv_first_90_days is not null))

union all

select mql_id, 'first_sale_before_won'
from {{ ref('fact_lead_funnel') }}
where first_sale_date_key <> -1
  and first_sale_date_key < won_date_key

union all

select null, 'won_count_mismatch'
from (select sum(is_won) as won from {{ ref('fact_lead_funnel') }}) as f
cross join (select count(*) as deals from {{ ref('stg_closed_deals') }}) as d
where f.won <> d.deals
