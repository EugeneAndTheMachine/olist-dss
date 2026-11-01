-- Đối soát tổng tiền stg → dw: Σ price, Σ freight của fact_order_item phải bằng stg_order_items (không mất / nhân dòng khi join dim).
with stg as (
    select sum(price) as price_total, sum(freight_value) as freight_total
    from {{ ref('stg_order_items') }}
),

fact as (
    select sum(item_price) as price_total, sum(freight_value) as freight_total
    from {{ ref('fact_order_item') }}
)

select
    stg.price_total as stg_price_total,
    fact.price_total as fact_price_total,
    stg.freight_total as stg_freight_total,
    fact.freight_total as fact_freight_total
from stg
cross join fact
where stg.price_total <> fact.price_total
   or stg.freight_total <> fact.freight_total
