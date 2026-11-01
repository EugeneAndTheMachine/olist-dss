{#-
    S1 (A2): 789 review_id gắn > 1 đơn, 547 đơn có > 1 review → khoá là (review_id, order_id).
    is_latest_for_order chọn 1 review / đơn cho KPI: answer mới nhất → creation mới nhất → review_id.
-#}
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
        {{ clean_text('review_id') }} as review_id,
        {{ clean_text('order_id') }} as order_id,
        {{ clean_text('review_score') }}::int as review_score,
        {{ clean_text('review_comment_title') }} as review_comment_title,
        {{ clean_text('review_comment_message') }} as review_comment_message,
        {{ clean_text('review_creation_date') }}::timestamp as review_creation_date,
        {{ clean_text('review_answer_timestamp') }}::timestamp as review_answer_timestamp,
        _batch_id,
        _loaded_at::timestamptz as _loaded_at
    from deduped
    where _rn = 1
),

final as (
    select
        review_id,
        order_id,
        review_score,
        review_comment_title,
        review_comment_message,
        review_creation_date,
        review_answer_timestamp,
        (review_comment_title is not null or review_comment_message is not null) as has_comment,
        coalesce(length(review_comment_message), 0) as comment_length,
        review_score <= 2 as is_low_score,
        extract(epoch from review_answer_timestamp - review_creation_date) / 3600.0 as response_hours,
        row_number() over (
            partition by order_id
            order by review_answer_timestamp desc nulls last, review_creation_date desc nulls last, review_id
        ) = 1 as is_latest_for_order,
        _batch_id,
        _loaded_at
    from typed
)

select * from final
