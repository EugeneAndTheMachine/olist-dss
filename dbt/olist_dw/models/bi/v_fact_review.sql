select
    review_creation_date_key,
    review_answer_date_key,
    customer_key,
    primary_seller_key,
    customer_geo_key,
    order_status_key,
    review_id,
    order_id,
    review_count,
    score_sum,
    is_low_score,
    has_comment,
    comment_length,
    response_hours,
    is_latest_for_order
from {{ ref('fact_review') }}
