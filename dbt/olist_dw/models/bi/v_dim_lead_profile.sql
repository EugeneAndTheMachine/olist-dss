{#- Chỉ có thuộc tính cho lead đã chốt; key -1 = lead chưa chốt (not won). -#}
select
    lead_profile_key,
    business_segment as "Business Segment",
    lead_type as "Lead Type",
    lead_behaviour_profile as "Behaviour Profile",
    business_type as "Business Type",
    has_company as "Has Company",
    has_gtin as "Has GTIN",
    stock_band as "Stock Band"
from {{ ref('dim_lead_profile') }}
