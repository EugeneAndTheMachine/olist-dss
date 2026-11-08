-- BR-CW8-2: tổng giá item và GMV doanh số của fact phải khớp nguồn staging.
with fact as (
    select
        sum(f.item_price) as price_all,
        sum(f.item_price) filter (where st.counts_as_sale = 1) as gmv_sale
    from {{ ref('fact_order_item') }} as f
    join {{ ref('dim_order_status') }} as st on st.order_status_key = f.order_status_key
),

source as (
    select
        sum(i.price) as price_all,
        sum(i.price) filter (where m.counts_as_sale) as gmv_sale
    from {{ ref('stg_order_items') }} as i
    left join {{ ref('stg_orders') }} as o on o.order_id = i.order_id
    left join {{ ref('order_status_map') }} as m on m.order_status = o.order_status
)

select fact.price_all as fact_price, source.price_all as source_price, fact.gmv_sale as fact_gmv, source.gmv_sale as source_gmv
from fact cross join source
where fact.price_all <> source.price_all
   or coalesce(fact.gmv_sale, 0) <> coalesce(source.gmv_sale, 0)
