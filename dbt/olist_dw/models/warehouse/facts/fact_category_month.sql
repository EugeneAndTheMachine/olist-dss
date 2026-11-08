{#-
    Periodic snapshot: category × bang của khách × tháng mua, chỉ đơn counts_as_sale (BR-P3-2).
    Gộp về (đơn, category) trước khi nối review / fulfillment: nối ở grain item nhân review theo số item (BR-P3-3).
-#}
with sale_items as (
    select
        f.order_id,
        f.customer_key,
        f.seller_id,
        f.item_count,
        f.item_price,
        f.freight_value,
        p.category_key,
        p.weight_g,
        g.state_code as customer_state_code,
        case when f.purchase_date_key = -1 then -1 else f.purchase_date_key / 100 * 100 + 1 end as month_date_key
    from {{ ref('fact_order_item') }} as f
    join {{ ref('dim_order_status') }} as st on st.order_status_key = f.order_status_key
    join {{ ref('dim_product') }} as p on p.product_key = f.product_key
    join {{ ref('dim_geography') }} as g on g.geo_key = f.customer_geo_key
    where st.counts_as_sale = 1
),

order_category as (
    select
        order_id,
        category_key,
        customer_state_code,
        month_date_key,
        min(customer_key) as customer_key,
        sum(item_count) as items,
        sum(item_price) as gmv,
        sum(freight_value) as freight,
        sum(weight_g) as weight_g_sum,
        count(weight_g) as weight_g_items
    from sale_items
    group by order_id, category_key, customer_state_code, month_date_key
),

fulfillment as (
    select order_id, is_delivered, is_late from {{ ref('fact_order_fulfillment') }}
),

latest_review as (
    select order_id, review_count, score_sum, is_low_score
    from {{ ref('fact_review') }}
    where is_latest_for_order = 1
),

sellers as (
    select category_key, customer_state_code, month_date_key, count(distinct seller_id) as sellers_active
    from sale_items
    group by category_key, customer_state_code, month_date_key
)

select
    oc.category_key,
    oc.customer_state_code,
    oc.month_date_key,
    count(*) as orders,
    sum(oc.items) as items,
    sum(oc.gmv) as gmv,
    sum(oc.freight) as freight,
    count(distinct oc.customer_key) as customers,
    max(s.sellers_active) as sellers_active,
    coalesce(sum(r.review_count), 0) as review_count,
    coalesce(sum(r.score_sum), 0) as score_sum,
    coalesce(sum(r.is_low_score), 0) as low_score_count,
    sum(oc.weight_g_sum) as weight_g_sum,
    sum(oc.weight_g_items) as weight_g_items,
    coalesce(sum(ff.is_delivered), 0) as delivered_orders,
    coalesce(sum(ff.is_late), 0) as late_orders
from order_category as oc
left join latest_review as r on r.order_id = oc.order_id
left join fulfillment as ff on ff.order_id = oc.order_id
join sellers as s
    on s.category_key = oc.category_key
    and s.customer_state_code = oc.customer_state_code
    and s.month_date_key = oc.month_date_key
group by oc.category_key, oc.customer_state_code, oc.month_date_key
