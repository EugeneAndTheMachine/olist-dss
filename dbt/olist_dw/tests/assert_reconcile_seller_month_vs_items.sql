-- Đối soát (implementation.md mục 11.1): Σ fact_seller_month = Σ fact_order_item cùng tháng
-- (đơn counts_as_sale, tháng <= ANALYSIS_END). So từng tháng để lệch ở đâu thấy ngay. Trả dòng = lỗi.
with items as (
    select
        date_trunc('month', d.full_date)::date as month_start,
        count(*) as items,
        sum(f.item_price) as gmv
    from {{ ref('fact_order_item') }} as f
    inner join {{ ref('dim_date') }} as d on f.purchase_date_key = d.date_key
    inner join {{ ref('dim_order_status') }} as st on f.order_status_key = st.order_status_key
    where st.counts_as_sale
      and d.full_date <= '{{ var("analysis_end") }}'::date
    group by 1
),

seller_month as (
    select
        d.full_date as month_start,
        sum(f.items) as items,
        sum(f.gmv) as gmv
    from {{ ref('fact_seller_month') }} as f
    inner join {{ ref('dim_date') }} as d on f.month_date_key = d.date_key
    group by 1
)

select
    coalesce(i.month_start, s.month_start) as month_start,
    i.items as item_fact_items,
    s.items as seller_month_items,
    i.gmv as item_fact_gmv,
    s.gmv as seller_month_gmv
from items as i
full outer join seller_month as s on i.month_start = s.month_start
where coalesce(i.items, 0) <> coalesce(s.items, 0)
   or coalesce(i.gmv, 0) <> coalesce(s.gmv, 0)
