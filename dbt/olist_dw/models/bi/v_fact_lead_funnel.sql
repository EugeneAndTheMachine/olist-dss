{#-
    Funnel thu hút seller — 1 dòng / MQL. Date key = -1 khi mốc chưa xảy ra.
    So giá trị kênh (GMV 90 ngày) chỉ trên lead "Has Full 90d Window" = 1.
-#}
select
    mql_id as "MQL ID",
    first_contact_date_key,
    won_date_key,
    first_sale_date_key,
    lead_origin_key,
    lead_profile_key,
    sales_rep_key,
    seller_key,
    lead_count as "Lead Count",
    is_won as "Is Won",
    has_first_sale as "Has First Sale",
    days_to_close as "Days To Close",
    declared_product_catalog_size as "Declared Catalog Size",
    declared_monthly_revenue as "Declared Monthly Revenue",
    gmv_first_90_days as "GMV First 90 Days",
    has_full_90d_window as "Has Full 90d Window",
    _dq_issue as "DQ Issue"
from {{ ref('fact_lead_funnel') }}
