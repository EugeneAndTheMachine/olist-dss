-- BR-P3-3: đơn giao / trễ được đếm đúng một lần cho mỗi cặp (đơn bán, category); fulfillment phải unique theo đơn.
with pairs as (
    select distinct f.order_id, p.category_key
    from {{ ref('fact_order_item') }} as f
    join {{ ref('dim_order_status') }} as st on st.order_status_key = f.order_status_key
    join {{ ref('dim_product') }} as p on p.product_key = f.product_key
    where st.counts_as_sale = 1
),

expected as (
    select sum(ff.is_delivered) as delivered, sum(ff.is_late) as late
    from pairs
    join {{ ref('fact_order_fulfillment') }} as ff on ff.order_id = pairs.order_id
)

select m.delivered, e.delivered as expected_delivered, m.late, e.late as expected_late
from (select sum(delivered_orders) as delivered, sum(late_orders) as late from {{ ref('fact_category_month') }}) as m
cross join expected as e
where m.delivered <> e.delivered or m.late <> e.late
