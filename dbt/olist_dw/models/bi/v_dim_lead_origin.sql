select
    lead_origin_key,
    origin as "Lead Origin",
    landing_page_id as "Landing Page ID"
from {{ ref('dim_lead_origin') }}
