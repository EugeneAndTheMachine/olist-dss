{#-
    Periodic snapshot — grain: 1 seller × 1 tháng, dày đặc từ tháng có đơn đầu tiên đến ANALYSIS_END
    (tháng không bán vẫn có dòng, is_active = 0).
    - Đơn, giao, trễ, huỷ, review lấy từ int_seller_month_metrics (cùng định nghĩa với tier SCD2).
    - items, gmv, distinct_customers lấy từ fact_order_item (đơn counts_as_sale).
    - seller_key = version hiệu lực tại ngày cuối tháng (tier chấm cho tháng M-1).
    Additivity: orders, items, gmv, delivered_orders, late_orders, cancelled_orders, review_count, score_sum
    additive; is_active semi-additive (cộng qua seller, không cộng qua tháng); distinct_customers non-additive.
-#}
with metrics as (
    select * from {{ ref('int_seller_month_metrics') }}
),

item_sales as (
    select
        s.seller_id,
        date_trunc('month', d.full_date)::date as month_start,
        count(*) as items,
        sum(f.item_price) as gmv,
        count(distinct f.customer_key) as distinct_customers
    from {{ ref('fact_order_item') }} as f
    inner join {{ ref('dim_seller') }} as s on f.seller_key = s.seller_key
    inner join {{ ref('dim_date') }} as d on f.purchase_date_key = d.date_key
    inner join {{ ref('dim_order_status') }} as st on f.order_status_key = st.order_status_key
    where st.counts_as_sale
    group by 1, 2
),

final as (
    select
        {{ date_key('m.month_start') }} as month_date_key,
        m.seller_id,
        {{ coalesce_key('s.seller_key') }} as seller_key,
        {{ coalesce_key('s.seller_geo_key') }} as seller_geo_key,
        m.orders,
        coalesce(i.items, 0) as items,
        coalesce(i.gmv, 0) as gmv,
        m.delivered_orders,
        m.late_orders,
        m.cancelled_orders,
        m.review_count,
        m.score_sum,
        (m.orders > 0)::int as is_active,
        coalesce(i.distinct_customers, 0) as distinct_customers,
        current_timestamp as _dw_loaded_at
    from metrics as m
    left join item_sales as i
        on m.seller_id = i.seller_id
        and m.month_start = i.month_start
    left join {{ ref('dim_seller') }} as s
        on m.seller_id = s.seller_id
        and (m.month_start + interval '1 month' - interval '1 day')::date between s.valid_from and s.valid_to
)

select * from final
