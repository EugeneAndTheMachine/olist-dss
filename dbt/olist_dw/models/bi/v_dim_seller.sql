{#-
    Dim seller SCD2: 1 dòng / version. Fact đã trỏ đúng version hiệu lực tại thời điểm sự kiện
    → lọc theo "Seller Tier" = tier lúc đó (point-in-time). Muốn lọc theo tier hôm nay dùng "Current Tier".
    "Previous Tier" phục vụ ma trận chuyển tier (trang 5).
-#}
with versions as (
    select
        *,
        lag(seller_tier) over (partition by seller_id order by valid_from) as previous_tier,
        max(case when is_current then seller_tier end) over (partition by seller_id) as current_tier
    from {{ ref('dim_seller') }}
)

select
    seller_key,
    seller_id as "Seller ID",
    version_no as "Version No",
    seller_tier as "Seller Tier",
    {{ tier_sort('seller_tier') }} as "Seller Tier Sort",
    previous_tier as "Previous Tier",
    {{ tier_sort('previous_tier') }} as "Previous Tier Sort",
    current_tier as "Current Tier",
    {{ tier_sort('current_tier') }} as "Current Tier Sort",
    tier_rule_version as "Tier Rule Version",
    valid_from as "Valid From",
    valid_to as "Valid To",
    is_current as "Is Current",
    has_sales as "Has Sales",
    is_from_funnel as "Is From Funnel"
from versions
