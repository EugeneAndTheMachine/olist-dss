{#-
    Transaction fact — grain: 1 review của 1 đơn (review_id + order_id).
    KPI điểm review chỉ dùng dòng is_latest_for_order (đơn có nhiều review, S1: 547 đơn).
    review_score đơn lẻ non-additive → dùng score_sum / review_count.
-#}
with reviews as (
    select * from {{ ref('stg_order_reviews') }}
),

orders as (
    select order_id, customer_id, order_status, order_purchase_timestamp
    from {{ ref('stg_orders') }}
),

final as (
    select
        r.review_id,
        r.order_id,
        {{ date_key('r.review_creation_date') }} as review_creation_date_key,
        {{ date_key('r.review_answer_timestamp') }} as review_answer_date_key,
        {{ coalesce_key('c.customer_key') }} as customer_key,
        {{ coalesce_key('s.seller_key') }} as primary_seller_key,
        {{ coalesce_key('cg.geo_key') }} as customer_geo_key,
        {{ coalesce_key('st.order_status_key') }} as order_status_key,
        1 as review_count,
        r.review_score,
        r.review_score as score_sum,
        r.is_low_score::int as is_low_score,
        r.has_comment::int as has_comment,
        r.comment_length,
        round(r.response_hours::numeric, 2) as response_hours,
        r.is_latest_for_order,
        current_timestamp as _dw_loaded_at
    from reviews as r
    inner join orders as o on r.order_id = o.order_id
    left join {{ ref('int_customer_map') }} as m on o.customer_id = m.customer_id
    left join {{ ref('dim_customer') }} as c on m.customer_unique_id = c.customer_unique_id
    left join {{ ref('dim_geography') }} as cg on m.customer_zip_prefix = cg.zip_prefix
    left join {{ ref('int_order_primary_seller') }} as ps on r.order_id = ps.order_id
    left join {{ ref('dim_seller') }} as s
        on ps.primary_seller_id = s.seller_id
        and o.order_purchase_timestamp::date between s.valid_from and s.valid_to
    left join {{ ref('dim_order_status') }} as st on o.order_status = st.order_status
)

select * from final
