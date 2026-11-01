-- Mỗi seller đúng 1 version is_current (implementation.md mục 10, test bắt buộc SCD2). Trả dòng = lỗi.
select
    seller_id,
    count(*) filter (where is_current) as current_versions
from {{ ref('dim_seller') }}
group by seller_id
having count(*) filter (where is_current) <> 1
