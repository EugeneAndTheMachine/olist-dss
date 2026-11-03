{#- Phản hồi khách — 1 dòng / (review, đơn). KPI điểm review chỉ dùng "Is Latest For Order" = true. -#}
select
    review_id as "Review ID",
    order_id as "Order ID",
    review_creation_date_key,
    review_answer_date_key,
    customer_key,
    primary_seller_key as seller_key,
    customer_geo_key,
    order_status_key,
    review_count as "Review Count",
    review_score as "Review Score",
    score_sum as "Score Sum",
    is_low_score as "Is Low Score",
    has_comment as "Has Comment",
    comment_length as "Comment Length",
    response_hours as "Response Hours",
    is_latest_for_order as "Is Latest For Order"
from {{ ref('fact_review') }}
