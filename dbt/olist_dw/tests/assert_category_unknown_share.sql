{{ config(severity='warn') }}
-- BR-P3-11: item thuộc category -1 hoặc 'unknown' cảnh báo khi quá 2% (hiện ~1,4%).
select count(*) filter (where c.category_key = -1 or c.category_pt = 'unknown')::numeric / count(*) as unknown_share
from {{ ref('fact_order_item') }} as f
join {{ ref('dim_product') }} as p on p.product_key = f.product_key
join {{ ref('dim_category') }} as c on c.category_key = p.category_key
having count(*) filter (where c.category_key = -1 or c.category_pt = 'unknown')::numeric / count(*) > 0.02
