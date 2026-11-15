-- C-W2 / BR-CW2-1: mọi zip của customers và sellers phải có dòng riêng trong dim_geography (không rơi vào -1).
select 'customer' as side, c.customer_zip_prefix as zip_prefix
from {{ ref('stg_customers') }} as c
left join {{ ref('dim_geography') }} as g on g.zip_prefix = c.customer_zip_prefix
where g.geo_key is null

union all

select 'seller', s.seller_zip_prefix
from {{ ref('stg_sellers') }} as s
left join {{ ref('dim_geography') }} as g on g.zip_prefix = s.seller_zip_prefix
where g.geo_key is null
