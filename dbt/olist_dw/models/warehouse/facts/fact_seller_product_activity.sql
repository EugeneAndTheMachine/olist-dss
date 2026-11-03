{#-
    Factless fact (COULD) — grain: 1 seller bán 1 product trong 1 tháng (đơn counts_as_sale, trong ANALYSIS window).
    Không có measure: đếm dòng = số listing đang hoạt động → đo độ rộng danh mục của seller.
-#}
select distinct
    {{ date_key("date_trunc('month', d.full_date)") }} as month_date_key,
    f.seller_key,
    f.product_key
from {{ ref('fact_order_item') }} as f
inner join {{ ref('dim_date') }} as d on f.purchase_date_key = d.date_key
inner join {{ ref('dim_order_status') }} as st on f.order_status_key = st.order_status_key
where st.counts_as_sale
  and d.full_date between '{{ var("analysis_start") }}'::date and '{{ var("analysis_end") }}'::date
