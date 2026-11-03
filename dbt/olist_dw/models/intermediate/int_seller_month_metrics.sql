{#-
    S6 bước 1 (implementation.md mục 10): seller × tháng, đọc từ STG (không từ fact) để tránh vòng
    dim_seller → fact → dim_seller. Dày đặc từ tháng có đơn đầu tiên đến ANALYSIS_END.
    Đơn được gán cho mọi seller có item trong đơn (cặp order × seller); tháng = tháng mua.
    Cửa sổ trượt 3 tháng (tháng hiện tại + 2 tháng trước) để tier không nhảy liên tục.
    fact_seller_month dùng lại bảng này → hai nơi luôn cùng định nghĩa.
-#}
with order_sellers as (
    select distinct order_id, seller_id
    from {{ ref('stg_order_items') }}
),

orders as (
    select
        o.order_id,
        date_trunc('month', o.order_purchase_timestamp)::date as month_start,
        o.is_delivered,
        o.is_late,
        s.counts_as_sale,
        s.status_group
    from {{ ref('stg_orders') }} as o
    inner join {{ ref('order_status_map') }} as s on o.order_status = s.order_status
),

latest_reviews as (
    select order_id, review_score
    from {{ ref('stg_order_reviews') }}
    where is_latest_for_order
),

pairs as (
    select
        os.seller_id,
        o.month_start,
        o.order_id,
        o.counts_as_sale,
        o.status_group,
        o.is_delivered,
        o.is_late,
        r.review_score
    from order_sellers as os
    inner join orders as o on os.order_id = o.order_id
    left join latest_reviews as r on os.order_id = r.order_id
),

monthly as (
    select
        seller_id,
        month_start,
        count(*) filter (where counts_as_sale) as orders,
        count(*) filter (where counts_as_sale and is_delivered) as delivered_orders,
        count(*) filter (where counts_as_sale and is_late) as late_orders,
        count(*) filter (where status_group = 'Cancelled') as cancelled_orders,
        count(review_score) filter (where counts_as_sale) as review_count,
        coalesce(sum(review_score) filter (where counts_as_sale), 0) as score_sum
    from pairs
    group by seller_id, month_start
),

first_month as (
    select seller_id, min(month_start) as first_month
    from monthly
    group by seller_id
),

spine as (
    select
        f.seller_id,
        f.first_month,
        gs::date as month_start
    from first_month as f
    cross join lateral generate_series(
        f.first_month,
        date_trunc('month', '{{ var("analysis_end") }}'::date),
        interval '1 month'
    ) as gs
),

dense as (
    select
        s.seller_id,
        s.month_start,
        s.first_month,
        coalesce(m.orders, 0) as orders,
        coalesce(m.delivered_orders, 0) as delivered_orders,
        coalesce(m.late_orders, 0) as late_orders,
        coalesce(m.cancelled_orders, 0) as cancelled_orders,
        coalesce(m.review_count, 0) as review_count,
        coalesce(m.score_sum, 0) as score_sum
    from spine as s
    left join monthly as m
        on s.seller_id = m.seller_id
        and s.month_start = m.month_start
),

rolling as (
    select
        *,
        (extract(year from age(month_start, first_month)) * 12
            + extract(month from age(month_start, first_month)))::int as months_since_first,
        sum(orders) over w3 as orders_3m,
        sum(delivered_orders) over w3 as delivered_3m,
        sum(late_orders) over w3 as late_3m,
        sum(review_count) over w3 as review_count_3m,
        sum(score_sum) over w3 as score_sum_3m
    from dense
    window w3 as (partition by seller_id order by month_start rows between 2 preceding and current row)
)

select
    seller_id,
    month_start,
    first_month,
    months_since_first,
    orders,
    delivered_orders,
    late_orders,
    cancelled_orders,
    review_count,
    score_sum,
    orders_3m,
    delivered_3m,
    late_3m,
    review_count_3m,
    score_sum_3m,
    round(late_3m::numeric / nullif(delivered_3m, 0), 4) as late_rate_3m,
    round(score_sum_3m::numeric / nullif(review_count_3m, 0), 4) as avg_score_3m
from rolling
