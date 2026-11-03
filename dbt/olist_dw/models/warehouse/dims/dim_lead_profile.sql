{#-
    Junk dimension các thuộc tính hồ sơ lead. CHỈ tồn tại cho lead đã chốt (closed_deals) →
    lead chưa chốt có lead_profile_key = -1 và không được dùng làm feature dự đoán conversion.
-#}
with profiles as (
    select distinct
        coalesce(business_segment, 'unknown') as business_segment,
        coalesce(lead_type, 'unknown') as lead_type,
        coalesce(lead_behaviour_profile, 'unknown') as lead_behaviour_profile,
        coalesce(business_type, 'unknown') as business_type,
        coalesce(has_company::text, 'unknown') as has_company,
        coalesce(has_gtin::text, 'unknown') as has_gtin,
        coalesce(average_stock, 'unknown') as stock_band
    from {{ ref('stg_closed_deals') }}
)

select
    {{ int_sk(['business_segment', 'lead_type', 'lead_behaviour_profile', 'business_type',
               'has_company', 'has_gtin', 'stock_band']) }} as lead_profile_key,
    business_segment,
    lead_type,
    lead_behaviour_profile,
    business_type,
    has_company,
    has_gtin,
    stock_band
from profiles

union all

select {{ unknown_key() }}, 'not_won', 'not_won', 'not_won', 'not_won', 'not_won', 'not_won', 'not_won'
