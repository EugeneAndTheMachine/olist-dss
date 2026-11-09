-- Mỗi đơn có review phải có đúng một review is_latest_for_order = 1 (BR-CS7-2).
select order_id, sum(is_latest_for_order) as latest_count
from {{ ref('stg_order_reviews') }}
group by order_id
having sum(is_latest_for_order) <> 1
