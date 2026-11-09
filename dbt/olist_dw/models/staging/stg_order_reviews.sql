{#- Làm sạch text inline cho tới khi macro clean_text dùng chung (C-R1, owner C-S1) có trên main. -#}
with source as (
    select * from {{ source('raw', 'order_reviews') }}
),

deduped as (
    select
        *,
        row_number() over (partition by review_id, order_id order by _loaded_at desc) as _rn
    from source
),

typed as (
    select
        nullif(trim(review_id), '') as review_id,
        nullif(trim(order_id), '') as order_id,
        nullif(trim(review_score), '')::smallint as review_score,
        nullif(trim(review_comment_title), '') as review_comment_title,
        nullif(trim(review_comment_message), '') as review_comment_message,
        nullif(trim(review_creation_date), '')::timestamp as review_created_at,
        nullif(trim(review_answer_timestamp), '')::timestamp as review_answered_at,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
)

select
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_created_at,
    review_answered_at,
    (review_comment_message is not null)::int::smallint as has_comment,
    coalesce(length(review_comment_message), 0) as comment_length,
    (row_number() over (
        partition by order_id
        order by review_answered_at desc nulls last, review_created_at desc nulls last, review_id desc
    ) = 1)::int::smallint as is_latest_for_order,
    _batch_id,
    _loaded_at
from typed
