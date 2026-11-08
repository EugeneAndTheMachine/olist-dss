-- BR-P3-3: items và GMV của fact_category_month khớp fact_order_item (đơn counts_as_sale).
with mart as (
    select sum(items) as items, sum(gmv) as gmv from {{ ref('fact_category_month') }}
),

source as (
    select sum(f.item_count) as items, sum(f.item_price) as gmv
    from {{ ref('fact_order_item') }} as f
    join {{ ref('dim_order_status') }} as st on st.order_status_key = f.order_status_key
    where st.counts_as_sale = 1
)

select mart.items as mart_items, source.items as source_items, mart.gmv as mart_gmv, source.gmv as source_gmv
from mart cross join source
where mart.items <> source.items or mart.gmv <> source.gmv
