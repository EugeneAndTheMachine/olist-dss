-- P2 / BR-P2-1: fact_geo_month phải khớp các fact nguồn, cả phía cầu lẫn phía cung.
-- GMV và số đơn = KPI GMV / Orders của fact_order_item; late = fact_order_fulfillment; khách mới = số khách thật.
with geo as (
    select
        sum(gmv_placed) as gmv_placed,
        sum(gmv_sold) as gmv_sold,
        sum(orders_placed) as orders_placed,
        sum(orders_shipped) as orders_shipped,
        sum(late_orders) as late_orders,
        sum(delivered_orders) as delivered_orders,
        sum(customers_new) as customers_new
    from {{ ref('fact_geo_month') }}
),

items as (
    select sum(i.item_price) as gmv, count(distinct i.order_id) as orders
    from {{ ref('fact_order_item') }} as i
    join {{ ref('dim_order_status') }} as st on st.order_status_key = i.order_status_key
    where st.counts_as_sale = 1
),

fulfillment as (
    select sum(is_late) as late_orders, sum(is_delivered) as delivered_orders
    from {{ ref('fact_order_fulfillment') }}
    where item_count > 0
),

customers as (
    select count(*) as n from {{ ref('dim_customer') }} where customer_key <> -1
)

select geo.*, items.gmv, items.orders, fulfillment.late_orders as ff_late, customers.n as customers
from geo, items, fulfillment, customers
where geo.gmv_placed <> items.gmv
   or geo.gmv_sold <> items.gmv
   or geo.orders_placed <> items.orders
   or geo.orders_shipped <> items.orders
   or geo.late_orders <> fulfillment.late_orders
   or geo.delivered_orders <> fulfillment.delivered_orders
   or geo.customers_new <> customers.n
