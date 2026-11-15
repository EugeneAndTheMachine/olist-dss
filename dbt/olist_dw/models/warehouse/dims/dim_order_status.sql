{#-
    C-W6: dim_order_status — Dimension trạng thái đơn hàng từ seed order_status_map + dòng unknown (-1).
    Rules: BR-W1, BR-W2, BR-K1, BR-O1 (docs/business_rules.md).
-#}
with status_map as (
    select
        order_status,
        status_group,
        counts_as_sale
    from {{ ref('order_status_map') }}
),

final as (
    select
        {{ int_sk(['order_status']) }} as order_status_key,
        order_status,
        status_group,
        counts_as_sale::int as counts_as_sale
    from status_map

    union all

    select
        {{ unknown_key() }} as order_status_key,
        'unknown' as order_status,
        'Unknown' as status_group,
        0 as counts_as_sale
)

select
    order_status_key,
    order_status,
    status_group,
    counts_as_sale
from final

