-- C-W4 / BR-CW4-0: mỗi seller có đúng 1 phiên bản hiện hành, các khoảng [valid_from, valid_to] liền nhau
-- (không chồng, không hở), bắt đầu 1900-01-01 và kết thúc 9999-12-31, nên mọi ngày mua tra ra đúng 1 phiên bản.
with ordered as (
    select
        seller_id,
        valid_from,
        valid_to,
        is_current,
        lag(valid_to) over (partition by seller_id order by valid_from) as prev_valid_to,
        min(valid_from) over (partition by seller_id) as first_from,
        max(valid_to) over (partition by seller_id) as last_to,
        sum(is_current) over (partition by seller_id) as current_count
    from {{ ref('dim_seller') }}
)

select *
from ordered
where valid_from > valid_to
   or (prev_valid_to is not null and valid_from <> prev_valid_to + 1)
   or first_from <> '1900-01-01'::date
   or last_to <> '9999-12-31'::date
   or current_count <> 1
   or (is_current = 1 and valid_to <> '9999-12-31'::date)
