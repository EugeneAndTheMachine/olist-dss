-- C-S3 / C-S4: staging không được mất dòng ngoài phần dedup giữa các batch.
-- Số dòng stg phải bằng số natural key phân biệt trong raw.
select 'stg_customers' as model, s.n as stg_rows, r.n as raw_keys
from (select count(*) as n from {{ ref('stg_customers') }}) as s
cross join (select count(distinct trim(customer_id)) as n from {{ source('raw', 'customers') }}) as r
where s.n <> r.n

union all

select 'stg_sellers', s.n, r.n
from (select count(*) as n from {{ ref('stg_sellers') }}) as s
cross join (select count(distinct trim(seller_id)) as n from {{ source('raw', 'sellers') }}) as r
where s.n <> r.n
