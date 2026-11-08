-- BR-P3-3: mỗi cặp (đơn bán, category) có review mới nhất được đếm đúng một lần (bắt lỗi nhân dòng khi nối ở grain item).
with pairs as (
    select distinct f.order_id, p.category_key
    from {{ ref('fact_order_item') }} as f
    join {{ ref('dim_order_status') }} as st on st.order_status_key = f.order_status_key
    join {{ ref('dim_product') }} as p on p.product_key = f.product_key
    where st.counts_as_sale = 1
),

expected as (
    select count(*) as review_count
    from pairs
    join {{ ref('fact_review') }} as r on r.order_id = pairs.order_id and r.is_latest_for_order = 1
)

select m.review_count as mart_review_count, e.review_count as expected_review_count
from (select sum(review_count) as review_count from {{ ref('fact_category_month') }}) as m
cross join expected as e
where m.review_count <> e.review_count
