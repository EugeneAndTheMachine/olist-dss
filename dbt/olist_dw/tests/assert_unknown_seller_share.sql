-- BR-CW8-1: item không khớp phiên bản seller (seller_key = -1) không được quá 1%.
select count(*) filter (where seller_key = -1)::numeric / count(*) as unknown_share
from {{ ref('fact_order_item') }}
having count(*) filter (where seller_key = -1)::numeric / count(*) > 0.01
