{#- C-B1: v_dim_seller — 1 dòng / phiên bản seller (SCD2) + -1. -#}
select
    seller_key,
    seller_id,
    version_no,
    seller_geo_key,
    seller_tier,
    valid_from,
    valid_to,
    is_current
from {{ ref('dim_seller') }}
