{#-
    P2: fact_geo_month — periodic snapshot, 1 dòng / zip × tháng mua (sparse: chỉ cặp có ít nhất 1 sự kiện).
    Phía cầu theo zip của khách trên đơn, phía cung theo zip của seller. Chỉ đơn counts_as_sale có ít nhất 1 item,
    cùng tập đơn với KPI Orders / GMV của fact_order_item (C-W8).
    Rules: BR-P2-1 … BR-P2-5 (docs/business_rules.md).
-#}
with sale_orders as (
    select
        f.order_id,
        f.purchase_date_key / 100 * 100 + 1 as month_date_key,
        f.customer_key,
        f.customer_geo_key,
        f.seller_geo_key,
        f.order_value,
        f.freight_total,
        f.is_delivered,
        f.is_late,
        f.delivery_lag,
        -- BR-P2-3: đơn local = primary seller cùng bang với khách
        (cg.state_code = sg.state_code)::int as is_local
    from {{ ref('fact_order_fulfillment') }} as f
    join {{ ref('dim_order_status') }} as st on st.order_status_key = f.order_status_key
    join {{ ref('dim_geography') }} as cg on cg.geo_key = f.customer_geo_key
    join {{ ref('dim_geography') }} as sg on sg.geo_key = f.seller_geo_key
    where st.counts_as_sale = 1
      and f.item_count > 0
      and f.purchase_date_key <> -1
),

-- Phía cầu (BR-P2-2): zip của khách trên đơn
demand as (
    select
        customer_geo_key as geo_key,
        month_date_key,
        count(*) as orders_placed,
        sum(order_value) as gmv_placed,
        sum(freight_total) as freight_placed,
        sum(is_local) as orders_local,
        sum(order_value) filter (where is_local = 1) as gmv_local,
        count(distinct customer_key) as customers_active,
        sum(is_delivered) as delivered_orders,
        sum(is_late) as late_orders,
        sum(delivery_lag) filter (where is_delivered = 1) as delivery_lag_sum
    from sale_orders
    group by customer_geo_key, month_date_key
),

-- BR-P2-4: khách mới theo zip và tháng của đơn đầu tiên (dim_customer, BR-CW3-1, BR-CW3-2)
new_customers as (
    select
        customer_geo_key as geo_key,
        first_order_date_key / 100 * 100 + 1 as month_date_key,
        count(*) as customers_new
    from {{ ref('dim_customer') }}
    where customer_key <> -1
      and first_order_date_key <> -1
    group by 1, 2
),

-- Phía cung (BR-P2-2): đơn theo zip của primary seller
supply_orders as (
    select seller_geo_key as geo_key, month_date_key, count(*) as orders_shipped
    from sale_orders
    group by seller_geo_key, month_date_key
),

-- Phía cung: GMV và seller theo zip của seller trên từng item (đơn nhiều seller tách đúng phần của từng seller)
supply_items as (
    select
        i.seller_geo_key as geo_key,
        i.purchase_date_key / 100 * 100 + 1 as month_date_key,
        sum(i.item_price) as gmv_sold,
        count(distinct i.seller_id) as sellers_active
    from {{ ref('fact_order_item') }} as i
    join {{ ref('dim_order_status') }} as st on st.order_status_key = i.order_status_key
    where st.counts_as_sale = 1
      and i.purchase_date_key <> -1
    group by 1, 2
),

grid as (
    select geo_key, month_date_key from demand
    union
    select geo_key, month_date_key from new_customers
    union
    select geo_key, month_date_key from supply_orders
    union
    select geo_key, month_date_key from supply_items
)

select
    g.geo_key,
    g.month_date_key,
    coalesce(d.orders_placed, 0) as orders_placed,
    coalesce(d.gmv_placed, 0) as gmv_placed,
    coalesce(d.freight_placed, 0) as freight_placed,
    coalesce(d.orders_local, 0) as orders_local,
    coalesce(d.gmv_local, 0) as gmv_local,
    coalesce(d.customers_active, 0) as customers_active,
    coalesce(n.customers_new, 0) as customers_new,
    coalesce(d.delivered_orders, 0) as delivered_orders,
    coalesce(d.late_orders, 0) as late_orders,
    coalesce(d.delivery_lag_sum, 0) as delivery_lag_sum,
    coalesce(so.orders_shipped, 0) as orders_shipped,
    coalesce(si.gmv_sold, 0) as gmv_sold,
    coalesce(si.sellers_active, 0) as sellers_active
from grid as g
left join demand as d on d.geo_key = g.geo_key and d.month_date_key = g.month_date_key
left join new_customers as n on n.geo_key = g.geo_key and n.month_date_key = g.month_date_key
left join supply_orders as so on so.geo_key = g.geo_key and so.month_date_key = g.month_date_key
left join supply_items as si on si.geo_key = g.geo_key and si.month_date_key = g.month_date_key
