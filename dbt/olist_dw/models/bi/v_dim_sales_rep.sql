select
    sales_rep_key,
    sdr_id as "SDR ID",
    sr_id as "SR ID"
from {{ ref('dim_sales_rep') }}
